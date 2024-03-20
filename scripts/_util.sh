#!/usr/bin/env bash

# see https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
set -eu
set -o pipefail


#
# GLOBAL VARS
#
readonly UTIL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
readonly HOME_DIR="$( cd "$UTIL_DIR/.." >/dev/null && pwd )"
readonly BUNDLE_NAME=$(basename "$HOME_DIR")


#
# DEFAULT VARS
#
VERBOSE=${VERBOSE:=false}
DEBUG=${DEBUG:=false}


#
# UTILITY FUNCTIONS - Helpers to format stdout and validations
#
timestamp() { date +"%Y/%m/%d %T"; }
timestamp_safe() { date +"%Y%m%dT%H%M%S%Z"; }
red() { echo -e "\033[31m${1}\033[0m" 1>&2; }
green() { echo -e "\033[32m${1}\033[0m" 1>&2; }
yellow() { echo -e "\033[33m${1}\033[0m" 1>&2;  }
blue() { echo -e "\033[34m${1}\033[0m" 1>&2;  }
default() { echo -e "${1}" 1>&2;  }
warn() { yellow "$(timestamp) WARNING - $1";  }
error() { red "$(timestamp) ERROR - $1";  }
info() { default "$(timestamp) INFO - $1"; }
ok() { green "$(timestamp) OK - $1"; }
fatal() { error "$1" && exit 1; }
sep() { echo "-------------------------" 1>&2; }
version() { echo "$1" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }

debug() {
  if $VERBOSE; then
    blue "$(timestamp) DEBUG - $1"
  fi
}

check_dependency() {
  if ! command -v $2 &>/dev/null; then
    fatal "$1 not found"
  fi
}

check_version() {
  if [[ $(version $2) -ge $(version $3) ]]; then
    ok "$1 v$2"
  else
    fatal "$1 version should be >= $3, but got $2. Please visit $4"
  fi
}

check_version_range() {
  if [ $(version $2) -ge $(version $3) ] && [ $(version $2) -le $(version $4) ]; then
    ok "$1 v$2"
  else
    fatal "$1 version should be >= $3 and <= $4, but got $2. Please visit $5"
  fi
}

check_version_exception() {
  if [ $(version $2) -ne $(version $3) ]; then
    ok "$1 v$2"
  else
    fatal "$1 version cannot be == $3. Please visit $4"
  fi
}

repeat(){
  local start=1
  local end=${1:-80}
  local str="${2:-=}"
  for i in $(seq $start $end) ; do
    echo -n "${str}"
  done
}

header() {
  local str="$1"
  local len="${#str}"
  echo ""
  repeat $len '-'; echo -e "\n$str"
  repeat $len '-'; echo
}

prompt_to_continue_or_quit() {
    while true; do
        read -rsp $'Press "Y" to continue or "q" to exit...\n' -n1 key
        case "$key" in
            [Yy]) 
                echo "Continuing..."
                break
                ;;
            [Qq])
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid input. Please press 'Y' to continue or 'q' to quit."
                ;;
        esac
    done
}

verify_helm() {
  local -r name=$1
  local -r command=$2
  local -r required_version=$3
  local -r vendor_url=$4
  check_dependency $name $command
  local actual_version=$(eval helm version --template='{{.Version}}' | sed 's/v//')
  if [ -z "$actual_version" ]; then
    actual_version="no verison"
  fi
  check_version "$command (client)" "$actual_version" "$required_version" "$vendor_url"
  # Issue: Helm 3.13[.0] is not backward compatible with 3.12 (resolved in 3.13.1)
  # https://github.com/helm/helm/issues/12460
  check_version_exception "$command (client != 3.13.0)" "$actual_version" "3.13.0" "$vendor_url"
}

verify_istio() {
  local -r name=$1
  local -r command=$2
  local -r required_version=$3
  local -r vendor_url=$4
  check_dependency $name "kubectl"
  local actual_version=$(kubectl -n istio-system describe deployment istiod | grep Image: | sed 's/.*Image:.*pilot://')
  if [ -z "$actual_version" ]; then
    actual_version="no verison"
  fi
  check_version "$command (server)" "$actual_version" "$required_version" "$vendor_url"
}

verify_kubectl() {
  local -r name=$1
  local -r command=$2
  local -r required_version=$3
  local -r vendor_url=$4
  check_dependency $name $command
  local actual_version=$(eval kubectl version --client -oyaml | grep "gitVersion" | sed 's/.*gitVersion: v//')
  if [ -z "$actual_version" ]; then
    actual_version="no verison"
  fi
  check_version "$command (client)" "$actual_version" "$required_version" "$vendor_url"
  local actual_version=$(eval kubectl version -oyaml | sed -n '/^serverVersion:/,$p' | grep "gitVersion" | sed 's/.*gitVersion: v//')
  if [ -z "$actual_version" ]; then
    actual_version="no verison"
  fi
  check_version "$command (server)" "$actual_version" "$required_version" "$vendor_url"
}

check_deployments() {
  if [ "$#" -ne 2 ]; then
    fatal "syntax: check_deployments <namespace> <expected num of deployments>"
  fi

  local -r namespace=$1
  local -r expected=$2
  local -r deployment_count=$(kubectl get deployments -n "$namespace" --no-headers | wc -l)

  if [ "$deployment_count" -lt $expected ]; then
      return 1
  fi

  return 0
}

assert_command_exist() {
  if [ "$#" -ne 2 ]; then
    fatal "syntax: assert_command_exist <command> <message>"
  fi

  if command -v "$1" > /dev/null 2>&1; then
    return 0
  fi

  warn "$1 is NOT installed: $2"
  return 1
}

print_function_body() {
 if [ "$#" -ne 1 ]; then
   fatal "syntax: print_function_body <function>"
 fi

 declare -f $1 | tail -n +3 | sed '$d'
}

exit_usage() {
  [[ $# -gt 0 ]] && {
    error "$1"
  }
  show_usage
  exit 2
}

arg_required() {
  if [[ ! "${2:-}" || "${2:0:1}" = '-' ]]; then
    exit_usage "Option ${1} requires an argument."
  fi
}

assert_commands_exist() {
  for cmd in "$@"; do
    command -v "$cmd" &> /dev/null || fatal "Missing required executable: $cmd. Please install it and try again."
  done
}

silent() { if $DEBUG || $VERBOSE; then $*; else $* >/dev/null; fi }

install_dependency() {
  if [ "$#" -ne 4 ]; then
    fatal "syntax: install_dependency <auto-install> <prompt-for-install> <function>"
  fi

  local -r auto_install=$1
  local -r prompt_for_install=$2
  local -r more_info=$4

  # print instructions and prompt
  if [[ "$auto_install" == "false" && "$prompt_for_install" == "true" ]]; then
    info "The following commands will be executed:"
    echo ""
    print_function_body $3
    echo ""
    echo "$more_info"
    echo ""
    prompt_to_continue_or_quit
    $3
  fi

  # print instructions and exit
  if [[ "$auto_install" == "false" && "$prompt_for_install" == "false" ]]; then
    echo ""
    print_function_body $3
    echo ""
    exit 1
  fi

  # print instructions and install
  if [[ "$auto_install" == "true" && "$prompt_for_install" == "false" ]]; then
    echo "The following commands will be executed automatically:"
    echo ""
    print_function_body $3
    echo ""
    $3
  fi

  # fail
  if [[ "$auto_install" == "true" && "$prompt_for_install" == "true" ]]; then
    fatal "'disable prompt (--no-prompt) when using --auto-install"
  fi
}
