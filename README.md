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

## Apply incremental overlays to an existing rootfs

This repository can apply a small, self-contained stack to an existing rootfs image without
rerunning the complete Particle release stack. All image and chroot operations run in Docker.
The source image is mounted read-only and the result is written as a new raw ext4 image.

```bash
make apply-rootfs \
  INPUT_IMAGE=/path/to/rootfs.ext4 \
  STACK=custom-rootfs \
  OUTPUT_IMAGE=output/rootfs-custom.ext4
```

Supported inputs are a raw ext4 filesystem, a partitioned disk image, or either form compressed
with xz. For a disk containing multiple ext4 partitions, select one explicitly with
`ROOT_PARTITION=<number>`.

The default Docker image is `tachyon-rootfs-overlay-builder:1.0`. The container performs the
read-only mount, chroot setup, overlay execution, ext4 creation, and final `e2fsck` validation.
Use `ROOTFS_SIZE_MB=<MiB>` to override automatic output sizing.

To install a locally built kernel package into an existing rootfs, use the separate kernel
operation. It uses the same read-only input and new-ext4 output pipeline:

```bash
make apply-kernel \
  INPUT_IMAGE=/path/to/rootfs.ext4 \
  KERNEL_IMAGE_DEB=build-tachyon/linux-image-6.8.0-1058-particle_<version>_arm64.deb \
  KERNEL_MODULES_DEB=build-tachyon/linux-modules-6.8.0-1058-particle_<version>_arm64.deb \
  KERNEL_HEADERS_DEB=build-tachyon/linux-headers-6.8.0-1058-particle_<version>_arm64.deb \
  KERNEL_COMMON_HEADERS_DEB=build-tachyon/linux-particle-headers-6.8.0-1058_<version>_all.deb \
  OUTPUT_IMAGE=output/rootfs-with-kernel.ext4
```

The four debs must come from the same `dpkg-buildpackage` transaction. They are installed together
with `apt-get`, without `--force-overwrite`, so the rebuilt `linux-modules` package replaces the
stock module tree instead of leaving a mixed `.ko`/`.ko.zst` payload. The installer validates
package names, versions, architectures and dependency edges, checks packaged Iris and
v4l2loopback, audits dpkg, then holds all four packages so a routine apt upgrade cannot silently
restore the stock kernel. It also updates `/boot/vmlinuz` and `/boot/initrd.img` to point at the
matching versioned files.

Both operations normalize the root entry in `/etc/fstab` to the input
filesystem UUID, which is preserved on the output ext4. This prevents a stale
Composer label such as `cloudimg-rootfs` from leaving `systemd-remount-fs`
failed on an image whose actual label is `desktop-rootfs`.

`stacks/custom-rootfs.json` is intentionally an incremental stack. Add only the new overlays that
must be applied to an already composed rootfs; do not include `ubuntu-common-24.04` or the complete
release stacks unless their package pins and external resources are also supplied.
