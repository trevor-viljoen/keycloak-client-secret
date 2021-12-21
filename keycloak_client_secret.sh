#!/usr/bin/env bash
#set -x
#==============================================================================
#                   Copyright (c) 2021 Trevor Viljoen
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Purpose License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.
#==============================================================================
#
#  Name:        keycloak_client_secret.sh
#  Type:        shell script
#  Authors:     Trevor Viljoen <trevor.viljoen@gmail.com>
#
#  Purpose:     To pull or regenerate a client_secret for a given Keycloak
#               Client in a specific Realm. This may be useful for storing
#               the secret in an external secrets manager or creating
#               Kubernetes secrets for use with an OAuth client.
#
#==============================================================================

declare -A opthash

case "$(uname -s)" in
  Darwin*)
    head=(/usr/local/bin/ghead)
    ;;
  Linux*)
    head=(/usr/bin/head)
    ;&
  CYGWIN*)
    ;&
  MINGW*)
    ;&
  *)
  ;;
esac

function parseopts() {
  PARAMS=""

  while (( "$#" )); do
    case "$1" in
      -n|--namespace)
        if [[ ! -z "$2" ]]; then
          opthash[namespace]="$2"
          shift 2
        else
          echo "Error: No namespace was provided."
          exit 1
        fi
        ;;
      -r|--realm)
        if [[ ! -z "$2" ]]; then
          opthash[realm]="$2"
          shift 2
        else
          echo "Error: No realm was provided."
          exit 1
        fi
        ;;
      -c|--client-id)
        if [[ ! -z "$2" ]]; then
          opthash[client_id]="$2"
          shift 2
        else
          echo "Error: No client_id was provided."
          exit 1
        fi
        ;;
      -g|--generate)
        opthash[generate]=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -c|--conditions)
        conditions
        exit 0
        ;;
      -w|--warranty)
        warranty
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*|--*)
        echo "Error: Unsupported flag $1" >&2
        exit 1
        ;;
      *)
        PARAMS="${PARAMS} $1"
        shift
        ;;
    esac
  done

  eval set -- "${PARAMS}"
  check_opts
}

function usage() {
  cat <<EOF
  $(basename "$0") Copyright (C) 2021 Trevor Viljoen <trevor.viljoen@gmail.com>

  This program comes with ABSOLUTELY NO WARRANTY; for details type $(basename "$0") --warranty,
  This is free software, and you are welcome to redistribute it under certain conditions;
  type $(basename "$0") --conditions for details.

  Options:
    -n, --namespace Keycloak Namespace
    -r, --realm Kecloak Realm Name
    -c, --client-id Keycloak Realm Client ID (name)
    -g, --generate Generate a new Keycloak Realm Client Secret
    -c, --conditions Display the conditions
    -w, --warranty Display the warranty

EOF
}

function conditions() {
  cat <<EOF
  $(basename "$0") Copyright (C) 2021 Trevor Viljoen <trevor.viljoen@gmail.com>

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

EOF
}

function warranty() {
  cat <<EOF
  $(basename "$0") Copyright (C) 2021 Trevor Viljoen <trevor.viljoen@gmail.com>

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

EOF
}

