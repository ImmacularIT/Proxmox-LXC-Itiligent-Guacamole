#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2026 ImmacularIT
# License: MIT
# Upstream: https://github.com/itiligent/Easy-Guacamole-Installer

APP="Itiligent-Guacamole"
var_tags="${var_tags:-itiligent;guacamole;immacularit;remote-access}"
var_disk="${var_disk:-8}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

PROJECT_OWNER="ImmacularIT"
PROJECT_REPO="Proxmox-LXC-Itiligent-Guacamole"
PROJECT_REF="${ITILIGENT_REPO_REF:-main}"
UPSTREAM_PROJECT_URL="https://github.com/itiligent/Easy-Guacamole-Installer"
IMMACULARIT_PROFILE_URL="https://github.com/ImmacularIT"
PROJECT_URL="https://github.com/${PROJECT_OWNER}/${PROJECT_REPO}"

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

configure_default_identity() {
  [[ "${METHOD:-}" == "default" ]] || return 0
  if [[ "${PHS_SILENT:-0}" == "1" || ! -t 0 || "${TERM:-dumb}" == "dumb" ]]; then
    return 0
  fi

  local requested_id requested_hostname

  while true; do
    requested_id=$(whiptail \
      --backtitle "Proxmox VE Helper Scripts - ${APP}" \
      --title "DEFAULT INSTALL: CONTAINER ID" \
      --ok-button "Next" --cancel-button "Exit Script" \
      --inputbox "\nContainer ID [${CT_ID:-$NEXTID}]\n\nPress Enter to use the suggested ID." 12 62 \
      "${CT_ID:-$NEXTID}" \
      3>&1 1>&2 2>&3) || exit_script

    requested_id="${requested_id:-${CT_ID:-$NEXTID}}"
    if [[ "$requested_id" =~ ^[0-9]+$ ]] && validate_container_id "$requested_id"; then
      break
    fi
    whiptail --title "INVALID CONTAINER ID" \
      --msgbox "Container ID must be numeric and unused across the Proxmox cluster." 9 62
  done

  while true; do
    requested_hostname=$(whiptail \
      --backtitle "Proxmox VE Helper Scripts - ${APP}" \
      --title "DEFAULT INSTALL: CONTAINER NAME" \
      --ok-button "Next" --cancel-button "Exit Script" \
      --inputbox "\nContainer name [${HN:-$NSAPP}]\n\nPress Enter to use the suggested name." 12 66 \
      "${HN:-$NSAPP}" \
      3>&1 1>&2 2>&3) || exit_script

    requested_hostname="${requested_hostname:-${HN:-$NSAPP}}"
    requested_hostname=$(echo "${requested_hostname,,}" | tr -d ' ')
    if validate_hostname "$requested_hostname"; then
      break
    fi
    whiptail --title "INVALID CONTAINER NAME" \
      --msgbox "Use lowercase letters, numbers, dots and hyphens only. Labels cannot start or end with a hyphen." 10 66
  done

  CT_ID="$requested_id"
  CTID="$requested_id"
  HN="$requested_hostname"
  export CT_ID CTID HN
}

