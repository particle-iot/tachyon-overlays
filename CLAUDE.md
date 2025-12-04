# Tachyon Overlays System Documentation

## Overview

This repository contains a modular overlay system for customizing Ubuntu 24.04 and 20.04 installations for Particle's Tachyon device. The system allows building customized Ubuntu images through a composable architecture of overlays and stacks.

## Repository Structure

```
tachyon-overlays/
├── setup.sh                 # Device setup script for Tachyon modem configuration
├── stacks/                  # Stack definitions (collections of overlays)
│   ├── ubuntu-common-24.04.json
│   ├── ubuntu-desktop-24.04.json
│   ├── ubuntu-headless-24.04.json
│   ├── ubuntu-manufacturing-20.04.json
│   └── ...
└── overlays/                # Individual overlay modules (62 total)
    ├── add-particle-user/
    │   ├── overlay.json
    │   └── files/
    ├── add-network-manager/
    │   ├── overlay.json
    │   ├── add-packages.sh
    │   └── files/
    └── ...
```

## Core Concepts

### Overlays

An **overlay** is a self-contained module that performs a specific configuration task. Each overlay lives in its own directory under `overlays/` and contains:

- `overlay.json` - Defines the overlay's metadata and commands
- Optional `files/` directory - Contains files to be copied into the chroot
- Optional shell scripts - For complex installation logic

**Example overlay structure:**
```json
{
  "name": "add-particle-user",
  "description": "Adds a user for Particle development and makes it sudo.",
  "commands": [
    {
      "type": "chroot-cmd",
      "cmd": "useradd -m -s /bin/bash -G sudo particle || true"
    },
    {
      "type": "copy-into-chroot",
      "source": "files/team.jpg",
      "destination": "/usr/share/backgrounds/team.jpg",
      "permissions": "644"
    }
  ]
}
```

### Stacks

A **stack** is a collection of overlays executed in a specific order. Stacks can reference other stacks, creating a hierarchical composition. Stack files are JSON with JavaScript-style comments.

**Example stack:**
```json
{
  "name": "ubuntu-desktop-24.04",
  "description": "Sets up the desktop image.",
  "steps": [
    {
      "type": "overlay",
      "name": "pre-overlay-setup"
    },
    {
      "type": "stack",
      "name": "ubuntu-common-24.04"
    },
    {
      "type": "overlay",
      "name": "post-overlay-cleanup"
    }
  ]
}
```

## Command Types

Overlays support several command types for interacting with the chroot environment:

### 1. `chroot-cmd`
Executes a single command in the chroot environment.
```json
{
  "type": "chroot-cmd",
  "cmd": "apt update",
  "ignore-errors": true
}
```

### 2. `chroot-script`
Executes a shell script from the overlay directory in the chroot.
```json
{
  "type": "chroot-script",
  "script": "add-packages.sh"
}
```

### 3. `copy-into-chroot`
Copies files from the overlay into the chroot filesystem.
```json
{
  "type": "copy-into-chroot",
  "source": "files/01-network-manager-all.yaml",
  "destination": "/etc/netplan/01-network-manager-all.yaml",
  "permissions": "644"
}
```

## Key Overlays

### Essential System Overlays

- **pre-overlay-setup** - MUST be first. Sets up network resolution and apt configuration for the build process
- **post-overlay-cleanup** - MUST be last. Restores original network configuration
- **apt-upgrade** - Updates and upgrades all packages
- **add-particle-repo** - Adds Particle's custom package repository
- **pin-pkg-versions** - Pins specific package versions for stability
- **growfs** - Configures filesystem to grow on first boot

### User & Authentication

- **add-particle-user** - Creates particle user with sudo access (password: particle)
- **root-passwd** - Sets root password
- **add-root-ssh** - Enables SSH access for root
- **add-autologin-getty** - Configures automatic login

### Networking

- **add-network-manager** - Installs and configures NetworkManager
- **add-network-manager-policy** - Adds NetworkManager policies
- **add-tailscale** - Installs Tailscale VPN
- **disable-wait-online-service** - Disables systemd-networkd-wait-online for faster boot
- **tweak-cellular-priority** - Adjusts cellular connection priorities

### Hardware & Firmware

- **add-tachyon-firmware-pkg** - Installs Tachyon-specific firmware (protection-domain-mapper, rmtfs)
- **add-fstab-mounts** - Configures modem partition mounts (/persist, /firmware)
- **add-grub-configuration** - Sets up bootloader configuration
- **add-msm-blacklist** - Blacklists conflicting MSM kernel modules
- **update-adsp-fw** - Updates ADSP firmware

