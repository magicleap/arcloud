#!/bin/bash

# see https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
set -eu
set -o pipefail

readonly SCRIPTS_DIR="$( cd "$( dirname "$0" )" >/dev/null && pwd )"
. "$SCRIPTS_DIR/_util.sh" || { 1>&2 echo "ERROR!!! failed to source $SCRIPTS_DIR/_util.sh. (Please fix the path.) Exiting."; exit 1; }

readonly VERSION=0.0.1
readonly CLIENT_ID=com.magicleap.web.enterpriseportal
readonly PATH_PREFIX=${PATH_PREFIX:=/api/licensing/}
readonly REALM=magicleap
readonly SCOPE=email
readonly SCRIPT_NAME=${0##*/}

ACCESS_TOKEN=${ACCESS_TOKEN:=}
ACTIVE=${ACTIVE:=}
ARCLOUD_URL=${ARCLOUD_URL:=}
COMMAND=""
CURL_INSECURE=${CURL_INSECURE:=}
CURL_INSECURE="$(echo "$CURL_INSECURE" | tr '[:upper:]' '[:lower:]')"
case "$CURL_INSECURE" in
  true | t | yes | y | 1 )
    CURL_INSECURE=true
    ;;
  false | f | no | n | 0 )
    CURL_INSECURE=false
    ;;
  "" )
    CURL_INSECURE=false
    ;;
  * )
    fatal "cannot parse boolean value of '$CURL_INSECURE' for CURL_INSECURE"
    ;;
esac
LICENSE_KEY=""
IN=${IN:=}
OUT=${OUT:=}

