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

# The normal interactive entry path is project-owned. The Welcome screen carries
# the explanatory information; the following chooser intentionally mirrors the
# compact NPM layout with only the two mode names visible.
assert 'PROJECT_DISPLAY_NAME="Itiligent Guacamole LXC"' in launcher
assert 'show_project_welcome() {' in launcher
assert 'select_project_install_mode() {' in launcher
assert 'Privacy: this installer does not send telemetry or diagnostics.' in launcher
project_menu = launcher.split('select_project_install_mode() {', 1)[1].split('prepare_latest_debian_template() {', 1)[0]
assert '--title "INSTALL OPTIONS"' in project_menu
assert '--ok-button "Select" --cancel-button "Exit Script"' in project_menu
assert '--menu "\\nChoose an option:" 14 62 2' in project_menu
assert '"Default Install" ""' in project_menu
assert '"Advanced Install" ""' in project_menu
assert '--default-item "Default Install"' in project_menu
assert '"Default Install") mode="default"' in project_menu
assert '"Advanced Install") mode="advanced"' in project_menu
assert 'recommended guided setup with standard resources' not in project_menu
assert 'full Proxmox container configuration' not in project_menu
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
assert 'User Defaults' not in project_menu
assert 'Edit Default.vars' not in project_menu
assert 'Edit App.vars' not in project_menu

# Fresh Debian containers can inherit host regional LC_* values before those
# locales exist in the guest. Keep the neutral locale guards, but also capture
# the inherited UTF-8 locale names and generate them inside the guest. This
# fixes the underlying condition even if a downstream process later clears
# LC_ALL and exposes the individual regional LC_* variables again.
helper_source = 'source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"'
assert 'PROJECT_INHERITED_UTF8_LOCALES=()' in installer
assert 'project_capture_locale() {' in installer
assert 'project_capture_locale "${!locale_var:-}"' in installer
assert 'project_capture_locale "en_US.UTF-8"' in installer
assert installer.index('PROJECT_INHERITED_UTF8_LOCALES=()') < installer.index('export LANG=C.UTF-8')
assert installer.count('export LANG=C.UTF-8') >= 4
assert installer.count('export LC_ALL=C.UTF-8') >= 4
assert helper_source in installer
first_lang = installer.index('export LANG=C.UTF-8')
first_lc = installer.index('export LC_ALL=C.UTF-8')
helper_pos = installer.index(helper_source)
assert first_lang < helper_pos
assert first_lc < helper_pos
post_helper = installer[helper_pos + len(helper_source):]
assert 'export LANG=C.UTF-8' in post_helper
assert 'export LC_ALL=C.UTF-8' in post_helper
assert 'project_prepare_guest_locales() {' in installer
locale_fn = installer.split('project_prepare_guest_locales() {', 1)[1].split('\n}\n\ncolor', 1)[0]
assert 'apt-get install -y locales' in locale_fn
assert 'for locale_name in "${PROJECT_INHERITED_UTF8_LOCALES[@]}"' in locale_fn
assert '/etc/locale.gen' in locale_fn
assert 'locale-gen >/dev/null' in locale_fn
assert 'project_update_os\nproject_prepare_guest_locales\n' in installer
assert installer.index('project_prepare_guest_locales\n') < installer.index('readonly UPSTREAM_COMMIT=')
assert "'#!/bin/bash\\nexport LANG=C.UTF-8\\nexport LC_ALL=C.UTF-8\\n'" in installer
assert "sed -i '2i export LANG=C.UTF-8' \"$child_script\"" in installer
assert "sed -i '3i export LC_ALL=C.UTF-8' \"$child_script\"" in installer
assert 'env LANG=C.UTF-8 LC_ALL=C.UTF-8 bash "$SETUP_SCRIPT" </dev/tty' in installer
assert 'env LANG=C.UTF-8 LC_ALL=C.UTF-8 bash "$SETUP_SCRIPT"' in installer

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

print("Telemetry-free installer, clean project entry UI, Default storage, and generated guest locale invariants validated.")
