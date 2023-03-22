#!/usr/bin/env bash

# see https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
set -eu
set -o pipefail

readonly SCRIPTS_DIR="$( cd "$( dirname "$0" )/scripts" >/dev/null && pwd )"
. "$SCRIPTS_DIR/_util.sh" || { 1>&2 echo "ERROR!!! failed to source $SCRIPTS_DIR/_util.sh. (Please fix the path.) Exiting."; exit 1; }


#
# GLOBAL VARS
#
readonly VERSION="0.0.0"
readonly SCRIPT_NAME=${0##*/}
readonly CHART_DIR=$HOME_DIR/chart
readonly HELM_DEP=("Helm" "helm" "3.2.0" "https://github.com/helm/helm/")
readonly KUBECTL_DEP=("Kubectl" "kubectl" "1.20.0" "https://github.com/kubernetes/kubectl/")
readonly ISTIO_DEP=("Istio" "istio" "1.14.1" "https://github.com/istio/istio/")
readonly SERVICE_CHARTS=(
  "postgresql"
  "minio"
  "nats"
)
readonly OBSERVABILITY_CHARTS=(
  "loki"
  "promtail"
  "tempo"
  "prometheus"
  "grafana"
  "opentelemetry-collector"
)
readonly PRIORITY_CHARTS=(
  "istio-mtls" # mTLS
  "keycloak" # User JWKS
  "device-gateway" # Device JWKS (needs User JWKS)
  "opa-istio-device" # Device Sessions
  "migration"
)


#
# DEFAULT VARS
#
ACCEPT_SLA="${ACCEPT_SLA:=}"
DRY_RUN=${DRY_RUN:=false}
MINIMAL=${MINIMAL:=false}
CHARTS_SET=${CHARTS_SET:=false}
NAMESPACE=${NAMESPACE:=arcloud}
SECURE=${SECURE:=true}
OBSERVABILITY=${OBSERVABILITY:=true}
PARALLEL=${PARALLEL:=true}
UPDATE_DOCKER=${UPDATE_DOCKER:=false}
UPDATE_HELM=${UPDATE_HELM:=false}
CHECK_DEPENDENCIES=${CHECK_DEPENDENCIES:=true}
REGISTRY_SECRET=${REGISTRY_SECRET:=container-registry}
PRINT_INSTALLATION_INFO=${PRINT_INSTALLATION_INFO:=false}
SETS=()
VALUES=()
CHARTS=${CHARTS:=}
if [[ -n "$CHARTS" ]]; then
  tmp_charts="$CHARTS"
  CHARTS=()
  IFS=',' read -r -a CHARTS <<< "$tmp_charts"
  unset IFS
else
  CHARTS=()
fi
HELM_PARAMS=


#
# SCRIPT-SPECIFIC FUNCTIONS
#
check_cluster_resources() {
  header "Checking cluster dependencies"
  if [ "$(kubectl get ns istio-system -o jsonpath='{.status.phase}' 2>/dev/null)"  != "Active" ] ; then
    fatal "'istio-system' namespace not found."
  fi
  if [ "$(kubectl get ns $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null)" != "Active" ] ; then
    fatal "'$NAMESPACE' namespace not found."
  fi
  if [ "$(kubectl get namespace $NAMESPACE -o jsonpath='{.metadata.labels.istio-injection}')" != "enabled" ]; then
    fatal "'$NAMESPACE' namespace requires 'istio-injection=enabled' label."
  fi
  ok "namespaces"

  if [ "$(kubectl get secret $REGISTRY_SECRET -n $NAMESPACE -o jsonpath='{.metadata.name}' 2>/dev/null)" != $REGISTRY_SECRET ] ; then
    fatal "Could not find '$REGISTRY_SECRET' secret in '$NAMESPACE' namespace."
  fi
  ok "secrets"
}

print_installation_info() {
  header "Cluster Installation ($NAMESPACE)"

  local identity_username=$(kubectl get secrets/identity-backend -n $NAMESPACE \
    --template='{{ index .data "default-user-username" }}' | base64 -d || echo "")
  if [ -z "${identity_username}" ] ; then
    fatal "Failed to retrieve default user's username"
  fi

  local identity_password=$(kubectl get secrets/identity-backend -n $NAMESPACE \
    --template='{{ index .data "default-user-password" }}' | base64 -d || echo "")
  if [ -z "${identity_password}" ] ; then
    fatal "Failed to retrieve default user's password"
  fi

  local keycloak_username=$(kubectl get secrets/keycloak -n $NAMESPACE \
    --template='{{ index .data "username" }}' | base64 -d || echo "")
  if [ -z "${keycloak_username}" ] ; then
    fatal "Failed to retrieve Keycloak admin username"
  fi

  local keycloak_password=$(kubectl get secrets/keycloak -n $NAMESPACE \
    --template='{{ index .data "password" }}' | base64 -d || echo "")
  if [ -z "${keycloak_password}" ] ; then
    fatal "Failed to retrieve Keycloak admin password"
  fi

  local minio_username=$(kubectl get secrets/minio -n $NAMESPACE \
    --template='{{ index .data "accesskey" }}' | base64 -d || echo "")
  if [ -z "${minio_username}" ] ; then
    fatal "Failed to retrieve MinIO username"
  fi

  local minio_password=$(kubectl get secrets/minio -n $NAMESPACE \
    --template='{{ index .data "secretkey" }}' | base64 -d || echo "")
  if [ -z "${minio_password}" ] ; then
    fatal "Failed to retrieve MinIO password"
  fi

  local postgresql_username=$(kubectl get secrets/postgresql -n $NAMESPACE \
    --template='{{ index .data "username" }}' | base64 -d || echo "")
  if [ -z "${postgresql_username}" ] ; then
    fatal "Failed to retrieve PostgreSQL username"
  fi

  local postgresql_password=$(kubectl get secrets/postgresql -n $NAMESPACE \
    --template='{{ index .data "password" }}' | base64 -d || echo "")
  if [ -z "${postgresql_password}" ] ; then
    fatal "Failed to retrieve PostgreSQL password"
  fi

  local protocol=https
  if ! $SECURE; then
      protocol=http
  fi

  local webconsole=$(kubectl get virtualservice \
    --namespace $NAMESPACE enterprise-console-web --output=jsonpath='{.spec.hosts[0]}' || echo "")
  if [ -z "${webconsole}" ] ; then
    fatal "Failed to retrieve web console hostname"
  fi

  if $OBSERVABILITY; then
    local grafana_username=$(kubectl get secrets/grafana -n $NAMESPACE \
      --template='{{ index .data "admin-user" }}' | base64 -d || echo "")
    if [ -z "${grafana_username}" ] ; then
      fatal "Failed to retrieve Grafana admin username"
    fi

    local grafana_password=$(kubectl get secrets/grafana -n $NAMESPACE \
      --template='{{ index .data "admin-password" }}' | base64 -d || echo "")
    if [ -z "${grafana_password}" ] ; then
      fatal "Failed to retrieve Grafana admin password"
    fi
  fi

  echo ""
  echo "Enterprise Web:"
  echo "--------------"
  yellow "${protocol}://${webconsole}/"
  echo ""
  yellow "Username: ${identity_username}\nPassword: ${identity_password}"
  echo ""
  echo "Keycloak:"
  echo "---------"
  yellow "${protocol}://${webconsole}/auth/"
  echo ""
  yellow "Username: ${keycloak_username}\nPassword: ${keycloak_password}"
  echo ""
  echo "MinIO:"
  echo "------"
  yellow "kubectl -n ${NAMESPACE} port-forward svc/minio 8082:81"
  yellow "http://127.0.0.1:8082/"
  echo ""
  yellow "Username: ${minio_username}\nPassword: ${minio_password}"
  echo ""
  echo "PostgreSQL:"
  echo "------"
  yellow "kubectl -n ${NAMESPACE} port-forward svc/postgresql 5432:5432"
  yellow "psql -h 127.0.0.1 -p 5432 -U ${postgresql_username} -W"
  echo ""
  yellow "Username: ${postgresql_username}\nPassword: ${postgresql_password}"
  if $OBSERVABILITY; then
    echo ""
    echo "Grafana:"
    echo "---------"
    yellow "kubectl -n ${NAMESPACE} port-forward svc/grafana 8080:80"
    yellow "http://127.0.0.1:8080/"
    echo ""
    yellow "Username: ${grafana_username}\nPassword: ${grafana_password}"
    echo ""
    echo "Prometheus:"
    echo "---------"
    yellow "kubectl -n ${NAMESPACE} port-forward svc/prometheus-server 8081:80"
    yellow "http://127.0.0.1:8081/"
  fi
  echo ""
  echo "Network:"
  echo "--------"
  yellow "$(kubectl get services -A --selector=istio=ingressgateway)"
  echo ""
}

list_charts() {
  local charts=()

  for dir in "$CHART_DIR"/*; do
    if [ -d "$dir" ]; then
      if [ -f "$dir/Chart.yaml" ]; then
        charts+=("${dir##*/chart/}")
      fi
    fi
  done

  echo "${charts[@]}"
}