configure_default_network() {
  [[ "${METHOD:-}" == "default" ]] || return 0
  if [[ "${PHS_SILENT:-0}" == "1" || ! -t 0 || "${TERM:-dumb}" == "dumb" ]]; then
    return 0
  fi

  local bridge_path bridge selected_bridge ip_method static_ip gateway vlan
  local current_gateway="${GATE:-}"
  local -a bridges=()
  local -a bridge_menu=()

  case "$current_gateway" in
  ,gw=*) current_gateway="${current_gateway#,gw=}" ;;
  esac

  for bridge_path in /sys/class/net/*/bridge; do
    [[ -d "$bridge_path" ]] || continue
    bridge="${bridge_path%/bridge}"
    bridge="${bridge##*/}"
    if validate_bridge "$bridge"; then
      bridges+=("$bridge")
    fi
  done

  local bridge_found=0
  for bridge in "${bridges[@]}"; do
    [[ "$bridge" == "${BRG:-vmbr0}" ]] && bridge_found=1
  done
  if [[ "$bridge_found" -eq 0 ]] && validate_bridge "${BRG:-vmbr0}"; then
    bridges=("${BRG:-vmbr0}" "${bridges[@]}")
  fi

  if [[ ${#bridges[@]} -eq 0 ]]; then
    msg_error "No active Proxmox network bridge was found"
    exit 116
  fi

  for bridge in "${bridges[@]}"; do
    if [[ "$bridge" == "${BRG:-vmbr0}" ]]; then
      bridge_menu+=("$bridge" "Current default")
    else
      bridge_menu+=("$bridge" "Available bridge")
    fi
  done

  while true; do
    selected_bridge=$(whiptail --backtitle "Proxmox VE Helper Scripts - ${APP}" --title "DEFAULT INSTALL: NETWORK BRIDGE" --ok-button "Next" --cancel-button "Exit Script" --menu "\nSelect the Proxmox bridge for this container:" 16 64 7 "${bridge_menu[@]}" --default-item "${BRG:-vmbr0}" 3>&1 1>&2 2>&3) || exit_script

    ip_method="dhcp"
    [[ "${NET:-dhcp}" != "dhcp" ]] && ip_method="static"
    ip_method=$(whiptail --backtitle "Proxmox VE Helper Scripts - ${APP}" --title "DEFAULT INSTALL: IPv4" --ok-button "Next" --cancel-button "Exit Script" --menu "\nChoose how the container receives its IPv4 address:" 15 68 2 "dhcp" "Automatic address from DHCP (recommended)" "static" "Static address entered manually" --default-item "$ip_method" 3>&1 1>&2 2>&3) || exit_script

    if [[ "$ip_method" == "static" ]]; then
      while true; do
        static_ip=$(whiptail --backtitle "Proxmox VE Helper Scripts - ${APP}" --title "DEFAULT INSTALL: STATIC IPv4" --ok-button "Next" --cancel-button "Exit Script" --inputbox "\nEnter the IPv4 address in CIDR format.\nExample: 192.168.2.50/24" 12 62 "$([[ "${NET:-dhcp}" != "dhcp" ]] && printf '%s' "$NET")" 3>&1 1>&2 2>&3) || exit_script
        if validate_ip_address "$static_ip"; then break; fi
        whiptail --title "INVALID STATIC ADDRESS" --msgbox "Enter a valid IPv4 CIDR address.\n\nExample: 192.168.2.50/24" 10 58
      done

      while true; do
        gateway=$(whiptail --backtitle "Proxmox VE Helper Scripts - ${APP}" --title "DEFAULT INSTALL: GATEWAY" --ok-button "Next" --cancel-button "Exit Script" --inputbox "\nEnter the IPv4 gateway.\nLeave blank only when no gateway is required." 12 62 "$current_gateway" 3>&1 1>&2 2>&3) || exit_script
        if validate_gateway_ip "$gateway" && validate_gateway_in_subnet "$static_ip" "$gateway"; then break; fi
        whiptail --title "INVALID GATEWAY" --msgbox "The gateway must be a valid IPv4 address in the same subnet as:\n\n${static_ip}" 11 62
      done
    else
      static_ip="dhcp"
      gateway=""
    fi

    while true; do
      vlan=$(whiptail --backtitle "Proxmox VE Helper Scripts - ${APP}" --title "DEFAULT INSTALL: VLAN" --ok-button "Review" --cancel-button "Exit Script" --inputbox "\nEnter a VLAN tag from 1 to 4094.\nLeave blank for an untagged interface." 12 62 "${VLAN:-}" 3>&1 1>&2 2>&3) || exit_script
      if validate_vlan_tag "$vlan"; then break; fi
      whiptail --title "INVALID VLAN" --msgbox "VLAN must be blank or a number between 1 and 4094." 9 58
    done

    local gateway_display="${gateway:-None}"
    local vlan_display="${vlan:-None}"
    if whiptail --backtitle "Proxmox VE Helper Scripts - ${APP}" --title "CONFIRM NETWORK SETTINGS" --yes-button "Use Settings" --no-button "Change" --yesno "\nBridge: ${selected_bridge}\nIPv4: ${static_ip}\nGateway: ${gateway_display}\nVLAN: ${vlan_display}\n\nUse these network settings?" 15 64; then
      BRG="$selected_bridge"
      SDN_VNET=""
      NET="$static_ip"
      GATE="$gateway"
      VLAN="$vlan"
      export BRG SDN_VNET NET GATE VLAN
      break
    fi
  done

  header_info
  echo -e "${NETWORK}${BOLD}${DGN}Network Bridge: ${BGN}${BRG}${CL}"
  echo -e "${NETWORK}${BOLD}${DGN}IPv4 Address: ${BGN}${NET}${CL}"
  [[ -n "$GATE" ]] && echo -e "${GATEWAY}${BOLD}${DGN}IPv4 Gateway: ${BGN}${GATE}${CL}"
  echo -e "${NETWORK}${BOLD}${DGN}VLAN Tag: ${BGN}${VLAN:-None}${CL}"
  echo
}

configure_project_tags() {
  local raw_tags="${TAGS:-${var_tags:-}}"
  local tag cleaned=""
  local -a existing_tags=()
  local -a requested_tags=("itiligent" "guacamole" "immacularit" "remote-access")
  IFS=';' read -r -a existing_tags <<<"$raw_tags"
  for tag in "${existing_tags[@]}" "${requested_tags[@]}"; do
    tag="${tag//[[:space:]]/}"
    [[ -z "$tag" || "$tag" == "community-script" ]] && continue
    case ";${cleaned};" in
    *";${tag};"*) ;;
    *) cleaned="${cleaned:+${cleaned};}${tag}" ;;
    esac
  done
  TAGS="$cleaned"
  export TAGS
}

