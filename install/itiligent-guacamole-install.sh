#!/usr/bin/env bash
# Copyright (c) 2026 ImmacularIT
# License: MIT
# Proxmox LXC adaptation of the Itiligent Easy Guacamole Installer.

# Debian's C.UTF-8 locale is always available in the minimal container. Use it
# only for this installation process so inherited Proxmox host LC_* values (for
# example sv_SE.UTF-8 before that locale exists in the guest) cannot trigger
# noisy Perl/locale warnings. This does not change the container's configured
# regional locale or timezone.
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

# The retained helper library can re-import host/default locale state while it
# initializes. Reassert the neutral install locale immediately afterward so all
# project-side package operations run with deterministic UTF-8 settings.
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# The outer container builder supplies its helper library through
# FUNCTIONS_FILE_PATH. Keep those proven runtime helpers, but make this project
# permanently telemetry-free regardless of any host-side saved preference.
DIAGNOSTICS="no"
export DIAGNOSTICS
post_to_api() { return 0; }
post_progress_to_api() { return 0; }
post_update_to_api() { return 0; }
telemetry_new_attempt() { return 0; }

# Preserve the helper library's network checks while removing the unrelated
# external-framework DNS dependency from this project's installation path.
project_network_check() {
  set +e
  trap - ERR
  ipv4_connected=false
  ipv6_connected=false
  sleep 1

  if ping -c 1 -W 1 1.1.1.1 &>/dev/null || ping -c 1 -W 1 8.8.8.8 &>/dev/null || ping -c 1 -W 1 9.9.9.9 &>/dev/null; then
    msg_ok "IPv4 Internet Connected"
    ipv4_connected=true
  else
    msg_error "IPv4 Internet Not Connected"
  fi

  if ping6 -c 1 -W 1 2606:4700:4700::1111 &>/dev/null || ping6 -c 1 -W 1 2001:4860:4860::8888 &>/dev/null || ping6 -c 1 -W 1 2620:fe::fe &>/dev/null; then
    msg_ok "IPv6 Internet Connected"
    ipv6_connected=true
  else
    msg_error "IPv6 Internet Not Connected"
  fi

  if [[ $ipv4_connected == false && $ipv6_connected == false ]]; then
    read -r -p "No Internet detected, would you like to continue anyway? <y/N> " prompt </dev/tty
    if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
      echo -e "${INFO}${RD}Expect Issues Without Internet${CL}"
    else
      echo -e "${NETWORK}Check Network Settings"
      exit 122
    fi
  fi

  GIT_HOSTS=("github.com" "raw.githubusercontent.com" "api.github.com")
  GIT_STATUS="Git DNS:"
  DNS_FAILED=false

  for HOST in "${GIT_HOSTS[@]}"; do
    RESOLVEDIP=$(getent hosts "$HOST" | awk '{ print $1 }' | grep -E '(^([0-9]{1,3}\.){3}[0-9]{1,3}$)|(^[a-fA-F0-9:]+$)' | head -n1)
    if [[ -z "$RESOLVEDIP" ]]; then
      GIT_STATUS+="$HOST:($DNSFAIL)"
      DNS_FAILED=true
    else
      GIT_STATUS+=" $HOST:($DNSOK)"
    fi
  done

  if [[ "$DNS_FAILED" == true ]]; then
    fatal "$GIT_STATUS"
  else
    msg_ok "$GIT_STATUS"
  fi

  set -e
  trap 'error_handler' ERR
}