show_usage() {
    cat <<EOF
$SCRIPT_NAME $VERSION
usage: $SCRIPT_NAME <COMMAND> [OPTION]...

Configure & manage the license for an instance of AR Cloud,
such as configuring the license key or activating/deactivating the license
for the cloud instance.

The available/applicable commands depend on whether the AR Cloud instance is configured
to be in online mode or offline mode, which is configured via the helm (boolean) value 'global.offline'.
For example, one way to configure the instance for online mode would be to pass the option
"--set global.offline=false" to the setup.sh script.
Online mode allows the cluster to make network calls across the internet to the applicable license vendor
(namely LicenseSpring. See https://licensespring.com) automatically to perform certain activities,
such as license activation/deactivation and checks.
Offline mode prevents the cluster from making any such network calls, but requires manual steps of the
end-user/admin to perform the same kind of activities.

See example commands/flows in the Examples section below.

Single argument options (and flags, as flags are handled as boolean single arg options)
can also be passed via environment variables by using
the ALL_CAPS name. Options specified via flags take precedence over environment
variables.

Note the command uses the browser to authenticate with the AR Cloud instance. Follow the short interactive instructions
to authenticate, namely pasting the resulting url from the browser address bar back into the command line
(after logging in if not already logged in).

COMMANDS:
  activate                               Activates the license (if not already active) for the AR Cloud instance.
  activate-online                        (the license key must already be configured ahead of time or provided with
                                          --license-key option. see also the set-license-key command)
                                         (only valid if cluster is running in online mode, which
                                          is configured with the helm (boolean) value 'global.offline'.
                                          One way to configure for online mode would be to pass the option
                                          "--set global.offline=false" to the setup.sh script.
                                          for offline mode, i.e. global.offline=true,
                                          see the download-offline-activation-request command instead)
                                         Example usage:
                                         ARCLOUD_URL=... $0 activate
                                         # or equivalently:
                                         $0 activate --url "$ARCLOUD_URL"
                                         # or if activating and setting the license key simultaneously:
                                         ARCLOUD_URL=... $0 activate --license-key <YOUR_LICENSE_KEY>

  activation-request |                   Downloads an offline license activation request file (to stdout).
  download-activation-request |          (use the --out option to download to a file instead of stdout)
  download-offline-activation-request    Upload the file to https://saas.licensespring.com/offline, which
                                         will provide an offline license activation file that can be later uploaded
                                         to the cluster via the upload-offline-activation-file command to
                                         activate the license.
                                         (the license key must already be configured ahead of time. see the
                                          set-license-key command)
                                         (only valid if cluster is running in offline mode, which
                                          is configured with the helm (boolean) value 'global.offline'.
                                          One way to configure for offline mode would be to pass the option
                                          "--set global.offline=true" to the setup.sh script.
                                          for online mode, i.e. global.offline=false,
                                          see the activate-online command instead)
                                         Example usage:
                                         export ARCLOUD_URL=...
                                         $0 set-key <YOUR_LICENSE_KEY>
                                         $0 activation-request > activate_offline.req
                                         # or equivalently:
                                         $0 activation-request --out activate_offline.req
                                         # upload activate_offline.req to https://saas.licensespring.com/offline
                                         # in order to get activation file (usually named ls_activation.lic)
                                         # finally, upload the activation file to complete activation:
                                         cat ls_activation.lic | $0 upload-activation
                                         # or equivalently:
                                         $0 upload-activation --in ls_activation.lic

  set-key                                Configures the license key for the instance.
  set-license-key                        If in online mode (configured with the helm (boolean) value 'global.offline',
                                         e.g. sent as option to the setup.sh script as "--set global.offline=false")
                                         and the cluster is currently active with a different license, the cluster
                                         will try to automatically deactivate the old license and activate with the
                                         new one. If the license should also be activated (or to ensure that it should
                                         be activated, whether currently active or not), pass the --active==true option
                                         (only supported in online mode).
                                         If in offline mode, setting the license key is only allowed when the cluster
                                         license is currently inactive (see download-offline-deactivation-request command).
                                         (the --active option is not available in offline mode.
                                          see download-offline-activation-request command)
                                         Example usage:
                                         export ARCLOUD_URL=...
                                         $0 set-key <YOUR_LICENSE_KEY>
                                         # or to set the license key and activate it in one step (only available in online mode):
                                         $0 set-key <YOUR_LICENSE_KEY> --active true

  deactivate |                           Deactivates the license (if not already inactive) for the AR Cloud instance.
  deactivate-online                      (only valid if cluster is running in online mode, which
                                          is configured with the helm (boolean) value 'global.offline'.
                                          One way to configure for online mode would be to pass the option
                                          "--set global.offline=false" to the setup.sh script.
                                          for offline mode, i.e. global.offline=true,
                                          see the download-offline-deactivation-request command instead)
                                         Example usage:
                                         ARCLOUD_URL=... $0 deactivate
                                         # or equivalently:
                                         $0 deactivate --url "$ARCLOUD_URL"

  deactivation-request |                 Downloads an offline license deactivation request file (to stdout)
  download-deactivation-request |        to initiate deactivation
  download-offline-deactivation-request  (the AR Cloud instance will become inactive,
                                          but you still need to upload this file to
                                          https://saas.licensespring.com/offline to complete deactivation,
                                          freeing up the license).
                                         (use the --out option to download to a file instead of stdout)
                                         (only valid if cluster is running in offline mode, which
                                          is configured with the helm (boolean) value 'global.offline'.
                                          One way to configure for offline mode would be to pass the option
                                          "--set global.offline=true" to the setup.sh script.
                                          for online mode, i.e. global.offline=false,
                                          see the deactivate-online command instead)
                                         Example usage:
                                         export ARCLOUD_URL=...
                                         $0 deactivation-request > deactivate_offline.req
                                         # or equivalently:
                                         $0 deactivation-request --out deactivate_offline.req
                                         # upload deactivate_offline.req to https://saas.licensespring.com/offline
                                         # to complete deactivation

  show                                   Shows the current license state of the AR Cloud instance.
                                         Example usage:
                                         ARCLOUD_URL=... $0 show
                                         # or equivalently:
                                         $0 show --url "$ARCLOUD_URL"

  upload-activation |                    Uploads an offline license activation file (from stdin) to complete
  upload-activation-file |               offline activation.
  upload-offline-activation-file         (use the --in option to upload from a file instead of stdin)
                                         (only valid if cluster is running in offline mode, which
                                          is configured with the helm (boolean) value 'global.offline'.
                                          One way to configure for offline mode would be to pass the option
                                          "--set global.offline=true" to the setup.sh script.
                                          for online mode, i.e. global.offline=false,
                                          see the activate-online command instead)
                                         Example usage:
                                         export ARCLOUD_URL=...
                                         $0 set-key <YOUR_LICENSE_KEY>
                                         $0 activation-request > activate_offline.req
                                         # or equivalently:
                                         $0 activation-request --out activate_offline.req
                                         # upload activate_offline.req to https://saas.licensespring.com/offline
                                         # in order to get activation file (usually named ls_activation.lic)
                                         # finally, upload the activation file to complete activation:
                                         cat ls_activation.lic | $0 upload-activation
                                         # or equivalently:
                                         $0 upload-activation --in ls_activation.lic

REQUIRED:
  --url|--arcloud-url <URL>              The base url to the AR CLOUD instance to configure/manage the license,
                                         e.g. https://arcloud.at.my.company

OPTIONAL:
  --active <TRUE|FALSE>                  Ensure the license is activate or inactive. Applies to the set-license-key
                                         command (only supported for online mode).

  -i|--in <FILE>                         To upload a file by name (instead of stdin). Applies to the
                                         upload-offline-activation-file command.

  --license-key <KEY>                    To set the license key when activating the license (in online mode). Applies
                                         to the the activate-online command.

  -o|--out <FILE>                        To download a file to a specific location (instead of stdout).
                                         Applies to the download-offline-activation-request
                                         and download-offline-deactivation-request commands

FLAGS:
  --curl-insecure                        Use the "--insecure" flag with curl commands to avoid TLS/SSL cert verification
                                         issues for certain environments (generally not recommended,
                                         but can work around some headaches if necessary)

  -h|--help                              Print this message

  -v|--verbose                           Verbose output (debug traces)

Examples:
# NOTE that all the examples below assume the environment variable ARCLOUD_URL has been exported...
export ARCLOUD_URL=https://my.arcloud.instance.com

# get the state of the license (assuming ARCLOUD_URL exported):
$0 show

# activate the license in online mode (assuming ARCLOUD_URL exported):
$0 activate --license-key <YOUR_LICENSE_KEY>

# activate the license in offline mode (assuming ARCLOUD_URL exported):
$0 set-key <YOUR_LICENSE_KEY>
$0 activation-request > activate_offline.req
# upload activate_offline.req to https://saas.licensespring.com/offline
# to get activation file (usually named ls_activation.lic)
# then upload the activation file to complete activation:
$0 upload-activation --in ls_activation.lic

# deactivate the license in online mode (assuming ARCLOUD_URL exported):
$0 deactivate

# deactivate the license in offline mode (assuming ARCLOUD_URL exported):
$0 deactivation-request > deactivate_offline.req
# upload deactivate_offline.req to https://saas.licensespring.com/offline to complete deactivation

EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --active )
        arg_required "${@}"
        ACTIVE="$2"
        shift 2
        ;;
      --curl-insecure )
        CURL_INSECURE=true
        shift
        ;;
      -h | --help )
        show_usage
        exit 0
        ;;
      -i | --in )
        arg_required "${@}"
        IN="$2"
        shift 2
        ;;
      --license-key )
        arg_required "${@}"
        LICENSE_KEY="$2"
        shift 2
        ;;
      -o | --out )
        arg_required "${@}"
        OUT="$2"
        shift 2
        ;;
      --url | --arcloud-url )
        arg_required "${@}"
        ARCLOUD_URL="$2"
        shift 2
        ;;
      -v | --verbose )
        VERBOSE=true
        shift
        ;;
      * )
        COMMAND="$1"
        shift
        case "${COMMAND}" in
          set-key | set-license-key )
            if [[ $# -lt 1 ]]; then
              exit_usage "$COMMAND command requires an argument."
            fi
            LICENSE_KEY="$1"
            shift
            ;;
        esac
    esac
  done

  case "$ACTIVE" in
    true | t | yes | y | 1 )
      ACTIVE=true
      ;;
    false | f | no | n | 0 )
      ACTIVE=false
      ;;
    "" )
      ACTIVE=""
      ;;
    * )
      exit_usage "cannot parse boolean value of '$ACTIVE' for ACTIVE (--active option)"
      ;;
  esac

  readonly ACTIVE
  if [ -n "$ACCESS_TOKEN" ]; then
    readonly ACCESS_TOKEN
  fi
  readonly ARCLOUD_URL
  readonly COMMAND
  readonly CURL_INSECURE
  readonly IN
  readonly LICENSE_KEY
  readonly OUT
  readonly REDIRECT_URI="$ARCLOUD_URL/callback"
  readonly VERBOSE

  if $VERBOSE; then
    debug "ACTIVE: '$ACTIVE'"
    if [ -n "$ACCESS_TOKEN" ]; then
      debug "ACCESS_TOKEN: <redacted with ${#ACCESS_TOKEN} characters>"
    else
      debug "ACCESS_TOKEN: ''"
    fi
    debug "ARCLOUD_URL: '$ARCLOUD_URL'"
    debug "CLIENT_ID: '$CLIENT_ID'"
    debug "COMMAND: '$COMMAND'"
    debug "CURL_INSECURE: '$CURL_INSECURE'"
    debug "IN: '$IN'"
    if [ -n "$LICENSE_KEY" ]; then
      debug "LICENSE_KEY: <redacted with ${#LICENSE_KEY} characters>"
    else
      debug "LICENSE_KEY: ''"
    fi
    debug "OUT: '$OUT'"
    debug "PATH_PREFIX: '$PATH_PREFIX'"
    debug "REALM: '$REALM'"
    debug "REDIRECT_URI: '$REDIRECT_URI'"
    debug "SCOPE: '$SCOPE'"
    debug "SCRIPTS_DIR: '$SCRIPTS_DIR'"
    debug "SCRIPT_NAME: '$SCRIPT_NAME'"
    debug "VERBOSE: '$VERBOSE'"
    debug "VERSION: '$VERSION'"
  fi

  if [ -z "$ARCLOUD_URL" ]; then
    exit_usage "missing required arg --url (or --arcloud-url or setting the ARCLOUD_URL environment variable)"
  fi
}

