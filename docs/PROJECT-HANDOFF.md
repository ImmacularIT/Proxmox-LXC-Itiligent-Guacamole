# Project Technical Handoff and Maintenance Workflow

This document records the implementation, design decisions, test results, known limitations, failures encountered, and maintenance workflow for `ImmacularIT/Proxmox-Itiligent-Guacamole`.

**Status snapshot:** 2026-08-06  
**Production branch:** `main`  
**Test platform:** Proxmox VE 9.2.6, unprivileged Debian 13 LXC  
**Pinned Itiligent revision:** `676eb7e2711dabdf7f33fa7fe91eafc3dbdb7fce`

Always inspect the current repository state and upstream sources before making changes. The Community Scripts framework and Itiligent source may have changed since this snapshot.

## Executive summary

This project adapts the Itiligent Easy Guacamole Installer to a Community Scripts-style Proxmox LXC installation.

The adaptation does not reimplement Apache Guacamole. It downloads a pinned Itiligent installer at runtime and applies deterministic compatibility transformations so the suite can run inside a Proxmox-managed LXC where installation occurs as `root`.

The tested production installation method is:

```bash
bash <(curl -fsSL \
  https://raw.githubusercontent.com/ImmacularIT/Proxmox-Itiligent-Guacamole/main/ct/itiligent-guacamole.sh)
```

The validated core path includes:

- Proxmox VE 9.2.6;
- an unprivileged Debian 13 LXC;
- local database installation;
- visible interactive Itiligent configuration;
- native Guacamole access;
- successful login and management access;
- Advanced Install with a selected bridge, static IPv4 address, and VLAN tag;
- an RDP connection to a Windows 11 server.

A compact network wizard has been added to Default Install. It exposes bridge, DHCP/static IPv4, gateway, and VLAN choices without requiring the full Advanced wizard. That new Default path still requires a disposable runtime test before it should be considered validated.

## Project scope and ownership boundaries

The project preserves the upstream Itiligent menus and feature choices while changing assumptions that conflict with Proxmox LXC operation.

The following boundaries are intentional:

- Proxmox creates and owns the container.
- Proxmox owns bridge selection, VLAN tagging, DHCP/static addressing, IPv6, hostname, DNS, `/etc/hosts`, and `/etc/resolv.conf`.
- Firewall policy is managed by Proxmox and the surrounding network, not by UFW inside the container.
- Installation runs as `root`, which is the normal Community Scripts container-installation model.
- Itiligent application, backup, and upgrade files use root-owned appliance paths.
- The upstream Itiligent source is pinned to a commit for reproducibility.
- No credentials or access tokens are committed.

## Repository layout

```text
.github/workflows/syntax.yml
    Bash, JSON, and path validation.

ct/itiligent-guacamole.sh
    Proxmox-host launcher. Creates the LXC through Community Scripts build.func.
    Adds the compact Default Install network wizard.

install/itiligent-guacamole-install.sh
    Runs inside the container. Downloads and patches the pinned Itiligent suite.

json/itiligent-guacamole.json
    Community-style metadata and installation path definitions.

README.md
    User-facing project overview and direct installation instructions.

docs/PROJECT-HANDOFF.md
    This implementation and maintenance handoff.
```

## Runtime flow

### 1. Host-side launcher

`ct/itiligent-guacamole.sh` runs on the Proxmox host.

It performs the following work:

1. Sources the current Community Scripts `misc/build.func` from `community-scripts/ProxmoxVE/main`.
2. Defines the application defaults:
   - 8 GB disk;
   - 1 CPU;
   - 2048 MB RAM;
   - Debian 13;
   - unprivileged LXC;
   - ARM64 allowed by launcher metadata.
3. Initializes the standard Community Scripts menu and error handling.
4. Defines an `update_script()` function that invokes `/opt/itiligent-guacamole/upgrade-guacamole.sh` when an existing installation is detected.
5. Sets the project installer source to this repository and defaults the project ref to `main`.
6. Calls `start` to collect Default, Advanced, or saved container settings and storage selection.
7. When `METHOD=default` and an interactive terminal is available, runs `configure_default_network`.
8. Temporarily wraps the shell `curl` command so the Community Scripts request for its normal `install/${var_install}.sh` URL is rewritten to this repository's `install/itiligent-guacamole-install.sh`.
9. Calls `build_container`.
10. Removes the temporary `curl` wrapper.
11. Prints the native fallback URL at `http://CONTAINER-IP:8080/guacamole`.

