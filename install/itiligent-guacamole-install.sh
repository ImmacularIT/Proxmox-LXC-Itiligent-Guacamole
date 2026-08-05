#!/usr/bin/env bash
# Copyright (c) 2026 ImmacularIT
# License: MIT
# Proxmox LXC adaptation of the Itiligent Easy Guacamole Installer.

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

readonly UPSTREAM_COMMIT="676eb7e2711dabdf7f33fa7fe91eafc3dbdb7fce"
readonly UPSTREAM_BASE="https://raw.githubusercontent.com/itiligent/Easy-Guacamole-Installer/${UPSTREAM_COMMIT}"
readonly SETUP_SCRIPT="/root/1-setup.sh"
readonly INSTALL_DIR="/opt/itiligent-guacamole"

msg_info "Installing adaptation dependencies"
$STD apt-get install -y ca-certificates curl wget python3 iproute2 cron procps
msg_ok "Installed adaptation dependencies"

mkdir -p "$INSTALL_DIR" /var/backups/guacamole
chmod 700 "$INSTALL_DIR" /var/backups/guacamole

msg_info "Downloading pinned Itiligent installer"
curl_download "$SETUP_SCRIPT" "${UPSTREAM_BASE}/1-setup.sh"
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

# Root execution is the normal Community Scripts install model.
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
# Proxmox adaptation: patch child scripts for root-run LXC execution.
for child_script in "$DOWNLOAD_DIR"/*.sh; do
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

# Retain upstream Debian 13 behavior and menus. The parent and all downloaded
# child scripts have only their Proxmox-incompatible assumptions patched.
msg_info "Starting Itiligent Guacamole setup"
cd /root
bash "$SETUP_SCRIPT"
msg_ok "Itiligent Guacamole setup completed"

printf '%s\n' "$UPSTREAM_COMMIT" >/etc/itiligent-guacamole-upstream-commit
chmod 600 /etc/itiligent-guacamole-upstream-commit

motd_ssh
customize
cleanup_lxc
