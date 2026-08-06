# Project Technical Handoff and Maintenance Workflow

This document records the implementation, design decisions, test results, known limitations, failures encountered, and maintenance workflow for `ImmacularIT/Proxmox-Itiligent-Guacamole`.

**Status snapshot:** 2026-08-06  
**Production branch:** `main`  
**Production merge:** PR #6, commit `83bd61e0fee014f7b65604078b3a5c03fd9efd0e`  
**Test platform:** Proxmox VE 9.2.6, unprivileged Debian 13 LXC  
**Pinned Itiligent revision:** `676eb7e2711dabdf7f33fa7fe91eafc3dbdb7fce`

Always inspect the current repository state and upstream sources before making changes. The Community Scripts framework and Itiligent source may have changed since this snapshot.

## Executive summary

This project adapts the Itiligent Easy Guacamole Installer to a Proxmox LXC installation that uses the Community Scripts container-building framework.

The adaptation does not reimplement Apache Guacamole. It downloads a pinned Itiligent installer at runtime and applies compatibility transformations so the suite can run inside a Proxmox-managed LXC where installation occurs as `root`.

The tested production installation method is:

```bash
bash <(curl -fsSL \
  https://raw.githubusercontent.com/ImmacularIT/Proxmox-Itiligent-Guacamole/main/ct/itiligent-guacamole.sh)
```

The validated production path includes:

- Proxmox VE 9.2.6;
- unprivileged Debian 13 LXC creation;
- local MariaDB/MySQL installation;
- visible interactive Itiligent configuration;
- native Guacamole access and administration;
- Advanced Install with a selected bridge, static IPv4 address, and VLAN;
- Default Install with storage, suggested or custom container ID, suggested or custom hostname, bridge, DHCP or static IPv4, gateway, and VLAN selection;
- correct final Proxmox `net0` values;
- project-specific Itiligent and ImmacularIT Summary-panel branding and tags;
- an RDP session to a Windows 11 server.

The remaining Itiligent optional features have not all been validated. See the test matrix.

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
    Bash, JSON, metadata-path, asset, and launcher-hook validation.

assets/itiligent-logo.png
assets/itiligent-logo-card.png
assets/immacularit-logo.png
    Repository-hosted branding assets used by the Proxmox Summary panel.

ct/itiligent-guacamole.sh
    Proxmox-host launcher. Creates the LXC through Community Scripts build.func.
    Adds compact Default Install identity and networking prompts, project tags,
    and the final Proxmox Summary-panel description.

install/itiligent-guacamole-install.sh
    Runs inside the container. Downloads and patches the pinned Itiligent suite.

json/itiligent-guacamole.json
    Community-style metadata and installation path definitions.

README.md
    User-facing project overview and direct installation instructions.

docs/PROJECT-HANDOFF.md
    This implementation and maintenance handoff.

docs/PROXMOX-BRANDING.md
    Branding implementation and asset-maintenance notes.
```

## Runtime flow

### Host-side launcher

`ct/itiligent-guacamole.sh` runs on the Proxmox host.

It performs the following work:

1. Sources the current Community Scripts `misc/build.func` from `community-scripts/ProxmoxVE/main`.
2. Defines application defaults:
   - 8 GB disk;
   - 1 CPU;
   - 2048 MB RAM;
   - Debian 13;
   - unprivileged LXC;
   - ARM64 allowed by launcher metadata.
3. Initializes the standard Community Scripts menu and error handling.
4. Defines `update_script()`, which invokes `/opt/itiligent-guacamole/upgrade-guacamole.sh` when an existing installation is detected.
5. Sets the project installer source to this repository and defaults `PROJECT_REF` to `main`.
6. Calls `start` to collect Default, Advanced, or saved settings and storage selection.
7. For interactive Default Install, calls `configure_default_identity`.
8. For interactive Default Install, calls `configure_default_network`.
9. Calls `configure_project_tags` before container creation.
10. Temporarily wraps `curl` so the Community Scripts request for its normal `install/${var_install}.sh` URL is rewritten to this repository's `install/itiligent-guacamole-install.sh`.
11. Calls `build_container`.
12. Removes the temporary `curl` wrapper.
13. Calls the normal Community Scripts `description()` completion function.
14. Calls `set_project_description` to replace only the final visible Proxmox HTML description with project-specific branding.
15. Prints the native fallback URL at `http://CONTAINER-IP:8080/guacamole`.

### Default Install identity wizard

The compact identity step is shown only for interactive Default Install.