### Default Install network wizard

The compact network wizard is intentionally limited to the settings that commonly differ between Proxmox environments:

- bridge;
- DHCP or static IPv4;
- IPv4 gateway for static addressing;
- optional VLAN tag.

Implementation details:

- It runs only when the Community Scripts method is `default`.
- It is skipped for Advanced Install, User Defaults, App Defaults, generated settings, silent execution, and non-interactive execution.
- It runs after the standard storage selection and before `build_container`.
- It enumerates Linux bridge devices from `/sys/class/net/*/bridge`.
- Every bridge is checked with Community Scripts `validate_bridge()`.
- Static addresses are checked with `validate_ip_address()`.
- Gateways are checked with `validate_gateway_ip()` and `validate_gateway_in_subnet()`.
- VLAN values are checked with `validate_vlan_tag()` and may be blank for an untagged interface.
- A final review screen allows the settings to be accepted or changed.
- The selected values are assigned to and exported as:

  ```text
  BRG
  SDN_VNET
  NET
  GATE
  VLAN
  ```

- `SDN_VNET` is cleared because this compact path selects Linux bridges rather than Proxmox SDN vnets.
- Per-install static IP choices are not written into global defaults, avoiding reuse of a unique address on a later container.

### Why the installer URL interception exists

The Community Scripts builder normally calculates an installer URL inside the official `community-scripts/ProxmoxVE` repository. This project lives in a separate repository, so the launcher intercepts only that exact installer URL and substitutes this project's installer URL.

This is a compatibility bridge and depends on the current Community Scripts implementation continuing to:

- fetch the installer with `curl`;
- request the expected official raw URL;
- perform that request after the wrapper has been defined.

If `build.func` changes its download client, URL format, variable naming, or execution order, the interception may stop working. Every maintenance cycle should inspect the current `build.func` before assuming this mechanism remains valid.

The Community Scripts framework is loaded from its moving `main` branch. Therefore, the Itiligent source is pinned, but the outer container builder is not fully reproducible.

### 2. Container-side installer

`install/itiligent-guacamole-install.sh` runs inside the newly created LXC.

It performs the standard Community Scripts initialization:

- loads the function library supplied through `FUNCTIONS_FILE_PATH`;
- configures color and IPv6 behavior;
- enables error handling;
- checks networking;
- updates the operating system.

It installs these adaptation dependencies:

```text
ca-certificates curl wget python3 iproute2 cron procps
```

It creates and protects these paths:

```text
/opt/itiligent-guacamole
/var/backups/guacamole
```

Both are set to mode `0700`.

### 3. Pinned upstream download

The adapter initially downloads `1-setup.sh` from the pinned upstream commit:

```text
676eb7e2711dabdf7f33fa7fe91eafc3dbdb7fce
```

The temporary local path is:

```text
/root/1-setup.sh
```

The downloaded parent script is transformed with an embedded Python program before execution.

## Exact upstream transformations

The Python transformation is the core of the container-side adaptation. It modifies the downloaded upstream script and writes the result back to `/root/1-setup.sh`.

### Root execution

The upstream block that prevents root execution and expects a sudo user is removed.

All parent-script `sudo` and `sudo -E` invocations are removed, and references to `SUDO_USER` are replaced with `root`.

Reason: Community Scripts installers run as root inside the container.

### Stable appliance paths

These upstream variables are replaced:

```text
USER_HOME_DIR=/root
DOWNLOAD_DIR=/opt/itiligent-guacamole
DB_BACKUP_DIR=/var/backups/guacamole
```

The upstream `GITHUB` download base is replaced with a raw GitHub URL containing the pinned commit.

Reason: avoid dependence on a transient sudo user's home and prevent child-script downloads from drifting to a moving upstream branch.

### Misleading Ctrl+Z message

The upstream message suggesting `Ctrl+Z` is replaced with:

```text
Interactive configuration follows. Complete each prompt to continue.
```

