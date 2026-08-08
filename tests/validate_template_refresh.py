#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
launcher = (ROOT / "ct/itiligent-guacamole.sh").read_text()

required = [
    "prepare_latest_debian_template() {",
    '[[ "$(dpkg --print-architecture 2>/dev/null || true)" == "amd64" ]] || return 0',
    '[[ "${var_os:-debian}" == "debian" && "${var_version:-13}" == "13" ]] || return 0',
    'msg_info "Refreshing the official Proxmox appliance catalog"',
    'pveam update >>"${BUILD_LOG:-/dev/null}" 2>&1',
    "^debian-13-standard_.*_amd64\\.tar\\.zst$",
    'existing_name="${existing##*/}"',
    "newest_name=$(printf '%s\\n%s\\n' \"$existing_name\" \"$available\" | sort -V | tail -n1)",
    'msg_info "No cached Debian 13 template found on ${storage}; downloading ${available}"',
    'msg_info "Newer Debian 13 template available (${existing_name} -> ${available}); downloading ${available}"',
    'msg_warn "Cached Debian template ${existing_name} is newer than catalog ${available}; keeping cached template"',
    'pveam download "$storage" "$available"',
    'var_template_storage="$storage"',
    'msg_ok "Debian template ready:',
]
for marker in required:
    assert marker in launcher, f"Missing Debian template freshness marker: {marker}"

# The project-owned freshness pass must run after the framework has resolved the
# selected template storage, but before the framework creates the container.
start_call = launcher.index("\nstart\n")
prepare_call = launcher.index("\nprepare_latest_debian_template\n", start_call)
build_call = launcher.index("\nbuild_container\n", prepare_call)
assert start_call < prepare_call < build_call

# Old cached templates are intentionally retained. Freshness means selecting or
# downloading the newest image, not deleting administrator-managed cache files.
assert "pveam remove" not in launcher
assert "pveam delete" not in launcher

# The Welcome screen should accurately describe the automatic freshness policy.
assert "official Proxmox appliance catalog is refreshed" in launcher
assert "downloaded automatically when missing or when the cached image is older" in launcher

print("Debian template freshness invariants validated.")