# Keep the established OS-update, proxy, APT cacher, and mirror fallback
# behavior. The generic tools library downloaded afterward is not required by
# this installer, so omit that unrelated framework download.
project_update_os() {
  msg_info "Updating Container OS"
  configure_http_proxy
  if [[ "$CACHER" == "yes" && -z "${HTTP_PROXY:-${http_proxy:-}}" ]]; then
    echo 'Acquire::http::Proxy-Auto-Detect "/usr/local/bin/apt-proxy-detect.sh";' >/etc/apt/apt.conf.d/00aptproxy
    local _proxy_raw="${CACHER_IP}"
    local _proxy_host _proxy_port _proxy_url
    _proxy_host=$(echo "$_proxy_raw" | sed -e 's|https\?://||' -e 's|/.*||' | cut -d: -f1)
    _proxy_port=$(echo "$_proxy_raw" | sed -e 's|https\?://||' -e 's|/.*||' | cut -s -d: -f2)
    if [[ "$_proxy_raw" =~ ^https?:// ]]; then
      _proxy_url="$_proxy_raw"
      _proxy_port="${_proxy_port:-80}"
    else
      _proxy_port="${_proxy_port:-3142}"
      _proxy_url="http://${_proxy_raw}:${_proxy_port}"
    fi
    cat <<EOF_PROXY >/usr/local/bin/apt-proxy-detect.sh
#!/bin/bash
if nc -w1 -z "${_proxy_host}" ${_proxy_port}; then
  echo -n "${_proxy_url}"
else
  echo -n "DIRECT"
fi
EOF_PROXY
    chmod +x /usr/local/bin/apt-proxy-detect.sh
  fi
  apt_update_safe
  $STD apt-get -o Dpkg::Options::="--force-confold" -y dist-upgrade
  rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
  msg_ok "Updated Container OS"
}

color
verb_ip6
if [[ -f /etc/sysctl.d/99-disable-ipv6.conf ]]; then
  sed -i 's/set by community-scripts/set by ImmacularIT/' /etc/sysctl.d/99-disable-ipv6.conf
fi
catch_errors
setting_up_container

# setting_up_container and related helper code are external compatibility
# functions. Reassert once more at the handoff boundary before project package
# operations and the adapted Itiligent suite begin.
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

project_network_check
project_update_os

readonly UPSTREAM_COMMIT="676eb7e2711dabdf7f33fa7fe91eafc3dbdb7fce"
readonly UPSTREAM_BASE="https://raw.githubusercontent.com/itiligent/Easy-Guacamole-Installer/${UPSTREAM_COMMIT}"
readonly SETUP_SCRIPT="/root/1-setup.sh"
readonly INSTALL_DIR="/opt/itiligent-guacamole"
readonly PROJECT_UPDATE_URL="https://raw.githubusercontent.com/ImmacularIT/Proxmox-LXC-Itiligent-Guacamole/main/ct/itiligent-guacamole.sh"

msg_info "Installing adaptation dependencies"
$STD apt-get install -y ca-certificates curl wget python3 iproute2 cron procps
msg_ok "Installed adaptation dependencies"

mkdir -p "$INSTALL_DIR" /var/backups/guacamole
chmod 700 "$INSTALL_DIR" /var/backups/guacamole

msg_info "Downloading pinned Itiligent installer"
curl -fsSL --retry 3 --retry-delay 2 "${UPSTREAM_BASE}/1-setup.sh" -o "$SETUP_SCRIPT"
[[ -s "$SETUP_SCRIPT" ]] || fatal "Downloaded an empty Itiligent setup script"
chmod 700 "$SETUP_SCRIPT"
msg_ok "Downloaded pinned Itiligent installer"

msg_info "Adapting Itiligent installer for Proxmox LXC"
python3 - "$SETUP_SCRIPT" "$UPSTREAM_COMMIT" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
commit = sys.argv[2]
s = path.read_text()

# Make the neutral UTF-8 installation locale explicit inside the adapted parent
# script too. This protects child execution even if the surrounding launcher or
# retained helper framework changes its environment handling later.
if 'export LC_ALL=C.UTF-8' not in s:
    s = s.replace(
        '#!/bin/bash\n',
        '#!/bin/bash\nexport LANG=C.UTF-8\nexport LC_ALL=C.UTF-8\n',
        1,
    )

# Root execution is the normal Proxmox LXC installation model for this project.
s = re.sub(
    r'# Make sure the user is NOT running this script as root.*?'
    r'# Check to see if any previous version of build files exist',
    '# Proxmox adaptation: run as root; sudo-user preflight checks removed.\n\n'
    '# Check to see if any previous version of build files exist',
    s,
    flags=re.S,
)

# Use stable root-owned appliance paths instead of a sudo user home.
s = re.sub(r'^USER_HOME_DIR=.*$', 'USER_HOME_DIR=/root', s, flags=re.M)
s = re.sub(r'^DOWNLOAD_DIR=.*$', 'DOWNLOAD_DIR=/opt/itiligent-guacamole', s, flags=re.M)
s = re.sub(r'^DB_BACKUP_DIR=.*$', 'DB_BACKUP_DIR=/var/backups/guacamole', s, flags=re.M)
s = re.sub(
    r'^GITHUB=.*$',
    f'GITHUB="https://raw.githubusercontent.com/itiligent/Easy-Guacamole-Installer/{commit}"',
    s,
    flags=re.M,
)

# The upstream Ctrl+Z instruction is unsafe and misleading while running under
# the Proxmox container builder. The feature prompts themselves are preserved.
s = s.replace(
    'echo -e "${LYELLOW}Ctrl+Z now to exit now if you wish to customise 1-setup.sh options or create an unattended install."',
    'echo -e "${LYELLOW}Interactive configuration follows. Complete each prompt to continue.${GREY}"',
)

# Proxmox owns hostname, hosts entries, DNS and resolv.conf.
identity = r'''# Proxmox adaptation: retain container identity and network configuration.
SERVER_NAME="${SERVER_NAME:-$(hostname -s)}"
LOCAL_DOMAIN="${LOCAL_DOMAIN:-$(hostname -d 2>/dev/null || true)}"
DOMAIN_SUFFIX="${LOCAL_DOMAIN:-local}"
if [[ -n "${LOCAL_DOMAIN}" ]]; then
    DEFAULT_FQDN="${SERVER_NAME}.${LOCAL_DOMAIN}"
else
    DEFAULT_FQDN="${SERVER_NAME}"
fi
if [[ -z "${RDP_SHARE_HOST}" ]]; then
    RDP_SHARE_HOST="${SERVER_NAME}"
fi

'''
s = re.sub(
    r'# Consistent /etc/hosts and domain suffix values are needed.*?'
    r'# Prompt to install MySQL',
    identity + '# Prompt to install MySQL',
    s,
    flags=re.S,
)

# Remove sudo throughout the root-run parent script.
s = re.sub(r'(?<![A-Za-z0-9_])sudo\s+-E\s+', '', s)
s = re.sub(r'(?<![A-Za-z0-9_])sudo\s+', '', s)
s = s.replace('${SUDO_USER}', 'root').replace('$SUDO_USER', 'root')

# Patch downloaded child scripts before any child is executed.
patch_block = r'''
# Proxmox adaptation: patch child scripts for root-run LXC execution and force
# a known-good UTF-8 locale inside each child, independent of inherited host
# locale variables or future helper-framework environment changes.
for child_script in "$DOWNLOAD_DIR"/*.sh; do
    grep -Fqx 'export LANG=C.UTF-8' "$child_script" || sed -i '2i export LANG=C.UTF-8' "$child_script"
    grep -Fqx 'export LC_ALL=C.UTF-8' "$child_script" || sed -i '3i export LC_ALL=C.UTF-8' "$child_script"
    sed -i -E \
      -e 's/(^|[[:space:]])sudo[[:space:]]+-E[[:space:]]+/\1/g' \
      -e 's/(^|[[:space:]])sudo[[:space:]]+/\1/g' \
      -e 's/\$\{SUDO_USER\}/root/g' \
      -e 's/\$SUDO_USER/root/g' \
      "$child_script"
done

# UFW is not installed or configured inside the container. Firewall policy is
# managed by Proxmox and the surrounding network.
sed -i 's/ ${FREERDP} ufw pwgen/ ${FREERDP} pwgen/' "$DOWNLOAD_DIR/2-install-guacamole.sh"
for child_script in \
  "$DOWNLOAD_DIR/2-install-guacamole.sh" \
  "$DOWNLOAD_DIR/3-install-nginx.sh" \
  "$DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh" \
  "$DOWNLOAD_DIR/4b-install-tls-letsencrypt-nginx.sh"; do
    sed -i -E '/^[[:space:]]*(echo[[:space:]]+"y"[[:space:]]*\|[[:space:]]*)?ufw([[:space:]]|$)/c\:' "$child_script"
done

# Keep the upgrade helper on root-owned appliance paths.
sed -i -E \
  -e 's|^USER_HOME_DIR=.*|USER_HOME_DIR=/root|' \
  -e 's|^DOWNLOAD_DIR=.*|DOWNLOAD_DIR=/opt/itiligent-guacamole|' \
  "$DOWNLOAD_DIR/upgrade-guacamole.sh"

'''
s = s.replace(
    '# Pause here to optionally customise downloaded scripts before any actual install actions begin',
    patch_block + '# Pause here to optionally customise downloaded scripts before any actual install actions begin',
)

# Avoid moving a missing script if the upstream cleanup layout changes.
s = s.replace(
    'mv $USER_HOME_DIR/1-setup.sh $DOWNLOAD_DIR',
    '[[ -f $USER_HOME_DIR/1-setup.sh ]] && mv $USER_HOME_DIR/1-setup.sh $DOWNLOAD_DIR || true',
)

path.write_text(s)
PY
chmod 700 "$SETUP_SCRIPT"
msg_ok "Adapted Itiligent installer for Proxmox LXC"

# Do not wrap the interactive upstream menu in msg_info. Its spinner redraws
# the same terminal line and hides interactive prompts, so keep the installer
# attached directly to the active terminal instead. Set the locale explicitly
# on this execution boundary as an additional guard against inherited host state.
echo
echo -e "${INFO}${YW}Starting interactive Itiligent Guacamole configuration.${CL}"
echo -e "${INFO}${YW}Answer each prompt below; password input will not be echoed.${CL}"
echo
cd /root
if [[ -r /dev/tty ]]; then
  env LANG=C.UTF-8 LC_ALL=C.UTF-8 bash "$SETUP_SCRIPT" </dev/tty
else
  env LANG=C.UTF-8 LC_ALL=C.UTF-8 bash "$SETUP_SCRIPT"
fi
msg_ok "Itiligent Guacamole setup completed"

printf '%s\n' "$UPSTREAM_COMMIT" >/etc/itiligent-guacamole-upstream-commit
chmod 600 /etc/itiligent-guacamole-upstream-commit

motd_ssh
if [[ -f /etc/profile.d/00_lxc-details.sh ]]; then
  sed -i '/community-scripts/d' /etc/profile.d/00_lxc-details.sh
fi
customize
cat >/usr/bin/update <<EOF_UPDATE
#!/usr/bin/env bash
set -Eeuo pipefail
set -a
[ -f /etc/profile.d/90-http-proxy.sh ] && . /etc/profile.d/90-http-proxy.sh
set +a
bash -c "\$(curl -fsSL ${PROJECT_UPDATE_URL})"
EOF_UPDATE
chmod 0755 /usr/bin/update
cleanup_lxc

# install.func creates a diagnostics preference file during bootstrap. This
# project never uses it; remove the unused artifact after all framework helpers
# have finished.
rm -f /usr/local/community-scripts/diagnostics
rmdir /usr/local/community-scripts 2>/dev/null || true
