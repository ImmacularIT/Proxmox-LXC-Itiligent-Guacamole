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
PROJECT_DISPLAY_NAME="Itiligent Guacamole LXC"
UPSTREAM_PROJECT_URL="https://github.com/itiligent/Easy-Guacamole-Installer"
IMMACULARIT_PROFILE_URL="https://github.com/ImmacularIT"
PROJECT_URL="https://github.com/${PROJECT_OWNER}/${PROJECT_REPO}"

# The external Proxmox helper framework is retained only for its proven
# container-creation mechanics. This project does not participate in its
# diagnostics/telemetry service and does not expose its branding in dialogs.
DIAGNOSTICS="no"
export DIAGNOSTICS
post_to_api() { return 0; }
post_progress_to_api() { return 0; }
post_update_to_api() { return 0; }
telemetry_new_attempt() { return 0; }
diagnostics_check() {
  DIAGNOSTICS="no"
  export DIAGNOSTICS
  return 0
}
diagnostics_menu() { return 0; }

# The framework has no project-specific header for this application. Avoid its
# fallback network request (and the resulting unrelated URL warning) while
# preserving header_info's normal clear-screen behavior.
get_header() { return 0; }

# Keep the established Default/Advanced framework dialogs and behavior, but
# present them as part of this ImmacularIT installer rather than with unrelated
# framework branding.
whiptail() {
  local arg
  local -a rewritten=()
  for arg in "$@"; do
    arg="${arg//Proxmox VE Helper Scripts - ${APP}/ImmacularIT - ${APP}}"
    arg="${arg//Proxmox VE Helper Scripts/ImmacularIT - ${APP}}"
    arg="${arg//Community-Scripts Options/${APP} Options}"
    arg="${arg//Community-Scripts SETTINGS Menu/${APP} Settings}"
    rewritten+=("$arg")
  done
  command whiptail "${rewritten[@]}"
}

# Preserve the existing settings editor except for the diagnostics/telemetry
# option, which is intentionally unsupported by this project. It is retained
# only for explicit compatibility modes and is not shown by the normal launcher.
settings_menu() {
  local choice
  while true; do
    if [ -f "$(get_app_defaults_path)" ]; then
      choice=$(whiptail \
        --backtitle "ImmacularIT - ${APP}" \
        --title "${APP} Settings" \
        --ok-button "Select" --cancel-button "Exit Script" \
        --menu "\nChoose a settings option:" 18 60 6 \
        "1" "Edit Default.vars" \
        "2" "Edit App.vars for ${APP}" \
        "3" "Back to Main Menu" \
        3>&1 1>&2 2>&3) || exit_script
      case "$choice" in
      1) ${EDITOR:-nano} /usr/local/community-scripts/default.vars ;;
      2) ${EDITOR:-nano} "$(get_app_defaults_path)" ;;
      3) return ;;
      esac
    else
      choice=$(whiptail \
        --backtitle "ImmacularIT - ${APP}" \
        --title "${APP} Settings" \
        --ok-button "Select" --cancel-button "Exit Script" \
        --menu "\nChoose a settings option:" 16 60 5 \
        "1" "Edit Default.vars" \
        "2" "Back to Main Menu" \
        3>&1 1>&2 2>&3) || exit_script
      case "$choice" in
      1) ${EDITOR:-nano} /usr/local/community-scripts/default.vars ;;
      2) return ;;
      esac
    fi
  done
}

header_info "$APP"
variables
color
catch_errors

# variables() belongs to the external framework and resets DIAGNOSTICS to its
# own safe default. Reassert the project policy after initialization so neither
# saved host preferences nor later framework changes can opt this installer in.
DIAGNOSTICS="no"
export DIAGNOSTICS

