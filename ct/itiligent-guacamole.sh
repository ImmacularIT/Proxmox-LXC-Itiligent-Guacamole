#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2026 ImmacularIT
# License: MIT
# Upstream: https://github.com/itiligent/Easy-Guacamole-Installer

APP="Itiligent-Guacamole"
var_tags="${var_tags:-webserver;remote}"
var_disk="${var_disk:-8}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

PROJECT_OWNER="ImmacularIT"
PROJECT_REPO="Proxmox-Itiligent-Guacamole"
PROJECT_REF="${ITILIGENT_REPO_REF:-main}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -x /opt/itiligent-guacamole/upgrade-guacamole.sh ]]; then
    msg_error "No ${APP} installation found"
    exit 1
  fi
  msg_info "Starting the Itiligent Guacamole upgrade script"
  cd /opt/itiligent-guacamole
  bash ./upgrade-guacamole.sh
  msg_ok "Itiligent Guacamole upgrade script completed"
  exit 0
}

_PROJECT_INSTALL_URL="https://raw.githubusercontent.com/${PROJECT_OWNER}/${PROJECT_REPO}/${PROJECT_REF}/install/itiligent-guacamole-install.sh"
_COMMUNITY_INSTALL_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/${var_install}.sh"

start

# Community Scripts resolves the installer from its own repository. Intercept
# only that URL so the normal container builder can use this project's installer.
curl() {
  local arg project_fetch=0
  local token="${GITHUB_TOKEN:-${var_github_token:-}}"
  local -a rewritten=()
  for arg in "$@"; do
    if [[ "$arg" == "$_COMMUNITY_INSTALL_URL" ]]; then
      rewritten+=("$_PROJECT_INSTALL_URL")
      project_fetch=1
    else
      rewritten+=("$arg")
    fi
  done
  if [[ "$project_fetch" -eq 1 && -n "$token" ]]; then
    command curl -H "Authorization: Bearer ${token}" "${rewritten[@]}"
  else
    command curl "${rewritten[@]}"
  fi
}

build_container
unset -f curl
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Native Guacamole fallback:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8080/guacamole${CL}"
