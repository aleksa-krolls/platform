#!/bin/bash

declare ACTION=""
declare MODE=""
declare COMPOSE_FILE_PATH=""
declare UTILS_PATH=""
declare nodes_mode=""
declare service_name=""

function init_vars() {
  ACTION=$1
  MODE=$2

  COMPOSE_FILE_PATH=$(
    cd "$(dirname "${BASH_SOURCE[0]}")" || exit
    pwd -P
  )

  UTILS_PATH="${COMPOSE_FILE_PATH}/../utils"

  service_name="dashboard-visualiser-kibana"

  if [[ "${NODE_MODE}" == "cluster" ]]; then
    nodes_mode="-${NODE_MODE}"
  fi

  readonly ACTION
  readonly MODE
  readonly COMPOSE_FILE_PATH
  readonly UTILS_PATH
  readonly nodes_mode
  readonly service_name
}

# shellcheck disable=SC1091
function import_sources() {
  source "${UTILS_PATH}/docker-utils.sh"
  source "${UTILS_PATH}/config-utils.sh"
  source "${UTILS_PATH}/log.sh"
}

function check_elastic() {
  if [[ ! $(docker::get_current_service_status "$ES_LEADER_NODE") == *"Running"* ]]; then
    log error "FATAL: Elasticsearch is not running, Kibana is dependant on it\n \
      Failed to deploy Dashboard Visualiser Kibana"
    exit 1
  fi
}

function initialize_package() {
  check_elastic

  local kibana_dev_compose_filename=""
  if [[ "${MODE}" == "dev" ]]; then
    log info "Running Dashboard Visualiser Kibana package in DEV mode"
    kibana_dev_compose_filename="docker-compose.dev.yml"
  else
    log info "Running Dashboard Visualiser Kibana package in PROD mode"
  fi

  (
    export KIBANA_YML_CONFIG="kibana-kibana$nodes_mode.yml"

    docker::deploy_service "${COMPOSE_FILE_PATH}" "docker-compose.yml" "$kibana_dev_compose_filename"
    docker::deploy_sanity "$service_name"
  ) || {
    log error "Failed to deploy Dashboard Visualiser Kibana"
    exit 1
  }

  config::await_network_join "instant_dashboard-visualiser-kibana"

  docker::deploy_config_importer "$COMPOSE_FILE_PATH/importer/docker-compose.config.yml" "kibana-config-importer" "kibana"
}

function scale_services_down() {
  try \
    "docker service scale instant_$service_name=0" \
    catch \
    "Failed to scale down $service_name"
}

function destroy_package() {
  docker::service_destroy kibana-config-importer
  docker::service_destroy await-helper
  docker::service_destroy "$service_name"

  docker::prune_configs "kibana"
}

main() {
  init_vars "$@"
  import_sources

  if [[ "${ACTION}" == "init" ]] || [[ "${ACTION}" == "up" ]]; then
    log info "Running Dashboard Visualiser Kibana package in ${NODE_MODE} node mode"

    initialize_package
  elif [[ "${ACTION}" == "down" ]]; then
    log info "Scaling down Dashboard Visualiser Kibana"

    scale_services_down
  elif [[ "${ACTION}" == "destroy" ]]; then
    log info "Destroying Dashboard Visualiser Kibana"

    destroy_package
  else
    log error "Valid options are: init, up, down, or destroy"
  fi
}

main "$@"
