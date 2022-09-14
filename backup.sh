#!/usr/bin/env bash

# see https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
set -eu
set -o pipefail

readonly SCRIPTS_DIR="$( cd "$( dirname "$0" )/scripts" >/dev/null && pwd )"
. "$SCRIPTS_DIR/_util.sh" || { 1>&2 echo "ERROR!!! failed to source $SCRIPTS_DIR/_util.sh. (Please fix the path.) Exiting."; exit 1; }


#
# Constants
#
readonly BACKUP_DIR="${HOME_DIR}/backups"
readonly KUBECTL_DEP=("Kubectl" "kubectl" "1.20.0" "https://github.com/kubernetes/kubectl/")

#
# DEFAULT VARS
#
CREATE_BACKUP=${CREATE_BACKUP:=false}
NAMESPACE=${NAMESPACE:=arcloud}


#
# SCRIPT-SPECIFIC FUNCTIONS
#
create_database_backup() {
  local version=$1
  local backupdir=$2
  local namespace=$3
  local logfile=$4

  # Setup
  local pgdir="${backupdir}/arcloud_${version}/pg"
  local pgfile="${pgdir}/backup.sql"
  rm -rf $pgdir && mkdir -p $pgdir

  # Backup
  debug "Dumping database -> pg_dumpall -p 5432 -U postgres > $pgfile"
  kubectl exec statefulset/postgresql -n "${namespace}" -- pg_dumpall -p 5432 -U postgres > $pgfile
  du -hs $pgfile | tee -a $logfile
}

create_storage_backup() {
  local version=$1
  local backupdir=$2
  local namespace=$3
  local logfile=$4

  # Setup
  info "Checking host ports"
  local port=9000
  while [ $(nc -z 127.0.0.1 $port; echo $?) -eq 0 ]; do
    if [ $port -ge 65535 ]; then
      fatal "No well-known ports available in the host"
    fi
    let port+=1
  done
  info "Using port TCP:$port"

  silent kubectl port-forward service/minio "${port}:80" -n $namespace &
  trap 'kill -- "$!"' EXIT SIGINT SIGTERM

  local accesskey=$(kubectl get secrets/minio -n $namespace --template='{{ index .data "accesskey" }}' | base64 -d || echo "")
  if [ -z "${accesskey}" ] ; then
    fatal "Failed to retrieve Minio accesskey in namespace $namespace"
  fi
  local secretkey=$(kubectl get secrets/minio -n $namespace --template='{{ index .data "secretkey" }}' | base64 -d || echo "")
  if [ -z "${secretkey}" ] ; then
    fatal "Failed to retrieve Minio secretkey in namespace $namespace"
  fi

  local miniodir="${backupdir}/arcloud_${version}/minio"
  rm -rf $miniodir &&  mkdir -p $miniodir

  local docker_hostname="localhost"
  if [[ "$(uname)" == "Darwin"* ]]; then
    docker_hostname="gateway.docker.internal"
  fi

  debug "Setting minio-client alias -> mc alias set minio http://${docker_hostname}:${port} ${accesskey} ${secretkey} --api S3v4"
  silent docker pull minio/mc
  local mc_alias="mc alias set minio http://${docker_hostname}:${port} ${accesskey} ${secretkey} --api S3v4"
  local mc_info="mc admin info minio"
  local mc_mirror="mc mirror --overwrite --preserve minio /backups $($VERBOSE || echo ">/dev/null")"
  debug "mc: ${mc_alias}"
  debug "mc: ${mc_info}"
  debug "mc: ${mc_mirror}"
  docker run --rm --network host --entrypoint /bin/bash --volume $miniodir:/backups minio/mc -c "${mc_alias} && ${mc_info} && ${mc_mirror}"
  du -hs $miniodir | tee -a $logfile
}

get_version() {
  local namespace=$1
  debug "Inspecting AR Cloud version -> kubectl describe deployment enterprise-console-web -n $namespace | grep ARCLOUD_BUNDLE_VERSION"
  local version=$(kubectl describe deployment enterprise-console-web -n $namespace | grep ARCLOUD_BUNDLE_VERSION | awk 'NR==1{ print $2 }')
  if [ -z "$version" ]; then
    fatal "Failed to get the deployment version from cluster"
  fi
  echo $version
}

compress_files() {
  local version=$1
  local backupdir=$2
  local namespace=$3
  local logfile=$4
  local filename="${namespace}_${version}_$(timestamp_safe).tar.gz"
  cd $backupdir
  echo "" >> $logfile
  echo "------" >> $logfile
  du -hcs "${backupdir}/${namespace}_${version}" >> $logfile
  tar -zcf $filename "${namespace}_${version}"
  du -hs "${backupdir}/${filename}"
  rm -rf "${backupdir}/${namespace}_${version}"
}

create_log_file() {
  local version=$1
  local backupdir=$2
  local namespace=$3
  local filename=$4
  rm -rf "${backupdir}/${namespace}_${version}"
  mkdir -p "${backupdir}/${namespace}_${version}"
  local file="${backupdir}/${namespace}_${version}/${filename}"
  debug "log file created: $file"
  echo "version: $version" >> $file
  echo "" >> $file
  echo $file
}

show_usage() {
  cat <<EOF
usage: /bin/bash backup.sh [OPTION]...

OPTION:
  --namespace <NAMESPACE> The name of the installation's namespace to be backed up (default: arcloud)

FLAGS:
  --verbose Enable verbose output
  -h|--help Print this message
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --verbose )
        VERBOSE=true
        shift
        ;;
      -h | --help )
        show_usage
        exit 0
        ;;
      --namespace)
        arg_required "${@}"
        NAMESPACE="$2"
        shift 2
        ;;
      * )
        exit_usage "Unrecognized option '${1}'"
        ;;
    esac
  done

  readonly VERBOSE
  readonly DEBUG
  readonly NAMESPACE

  if $VERBOSE; then
    debug "HOME_DIR: $HOME_DIR"
    debug "VERBOSE: $VERBOSE"
    debug "DEBUG: $DEBUG"
    debug "NAMESPACE: $NAMESPACE"
  fi
}

trap 'fatal "$0 failed at line $LINENO"' ERR


#
# MAIN SCRIPT
#
assert_commands_exist kubectl docker

parse_args "$@"

header "Bundle Version"
BUNDLE_VERSION=$(get_version $NAMESPACE)
default "$BUNDLE_VERSION"

debug "Creating log file and directories"
LOGFILE=$(create_log_file ${BUNDLE_VERSION} ${BACKUP_DIR} ${NAMESPACE} files.log)

header "Backing up PostgreSQL"
create_database_backup $BUNDLE_VERSION $BACKUP_DIR $NAMESPACE $LOGFILE

header "Backing up Minio"
create_storage_backup $BUNDLE_VERSION $BACKUP_DIR $NAMESPACE $LOGFILE

header "Compressing files"
compress_files $BUNDLE_VERSION $BACKUP_DIR $NAMESPACE $LOGFILE

echo ""
ok "Backup complete"