show_project_welcome() {
  whiptail \
    --backtitle "ImmacularIT - ${PROJECT_DISPLAY_NAME}" \
    --title "WELCOME" \
    --ok-button "Continue" --cancel-button "Exit" \
    --msgbox "\n${PROJECT_DISPLAY_NAME}\n\nProxmox VE LXC adaptation of the Itiligent Easy Guacamole Installer, maintained by ImmacularIT.\n\nDefault container profile:\n  - Debian 13\n  - Unprivileged LXC\n  - 1 CPU / 2048 MiB RAM / 8 GB disk\n\nBefore container creation, the official Proxmox appliance catalog is refreshed. The current Debian 13 AMD64 image is downloaded automatically when missing or when the cached image is older.\n\nAfter the LXC is created, the original interactive Itiligent setup lets you choose the database, authentication extensions, Nginx, TLS and other Guacamole options.\n\nProxmox remains responsible for container identity, networking and firewall policy.\n\nPrivacy: this installer does not send telemetry or diagnostics." 29 78 || exit_script
}

select_project_install_mode() {
  local requested_mode="${1:-}"
  local choice

  # The same ct script is also used by the in-container update path. Only show
  # the installation UI on a Proxmox host, with an interactive terminal, and
  # when no explicit framework mode was supplied by the caller.
  command -v pveversion >/dev/null 2>&1 || return 0
  [[ -n "${mode:-}" || -n "$requested_mode" ]] && return 0
  if [[ "${PHS_SILENT:-0}" == "1" || ! -t 0 || "${TERM:-dumb}" == "dumb" ]]; then
    return 0
  fi

  ensure_whiptail
  show_project_welcome

  choice=$(whiptail \
    --backtitle "ImmacularIT - ${PROJECT_DISPLAY_NAME}" \
    --title "INSTALLATION MODE" \
    --ok-button "Select" --cancel-button "Exit" \
    --menu "\nChoose how you want to configure the Proxmox container:" 17 76 2 \
    "1" "Default Install - recommended guided setup with standard resources" \
    "2" "Advanced Install - full Proxmox container configuration" \
    3>&1 1>&2 2>&3) || exit_script

  case "$choice" in
  1) mode="default" ;;
  2) mode="advanced" ;;
  *) exit_script ;;
  esac
}

prepare_latest_debian_template() {
  # The retained framework normally prefers a cached template and can skip its
  # catalog refresh when one is already present. For this project, make Debian
  # 13 AMD64 freshness deterministic while leaving ARM64 handling unchanged.
  command -v pveversion >/dev/null 2>&1 || return 0
  [[ "$(dpkg --print-architecture 2>/dev/null || true)" == "amd64" ]] || return 0
  [[ "${var_os:-debian}" == "debian" && "${var_version:-13}" == "13" ]] || return 0

  local storage="${TEMPLATE_STORAGE:-${var_template_storage:-}}"
  local available existing existing_name newest_name

  if [[ -z "$storage" ]]; then
    msg_error "No Proxmox template storage was selected before Debian template preparation"
    exit 226
  fi

  msg_info "Refreshing the official Proxmox appliance catalog"
  if ! pveam update >>"${BUILD_LOG:-/dev/null}" 2>&1; then
    msg_error "Failed to refresh the official Proxmox appliance catalog"
    exit 226
  fi
  msg_ok "Official Proxmox appliance catalog refreshed"

  available=$(pveam available --section system 2>/dev/null \
    | awk '$2 ~ /^debian-13-standard_.*_amd64\.tar\.zst$/ {print $2}' \
    | sort -V | tail -n1)
  if [[ -z "$available" ]]; then
    msg_error "No Debian 13 AMD64 standard template is available from the Proxmox appliance catalog"
    exit 226
  fi

  existing=$(pveam list "$storage" 2>/dev/null \
    | awk '$1 ~ /debian-13-standard_.*_amd64\.tar\.zst$/ {print $1}' \
    | sed 's|.*/||' | sort -V | tail -n1)
  existing_name="${existing##*/}"

  if [[ -z "$existing_name" ]]; then
    msg_info "No cached Debian 13 template found on ${storage}; downloading ${available}"
    if ! pveam download "$storage" "$available" >>"${BUILD_LOG:-/dev/null}" 2>&1; then
      msg_error "Failed to download Debian template ${available} to ${storage}"
      exit 226
    fi
  elif [[ "$existing_name" == "$available" ]]; then
    msg_ok "Current Debian template is already cached: ${available}"
  else
    newest_name=$(printf '%s\n%s\n' "$existing_name" "$available" | sort -V | tail -n1)
    if [[ "$newest_name" == "$existing_name" ]]; then
      msg_warn "Cached Debian template ${existing_name} is newer than catalog ${available}; keeping cached template"
    else
      msg_info "Newer Debian 13 template available (${existing_name} -> ${available}); downloading ${available}"
      if ! pveam download "$storage" "$available" >>"${BUILD_LOG:-/dev/null}" 2>&1; then
        msg_error "Failed to download Debian template ${available} to ${storage}"
        exit 226
      fi
    fi
  fi

  if [[ "$newest_name" != "$existing_name" || -z "$existing_name" ]]; then
    if ! pveam list "$storage" 2>/dev/null \
      | awk -v wanted="vztmpl/${available}" '
          length($1) >= length(wanted) && substr($1, length($1) - length(wanted) + 1) == wanted {found=1}
          END {exit !found}
        '; then
      msg_error "Debian template ${available} is not available on ${storage} after download"
      exit 226
    fi
  fi

  TEMPLATE_STORAGE="$storage"
  var_template_storage="$storage"
  export TEMPLATE_STORAGE var_template_storage

  if [[ -n "$existing_name" && "$newest_name" == "$existing_name" && "$existing_name" != "$available" ]]; then
    msg_ok "Debian template ready: ${existing_name}"
  else
    msg_ok "Debian template ready: ${available}"
  fi
}

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