Reason: suspending the process inside the Proxmox container builder is unsafe and confusing.

### Container identity and networking

The upstream block that normalizes `/etc/hosts`, domain suffixes, and related host identity is replaced.

The replacement derives values from the existing container identity without rewriting Proxmox-managed files:

- `SERVER_NAME` from `hostname -s`;
- `LOCAL_DOMAIN` from `hostname -d` when available;
- `DOMAIN_SUFFIX` from the local domain or `local`;
- `DEFAULT_FQDN` from the existing hostname/domain;
- `RDP_SHARE_HOST` from the existing server name when unset.

Reason: Proxmox must remain the authority for container hostname and network configuration.

### Child-script root adaptation

Before any downloaded child script is executed, an inserted shell block loops over:

```text
/opt/itiligent-guacamole/*.sh
```

For every child script it:

- removes `sudo -E`;
- removes `sudo`;
- replaces `${SUDO_USER}` with `root`;
- replaces `$SUDO_USER` with `root`.

Reason: adapting only the parent script is insufficient because the parent downloads and executes additional scripts.

### UFW removal

The package list in `2-install-guacamole.sh` is modified to remove `ufw`.

UFW command lines are replaced with no-op commands in these known scripts:

```text
2-install-guacamole.sh
3-install-nginx.sh
4a-install-tls-self-signed-nginx.sh
4b-install-tls-letsencrypt-nginx.sh
```

Reason: firewall policy belongs to Proxmox and the surrounding network. Installing or changing UFW inside the LXC can conflict with that policy.

### Upgrade-helper paths

The downloaded `upgrade-guacamole.sh` is modified to retain:

```text
USER_HOME_DIR=/root
DOWNLOAD_DIR=/opt/itiligent-guacamole
```

The existence of the helper is used by the host-side `update_script()` detection logic.

The upgrade workflow has not yet been functionally tested and should be treated as unvalidated.

### Cleanup guard

The upstream move operation for `1-setup.sh` is changed from an unconditional `mv` to a guarded operation that succeeds when the source file has already moved or no longer exists.

Reason: avoid a fatal cleanup failure if upstream layout or ordering changes.

## Interactive terminal issue and fix

### Original symptom

The first real installation reached the Itiligent setup, but interactive questions appeared blank or were overwritten. The display repeatedly showed the Community Scripts spinner while the installer silently waited for input. Pressing Enter several times eventually produced an empty-password warning.

The relevant visible behavior included:

```text
Starting Itiligent Guacamole setup
MySQL setup options:
Passwords don't match or can't be null. Please try again.
```

### Root cause

The interactive upstream setup was wrapped in Community Scripts `msg_info`/`msg_ok` status handling.

`msg_info` starts an animated spinner that redraws the terminal line. The upstream installer was still accepting input, but the spinner repeatedly erased or obscured its questions.

### Fix

Commit `105ce8e997ba00b7699e2a43800e5e261a8d07bd` made three changes:

1. Removed the `msg_info` wrapper around the interactive setup.
2. Added static explanatory messages before the menu.
3. Attached the upstream script's standard input directly to `/dev/tty` when available:

```bash
if [[ -r /dev/tty ]]; then
  bash "$SETUP_SCRIPT" </dev/tty
else
  bash "$SETUP_SCRIPT"
fi
```

This preserved the original interactive menus and made the questions visible. The subsequent installation completed successfully.

## Network-selection behavior

Network configuration is applied by the Community Scripts container builder. This project now exposes two levels of network configuration:

### Default Install

Default Install keeps the normal application resource defaults and the standard storage selection. It then presents the compact project-specific network wizard for:

- bridge;
- DHCP or static IPv4;
- gateway;
- VLAN.

IPv6, DNS, MTU, MAC address, SDN vnets, and other uncommon properties remain outside the compact wizard.

### Advanced Install

Advanced Install retains the full Community Scripts wizard, including:

- bridge or supported SDN selection;
- DHCP, static IPv4, or range scanning;
- gateway;
- IPv6;
- DNS;
- MTU;
- MAC address;
- VLAN;
- CPU, RAM, disk, SSH, and container features.

