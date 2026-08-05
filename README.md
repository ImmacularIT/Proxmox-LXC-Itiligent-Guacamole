# Proxmox Itiligent Guacamole

A Proxmox VE LXC adaptation of the [Itiligent Easy Guacamole Installer](https://github.com/itiligent/Easy-Guacamole-Installer).

## Scope

This project preserves the existing Itiligent installation choices and optional helper scripts. It changes only the operating assumptions that are incompatible with a Community Scripts-style Proxmox container installation:

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

## Validation status

The core installation path has been successfully tested on Proxmox VE 9.2.6 using an unprivileged Debian 13 LXC with a local database. The Guacamole login and management interface were confirmed working.

The optional Itiligent choices remain available and should be tested individually before production use, especially remote database access, Nginx, TLS, external authentication, recordings, protocol connectivity, backups, and upgrades.

## Direct installation

Run this command as `root` in the Proxmox host shell:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ImmacularIT/Proxmox-Itiligent-Guacamole/main/ct/itiligent-guacamole.sh)
```

Select **Advanced Install** in the first menu to configure bridge, VLAN, DHCP or static IPv4, IPv6, and other container properties.

The container setup is followed by the original interactive Itiligent configuration menus.

## PVE Scripts Management

This repository includes the metadata and conventional paths required by PVE Scripts Management:

```text
json/itiligent-guacamole.json
ct/itiligent-guacamole.sh
install/itiligent-guacamole-install.sh
```

Add the following repository URL in **Settings → Repositories**:

```text
https://github.com/ImmacularIT/Proxmox-Itiligent-Guacamole
```

Leave the repository enabled and run a metadata synchronization. **Itiligent Guacamole** should then appear as an installable CT script.

The management application uses the repository's `main` branch. Its global repository branch setting should remain `main`.

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

## Suggested functional checks

1. Verify RDP, SSH, and VNC connections.
2. Test Nginx HTTP.
3. Test self-signed TLS.
4. Test Let's Encrypt using valid public DNS and reachable ports 80 and 443.
5. Test TOTP, Duo, LDAP, Quick Connect, and History Recording independently.
6. Verify the database backup cron job.
7. Snapshot the container and test the existing Itiligent upgrade helper.

## Attribution

The application installation logic and feature suite originate from Itiligent. The LXC launcher follows the structure of the Community Scripts Proxmox VE project. See the source repositories for their respective licenses and attribution.