function check_opts() {
  if [ -v "opthash[help]" ]; then
    usage
    exit 0
  fi
  if [ ! -v "opthash[generate]" ]; then
    opthash[generate]=0
  fi

  if [ -v "opthash[namespace]" ]; then
    if [ -v "opthash[realm]" ]; then
      if [ -v "opthash[client_id]" ]; then
        local namespace="${opthash[namespace]}"
        local_cluster_http_code=$(curl -s -o /dev/null -w "%{http_code}" https://keycloak.${namespace}.svc.cluster.local:8443)
        # curl: (6) Could not resolve host keycloak.${namespace}.svc.cluster.local
        # curl: (7) Failed to connect to keycloak.${namespace}.svc.cluster.local port 8443
        local local_cluster_exit_code=$?

        if [ ${local_cluster_http_code} -eq 200 ]; then
          local keycloak_host="keycloak.${namespace}.svc.cluster.local:8443"
        else
          local keycloak_host=$(oc get route keycloak -n ${namespace} -o jsonpath={.spec.host})
        fi

        local realm="${opthash[realm]}"
        local client_id_name="${opthash[client_id]}"
        if [ ${opthash[generate]} -eq 1 ]; then
          generate_new_client_secret
        else
          get_client_secret
        fi
      else
        echo "A client_id is required."
        exit 1
      fi
    else
      echo "Realm is required."
      exit 1
    fi
  else
    echo "Namespace is required."
    exit 1
  fi
}

function get_bearer_token(){
  local oidc_token_endpoint="auth/realms/master/protocol/openid-connect/token"
  # if there is more than one keycloak instance in the namespace, this should cause an error
  local keycloak_instance=$(oc get keycloaks -n ${namespace} -o name)
  local credential_secret=$(oc get ${keycloak_instance} -n ${namespace} -o jsonpath={.status.credentialSecret})
  local username=$(oc get secret ${credential_secret} \
    -n ${namespace} \
    -o jsonpath={.data.ADMIN_USERNAME} \
    | base64 -d)
  local password=$(oc get secret ${credential_secret} \
    -n ${namespace} \
    -o jsonpath={.data.ADMIN_PASSWORD} \
    | base64 -d)

  local response=$(curl -s -w '%{http_code}' -X POST https://${keycloak_host}/${oidc_token_endpoint} \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -H "Accept: application/json" \
    -d username="${username}" \
    -d password="${password}" \
    -d grant_type=password \
    -d client_id="admin-cli")
  local http_code=${response: -3}

  if check_http_response_code ${http_code}; then
    local content=$(strip_http_code "${response}" | jq -r .access_token)
    echo -n ${content}
  fi
}

function get_client_id() {
  local clients_endpoint="auth/admin/realms/${realm}/clients"
  local response=$(curl -s -w '%{http_code}' -X GET https://${keycloak_host}/${clients_endpoint} \
    -H 'Content-Type: application/json' \
    -H "Authorization: bearer ${bearer_token}")
  local http_code=${response: -3}

  if check_http_response_code ${http_code}; then
    local content=$(strip_http_code "${response}" \
      | jq -r --arg client_id "${client_id_name}" '.[] | select(.clientId == $client_id) | .id')
    echo -n ${content}
  fi
}

function get_client_secret() {
  local bearer_token=$(get_bearer_token)
  local client_id=$(get_client_id)
  local client_secret_endpoint="auth/admin/realms/${realm}/clients/${client_id}/client-secret"
  local response=$(curl -s -w '%{http_code}' -X GET https://${keycloak_host}/${client_secret_endpoint} \
    -H 'Content-Type: application/json' \
    -H "Authorization: bearer ${bearer_token}")
  local http_code=${response: -3}

  if check_http_response_code ${http_code}; then
    local content=$(strip_http_code "${response}" | jq -r .value)
    echo -n ${content}
  fi
}

function check_http_response_code() {
  local http_code=$1
  if [ ${http_code} -ne 200 ]; then
    echo "Invalid http_code: ${http_code}."
    exit 1
  fi
}

function strip_http_code() {
  response=$1
  echo "${response}" | "${head[@]}" -c-4
}

function generate_new_client_secret() {
  local bearer_token=$(get_bearer_token)
  local client_id=$(get_client_id)
  local client_secret_endpoint="auth/admin/realms/${realm}/clients/${client_id}/client-secret"
  local response=$(curl -s -w '%{http_code}' -X POST https://${keycloak_host}/${client_secret_endpoint} \
    -H 'Content-Type: application/json' \
    -H "Authorization: bearer ${bearer_token}")
  local http_code=${response: -3}

  if check_http_response_code ${http_code}; then
    local content=$(strip_http_code "${response}" | jq -r .value)
    echo -n ${content}
  fi
}


parseopts "$@"