configure_default_container_storage() {
  [[ "${METHOD:-}" == "default" ]] || return 0
  if [[ "${PHS_SILENT:-0}" == "1" || ! -t 0 || "${TERM:-dumb}" == "dumb" ]]; then
    return 0
  fi

  local storage selected default_storage found=0
  local -a stores=() storage_menu=()

  mapfile -t stores < <(pvesm status --content rootdir 2>/dev/null | awk 'NR > 1 && $3 == "active" {print $1}')
  if [[ ${#stores[@]} -eq 0 ]]; then
    msg_error "No active Proxmox storage supports LXC root disks"
    exit 116
  fi

  default_storage="${CONTAINER_STORAGE:-${var_container_storage:-${stores[0]}}}"
  for storage in "${stores[@]}"; do
    [[ "$storage" == "$default_storage" ]] && found=1
  done
  [[ "$found" -eq 1 ]] || default_storage="${stores[0]}"

  for storage in "${stores[@]}"; do
    if [[ "$storage" == "$default_storage" ]]; then
      storage_menu+=("$storage" "Current default")
    else
      storage_menu+=("$storage" "Active container storage")
    fi
  done

  selected=$(whiptail \
    --backtitle "ImmacularIT - ${APP}" \
    --title "DEFAULT INSTALL: STORAGE" \
    --ok-button "Next" --cancel-button "Exit Script" \
    --menu "\nSelect storage for the LXC root disk:" 18 72 10 \
    "${storage_menu[@]}" \
    --default-item "$default_storage" 3>&1 1>&2 2>&3) || exit_script

  CONTAINER_STORAGE="$selected"
  var_container_storage="$selected"
  export CONTAINER_STORAGE var_container_storage

  header_info
  echo -e "${STORAGE}${BOLD}${DGN}Container Storage: ${BGN}${CONTAINER_STORAGE}${CL}"
  echo
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
_FRAMEWORK_INSTALL_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/${var_install}.sh"

select_project_install_mode "${1:-}"
start
configure_default_identity
configure_default_container_storage
configure_default_network
prepare_latest_debian_template
configure_project_tags

curl() {
  local arg project_fetch=0
  local token="${GITHUB_TOKEN:-${var_github_token:-}}"
  local -a rewritten=()
  for arg in "$@"; do
    if [[ "$arg" == "$_FRAMEWORK_INSTALL_URL" ]]; then
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
