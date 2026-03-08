# Tachyon Overlays

A modular overlay system for customizing Ubuntu 24.04 and 20.04 installations for Particle's [Tachyon](https://www.particle.io/tachyon/) device.

These overlays are consumed by [Tachyon Composer](https://github.com/particle-iot/tachyon-composer) to build customized Ubuntu images.

## Structure

- **`overlays/`** - Individual overlay modules, each performing a specific configuration task (adding packages, configuring services, copying files, etc.)
- **`stacks/`** - Collections of overlays executed in a specific order. Stacks can reference other stacks for hierarchical composition.
- **`setup.sh`** - Device setup script for Tachyon modem configuration.

## Overlays

Each overlay lives in its own directory under `overlays/` and contains:

- `overlay.json` - Metadata and commands to execute
- Optional `files/` directory - Files to copy into the target filesystem
- Optional shell scripts - For complex installation logic

Overlays support three command types:
- **`chroot-cmd`** - Run a command in the chroot environment
- **`chroot-script`** - Run a shell script in the chroot environment
- **`copy-into-chroot`** - Copy files into the chroot filesystem

## Stacks

Stacks define which overlays to apply and in what order. Key stacks:

- **`ubuntu-common-24.04`** - Base system with core packages, networking, firmware, and development tools
- **`ubuntu-desktop-24.04`** - Extends common with GNOME desktop environment
- **`ubuntu-headless-24.04`** - Headless server configuration
