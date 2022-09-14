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
  if [ $(version $2) -ge $(version $3) ]; then
    ok "$1 v$2"
  else
    fatal "$1 version should be >= $3, but got $2. Please visit $4"
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

verify_helm() {
  local name=$1
  local command=$2
  local required_version=$3
  local vendor_url=$4
  check_dependency $name $command
  local actual_version=$(eval helm version --template='{{.Version}}' | sed 's/v//')
  check_version "$command" "$actual_version" "$required_version" "$vendor_url"
}

verify_istio() {
  local name=$1
  local command=$2
  local required_version=$3
  local vendor_url=$4
  check_dependency $name "kubectl"
  local actual_version=$(kubectl -n istio-system describe deployment istiod | grep Image: | sed 's/.*Image:.*pilot://')
  check_version "$command (server)" "$actual_version" "$required_version" "$vendor_url"
}

verify_kubectl() {
  local name=$1
  local command=$2
  local required_version=$3
  local vendor_url=$4
  check_dependency $name $command
  local actual_version=$(eval kubectl version --client -oyaml | grep "gitVersion" | sed 's/.*gitVersion: v//')
  check_version "$command (client)" "$actual_version" "$required_version" "$vendor_url"
  local actual_version=$(eval kubectl version -oyaml | sed -n '/^serverVersion:/,$p' | grep "gitVersion" | sed 's/.*gitVersion: v//')
  check_version "$command (server)" "$actual_version" "$required_version" "$vendor_url"
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