Advanced Install was tested successfully with a selected bridge, static IPv4 address, and VLAN tag on 2026-08-06.

For a VLAN-aware trunk, select the appropriate bridge and enter the VLAN tag. If a bridge is already an untagged/access connection to the target network, do not also set a VLAN tag.

## Metadata and CI work

### Metadata

`json/itiligent-guacamole.json` contains:

- name and slug;
- CT type;
- unprivileged-container status;
- port 8080;
- Debian 13 resource defaults;
- launcher path `ct/itiligent-guacamole.sh`;
- initial upstream credentials;
- repository URL and user notes.

The metadata path and naming conventions are internally consistent with the repository layout.

### Repository validation workflow

`.github/workflows/syntax.yml` runs on pushes and pull requests.

It currently validates:

- Bash syntax for the launcher;
- Bash syntax for the container installer;
- JSON syntax for the metadata;
- presence of required metadata fields;
- expected slug and type;
- existence of every metadata launcher path;
- existence of `install/${slug}-install.sh`.

The workflow does not currently:

- download the pinned upstream source;
- execute the Python adaptation in a temporary directory;
- verify that every expected replacement matched exactly once;
- run ShellCheck;
- create an LXC;
- exercise the compact Default network wizard;
- validate optional Itiligent features.

Adding deterministic transformation and launcher tests is a high-value future enhancement.

## PVE Scripts Management interoperability finding

The metadata was created because PVE Scripts Management exposes a custom repository setting. Testing showed that adding this repository did not make the script appear after synchronization.

Observed evidence from the PVE Scripts Management container:

- no `itiligent-guacamole.json` file existed under `/opt/**/scripts/json/`;
- service logs contained no request to `ImmacularIT/Proxmox-Itiligent-Guacamole`;
- service logs showed downloads only from `community-scripts/ProxmoxVE`.

Source review of the tested PVE Scripts Management/ProxmoxVE-Local version showed an integration gap:

- repository settings expose create/update/delete/enable operations;
- the active Available Scripts page is populated from PocketBase;
- normal synchronization refreshes PocketBase data and logos;
- auto-sync also treats PocketBase as the source of truth;
- the active download routes require a PocketBase script record;
- lower-level local JSON code exists but is not connected end-to-end to custom repository synchronization and selection.

Therefore, the currently tested installation method is the direct host command. The JSON metadata is retained for future interoperability testing.

Do not document custom-repository installation as working unless the full synchronization, catalogue, and download flow has been retested against the installed PVE Scripts Management version.

## Test matrix

| Area | Status | Notes |
|---|---|---|
| Unprivileged Debian 13 LXC creation | Passed | Tested on Proxmox VE 9.2.6. |
| Local database installation | Passed | Completed through interactive Itiligent setup. |
| Interactive question visibility and password entry | Passed | Fixed by removing the spinner wrapper and using `/dev/tty`. Password input intentionally does not echo. |
| Native Guacamole access | Passed | Native URL available on port 8080. |
| Initial login and management UI | Passed | Login and administration confirmed. |
| Advanced bridge/static IPv4/VLAN install | Passed | Confirmed on 2026-08-06. |
| Default compact network wizard | Implemented; runtime test pending | Requires a disposable Default Install test with DHCP and static/VLAN paths. |
| RDP connection | Passed | Connection to a Windows 11 server worked without problems. |
| SSH connection | Not tested | Pending. |
| VNC connection | Not tested | Pending. |
| Remote MySQL/MariaDB | Not tested | Pending. |
| Nginx HTTP frontend | Not tested | Pending. |
| Self-signed TLS | Not tested | Pending. |
| Let's Encrypt | Not tested | Requires valid DNS and reachable ports 80/443. |
| TOTP | Not tested | Pending. |
| Duo | Not tested | Pending. |
| LDAP | Not tested | Pending. |
| Quick Connect | Not tested | Pending. |
| History Recording Storage | Not tested | Pending. |
| SMTP relay helper | Not tested | Pending. |
| guacd TLS helper | Not tested | Pending. |
| fail2ban helper | Not tested | Pending. |
| Backup cron/helper | Not tested | Pending. |
| Upgrade helper | Not tested | Take a snapshot before testing. |
| ARM64 | Not tested | Launcher currently declares ARM64 support. |
| PVE Scripts Management custom repository | Blocked by tested management-app flow | Metadata is present, but the tested app flow did not ingest or display it. |

