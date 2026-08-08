#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
launcher = (ROOT / "ct/itiligent-guacamole.sh").read_text()
installer = (ROOT / "install/itiligent-guacamole-install.sh").read_text()
combined = launcher + "\n" + installer

# The established external Proxmox build framework remains a compatibility
# dependency for container-creation mechanics, but this project must never opt
# in to, call, or expose its diagnostics/telemetry service.
for text in (launcher, installer):
    assert 'DIAGNOSTICS="no"' in text
    assert 'post_to_api() { return 0; }' in text
    assert 'post_progress_to_api() { return 0; }' in text
    assert 'post_update_to_api() { return 0; }' in text
    assert 'telemetry_new_attempt() { return 0; }' in text

for forbidden in [
    "telemetry.community-scripts.org",
    "git.community-scripts.org",
    "Manage API-Diagnostic Setting",
    "TELEMETRY & DIAGNOSTICS",
    "community-scripts ORG",
]:
    assert forbidden not in combined, f"Forbidden telemetry/branding marker: {forbidden}"

# The host launcher must suppress the framework's diagnostics prompt and
# external fallback header while preserving its Default/Advanced machinery.
assert 'diagnostics_check() {' in launcher
assert 'get_header() { return 0; }' in launcher
assert 'settings_menu() {' in launcher
assert 'build_container' in launcher
assert 'configure_default_identity' in launcher
assert 'configure_default_container_storage' in launcher
assert 'configure_default_network' in launcher
assert 'set_project_description' in launcher

# The normal interactive entry path is project-owned. It presents useful
# project/privacy context and exposes only Default and Advanced installation
# modes, then hands the selected preset to the unchanged framework machinery.
assert 'PROJECT_DISPLAY_NAME="Itiligent Guacamole LXC"' in launcher
assert 'show_project_welcome() {' in launcher
assert 'select_project_install_mode() {' in launcher
assert 'Privacy: this installer does not send telemetry or diagnostics.' in launcher
assert 'Default Install - recommended guided setup with standard resources' in launcher
assert 'Advanced Install - full Proxmox container configuration' in launcher
assert 'mode="default"' in launcher
assert 'mode="advanced"' in launcher
selector = 'select_project_install_mode "${1:-}"'
assert selector in launcher
assert launcher.index(selector) < launcher.index('\nstart\n')

# Default Install must always expose the root-disk storage chooser instead of
# silently inheriting a saved framework default. The current/saved storage may
# be preselected, but the user's selection must be exported before creation.
storage_fn = launcher.split('configure_default_container_storage() {', 1)[1].split('configure_default_network() {', 1)[0]
assert 'pvesm status --content rootdir' in storage_fn
assert 'DEFAULT INSTALL: STORAGE' in storage_fn
assert 'Select storage for the LXC root disk:' in storage_fn
assert 'CONTAINER_STORAGE="$selected"' in storage_fn
assert 'var_container_storage="$selected"' in storage_fn
assert 'export CONTAINER_STORAGE var_container_storage' in storage_fn

flow_markers = [
    'configure_default_identity\n',
    'configure_default_container_storage\n',
    'configure_default_network\n',
    'prepare_latest_debian_template\n',
    'configure_project_tags\n',
    '\nbuild_container\n',
]
positions = [launcher.index(marker) for marker in flow_markers]
assert positions == sorted(positions), "Default storage/network/template flow is out of order"

# User Defaults and Settings remain internal compatibility capabilities only;
# they are not options in the project-owned normal installation mode menu.
project_menu = launcher.split('select_project_install_mode() {', 1)[1].split('function update_script()', 1)[0]
assert 'User Defaults' not in project_menu
assert 'Edit Default.vars' not in project_menu
assert 'Edit App.vars' not in project_menu

# Container-side DNS checks must be limited to the actual GitHub hosts needed by
# this project, and the generated update helper must return to this repository.
assert 'GIT_HOSTS=("github.com" "raw.githubusercontent.com" "api.github.com")' in installer
assert 'PROJECT_UPDATE_URL="https://raw.githubusercontent.com/ImmacularIT/Proxmox-LXC-Itiligent-Guacamole/main/ct/itiligent-guacamole.sh"' in installer
assert 'cat >/usr/bin/update <<EOF_UPDATE' in installer
assert "sed -i '/community-scripts/d' /etc/profile.d/00_lxc-details.sh" in installer
assert 'rm -f /usr/local/community-scripts/diagnostics' in installer

# Preserve the exact pinned Itiligent release and normal project adaptation
# flow; this privacy/UI cleanup must not silently switch upstream versions.
assert 'UPSTREAM_COMMIT="676eb7e2711dabdf7f33fa7fe91eafc3dbdb7fce"' in installer
assert 'bash "$SETUP_SCRIPT" </dev/tty' in installer
assert 'cleanup_lxc' in installer

print("Telemetry-free installer, project entry UI, and Default storage invariants validated.")