It asks for:

- container ID;
- container hostname.

Both fields are prefilled. Pressing Enter accepts the suggested value.

Implementation details:

- the suggested ID is the current Community Scripts/Proxmox next ID;
- `validate_container_id()` ensures the ID is numeric and unused across the cluster;
- the suggested hostname is the normal application default;
- `validate_hostname()` checks the entered name;
- accepted values are exported as `CT_ID`, `CTID`, and `HN` before `build_container`;
- saved/generated defaults, silent execution, and noninteractive execution are not interrupted by these prompts.

Both accepting suggested values and entering custom values were tested successfully.

### Default Install network wizard

The compact network wizard exposes the settings most likely to differ between Proxmox environments:

- bridge;
- DHCP or static IPv4;
- IPv4 gateway for static addressing;
- optional VLAN tag.

Implementation details:

- it runs only when `METHOD=default` and a usable interactive terminal is present;
- Advanced Install and saved/generated defaults retain their original behavior;
- it runs after storage and identity selection and before `build_container`;
- Linux bridges are enumerated from `/sys/class/net/*/bridge`;
- bridge choices are checked with `validate_bridge()`;
- static addresses are checked with `validate_ip_address()`;
- gateways are checked with `validate_gateway_ip()` and `validate_gateway_in_subnet()`;
- VLAN values are checked with `validate_vlan_tag()` and may be blank;
- a final review screen allows the user to accept or change the settings;
- accepted values are exported as `BRG`, `SDN_VNET`, `NET`, `GATE`, and `VLAN`;
- `SDN_VNET` is cleared because the compact path selects Linux bridges rather than Proxmox SDN vnets;
- per-install static IP values are not written into global defaults.

The Default path was tested successfully with bridge selection, DHCP and static addressing, gateway, and VLAN. The resulting `net0` configuration matched the chosen values.

### Installer URL interception

The Community Scripts builder normally calculates an installer URL inside the official `community-scripts/ProxmoxVE` repository. This project lives in a separate repository, so the launcher intercepts only that exact installer URL and substitutes this project's installer URL.

This compatibility bridge depends on the current Community Scripts implementation continuing to:

- fetch the installer with `curl`;
- request the expected official raw URL;
- perform that request after the wrapper has been defined.

If `build.func` changes its download client, URL format, variable naming, or execution order, the interception may stop working. Inspect the current `build.func` during every maintenance cycle.

The Itiligent source is pinned, but the outer Community Scripts builder is loaded from a moving `main` branch and is therefore not fully reproducible.

### Project tags and Summary-panel branding

The launcher removes the automatic `community-script` marker while preserving user-supplied tags and ensuring these tags exist:

```text
itiligent
guacamole
immacularit
remote-access
```

The final Proxmox Summary panel:

- displays the Itiligent logo;
- identifies the application as Itiligent Guacamole LXC;
- states that this is an unofficial Proxmox LXC adaptation of the Itiligent Easy Guacamole Installer;
- displays the ImmacularIT logo;
- credits ImmacularIT as adaptation maintainer;
- links to the Itiligent repository, the ImmacularIT profile, this project repository, and its issue tracker;
- omits Community Scripts donation, script-page, discussion, and repository links.

The standard Community Scripts `description()` function must run first so its completion hooks remain intact. `set_project_description()` must run afterward so the project-specific HTML remains visible.

The first Itiligent asset path rendered only its alternative text in Proxmox. A refreshed PNG was added as `assets/itiligent-logo-card.png`, the launcher was switched to that filename, and the final runtime test passed.

## Container-side installer

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

It creates and protects:

```text
/opt/itiligent-guacamole
/var/backups/guacamole
```

Both paths use mode `0700`.

## Pinned upstream download

The adapter downloads `1-setup.sh` from:

```text
676eb7e2711dabdf7f33fa7fe91eafc3dbdb7fce
```

The temporary parent-script path is:

```text
/root/1-setup.sh
```

An embedded Python program transforms the downloaded parent script before it is executed.

## Exact upstream transformations

### Root execution

The upstream block that prevents root execution and expects a sudo user is removed.

Parent-script `sudo` and `sudo -E` invocations are removed, and `SUDO_USER` references are replaced with `root`.

Reason: Community Scripts installers run as root inside the container.

### Stable appliance paths

These values are substituted:

```text
USER_HOME_DIR=/root
DOWNLOAD_DIR=/opt/itiligent-guacamole
DB_BACKUP_DIR=/var/backups/guacamole
```