parse_args "$@"

assert_commands_exist curl jq

sha256_base64() {
  local input
  readonly input="$1"

  assert_commands_exist shasum xxd

  # shasum outputs in hex and we need a base64 encoding of the binary data
  echo -n "$input" | shasum -a 256 | head -c 64 | xxd -r -p | base64 | tr '/+' '_-' | tr -d '='
}

generate_auth_url() {
  local challenge
  local challenge_s256_b64
  readonly challenge="$1"
  readonly challenge_s256_b64=$(sha256_base64 "$challenge")

  echo "$ARCLOUD_URL/auth/realms/$REALM/protocol/openid-connect/auth?grant_type=authorization_code&response_type=code&client_id=$CLIENT_ID&redirect_uri=$REDIRECT_URI&state=some_random_string&code_challenge_method=S256&code_challenge=$challenge_s256_b64&scope=$SCOPE"
}

open_url_in_browser() {
  local url
  local os
  readonly url="$1"
  readonly os=$(uname -s | tr '[:upper:]' '[:lower:]')

  case $os in
    darwin)
      open "$url"
      ;;
    linux)
      xdg-open "$url"
      ;;
    * )
      fatal "unknown/unhandled os $os"
      ;;
  esac
}

curl_fail_with_body() {
  # we would just use the --fail-with-body option of curl, but this is not available in older versions, especially
  # in environments like ubuntu (at this time).
  # thus, this function just wraps curl, fails if the response code is not >= 200 and < 300, and writes out the response,
  # failure or not (unless the curl call explicitly uses the --output|-o argument
  local output_file=""
  local output_is_temp
  local http_code
  for (( i=1; i<=$#; i++ )); do
    case "${!i}" in
      -o | --output )
        i=$((i+1))
        output_file="${!i}"
        output_is_temp=false
        ;;
    esac
  done
  if [ -z "$output_file" ]; then
    output_file=$(mktemp)
    output_is_temp=true
  fi
  readonly output_file
  readonly output_is_temp
  readonly http_code=$(curl --silent --output "$output_file" --write-out "%{http_code}" "$@")
  if [[ ${http_code} -lt 200 || ${http_code} -gt 299 ]] ; then
    >&2 cat "$output_file"
    return 22
  fi
  if $output_is_temp; then
    cat "$output_file"
    rm "$output_file"
  fi
}

get_token() {
  local code
  local challenge
  readonly code="$1"
  readonly challenge="$2"

  curl_fail_with_body -S \
    -X POST \
    "$ARCLOUD_URL/auth/realms/$REALM/protocol/openid-connect/token" \
    -d grant_type=authorization_code \
    -d "client_id=$CLIENT_ID" \
    -d "redirect_uri=$REDIRECT_URI" \
    -d "code=$code" \
    -d "code_verifier=$challenge"
}

if [ -z "$ACCESS_TOKEN" ]; then
  debug "ACCESS_TOKEN environment variable not present. Getting the token via OATH 2.0 flow with the browser..."
  # generate random challenge string (needs to be between 43 and 128 characters)
  readonly CHALLENGE=$(sha256_base64 "$RANDOM")
  debug "CHALLENGE: '$CHALLENGE'"
  readonly AUTH_URL=$(generate_auth_url "$CHALLENGE")
  debug "AUTH_URL: '$AUTH_URL'"
  open_url_in_browser "$AUTH_URL"
  default "Paste in browser: $AUTH_URL"
  echo -e -n "Paste callback URL (from resulting url in browser address bar): " 1>&2;
  read -r CALLBACK_URL
  readonly CALLBACK_URL
  debug "CALLBACK_URL: '$CALLBACK_URL'"
  readonly CODE=${CALLBACK_URL##*code=}
  debug "CODE: '$CODE'"
  token="$(get_token "$CODE" "$CHALLENGE")"
  # validate the json output...
  echo "$token" | jq > /dev/null || fatal "failed to get access token: $token"
  readonly ACCESS_TOKEN="$(echo "$token" | jq -r '.access_token // empty')"
  debug "ACCESS_TOKEN: <redacted with ${#ACCESS_TOKEN} characters>"
fi

get_license() {
  # shellcheck disable=SC2046
  curl_fail_with_body \
    $(if $CURL_INSECURE; then echo '--insecure'; fi) \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "${ARCLOUD_URL}${PATH_PREFIX}v1/license"
}

redact_license_key_in_json() {
  local info
  local license_key
  readonly info="$1"
  readonly license_key="$(echo "$info" | jq -r '.license_key // empty')"
  if [ -n "$license_key" ]; then
    echo "$info" | jq -c ".license_key=\"<redacted with ${#license_key} characters>\""
  else
    echo "$info"
  fi
}

readonly LICENSE_JSON_INFO="$(get_license)"
# validate the json output...
echo "$LICENSE_JSON_INFO" | jq > /dev/null || fatal "$LICENSE_JSON_INFO"
debug "LICENSE_JSON_INFO: '$(redact_license_key_in_json "$LICENSE_JSON_INFO")'"
if [ -z "$LICENSE_JSON_INFO" ]; then
  fatal "could not get current license output"
fi

license_key_must_be_configured() {
  local license_key
  readonly license_key="$(echo "$LICENSE_JSON_INFO" | jq -r '.license_key // empty')"
  if [ -z "$license_key" ]; then
    exit_usage "the license key must be configured to use the $COMMAND command. See the set-license-key command."
  fi
}

must_be_online_mode() {
  local alternative_command
  local online
  readonly alternative_command="$1"
  readonly online="$(echo "$LICENSE_JSON_INFO" | jq -r .online)"
  case "$online" in
    true )
      debug "verified system is in online mode"
      ;;
    false )
      exit_usage "${COMMAND} command not available in offline mode. See the $alternative_command command instead."
      ;;
    * )
      fatal "$online"
      ;;
  esac
}