### Development Tools

- **add-docker** - Installs Docker
- **add-particle-cli** - Installs Particle CLI tools
- **add-vscode** - Installs VS Code
- **add-adbd** - Adds Android Debug Bridge daemon
- **add-gpio-tools** - Installs GPIO utilities
- **add-linux-tools** - Adds Linux performance tools
- **add-perf-utils** - Performance monitoring utilities

### Desktop Environment

- **add-gnome-packages** - Installs GNOME desktop packages
- **add-gnome-tweaks** - GNOME customization tools
- **add-firefox** - Firefox browser
- **add-chromium** - Chromium browser
- **add-desktop-setup** - Desktop environment configuration

### System Services

- **particle-service** - Main Particle system service
- **particle-tachyon-deb** - Particle Tachyon Debian package
- **add-systemd-suspend-hooks** - Suspend/resume hooks
- **disable-weston-display** - Disables Weston compositor
- **configure-unattended-upgrade** - Automatic security updates
- **configure-logs** - Log management configuration

### Specialized

- **manufacturing** - Manufacturing-specific configurations
- **particle-manufacturing-tweaks** - Additional manufacturing setup
- **enable-fct-console** - Factory test console
- **minimum-swap** - Minimal swap configuration
- **set-initial-time** - Initial system time setup
- **add-particle-version** - Version information

## Stack Configurations

### ubuntu-common-24.04
Base stack with ~40 core overlays including:
- Package management (pin versions, add repos, upgrades)
- User setup (particle user, root access)
- Networking (NetworkManager, Tailscale)
- Firmware (Tachyon firmware, ADSP)
- Development tools (Docker, CLI, ADB)
- System configuration (fstab, GRUB, services)

### ubuntu-desktop-24.04
Extends ubuntu-common-24.04 with desktop environment overlays.

### ubuntu-headless-24.04
Headless server configuration based on ubuntu-common-24.04.

### Legacy (20.04)
- ubuntu-common-20.04.json
- ubuntu-desktop-20.04.json
- ubuntu-desktop-common-20.04.json
- ubuntu-headless-20.04.json
- ubuntu-manufacturing-20.04.json

## Build Process Flow

1. **Pre-setup** (pre-overlay-setup)
   - Configure network resolution for apt
   - Set debconf to noninteractive mode
   - Add hostname to /etc/hosts

2. **Core System** (ubuntu-common-24.04)
   - Pin package versions
   - Add Particle repository
   - Upgrade system
   - Install firmware and drivers
   - Configure users and authentication
   - Set up networking
   - Install development tools

3. **Variant-Specific** (desktop/headless overlays)
   - Desktop: GNOME, browsers, GUI tools
   - Headless: Server-focused packages

4. **Post-cleanup** (post-overlay-cleanup)
   - Restore original network configuration
   - Clean up build artifacts

## Important Notes

### Execution Order
- **pre-overlay-setup** must always be first
- **post-overlay-cleanup** must always be last
- Order matters - overlays depend on previous configurations

### Chroot Environment
All commands execute in a chroot environment, meaning they run as if inside the target system being built, not on the host system.

### Comments in JSON
Stack and overlay JSON files support JavaScript-style comments (`//`), which are stripped before parsing.

### Modem Configuration
The Tachyon device requires specific modem firmware and partition setup:
- `/dev/sdf8` → `/persist` (ext4)
- `/dev/sdg1` → `/firmware` (vfat)
- rmtfs service for remote filesystem access
- protection-domain-mapper for Qualcomm services

### Version Support
- Primary focus: Ubuntu 24.04
- Legacy support: Ubuntu 20.04
- Some overlays may be version-specific

## Development Guidelines

### Creating a New Overlay

1. Create directory: `overlays/my-new-overlay/`
2. Create `overlay.json` with name, description, commands
3. Add any required files to `files/` subdirectory
4. Add scripts if complex logic needed
5. Reference in appropriate stack file

### Testing

Test overlays individually before adding to stacks. Overlays should be:
- Idempotent (safe to run multiple times)
- Self-contained (all dependencies explicit)
- Well-documented (clear description)

### Error Handling

Use `"ignore-errors": true` for commands that may fail harmlessly (e.g., removing non-existent files).

## Related Systems

This overlay system is designed to work with:
- Ubuntu chroot build environments
- Particle Tachyon device hardware
- Qualcomm modem firmware (rmtfs, pd-mapper)
- Android Debug Bridge (ADB) for device provisioning