The upstream `GITHUB` download base is replaced with a raw GitHub URL containing the pinned commit.

Reason: avoid dependence on a sudo user's home and prevent child-script downloads from drifting to a moving upstream branch.

### Misleading Ctrl+Z message

The upstream message suggesting `Ctrl+Z` is replaced with:

```text
Interactive configuration follows. Complete each prompt to continue.
```

Reason: suspending the process inside the Proxmox builder is unsafe and confusing.

### Container identity and networking

The upstream block that normalizes `/etc/hosts`, domain suffixes, and related host identity is replaced.

The replacement derives values from the existing container identity without rewriting Proxmox-managed files:

- `SERVER_NAME` from `hostname -s`;
- `LOCAL_DOMAIN` from `hostname -d` when available;
- `DOMAIN_SUFFIX` from the local domain or `local`;
- `DEFAULT_FQDN` from the existing hostname/domain;
- `RDP_SHARE_HOST` from the existing server name when unset.

Reason: Proxmox remains the authority for container identity and networking.

### Child-script root adaptation

Before any downloaded child script is executed, an inserted shell block loops over:

```text
/opt/itiligent-guacamole/*.sh
```

For each child script it:

- removes `sudo -E`;
- removes `sudo`;
- replaces `${SUDO_USER}` with `root`;
- replaces `$SUDO_USER` with `root`.

Reason: the parent downloads and executes additional scripts that carry the same sudo-user assumptions.

### UFW removal

The package list in `2-install-guacamole.sh` is modified to remove `ufw`.

UFW command lines are replaced with no-ops in:

```text
2-install-guacamole.sh
3-install-nginx.sh
4a-install-tls-self-signed-nginx.sh
4b-install-tls-letsencrypt-nginx.sh
```

Reason: firewall policy belongs to Proxmox and the surrounding network.

### Upgrade-helper paths

The downloaded `upgrade-guacamole.sh` is modified to retain:

```text
USER_HOME_DIR=/root
DOWNLOAD_DIR=/opt/itiligent-guacamole
```

The helper exists and is exposed through the launcher update path, but its actual upgrade behavior has not yet been functionally validated.

### Cleanup guard

The upstream move operation for `1-setup.sh` is changed from an unconditional `mv` to a guarded operation.

Reason: avoid a fatal cleanup failure if upstream layout or ordering changes.

## Interactive terminal issue and fix

### Original symptom

The first installation reached the Itiligent setup, but questions appeared blank or were overwritten. The Community Scripts spinner continued redrawing the terminal while the installer waited for input. Repeated Enter presses eventually produced an empty-password warning.

### Root cause

The interactive upstream setup was wrapped in Community Scripts `msg_info`/`msg_ok` handling. `msg_info` starts a spinner that repeatedly redraws the terminal line and obscured the interactive questions.

### Fix

Commit `105ce8e997ba00b7699e2a43800e5e261a8d07bd`:

1. removed the `msg_info` wrapper around the interactive setup;
2. added static explanatory messages;
3. attached standard input to `/dev/tty` when available:

```bash
if [[ -r /dev/tty ]]; then
  bash "$SETUP_SCRIPT" </dev/tty
else
  bash "$SETUP_SCRIPT"
fi
```

This preserved the upstream menus and made all questions visible. Password input intentionally does not echo.

## Browser-cache observation

During final validation, the Guacamole user editor temporarily appeared without the `Login disabled` checkbox.

The installed Guacamole 1.6.0 WAR and exploded Tomcat template both contained `FIELD_HEADER_USER_DISABLED`. A Shift+Refresh restored the field, confirming stale browser frontend content rather than an installer or application defect.

Maintenance implication: after reinstalling or upgrading Guacamole, use a hard refresh or clear site data before treating a missing frontend control as a server-side regression.

## Metadata and repository validation

`json/itiligent-guacamole.json` contains the application name and slug, CT type, unprivileged status, port, Debian 13 resource defaults, launcher path, initial credentials, repository URL, and user notes.

`.github/workflows/syntax.yml` validates:

- Bash syntax for the launcher and container installer;
- JSON syntax and required metadata fields;
- expected slug and CT type;
- existence of metadata-derived launcher and installer paths;
- valid nonempty PNG signatures for the branding assets;
- presence of Default identity/network, branding, and tag hooks in the launcher.

The workflow does not yet:

