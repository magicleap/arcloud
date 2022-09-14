#!/usr/bin/env bash

# see https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
set -eu
set -o pipefail

readonly HOME_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
readonly FIX_START_SCRIPT="fix-cold-start.sh"
readonly FIX_SYSTEMD_SERVICE="arcloud-fix-cold-start.service"

NAMESPACE=${NAMESPACE:=arcloud}

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

show_usage() {
    cat <<EOF
$SCRIPT_NAME $VERSION
usage: $SCRIPT_NAME [OPTION]...

Create a systemd service to fix cold start

Single argument options (and flags, as flags are handled as boolean single arg options)
can also be passed via environment variables by using
the ALL_CAPS name. Options specified via flags take precedence over environment
variables.

OPTIONAL:
  --namespace <NAMESPACE> The name of the kubernetes namespace to restart
                          the bundled charts.
                          By default, "arcloud" is used.

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
      * )
        exit_usage "Unrecognized option '${1}'"
        ;;
    esac
  done

  readonly NAMESPACE
}

trap 'fatal "$0 failed at line $LINENO"' ERR

parse_args "$@"

# if not root
SUDO=sudo
if [ $(id -u) -eq 0 ]; then
   SUDO=
fi

$SUDO rm -f "/usr/local/bin/${FIX_START_SCRIPT}"
$SUDO cp "$HOME_DIR/${FIX_START_SCRIPT}" "/usr/local/bin/${FIX_START_SCRIPT}"

$SUDO rm -f "/etc/systemd/system/${FIX_SYSTEMD_SERVICE}"
$SUDO tee "/etc/systemd/system/${FIX_SYSTEMD_SERVICE}" >/dev/null << EOF
[Unit]
Description="Fix AR Cloud cold start Kubernetes cluster"
After=k3s.service

StartLimitIntervalSec=600
StartLimitBurst=5

[Service]
User=root
Restart=on-failure
ExecStart=/bin/bash /usr/local/bin/${FIX_START_SCRIPT} --namespace ${NAMESPACE}

[Install]
WantedBy=multi-user.target
EOF

$SUDO systemctl daemon-reload
$SUDO systemctl enable $FIX_SYSTEMD_SERVICE
$SUDO systemctl daemon-reload
echo "Service created"