## Known risks and fragile assumptions

### Moving Community Scripts builder

The launcher sources `community-scripts/ProxmoxVE/main/misc/build.func`. A future Community Scripts change can affect this project without any commit here.

Before a release or maintenance change, inspect the current builder and retest:

- installer URL interception;
- `METHOD` values;
- `start` returning before `build_container`;
- runtime variables `BRG`, `SDN_VNET`, `NET`, `GATE`, and `VLAN`;
- validation helpers used by the compact network wizard.

### Default network wizard assumptions

The compact wizard depends on:

- Linux bridge devices appearing under `/sys/class/net/<name>/bridge`;
- Community Scripts validation helpers remaining available after sourcing `build.func`;
- `build_container` continuing to consume the exported network variables;
- interactive Default Install retaining terminal input.

The wizard deliberately does not expose Proxmox SDN vnets. Use Advanced Install for SDN and the complete network feature set.

### Silent upstream patch misses

Several Python replacements use `re.sub()` or `str.replace()` without checking how many matches were found.

If upstream changes a comment, variable assignment, filename, or exact message, a patch can stop applying without failing immediately.

A future hardening change should use `re.subn()` or explicit precondition checks and abort unless every required transformation matches the expected count.

### Exact upstream markers

The current adapter depends on these upstream text anchors and conventions:

- the root-preflight comment block;
- `USER_HOME_DIR`, `DOWNLOAD_DIR`, `DB_BACKUP_DIR`, and `GITHUB` assignments;
- the identity block beginning near the `/etc/hosts` consistency comment and ending before the MySQL selection;
- the exact Ctrl+Z message;
- the customization-pause comment used as the child-patch insertion point;
- the exact `mv $USER_HOME_DIR/1-setup.sh $DOWNLOAD_DIR` line;
- known child-script filenames;
- the package-list fragment containing `ufw`;
- upgrade-helper variable assignments.

Every upstream update must verify these markers.

### Interactive TTY requirement

The Itiligent installer remains interactive. It expects a usable terminal and cannot be treated as a fully unattended Community Scripts installer without additional design work.

Do not reintroduce spinner-based status output around the interactive section.

### Upgrade behavior

The upgrade helper is inherited from Itiligent and patched only for root-owned paths. Its actual download behavior, application changes, rollback behavior, and compatibility with the LXC adaptation have not been validated.

### Security defaults

The initial upstream credentials are:

```text
Username: guacadmin
Password: guacadmin
```

The password must be changed immediately after first login.

## Git and pull-request history

Relevant implementation milestones:

- `014e5c126de31f8512d8d95e94d6182c63a67345` — added the Proxmox LXC launcher.
- `ea6b4ec33d6e14a60e10591210a7cc3dcbac580b` — added the root-adapted Itiligent installer.
- `55160b0338976dffd693ed155ee14c614e9826f1` — documented scope and test plan.
- `2b7db5b3142214f7411e33d1e4f35ae06a598876` — added Bash syntax validation.
- PR #1 / `6c5c28e3ebf21e3a7c7bde5612b64e0cd8168b8e` — merged the initial adaptation.
- `105ce8e997ba00b7699e2a43800e5e261a8d07bd` — fixed hidden interactive questions.
- `b935ee737043831caeb9473354d959f6b2ee0629` — added PVE Scripts Management metadata.
- `c628e95fa41c8c74cb7e9ef7555e8ff3f2337f29` — changed the default project ref to `main`.
- `84cbf77dd88059efadb7c9f52d60232f3f62bcb4` — expanded metadata/path validation.
- `933032af2fbb00bff5061de97ae0c995097140df` — documented production use.
- PR #2 / `620b4ed93475169551d939e2e7e711fac5b70116` — merged production fixes and metadata.
- PR #3 / `6d4134d7cbc1a04fe3c6e9abcd64eee349e5250b` — re-merged the already integrated development branch without file-tree differences relative to PR #2.
- PR #4 / `457220a3d20fd38ce7c0ad2fa7de3236c34d28d1` — added the initial technical handoff, corrected README PVE Scripts Management status, and removed obsolete empty prototypes.
- PR #5 / `d122e8d9a09d3bdcf484c59eb1a855dccdea3adc` — removed unrelated community-outreach and authorship-oriented material from the handoff.
- `0e6a0b0701a93f7cef8265c677dd38a714e6e133` — added the compact Default Install network wizard.
- `d68d6469366dbf74f34cd7808c27efb8d54695a3` — recorded Advanced networking and Windows 11 RDP validation in the README.