- download and transform the pinned upstream source;
- verify required replacement counts;
- run ShellCheck;
- create an LXC;
- automate the interactive Default wizard;
- test optional Itiligent features.

One PR #6 validation attempt failed before checkout because GitHub Actions returned `Service Unavailable` while resolving `actions/checkout`. This was an external runner failure, not a project validation failure. The complete Proxmox runtime test passed.

## PVE Scripts Management interoperability finding

The repository includes Community-style JSON metadata, but testing showed that the installed PVE Scripts Management/ProxmoxVE-Local custom-repository flow did not import it into the searchable catalogue.

Observed evidence:

- no local `itiligent-guacamole.json` was downloaded under the application's scripts directory;
- logs contained no request to this repository;
- active synchronization and catalogue paths used PocketBase and the official Community Scripts repository.

Keep the metadata for future compatibility, but do not document custom-repository installation as working until repository synchronization, catalogue merging, script resolution, and downloads have been retested end to end.

The supported installation method remains the direct host command.

## Test matrix

| Area | Status | Notes |
|---|---|---|
| Unprivileged Debian 13 LXC creation | Passed | Tested on Proxmox VE 9.2.6. |
| Local database installation | Passed | Completed through interactive Itiligent setup. |
| Interactive question visibility/password entry | Passed | Spinner removed; `/dev/tty` used; passwords do not echo. |
| Native Guacamole access | Passed | Port 8080 fallback confirmed. |
| Initial login and management UI | Passed | Administration confirmed. |
| Advanced bridge/static IPv4/VLAN | Passed | Confirmed 2026-08-06. |
| Default storage selection | Passed | Confirmed 2026-08-06. |
| Default suggested container ID/name | Passed | Enter accepted displayed defaults. |
| Default custom container ID/name | Passed | Custom values appeared correctly in Proxmox. |
| Default bridge/DHCP/static/gateway/VLAN | Passed | Final `net0` matched selected values. |
| Project Summary-panel branding | Passed | Both logos, attribution, and links displayed. |
| Project tags | Passed | Required tags present; `community-script` absent. |
| Browser-cache handling | Passed | Hard refresh restored stale Guacamole UI control. |
| RDP connection | Passed | Windows 11 session worked after final changes. |
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
| Upgrade helper | Not tested | Snapshot before testing. |
| ARM64 | Not tested | Launcher declares support. |
| PVE Scripts Management custom repository | Blocked by tested app flow | Metadata present; active app flow did not ingest it. |

## Known risks and fragile assumptions

### Moving Community Scripts builder

The launcher sources `community-scripts/ProxmoxVE/main/misc/build.func`. A future change can affect this project without any commit here.

Before a release or maintenance change, verify:

- installer URL interception;
- `METHOD` values;
- `start` returning before `build_container`;
- runtime variables `CT_ID`, `CTID`, `HN`, `BRG`, `SDN_VNET`, `NET`, `GATE`, `VLAN`, and `TAGS`;
- validation helpers used by the compact wizards;
- the order and side effects of `description()`.

### Default-wizard assumptions

The compact wizards depend on:

- an interactive terminal;
- Community Scripts validation helpers remaining available;
- Linux bridges appearing under `/sys/class/net/<name>/bridge`;
- `build_container` consuming the exported identity and network variables.

The compact path does not expose Proxmox SDN vnets, IPv6, DNS, MTU, MAC address, SSH settings, or uncommon container features. Use Advanced Install for those.

### Silent upstream patch misses

Several Python substitutions use `re.sub()` or `str.replace()` without verifying the number of matches. An upstream text change can therefore cause a patch to stop applying without an immediate, specific error.

A future hardening change should use checked substitutions and abort unless every required marker matches the expected count.

### Exact upstream markers

The adapter depends on:

- the root-preflight comment block;
- `USER_HOME_DIR`, `DOWNLOAD_DIR`, `DB_BACKUP_DIR`, and `GITHUB` assignments;
- the identity block before MySQL selection;
- the exact Ctrl+Z message;
- the child-patch insertion comment;
- the exact cleanup `mv` line;
- known child-script filenames;
- the package-list fragment containing `ufw`;
- upgrade-helper path assignments.

Every upstream update must verify these markers.

### Interactive TTY requirement

The Itiligent installer remains interactive. Do not wrap it in spinner-based status output. A fully unattended mode would require separate design and testing.

### External branding images

The Proxmox browser must be able to retrieve images from `raw.githubusercontent.com`. Text and links remain usable if an image is unavailable. A new asset filename may be needed to bypass stale caching after replacing an image.

