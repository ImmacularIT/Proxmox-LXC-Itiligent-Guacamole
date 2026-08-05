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

## Development status

The current branch is an initial implementation. It requires installation and functional testing on a disposable Proxmox VE 9.2.6 host before production use.

## Running while the repository is private

The launcher uses the Community Scripts container builder and loads this repository's installer. Export a fine-grained GitHub token with read access to this repository before running it:

```bash
export GITHUB_TOKEN='github_pat_...'
export ITILIGENT_REPO_REF='agent/proxmox-lxc-adaptation'
bash ct/itiligent-guacamole.sh
```

Do not store the token in the repository or shell history. When the repository becomes public, the token will no longer be needed.

## Expected installation flow

The Proxmox launcher creates an unprivileged Debian 13 LXC. Inside the container, the installer downloads the pinned Itiligent suite, applies the compatibility changes, and starts the original Itiligent setup menus.

The Itiligent menus continue to control database, authentication extensions, optional extras, Nginx, self-signed TLS, and Let's Encrypt.

## Validation checklist

1. Create an unprivileged Debian 13 container on Proxmox VE 9.2.6.
2. Complete a local-database install with native Tomcat access.
3. Verify login and immediately change the default `guacadmin` password.
4. Test RDP, SSH, and VNC connections.
5. Repeat with Nginx HTTP.
6. Test self-signed TLS.
7. Test Let's Encrypt using valid public DNS and reachable ports 80 and 443.
8. Test TOTP, Duo, LDAP, Quick Connect, and History Recording independently.
9. Verify the database backup cron job.
10. Snapshot the container and test the existing Itiligent upgrade helper.

## Attribution

The application installation logic and feature suite originate from Itiligent. The LXC launcher follows the structure of the Community Scripts Proxmox VE project. See the source repositories for their respective licenses and attribution.