must_be_offline_mode() {
  local alternative_command
  local online
  readonly alternative_command="$1"
  readonly online="$(echo "$LICENSE_JSON_INFO" | jq -r .online)"
  case "$online" in
    true )
      exit_usage "${COMMAND} command not available in online mode. See the $alternative_command command instead."
      ;;
    false )
      debug "verified system is in offline mode"
      ;;
    * )
      fatal "$online"
      ;;
  esac
}

case "${COMMAND}" in
  activate | activate-online )
    must_be_online_mode "download-offline-activation-request"
    if [ "$LICENSE_KEY" = "" ]; then
      current_license_key="$(echo "$LICENSE_JSON_INFO" | jq -r '.license_key // empty')"
      if [ -z "$current_license_key" ]; then
        exit_usage "the license key must be configured to use the $COMMAND command. Either specify it with the --license-key option or use the set-license-key command first."
      fi
      data='{"active":true}'
    else
      data="{\"active\":true,\"license_key\":\"${LICENSE_KEY}\"}"
    fi
    # shellcheck disable=SC2046
    curl_fail_with_body -X PATCH \
      $(if $CURL_INSECURE; then echo '--insecure'; fi) \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      "${ARCLOUD_URL}${PATH_PREFIX}v1/license" \
      --data "$data"
    ;;
  activation-request | download-activation-request | download-offline-activation-request )
    must_be_offline_mode "activate-online"
    license_key_must_be_configured
    # shellcheck disable=SC2046
    # shellcheck disable=SC2030
    curl_fail_with_body \
      $(if $CURL_INSECURE; then echo '--insecure'; fi) \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/octet-stream" \
      "${ARCLOUD_URL}${PATH_PREFIX}v1/offline/activation/request" \
      $(if [ -n "$OUT" ]; then echo "--output $OUT"; fi)
    ;;
  set-key | set-license-key )
    if [ "$ACTIVE" = "" ]; then
      data="{\"license_key\":\"${LICENSE_KEY}\"}"
    else
      online="$(echo "$LICENSE_JSON_INFO" | jq -r .online)"
      case "$online" in
        true )
          debug "verified system is in online mode"
          ;;
        false )
          message="the --active option is not allowed when the system is in offline mode."
          if $ACTIVE; then
            message="$message see the download-offline-activation-request command"
          else
            message="$message see the download-offline-deactivation-request command"
          fi
          exit_usage "$message"
          ;;
        * )
          fatal "$online"
          ;;
      esac
      data="{\"license_key\":\"${LICENSE_KEY}\",\"active\":${ACTIVE}}"
    fi
    # shellcheck disable=SC2046
    curl_fail_with_body -X PATCH \
      $(if $CURL_INSECURE; then echo '--insecure'; fi) \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      "${ARCLOUD_URL}${PATH_PREFIX}v1/license" \
      --data "$data"
    ;;
  deactivate | deactivate-online )
    must_be_online_mode "download-offline-deactivation-request"
    license_key_must_be_configured
    # shellcheck disable=SC2046
    curl_fail_with_body -X PATCH \
      $(if $CURL_INSECURE; then echo '--insecure'; fi) \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      "${ARCLOUD_URL}${PATH_PREFIX}v1/license" \
      --data '{"active":false}'
    ;;
  deactivation-request | download-deactivation-request | download-offline-deactivation-request )
    must_be_offline_mode "deactivate-online"
    license_key_must_be_configured
    # shellcheck disable=SC2046
    # shellcheck disable=SC2031
    curl_fail_with_body \
      $(if $CURL_INSECURE; then echo '--insecure'; fi) \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/octet-stream" \
      "${ARCLOUD_URL}${PATH_PREFIX}v1/offline/deactivation/request" \
      $(if [ -n "$OUT" ]; then echo "--output $OUT"; fi)
    ;;
  show )
    echo "$LICENSE_JSON_INFO"
    ;;
  upload-activation | upload-activation-file | upload-offline-activation-file )
    must_be_offline_mode "activate-online"
    license_key_must_be_configured
    # shellcheck disable=SC2046
    curl_fail_with_body -X POST \
      $(if $CURL_INSECURE; then echo '--insecure'; fi) \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/octet-stream" \
      "${ARCLOUD_URL}${PATH_PREFIX}v1/offline/activation/file" \
      --data $(if [ -n "$IN" ]; then echo "@$IN"; else echo '@-'; fi)
    ;;
  "" )
    exit_usage "no command was specified"
    ;;
  * )
    exit_usage "unrecognized command '$COMMAND'"
    ;;
esac