### Upgrade behavior

The upgrade helper is inherited from Itiligent and patched only for root-owned paths. Its application changes, rollback behavior, and LXC compatibility remain unvalidated.

### Security defaults

Initial upstream credentials are:

```text
Username: guacadmin
Password: guacadmin
```

Change the password immediately after first login.

## Git and pull-request history

Relevant milestones:

- `014e5c126de31f8512d8d95e94d6182c63a67345` — added the Proxmox LXC launcher.
- `ea6b4ec33d6e14a60e10591210a7cc3dcbac580b` — added the root-adapted Itiligent installer.
- `2b7db5b3142214f7411e33d1e4f35ae06a598876` — added Bash syntax validation.
- PR #1 / `6c5c28e3ebf21e3a7c7bde5612b64e0cd8168b8e` — merged the initial adaptation.
- `105ce8e997ba00b7699e2a43800e5e261a8d07bd` — fixed hidden interactive questions.
- `b935ee737043831caeb9473354d959f6b2ee0629` — added metadata.
- `c628e95fa41c8c74cb7e9ef7555e8ff3f2337f29` — changed the default project ref to `main`.
- `84cbf77dd88059efadb7c9f52d60232f3f62bcb4` — expanded metadata/path validation.
- PR #2 / `620b4ed93475169551d939e2e7e711fac5b70116` — merged production fixes and metadata.
- PR #3 / `6d4134d7cbc1a04fe3c6e9abcd64eee349e5250b` — re-merged the already integrated development branch without file-tree differences relative to PR #2.
- PR #4 / `457220a3d20fd38ce7c0ad2fa7de3236c34d28d1` — added the initial technical handoff and corrected README status.
- PR #5 / `d122e8d9a09d3bdcf484c59eb1a855dccdea3adc` — removed unrelated outreach and authorship-oriented material from the handoff.
- `0e6a0b0701a93f7cef8265c677dd38a714e6e133` — added the compact Default network wizard.
- PR #6 / `83bd61e0fee014f7b65604078b3a5c03fd9efd0e` — merged compact Default identity/networking, project branding, assets, tags, validation, and final runtime-test documentation.

The supported launcher and installer paths are under `ct/` and `install/`.

## Workflow for a normal enhancement

1. Inspect current `main`, recent commits, and open pull requests.
2. Read this document and identify affected assumptions.
3. Create a focused branch from current `main`.
4. Preserve the runtime model unless intentionally redesigning it:
   - launcher on the Proxmox host;
   - installer inside the LXC;
   - pinned upstream source;
   - auditable runtime transformations;
   - Proxmox-owned identity, networking, DNS, and firewall.
5. Express compatibility changes in the adapter rather than committing manually edited upstream copies.
6. Run local validation:

   ```bash
   bash -n ct/itiligent-guacamole.sh
   bash -n install/itiligent-guacamole-install.sh
   python3 -m json.tool json/itiligent-guacamole.json >/dev/null
   ```

7. Test runtime changes in a disposable LXC.
8. Record the exact environment and selections used.
9. Update this document's status, test matrix, risks, and history.
10. Open a focused pull request, review validation and the diff, then merge.

## Workflow when Itiligent publishes an update

Do not simply replace the pinned SHA.

### Identify and compare

1. Select the intended upstream release, tag, or commit.
2. Record its SHA.
3. Review upstream release notes and history.
4. Compare at least:
   - `1-setup.sh`;
   - `2-install-guacamole.sh`;
   - Nginx and TLS scripts;
   - authentication and optional-feature scripts;
   - backup and upgrade helpers;
   - custom-theme assets and manifest.

### Verify the patch contract

Confirm every marker listed under **Known risks and fragile assumptions** still exists or deliberately update the adapter.

Recommended hardening:

- convert required substitutions to checked substitutions;
- fail when a marker is missing or unexpectedly duplicated;
- add a CI fixture that downloads the pinned parent script and applies the transformation;
- inspect child scripts for new sudo, UFW, hostname, DNS, firewall, or user-home assumptions.

### Update and validate

1. Change `UPSTREAM_COMMIT` only after comparison.
2. Update affected filenames or patch patterns.
3. Run syntax, metadata, asset, and launcher-hook validation.
4. Run the transformation against the candidate source.
5. Verify root paths, pinned child downloads, child patch block, identity preservation, and interactive execution.
6. Perform a full new installation in an unprivileged Debian LXC.
7. Retest Default identity/networking, branding, login, administration, and RDP.
8. Test the upgrade helper separately using a Proxmox snapshot.
9. Update this document with the new SHA and evidence.

