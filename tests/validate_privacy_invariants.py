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
assert '"Default Install"' not in launcher or 'start' in launcher
assert 'build_container' in launcher
assert 'configure_default_identity' in launcher
assert 'configure_default_network' in launcher
assert 'set_project_description' in launcher

# Container-side DNS checks must be limited to the actual GitHub hosts needed by
# this project, and the generated update helper must return to this repository.
assert 'GIT_HOSTS=("github.com" "raw.githubusercontent.com" "api.github.com")' in installer
assert 'PROJECT_UPDATE_URL="https://raw.githubusercontent.com/ImmacularIT/Proxmox-LXC-Itiligent-Guacamole/main/ct/itiligent-guacamole.sh"' in installer
assert 'cat >/usr/bin/update <<EOF_UPDATE' in installer
assert "sed -i '/community-scripts/d' /etc/profile.d/00_lxc-details.sh" in installer
assert 'rm -f /usr/local/community-scripts/diagnostics' in installer

# Preserve the exact pinned Itiligent release and normal project adaptation
# flow; this privacy cleanup must not silently switch upstream versions.
assert 'UPSTREAM_COMMIT="676eb7e2711dabdf7f33fa7fe91eafc3dbdb7fce"' in installer
assert 'bash "$SETUP_SCRIPT" </dev/tty' in installer
assert 'cleanup_lxc' in installer

print("Telemetry-free installer invariants validated.")
