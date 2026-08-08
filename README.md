# Proxmox LXC Itiligent Guacamole

A Proxmox VE LXC adaptation of the [Itiligent Easy Guacamole Installer](https://github.com/itiligent/Easy-Guacamole-Installer), maintained by [ImmacularIT](https://github.com/ImmacularIT).

<a href="https://www.buymeacoffee.com/eli66" target="_blank"><img src="http://public.jc21.com/github/by-me-a-coffee.png" alt="Buy Me A Coffee" style="height: 51px !important;width: 217px !important;" ></a>

## Scope

This project preserves the existing Itiligent installation choices and optional helper scripts. It changes only the operating assumptions that are incompatible with a Proxmox helper-framework container installation:

- Debian 13 LXC on Proxmox VE 9
- installation runs as root inside the container
- no sudo-user requirement
- no UFW installation or firewall modification
- no hostname, `/etc/hosts`, or `/etc/resolv.conf` modification
- container identity and networking remain managed by Proxmox
- root-owned installer, backup, and upgrade paths

The upstream Itiligent suite is pinned to commit `676eb7e2711dabdf7f33fa7fe91eafc3dbdb7fce` for reproducibility.

## Preserved Itiligent features

- local or remote MySQL/MariaDB
- TOTP, Duo, and LDAP
- Quick Connect and History Recording Storage
- Itiligent dark branding
- native Tomcat access and optional root URL redirect
- Nginx reverse proxy
- self-signed TLS
- Let's Encrypt TLS
- database backups
- existing SMTP relay, guacd TLS, fail2ban, and upgrade helper scripts

No additional Guacamole functions are introduced by this project.

## Installer privacy and project identity

The existing external Proxmox helper framework is retained only for its established container-creation mechanics so Default and Advanced Install behavior does not have to be rewritten. This project hard-disables the framework's diagnostics and telemetry reporting on both the Proxmox host and inside the LXC.

The installer does not offer a telemetry/diagnostics preference, does not report installation progress or results to the external framework service, and does not require its diagnostics DNS endpoint. User-facing installer dialogs use ImmacularIT/Itiligent project identity instead of unrelated framework branding.

Inside the completed container, the login profile does not display external-framework promotional attribution and `/usr/bin/update` points back to this ImmacularIT repository.

## Validation status

The core installation path has been successfully tested on Proxmox VE 9.2.6 using an unprivileged Debian 13 LXC with a local database. The Guacamole login and management interface were confirmed working.

Advanced container creation was tested successfully with a selected bridge, static IPv4 address, and VLAN tag.

Default Install was tested successfully with:

- accepting and changing the suggested container ID and hostname;
- storage selection;
- bridge selection;
- DHCP and static IPv4 configuration;
- gateway and VLAN configuration;
- project-specific Proxmox Summary branding and tags.

An RDP connection from Guacamole to a Windows 11 server was created and used successfully after the final Default Install changes.

The remaining optional Itiligent choices should be tested individually before production use, especially remote database access, Nginx, TLS, external authentication, recordings, SSH/VNC connectivity, backups, and upgrades.

For the complete implementation history, known quirks, test matrix, upstream-update process, and maintenance workflow, see [Project Technical Handoff and Maintenance Workflow](docs/PROJECT-HANDOFF.md).

## Direct installation

Run this command as `root` in the Proxmox host shell:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ImmacularIT/Proxmox-LXC-Itiligent-Guacamole/main/ct/itiligent-guacamole.sh)
```

**Default Install** keeps the normal resource defaults and adds compact choices for:

- suggested or custom container ID;
- suggested or custom container hostname;
- Proxmox storage;
- Proxmox bridge;
- DHCP or static IPv4;
- IPv4 gateway when static addressing is selected;
- optional VLAN tag.

Pressing Enter in the container ID and hostname fields accepts the suggested values.

Use **Advanced Install** for the full advanced Proxmox configuration wizard provided by the retained helper framework, including CPU, RAM, disk size, IPv6, DNS, MTU, MAC address, SSH, container features, and other advanced properties.

The container setup is followed by the original interactive Itiligent configuration menus.

## Proxmox container information panel

New containers receive a project-specific description in the Proxmox VE Summary panel rather than a generic external-framework promotional panel.

The panel:

- displays the Itiligent logo and links to the upstream Easy Guacamole Installer;
- identifies this project as an unofficial Proxmox LXC adaptation;
- displays the ImmacularIT logo and links to the maintainer profile;
- links to this adaptation repository and its issue tracker;
- omits unrelated framework donation, script-page, discussion, and repository links.

The associated Proxmox tags are:

```text
itiligent
guacamole
immacularit
remote-access
```

The automatic legacy-framework `community-script` marker is removed because this repository is independently maintained. User-defined tags are preserved.

Branding assets used by the panel are stored in:

```text
assets/itiligent-logo-card.png
assets/immacularit-logo.png
```

Implementation and validation details are documented in [Proxmox Container Branding](docs/PROXMOX-BRANDING.md).

## PVE Scripts Management status

This repository includes conventional PVE Scripts Management metadata and paths:

```text
json/itiligent-guacamole.json
ct/itiligent-guacamole.sh
install/itiligent-guacamole-install.sh
```

Testing against the current PVE Scripts Management/ProxmoxVE-Local flow showed that custom repository entries are not synchronized into the active PocketBase-backed Available Scripts catalogue. Adding this repository therefore does **not currently make Itiligent Guacamole appear in search**, even though the metadata and paths are valid.

Use the direct installation command above. Retest custom-repository support only after a newer PVE Scripts Management release documents and implements end-to-end repository synchronization, catalogue merging, and custom script downloads.

## Access

Native Guacamole access remains available at:

```text
http://CONTAINER-IP:8080/guacamole
```

The initial upstream credentials are:

```text
Username: guacadmin
Password: guacadmin
```

Change the password immediately after the first login. Nginx and TLS choices may provide a different preferred frontend URL while native port 8080 remains the fallback.

After replacing an older Guacamole installation at the same URL, use a hard refresh or clear site data if the browser displays stale interface elements.

## Suggested functional checks

1. Verify SSH and VNC connections. RDP to a Windows 11 server has been tested successfully.
2. Test Nginx HTTP.
3. Test self-signed TLS.
4. Test Let's Encrypt using valid public DNS and reachable ports 80 and 443.
5. Test TOTP, Duo, LDAP, Quick Connect, and History Recording independently.
6. Verify the database backup cron job.
7. Snapshot the container and test the existing Itiligent upgrade helper.

## Attribution

The application installation logic, feature suite, and Itiligent branding originate from Itiligent. The Proxmox LXC adaptation and ImmacularIT branding are maintained in this repository. The launcher retains an external Proxmox VE helper framework for container-creation mechanics only; its diagnostics and telemetry are disabled by this project and its user-facing branding is replaced. See the source repositories for their respective licenses and attribution.