## Suggested automated tests

### Upstream transformation test

A useful CI enhancement would download the pinned `1-setup.sh`, run the exact Python transformation, assert all required replacements, verify root-owned paths and child-patch blocks, verify removed identity/UFW/sudo behavior, and run `bash -n` on the result.

### Default wizard test

A launcher test could stub Community Scripts validation functions and `whiptail`, then verify:

- the functions run only for interactive Default Install;
- suggested and custom ID/hostname handling;
- bridge enumeration and validation;
- DHCP clearing the gateway;
- static CIDR and gateway handling;
- blank and valid VLAN handling;
- invalid inputs repeating the relevant question;
- accepted variables being exported before `build_container`.

### Branding test

A renderer-oriented check could validate the generated HTML, required URLs, image paths, ordering after Community Scripts `description()`, and removal of `community-script` from generated tags.

## PVE Scripts Management retest workflow

When a newer release claims improved custom-repository support:

1. Confirm the installed application version.
2. Add the public repository URL using branch `main`.
3. Run repository-specific synchronization.
4. Check logs for requests to this repository.
5. Verify the JSON is downloaded locally.
6. Verify the card appears in Available Scripts.
7. Verify selection resolves the custom record rather than requiring PocketBase.
8. Verify both launcher and installer download from this repository.
9. Verify any local `build.func` rewrite still permits installer URL interception.
10. Perform a disposable installation before documenting support.

## Operational runbook

### Installation

Run as root on the Proxmox host:

```bash
bash <(curl -fsSL \
  https://raw.githubusercontent.com/ImmacularIT/Proxmox-Itiligent-Guacamole/main/ct/itiligent-guacamole.sh)
```

Use **Default Install** for standard resources plus storage, ID, hostname, bridge, DHCP/static IPv4, gateway, and VLAN.

Use **Advanced Install** for the full Community Scripts wizard, including resource sizing, IPv6, DNS, MTU, MAC, SDN, SSH, and container features.

### Access

```text
http://CONTAINER-IP:8080/guacamole
```

```text
Username: guacadmin
Password: guacadmin
```

Change the password immediately.

### Debugging a failed build

A typical diagnostic run is:

```bash
dev_mode="trace,keep,logs" bash -c "$(curl -fsSL \
  https://raw.githubusercontent.com/ImmacularIT/Proxmox-Itiligent-Guacamole/main/ct/itiligent-guacamole.sh)"
```

Review current Community Scripts behavior before relying on developer flags.

### Upgrade testing

Before invoking the upgrade helper:

1. take a Proxmox snapshot or backup;
2. record installed Guacamole and adapter versions;
3. inspect `/opt/itiligent-guacamole/upgrade-guacamole.sh`;
4. run the upgrade in a nonproduction container first;
5. verify login, RDP, configured extensions, and database state;
6. restore the snapshot if needed.

## Completion checklist

Before declaring future work complete:

- [ ] Current `main`, recent commits, and open pull requests were inspected.
- [ ] Current Community Scripts `build.func` behavior was verified.
- [ ] The pinned Itiligent source and candidate were compared when applicable.
- [ ] Required patch markers were checked.
- [ ] Bash, JSON, metadata, asset, and hook validation passed.
- [ ] A disposable LXC installation was performed for runtime changes.
- [ ] Interactive question visibility was verified.
- [ ] Default or Advanced identity/network selections were verified when affected.
- [ ] Proxmox-managed identity, networking, DNS, and firewall were preserved.
- [ ] Summary-panel branding and tags were verified when affected.
- [ ] Browser cache was ruled out for frontend-only anomalies.
- [ ] Default credentials and security notes remain visible.
- [ ] RDP was regression-tested when relevant.
- [ ] Test matrix, risks, status, and history were updated.
- [ ] Pull-request and merge details were recorded.

## Current engineering priorities

The tested production installer, compact Default flow, branding, and RDP path are on `main`.

The most important next improvements are:

1. add checked upstream patch counts so drift fails fast;
2. add automated upstream-transformation and Default-wizard tests;
3. test SSH and VNC connectivity;
4. test the remaining optional Itiligent feature matrix;
5. test backup and upgrade helpers with snapshots;
6. retest PVE Scripts Management only after its custom-repository flow is demonstrably connected end to end;
7. test ARM64 before continuing to declare it supported in metadata.
