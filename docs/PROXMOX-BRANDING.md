# Proxmox Container Branding

New containers created by this project receive a project-specific HTML description in the Proxmox VE Summary panel.

The description deliberately replaces the Community Scripts promotional panel because this repository is an external adaptation, not a script distributed by the Community Scripts project.

## Displayed attribution

The information panel identifies:

- **Itiligent** as the origin of the Easy Guacamole Installer and feature suite;
- this repository as an **unofficial Proxmox LXC adaptation** of that installer;
- **ImmacularIT** as the maintainer of the Proxmox adaptation.

The panel links to:

- the upstream Itiligent repository: `https://github.com/itiligent/Easy-Guacamole-Installer`;
- the ImmacularIT GitHub profile: `https://github.com/ImmacularIT`;
- this adaptation repository and its issue tracker.

## Assets

The panel uses these repository-hosted PNG files:

```text
assets/itiligent-logo-card.png
assets/immacularit-logo.png
```

At installation time, image URLs are built from `PROJECT_OWNER`, `PROJECT_REPO`, and `PROJECT_REF`. This keeps development-branch tests isolated from production assets.

The browser displaying the Proxmox interface must be able to retrieve images from `raw.githubusercontent.com`. Text and links remain available if an external image cannot be loaded.

The Itiligent asset was renamed during testing to avoid a stale or incorrectly served earlier image path.

## Runtime implementation

Community Scripts `build.func` still supplies the LXC builder and its normal completion logic. The launcher calls its standard `description()` function first so existing completion hooks, monitoring restart, post-install handling, and telemetry behavior remain intact.

The project then calls:

```text
set_project_description
```

That function overwrites only the final Proxmox container description with the project-specific HTML by running:

```bash
pct set "$CTID" -description "$project_description"
```

This ordering must be preserved. Calling the Community Scripts `description()` function afterward would restore Community Scripts branding.

## Proxmox tags

Community Scripts normally adds a `community-script` marker to created containers. The launcher calls:

```text
configure_project_tags
```

before `build_container`. It removes that marker, preserves user-supplied tags, removes duplicates, and ensures these project tags are present:

```text
itiligent
guacamole
immacularit
remote-access
```

## Validation

Repository CI checks that both active assets are valid nonempty PNG files and that the launcher contains the branding and tag hooks.

Runtime validation on Proxmox VE 9.2.6 confirmed that:

1. both logos render in the Summary panel;
2. the attribution text is readable;
3. the project links are present;
4. Community Scripts donation, script-page, discussion, and repository links are absent;
5. `community-script` is absent from the container tags;
6. the four project tags are present.

The first test displayed only the Itiligent image alternative text. Replacing the asset under the new `itiligent-logo-card.png` path resolved the issue.

## Development-branch testing

When testing a branch whose assets have not been merged into `main`, set `ITILIGENT_REPO_REF` to that branch. For example:

```bash
ITILIGENT_REPO_REF=agent/default-network-wizard bash <(curl -fsSL \
  https://raw.githubusercontent.com/ImmacularIT/Proxmox-Itiligent-Guacamole/agent/default-network-wizard/ct/itiligent-guacamole.sh)
```

Without that environment variable, `PROJECT_REF` defaults to `main`, so the installer and branding assets would be requested from the production branch.