prioritize_and_filter_charts() {
  local remaining_charts=("$@")

  for service_chart in "${SERVICE_CHARTS[@]}"; do
    for chart in "${remaining_charts[@]}"; do
      if [ "$chart" == "$service_chart" ]; then
        remaining_charts=("${remaining_charts[@]/$service_chart}")
      fi
    done
  done

  for observability_chart in "${OBSERVABILITY_CHARTS[@]}"; do
    for chart in "${remaining_charts[@]}"; do
      if [ "$chart" == "$observability_chart" ]; then
        remaining_charts=("${remaining_charts[@]/$observability_chart}")
      fi
    done
  done

  for priority_chart in "${PRIORITY_CHARTS[@]}"; do
    for chart in "${remaining_charts[@]}"; do
      if [ "$chart" == "$priority_chart" ]; then
        remaining_charts=("${remaining_charts[@]/$priority_chart}")
      fi
    done
  done

  echo "${remaining_charts[@]}"
}

docker_update() {
  local images=()
  if ! $CHARTS_SET; then
    for chart in "${SERVICE_CHARTS[@]}"; do
      local chart_images=$(helm template "$CHART_DIR/$chart" $HELM_PARAMS | grep image: | sed -e 's/[ ]*image:[ ]*//' -e 's/"//g' | sort -u)
      for chart_image in "${chart_images[@]}"; do
        local found=false
        for image in "${images[@]+"${images[@]}"}"; do
          if [ "$image" == "$chart_image" ]; then
            $found=true
            break
          fi
        done
        if ! $found ; then
          images+=("${chart_image}")
        fi
      done
    done

    if $OBSERVABILITY; then
      for chart in "${OBSERVABILITY_CHARTS[@]}"; do
        local chart_images=$(helm template "$CHART_DIR/$chart" $HELM_PARAMS | grep image: | sed -e 's/[ ]*image:[ ]*//' -e 's/"//g' | sort -u)
        for chart_image in "${chart_images[@]}"; do
          local found=false
          for image in "${images[@]+"${images[@]}"}"; do
            if [ "$image" == "$chart_image" ]; then
              $found=true
              break
            fi
          done
          if ! $found ; then
            images+=("${chart_image}")
          fi
        done
      done
    fi

    for chart in "${PRIORITY_CHARTS[@]}"; do
      local chart_images=$(helm template "$CHART_DIR/$chart" $HELM_PARAMS | grep image: | sed -e 's/[ ]*image:[ ]*//' -e 's/"//g' | sort -u)
      for chart_image in "${chart_images[@]}"; do
        local found=false
        for image in "${images[@]+"${images[@]}"}"; do
          if [ "$image" == "$chart_image" ]; then
            $found=true
            break
          fi
        done
        if ! $found ; then
          images+=("${chart_image}")
        fi
      done
    done
  fi

  for chart in "${CHARTS[@]}"; do
    local chart_images=$(helm template "$CHART_DIR/$chart" $HELM_PARAMS | grep image: | sed -e 's/[ ]*image:[ ]*//' -e 's/"//g' | sort -u)
    for chart_image in "${chart_images[@]}"; do
      local found=false
      for image in "${images[@]+"${images[@]}"}"; do
        if [ "$image" == "$chart_image" ]; then
          $found=true
          break
        fi
      done
      if ! $found ; then
        images+=("${chart_image}")
      fi
    done
  done

  IFS=$'\n' unique_images=($(sort -u <<< "${images[*]}"))
  unset IFS
  for image in ${unique_images[@]}; do
    silent docker pull "$image"
    ok "$image"
  done
}