Early empty root-level prototype files existed as `proxmox-guacamole.sh` and `proxmox-guacamole-install.sh`. They were removed. The supported paths are under `ct/` and `install/`.

## Workflow for a normal enhancement

1. Inspect current `main`, recent commits, and open pull requests.
2. Read this document and identify affected assumptions.
3. Create a focused branch from current `main`.
4. Keep the runtime model intact unless the enhancement explicitly redesigns it:
   - launcher on the Proxmox host;
   - installer inside the LXC;
   - pinned upstream source;
   - deterministic runtime transformations;
   - Proxmox-owned networking and firewall.
5. Do not commit manually edited copies of downloaded upstream scripts unless the architecture is intentionally changing. Express compatibility changes in the adapter so they remain auditable.
6. Run repository validation locally:

   ```bash
   bash -n ct/itiligent-guacamole.sh
   bash -n install/itiligent-guacamole-install.sh
   python3 -m json.tool json/itiligent-guacamole.json >/dev/null
   ```

7. Test runtime changes in a disposable LXC or on a disposable Proxmox test host.
8. Record the exact environment and selections used.
9. Update this document's test matrix, known risks, status information, and history.
10. Open a focused pull request, allow CI to pass, review the diff, and merge.

## Workflow when Itiligent publishes an update

Do not simply replace the pinned SHA and assume the adapter remains valid.

### Phase 1: identify a candidate

1. Determine the intended upstream release, tag, or commit from the official Itiligent repository.
2. Record the candidate SHA.
3. Review upstream release notes and commit history.
4. Compare the pinned revision with the candidate, especially:
   - `1-setup.sh`;
   - `2-install-guacamole.sh`;
   - `3-install-nginx.sh`;
   - TLS scripts;
   - authentication and optional-feature scripts;
   - `backup-guacamole.sh`;
   - `upgrade-guacamole.sh`.

### Phase 2: verify the patch contract

Before changing `UPSTREAM_COMMIT`, confirm that every marker listed under **Known risks and fragile assumptions** still exists or deliberately update the adapter.

Recommended hardening while doing this work:

- convert required substitutions to checked substitutions;
- fail when an expected marker is missing;
- fail when a replacement occurs more than once unexpectedly;
- add a CI fixture that downloads the pinned parent script, applies the adapter, and asserts the resulting paths and inserted blocks;
- inspect child scripts for newly introduced `sudo`, UFW, hostname, DNS, system firewall, or user-home assumptions.

### Phase 3: update and validate

1. Change `UPSTREAM_COMMIT` only after the comparison is complete.
2. Update any affected filenames or patch patterns.
3. Run syntax and metadata validation.
4. Run the transformation against the candidate source in a temporary environment.
5. Verify the resulting parent script contains:
   - root-owned paths;
   - pinned child download base;
   - child patch block;
   - no upstream identity rewrite block;
   - no spinner around interactive execution.
6. Perform the full core installation in a new unprivileged Debian 13 LXC.
7. Retest previously validated behavior, including RDP.
8. Test the upstream upgrade helper separately using a Proxmox snapshot.
9. Update the pinned SHA in this document and record the new test evidence.

## Suggested automated tests

### Upstream transformation test

A useful CI enhancement would:

1. download `${UPSTREAM_BASE}/1-setup.sh`;
2. run the exact Python patch logic against a temporary copy;
3. assert all required replacements matched;
4. assert expected path values;
5. assert the child-script patch block exists;
6. assert the old Ctrl+Z message is absent;
7. assert the upstream identity-mutating block is absent;
8. run `bash -n` on the transformed script.

### Default network wizard test

