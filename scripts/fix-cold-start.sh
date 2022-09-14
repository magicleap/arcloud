#!/usr/bin/env bash

# see https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
set -eu
set -o pipefail

# global vars
readonly VERSION="0.1.1"
readonly SCRIPT_NAME=${0##*/}

VERBOSE=${VERBOSE:=false}
NAMESPACE=${NAMESPACE:=arcloud}
TIMEOUT=${TIMEOUT:=5m}

# print functions : helpers to format info and error messages
timestamp() { date +"%Y/%m/%d %T"; }
red() { echo -e "\033[31m${1}\033[0m" 1>&2; }
green() { echo -e "\033[32m${1}\033[0m" 1>&2; }
yellow() { echo -e "\033[33m${1}\033[0m" 1>&2;  }
blue() { echo -e "\033[34m${1}\033[0m" 1>&2;  }
default() { echo -e "${1}" 1>&2;  }
warn() { yellow "$(timestamp) WARNING - $1";  }
error() { red "$(timestamp) ERROR - $1";  }
info() { default "$(timestamp) INFO - $1"; }
ok() { green "$(timestamp) OK - $1"; }
debug() {
  if $VERBOSE; then
    blue "$(timestamp) DEBUG - $1"
  fi
}
fatal() { error "$1" && exit 1; }
sep() { echo "-------------------------" 1>&2; }

trap 'fatal "$0 failed at line $LINENO"' ERR

# more utility functions
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

# script-specific functions
show_usage() {
    cat <<EOF
$SCRIPT_NAME $VERSION
usage: $SCRIPT_NAME [OPTION]...

Restart the charts to fix cold startup order.

Single argument options (and flags, as flags are handled as boolean single arg options)
can also be passed via environment variables by using
the ALL_CAPS name. Options specified via flags take precedence over environment
variables.

OPTIONAL:
  --namespace <NAMESPACE> The name of the kubernetes namespace to restart
                          the bundled charts.
                          By default, "default" is used.
  --timeout <TIMEOUT>     Global duration before kubernetes command times out (defaut: 5m)

FLAGS:
  -h|--help       Print this message
  -v|--verbose    Verbose output (debug traces)
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      -h | --help )
        show_usage
        exit 0
        ;;
      --namespace)
        arg_required "${@}"
        NAMESPACE="$2"
        shift 2
        ;;
      --timeout)
        arg_required "${@}"
        TIMEOUT="$2"
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

  readonly NAMESPACE
  readonly VERBOSE

  if $VERBOSE; then
    debug "VERSION: $VERSION"
    debug "NAMESPACE: $NAMESPACE"
    debug "TIMEOUT: $TIMEOUT"
    debug "VERBOSE: $VERBOSE"
  fi
}

# begin main script
##############
assert_commands_exist kubectl

parse_args "$@"

kubectl -n ${NAMESPACE} rollout restart statefulset keycloak
kubectl -n ${NAMESPACE} rollout status statefulset keycloak --timeout ${TIMEOUT}

# Restart Istiod to pick up Keycloak JWKS
kubectl -n istio-system rollout restart deployment/istiod
kubectl -n istio-system rollout status deployment/istiod --timeout ${TIMEOUT}

kubectl -n ${NAMESPACE} rollout restart deployment opa-istio-device
kubectl -n ${NAMESPACE} rollout status deployment opa-istio-device --timeout ${TIMEOUT}

kubectl -n ${NAMESPACE} rollout restart deployment device-gateway
kubectl -n ${NAMESPACE} rollout status deployment device-gateway --timeout ${TIMEOUT}

# Restart Istio to pickup Keycloak & Device-Gateway JWKS
kubectl -n istio-system rollout restart deployment/istiod
kubectl -n istio-system rollout status deployment/istiod --timeout ${TIMEOUT}

ok "DONE ✅\n"