install_chart() {
  local chart=$1
  local wait=
  [[ $# -gt 1 ]] && wait=$2
  local images;

  if [ ! "$(ls -A $CHART_DIR/$chart/charts/)" ] || $UPDATE_HELM ; then
    rm -f "$CHART_DIR/$chart"/charts/*.tgz
    rm -rf "$CHART_DIR/$chart"/tmpcharts
    silent helm dep update --skip-refresh "$CHART_DIR/$chart"
  fi

  # shellcheck disable=SC2086
  silent helm upgrade --timeout 10m --install --atomic --wait \
    --namespace "$NAMESPACE" \
    $($DEBUG && echo "--debug") \
    $($DRY_RUN && echo "--dry-run") \
    $(! $SECURE && echo "--set global.domainProtocol=http,global.domainPort=80,global.mqttProtocol=tcp,global.mqttPort=1883,global.istio.gateway.ports.http=80,global.istio.gateway.ports.mqtt=1883") \
    "$chart" "$CHART_DIR/$chart" $HELM_PARAMS

  local stdout=$(cat $CHART_DIR/$chart/Chart.yaml | grep "appVersion:" | sed -e 's/appVersion: /v/')
  if $UPDATE_HELM; then
    ok "[chart updated] ${chart} ${stdout}"
  else
    ok "${chart} ${stdout}"
  fi
}

trap 'fatal "$0 failed at line $LINENO"' ERR

show_usage() {
  cat <<EOF
$BUNDLE_NAME/$SCRIPT_NAME $VERSION
usage: $SCRIPT_NAME [OPTION]...

Installs the charts for $BUNDLE_NAME.

Single argument options (and flags, as flags are handled as boolean single arg options)
can also be passed via environment variables by using
the ALL_CAPS name. Options specified via flags take precedence over environment
variables.

OPTIONAL:
  --charts <NAME>,<NAME>  Optionally install/update only the provided chart names
                          This is a comma separated list of names
                          (no whitespace allowed).
                          By default, all charts will be installed/updated.
  --namespace <NAMESPACE> The name of the kubernetes namespace to install/update
                          the bundled charts (default: arcloud).
                          By default, "default" is used.
  --set <KEY>=<VALUE>     Helm set values on the command line
                          (can specify multiple, e.g. --set k1=v1 --set k2=v2 ...)
  --values <PATH>         Helm specify values in a YAML file or a URL
                          (can specify multiple, e.g. --values p1 --values p2)

FLAGS:
  --accept-sla            Inidcate acceptance of the SLA at:
                          https://www.magicleap.com/software-license-agreement-ml2
                          By default, the SLA is not accepted, and the installation
                          cannot proceed.
  --debug                 Enable Helm verbose output (defaults is not to use verbose output)
  --installation-info     Display information about the cluster installation if system is up and running
  --dry-run               Print commands instead of running them
  -h|--help               Print this message
  --minimal               Minimal installation
  --no-check-dependencies Disable check of local and remote pre-requisites before running installations
  --no-observability      Disable observability charts installation
  --no-parallel           Disable parallel chart installation
  --no-secure             Use insecure http and mqtt installation options
  --update-docker         Update the docker image (and roll the pods)
  --update-helm           Update helm chart
  -v|--verbose            Verbose output (debug traces)
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --accept-sla )
        ACCEPT_SLA=true
        shift
        ;;
      --charts )
        CHARTS_SET=true
        arg_required "${@}"
        IFS=',' read -r -a CHARTS <<< "$2"
        unset IFS
        shift 2
        ;;
      --debug )
        DEBUG=true
        shift
        ;;
      --dry-run )
        DRY_RUN=true
        shift
        ;;
      -h | --help )
        show_usage
        exit 0
        ;;
      --minimal )
        MINIMAL=true
        shift
        ;;
      --namespace)
        arg_required "${@}"
        NAMESPACE="$2"
        shift 2
        ;;
      --no-observability )
        OBSERVABILITY=false
        shift
        ;;
      --no-parallel )
        PARALLEL=false
        shift
        ;;
      --no-secure )
        SECURE=false
        shift
        ;;
      --installation-info )
        PRINT_INSTALLATION_INFO=true
        shift
        ;;
      --set )
        arg_required "${@}"
        if [[ ! "$2" =~ ^[^=]+=.*$ ]]; then
          exit_usage "expected <KEY>=<VALUE> as argument to --set, but found $2"
        fi
        SETS+=("$2")
        shift 2
        ;;
      --update-docker )
        UPDATE_DOCKER=true
        shift
        ;;
      --update-helm )
        UPDATE_HELM=true
        shift
        ;;
      --no-check-dependencies )
        CHECK_DEPENDENCIES=false
        shift
        ;;
      --values )
        arg_required "${@}"
        if [[ ! -f "$2" ]]; then
          exit_usage "$2 is not a valid file. Each --values argument must be."
        fi
        VALUES+=("$2")
        shift 2
        ;;
      -v | --verbose )
        VERBOSE=true
        shift
        ;;
      * )
        exit_usage "Unrecognized option '${1}'"
        ;;
    esac
  done

  if ! $CHARTS_SET; then
    # shellcheck disable=SC2046
    for chart in $(prioritize_and_filter_charts $(list_charts)); do CHARTS+=("$chart"); done
  fi

  HELM_PARAMS="-f $HOME_DIR/values.yaml"
  if $OBSERVABILITY; then
    HELM_PARAMS="$HELM_PARAMS -f $HOME_DIR/values-observability.yaml"
  fi
  if [[ ${#VALUES[@]} -gt 0 ]]; then
    for values in "${VALUES[@]}"; do
      HELM_PARAMS="$HELM_PARAMS --values $values"
    done
  fi
  HELM_PARAMS="$HELM_PARAMS --set global.namespace=$NAMESPACE"
  if [[ ${#SETS[@]} -gt 0 ]]; then
    for setting in "${SETS[@]}"; do
      HELM_PARAMS="$HELM_PARAMS --set $setting"
    done
  fi

  readonly VERBOSE
  readonly ACCEPT_SLA
  readonly DRY_RUN
  readonly DEBUG
  readonly CHARTS
  readonly CHECK_DEPENDENCIES
  readonly REGISTRY_SECRET
  readonly VALUES
  readonly SETS
  readonly MINIMAL
  readonly NAMESPACE
  readonly OBSERVABILITY
  readonly PARALLEL
  readonly PRINT_INSTALLATION_INFO
  readonly SECURE
  readonly UPDATE_DOCKER
  readonly UPDATE_HELM
  readonly HELM_PARAMS

  if $VERBOSE; then
    debug "VERSION: $VERSION"
    debug "ACCEPT_SLA: $ACCEPT_SLA"
    debug "HOME_DIR: $HOME_DIR"
    debug "BUNDLE_NAME: $BUNDLE_NAME"
    debug "SCRIPT_NAME: $SCRIPT_NAME"
    debug "CHART_DIR: $CHART_DIR"
    debug "CHECK_DEPENDENCIES: $CHECK_DEPENDENCIES"
    debug "REGISTRY_SECRET: $REGISTRY_SECRET"
    debug "VERBOSE: $VERBOSE"
    debug "DRY_RUN: $DRY_RUN"
    debug "DEBUG: $DEBUG"
    if [[ ${#CHARTS[@]} -gt 0 ]]; then debug "CHARTS (${#CHARTS[@]}): ${CHARTS[*]}"; else debug "no CHARTS"; fi
    if [[ ${#VALUES[@]} -gt 0 ]]; then debug "VALUES (${#VALUES[@]}): ${VALUES[*]}"; else debug "no VALUES"; fi
    if [[ ${#SETS[@]} -gt 0 ]]; then debug "SETS (${#SETS[@]}): ${SETS[*]}"; else debug "no SETS"; fi
    debug "MINIMAL: $MINIMAL"
    debug "NAMESPACE: $NAMESPACE"
    debug "OBSERVABILITY: $OBSERVABILITY"
    debug "PARALLEL: $PARALLEL"
    debug "PRINT_INSTALLATION_INFO: $PRINT_INSTALLATION_INFO"
    debug "SECURE: $SECURE"
    debug "UPDATE_DOCKER: $UPDATE_DOCKER"
    debug "UPDATE_HELM: $UPDATE_HELM"
  fi

  if [ "$ACCEPT_SLA" != "true" ] && [ "$ACCEPT_SLA" != "yes" ] && [ "$ACCEPT_SLA" != "y" ] && [ "$ACCEPT_SLA" != "1" ]; then
    default "Pass the --accept-sla flag to indicate your acceptance of the SLA."
    default "You can review the SLA at: https://www.magicleap.com/software-license-agreement-ml2"
    exit 1
  fi
}

#
# MAIN SCRIPT
#
parse_args "$@"

assert_commands_exist helm kubectl

if $UPDATE_DOCKER; then
  assert_commands_exist docker
fi

if $PRINT_INSTALLATION_INFO; then
  print_installation_info
  exit 0
fi

if $CHECK_DEPENDENCIES; then
  header "Checking versioned dependencies"
  verify_helm ${HELM_DEP[@]}
  verify_kubectl ${KUBECTL_DEP[@]}
  verify_istio ${ISTIO_DEP[@]}
  check_cluster_resources
fi

if $UPDATE_DOCKER; then
  header "Updating docker containers"
  docker_update
fi

header "Installing Helm charts"

if ! $CHARTS_SET; then
  for chart in "${SERVICE_CHARTS[@]}"; do
    if ${PARALLEL}; then install_chart "${chart}" & else install_chart "${chart}"; fi
  done

  if ${PARALLEL}; then
    FAIL=0

    for job in $(jobs -p); do
      wait $job || let "FAIL+=1"
    done

    if [ "$FAIL" != "0" ]; then
      echo "ERROR: Chart installation failed, will not continue";
      exit 1
    fi
  fi

  if $OBSERVABILITY; then
    for chart in "${OBSERVABILITY_CHARTS[@]}"; do
      install_chart "${chart}"
    done
  fi

  for chart in "${PRIORITY_CHARTS[@]}"; do
    install_chart "${chart}"
  done
fi

for chart in "${CHARTS[@]}"; do
  if ${PARALLEL}; then install_chart "${chart}" & else install_chart "${chart}"; fi
done

if ${PARALLEL}; then
  FAIL=0

  for job in $(jobs -p); do
    wait $job || let "FAIL+=1"
  done

  if [ "$FAIL" != "0" ]; then
    echo "ERROR: Chart installation failed, will not continue";
    exit 1
  fi
fi

if ! $DRY_RUN; then
    print_installation_info
fi
