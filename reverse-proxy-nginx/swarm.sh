#!/bin/bash

declare ACTION=""
declare MODE=""
declare COMPOSE_FILE_PATH=""
declare UTILS_PATH=""
declare TIMESTAMP
declare TIMESTAMPED_NGINX
declare SERVICE_NAMES=""

function init_vars() {
  ACTION=$1
  MODE=$2

  COMPOSE_FILE_PATH=$(
    cd "$(dirname "${BASH_SOURCE[0]}")" || exit
    pwd -P
  )

  TIMESTAMP="$(date "+%Y%m%d%H%M%S")"
  TIMESTAMPED_NGINX="${TIMESTAMP}-nginx.conf"

  UTILS_PATH="${COMPOSE_FILE_PATH}/../utils"

  SERVICE_NAMES="reverse-proxy-nginx"

  readonly ACTION
  readonly MODE
  readonly COMPOSE_FILE_PATH
  readonly UTILS_PATH
  readonly TIMESTAMP
  readonly TIMESTAMPED_NGINX
  readonly SERVICE_NAMES
}

# shellcheck disable=SC1091
function import_sources() {
  source "${UTILS_PATH}/docker-utils.sh"
  source "${UTILS_PATH}/config-utils.sh"
  source "${UTILS_PATH}/log.sh"
}

function publish_insecure_ports() {
  IFS='-' read -ra PORTS <<<"$INSECURE_PORTS"

  local ports_array=()

  for i in "${PORTS[@]}"; do
    IFS=':' read -ra PORTS_SPLIT <<<"$i"

    if [[ "${PORTS_SPLIT[0]}" != "" ]] && [[ "${PORTS_SPLIT[1]}" != "" ]]; then
      ports_array+=(--publish-add "published=${PORTS_SPLIT[0]},target=${PORTS_SPLIT[1]}")

      log info "Exposing ports: published=%s,target=%s " "${PORTS_SPLIT[0]}" "${PORTS_SPLIT[1]}"
    else
      log error "Failed to expose ports: published=%s,target=%s " "${PORTS_SPLIT[0]}" "${PORTS_SPLIT[1]}"
    fi
  done

  log info "Updating ${SERVICE_NAMES} service with configured ports..."
  try \
    "docker service update ${ports_array[*]} instant_${SERVICE_NAMES}" \
    throw \
    "Error updating ${SERVICE_NAMES} service"
  overwrite "Updating ${SERVICE_NAMES} service with configured ports... Done"
}

function add_insecure_configs() {
  try \
    "docker config create --label name=nginx ${TIMESTAMPED_NGINX} ${COMPOSE_FILE_PATH}/config/nginx-temp-insecure.conf" \
    throw \
    "Failed to create nginx insecure config"

  log info "Updating nginx service: adding config file..."
  try \
    "docker service update --config-add source=${TIMESTAMPED_NGINX},target=/etc/nginx/nginx.conf instant_$SERVICE_NAMES" \
    throw \
    "Error updating ${SERVICE_NAMES} service"
  overwrite "Updating nginx service: adding config file... Done"
}

function deploy_nginx() {
  local -r DEPLOY_TYPE=${1:?"FATAL: deploy_nginx DEPLOY_TYPE not provided"}

  config::generate_service_configs "$SERVICE_NAMES" /etc/nginx/conf.d "${COMPOSE_FILE_PATH}/package-conf-${DEPLOY_TYPE}" "${COMPOSE_FILE_PATH}" "nginx"

  docker::deploy_service "${COMPOSE_FILE_PATH}" "docker-compose.yml" "docker-compose.tmp.yml"
  docker::deploy_sanity "${SERVICE_NAMES}"
}

function initialize_package() {
  if [[ "${INSECURE}" == "true" ]]; then
    package::log info "Running package in INSECURE mode"
    (
      deploy_nginx "insecure"

      if [[ "${INSECURE_PORTS}" != "" ]]; then
        publish_insecure_ports
      fi
      add_insecure_configs
    ) ||
      {
        package::log error "Failed to deploy package in INSECURE MODE"
        exit 1
      }
  else
    package::log info "Running package in SECURE mode"
    (
      deploy_nginx "secure"

      try "${COMPOSE_FILE_PATH}/set-secure-mode.sh" throw "Fatal: Setting SECURE Mode has failed"
    ) ||
      {
        package::log error "Failed to deploy package in SECURE MODE"
        exit 1
      }
  fi
}

function destroy_package() {
  docker::service_destroy "$SERVICE_NAMES"

  mapfile -t nginx_secrets < <(docker secret ls -qf label=name=nginx)
  if [[ "${#nginx_secrets[@]}" -ne 0 ]]; then
    try "docker secret rm ${nginx_secrets[*]}" catch "Failed to remove nginx secrets"
  fi

  mapfile -t nginx_network < <(docker network ls -qf name=cert-renewal-network)
  if [[ "${#nginx_network[@]}" -ne 0 ]]; then
    try "docker network rm ${nginx_network[*]}" catch "Failed to remove nginx networks"
  fi

  docker::try_remove_volume renew-certbot-conf data-certbot-conf dummy-data-certbot-conf

  docker::prune_configs "nginx"
}

main() {
  init_vars "$@"
  import_sources

  if [[ "${MODE}" == "dev" ]]; then
    log info "Not including reverse proxy as we are running DEV mode"
    exit 0
  fi

  if [[ "${ACTION}" == "init" ]] || [[ "${ACTION}" == "up" ]]; then
    package::log info "Running package"

    initialize_package
  elif [[ "${ACTION}" == "down" ]]; then
    package::log info "Scaling down package"

    docker::scale_services_down "${SERVICE_NAMES}"
  elif [[ "${ACTION}" == "destroy" ]]; then
    package::log info "Destroying package"
    destroy_package
  else
    log error "Valid options are: init, up, down, or destroy"
  fi
}

main "$@"