set_project_description() {
  local asset_base="https://raw.githubusercontent.com/${PROJECT_OWNER}/${PROJECT_REPO}/${PROJECT_REF}/assets"
  local project_description
  project_description=$(cat <<EOF_DESCRIPTION
<div align='center'>
  <a href='${UPSTREAM_PROJECT_URL}' target='_blank' rel='noopener noreferrer'>
    <img src='${asset_base}/itiligent-logo-card.png' alt='Itiligent logo' style='width:180px;max-width:55%;height:auto;' />
  </a>
  <h2 style='font-size:24px;margin:16px 0 8px;'>Itiligent Guacamole LXC</h2>
  <p style='margin:8px 0;line-height:1.5;'>An unofficial Proxmox LXC adaptation of the <a href='${UPSTREAM_PROJECT_URL}' target='_blank' rel='noopener noreferrer' style='color:#88bf5b;'>Itiligent Easy Guacamole Installer</a>.</p>
  <p style='margin:8px 0 4px;'>Adapted and maintained for Proxmox by</p>
  <a href='${IMMACULARIT_PROFILE_URL}' target='_blank' rel='noopener noreferrer'><img src='${asset_base}/immacularit-logo.png' alt='ImmacularIT logo' style='width:210px;max-width:60%;height:auto;' /></a>
  <p style='margin:12px 0;'>
    <a href='${UPSTREAM_PROJECT_URL}' target='_blank' rel='noopener noreferrer'><img src='https://img.shields.io/badge/Upstream-Itiligent-88BF5B?logo=github&amp;logoColor=white' alt='Itiligent upstream repository' /></a>
    <a href='${PROJECT_URL}' target='_blank' rel='noopener noreferrer'><img src='https://img.shields.io/badge/Proxmox%20adaptation-ImmacularIT-29A9E8?logo=github&amp;logoColor=white' alt='ImmacularIT Proxmox adaptation' /></a>
  </p>
  <span style='margin:0 10px;'><i class='fa fa-code-fork fa-fw'></i><a href='${UPSTREAM_PROJECT_URL}' target='_blank' rel='noopener noreferrer' style='text-decoration:none;color:#88bf5b;'>Itiligent GitHub</a></span>
  <span style='margin:0 10px;'><i class='fa fa-github fa-fw'></i><a href='${PROJECT_URL}' target='_blank' rel='noopener noreferrer' style='text-decoration:none;color:#29a9e8;'>Project GitHub</a></span>
  <span style='margin:0 10px;'><i class='fa fa-exclamation-circle fa-fw'></i><a href='${PROJECT_URL}/issues' target='_blank' rel='noopener noreferrer' style='text-decoration:none;color:#29a9e8;'>Issues</a></span>
</div>
EOF_DESCRIPTION
)
  pct set "$CTID" -description "$project_description"
}

_PROJECT_INSTALL_URL="https://raw.githubusercontent.com/${PROJECT_OWNER}/${PROJECT_REPO}/${PROJECT_REF}/install/itiligent-guacamole-install.sh"
_COMMUNITY_INSTALL_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/${var_install}.sh"

start
configure_default_identity
configure_default_network
configure_project_tags

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
set_project_description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Native Guacamole fallback:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8080/guacamole${CL}"