A useful launcher test would provide stub implementations of the Community Scripts validation functions and `whiptail`, then assert that:

- the function runs only for `METHOD=default`;
- bridge choices are enumerated and validated;
- DHCP clears the gateway;
- static addressing retains CIDR and gateway values;
- VLAN blank and 1-4094 are accepted;
- invalid network values repeat the relevant question;
- accepted values are exported before `build_container`.

## PVE Scripts Management retest workflow

When a newer PVE Scripts Management release claims improved custom-repository support:

1. Confirm the installed application version.
2. Add the public repository URL with branch `main`.
3. Run its repository-specific synchronization operation, not merely a PocketBase or logo refresh.
4. Check service logs for requests to this repository.
5. Verify that `itiligent-guacamole.json` was downloaded locally.
6. Verify the card appears in Available Scripts.
7. Verify selection resolves the local/custom JSON record rather than requiring PocketBase.
8. Verify both files are downloaded from this repository:

   ```text
   ct/itiligent-guacamole.sh
   install/itiligent-guacamole-install.sh
   ```

9. Verify the management application's local rewrite of the `build.func` source still permits the installer URL interception.
10. Perform a disposable installation before documenting support as working.

## Operational runbook

### Installation

Run as root on the Proxmox host:

```bash
bash <(curl -fsSL \
  https://raw.githubusercontent.com/ImmacularIT/Proxmox-Itiligent-Guacamole/main/ct/itiligent-guacamole.sh)
```

Use **Default Install** for standard resources plus storage, bridge, DHCP/static IPv4, gateway, and VLAN selection.

Use **Advanced Install** for the full Community Scripts wizard, including resource sizing, IPv6, DNS, MTU, MAC, SDN, SSH, and container feature settings.

### Access

Native fallback URL:

```text
http://CONTAINER-IP:8080/guacamole
```

Initial credentials:

```text
Username: guacadmin
Password: guacadmin
```

Change the password immediately.

### Debugging a failed build

Community Scripts developer flags can be used when compatible with the current builder. A typical diagnostic run is:

```bash
dev_mode="trace,keep,logs" bash -c "$(curl -fsSL \
  https://raw.githubusercontent.com/ImmacularIT/Proxmox-Itiligent-Guacamole/main/ct/itiligent-guacamole.sh)"
```

The `keep` flag is useful when the failed container must remain available for inspection. Review current Community Scripts documentation before relying on flags because the outer builder is loaded from a moving branch.

### Upgrade testing

Before invoking the upgrade helper:

1. take a Proxmox snapshot or backup;
2. record the installed Guacamole and upstream adapter versions;
3. inspect `/opt/itiligent-guacamole/upgrade-guacamole.sh`;
4. run the upgrade in a non-production container first;
5. verify login, RDP, other configured protocols, extensions, and database state;
6. restore the snapshot if results are not acceptable.

## Completion checklist for future work

Before declaring a change complete:

- [ ] Current `main` and recent pull requests were inspected.
- [ ] Current Community Scripts `build.func` behavior was verified.
- [ ] The pinned Itiligent source and candidate source were compared when applicable.
- [ ] Required patch markers were checked.
- [ ] Bash and JSON validation passed.
- [ ] A disposable LXC installation was performed for runtime changes.
- [ ] Interactive question visibility was verified.
- [ ] Default or Advanced network selections were verified when affected.
- [ ] Proxmox-managed networking, identity, DNS, and firewall were not overridden.
- [ ] Default credentials and security notes remain visible.
- [ ] Previously validated RDP behavior was regression-tested when relevant.
- [ ] Test matrix was updated.
- [ ] This handoff was updated.
- [ ] Pull-request and merge details were recorded.

## Current engineering priorities

The core direct installer works and is on `main`.

The most important next engineering improvements are:

1. runtime-test the compact Default network wizard with DHCP and static/VLAN paths;
2. add checked patch counts so upstream drift fails fast;
3. add CI tests for the upstream transformation and Default network wizard;
4. test the remaining optional Itiligent feature matrix;
5. test the upgrade helper with snapshots;
6. retest PVE Scripts Management only after its custom-repository flow is demonstrably connected to the active catalogue and download routes.
