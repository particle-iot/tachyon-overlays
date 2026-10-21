# tachyon-firmware-dragonwing-compat

An empty package whose only job is to keep `linux-firmware-dragonwing` off this
board. Installing that package costs the board its wifi, and wifi is the only
remote access there is.

## Who wants it, and why they should not get it

Exactly one package in the CamX dependency closure asks for it. Checked across
all twelve:

```
qcom-fastrpc1
  Depends: libc6, qcom-libdmabufheap, linux-firmware-dragonwing (>= 1.0.0+20260126), adduser
```

The other eleven do not mention it.

`qcom-fastrpc1` is what CamX uses to reach the CDSP - 3A and part of the ISP
run there. The dependency looks reasonable from a distribution's point of
view: you cannot talk to a DSP whose firmware is missing, and on a generic
Ubuntu install `linux-firmware-dragonwing` is where that firmware comes from.

It does not hold here, and the package's own contents show why. `qcom-fastrpc1`
installs no firmware at all:

```
libadsprpc.so, libcdsprpc.so, libadsp_default_listener.so, libcdsp_default_listener.so
adsprpcd, cdsprpcd, gdsprpcd + their units
60-fastrpc.rules, 60-fastrpc-dmaheap.rules
```

Userspace libraries, daemons and udev rules. Nothing under `/lib/firmware`. The
DSP firmware this board actually runs comes from the `/vendor` partition and
the `add-qcm6490-bp-fw` overlay, and it is already there before any of this is
installed.

Confirmed in practice: the camera stack, fastrpc and CDSP all work with
`linux-firmware-dragonwing` never installed. This package is what makes that
possible.

## What installing it would break

`linux-firmware-dragonwing` ships 571 files, 381 of them under
`/lib/firmware/updates`. The kernel searches `updates/` **before**
`/lib/firmware/`, so anything it puts there wins - no `Replaces` relationship
needed, and no warning.

The `link-ath11k-firmware` overlay populates exactly that path:

```
/lib/firmware/updates/ath11k/QCA6698AQ/hw2.1/
    amss.bin    -> /vendor/wlan/amss20.bin
    amss20.bin  -> /vendor/wlan/amss20.bin
    m3.bin      -> /vendor/wlan/m3.bin
    regdb.bin   -> /vendor/wlan/regdb.bin
    board.bin   -> /vendor/wlan/bdwlang.elf
```

The adapter is PCI `17cb:1103` and ath11k requests it as `qca6698aq hw2.1`, so
those symlinks are what it loads. `linux-firmware-dragonwing` claims the same
tree from the other direction: real `WCN6855/hw2.1/*` blobs plus a
`QCA6698AQ -> WCN6855` symlink.

Both own the `WCN6855` path, so a plain install stops at a file conflict.
Forced through, `QCA6698AQ` requests resolve to dragonwing's generic blobs
instead of the Particle-tuned ones in `/vendor/wlan`, and wifi stops working -
taking ssh with it.

## How this package avoids it

```
Provides:  linux-firmware-dragonwing (= 9999.0.0)
Conflicts: linux-firmware-dragonwing
Depends:   tachyon-firmware
```

`Provides` satisfies the dependency; `Conflicts` makes it impossible for the
real package to be co-installed. dpkg enforces both itself, which is the
reason to do it this way rather than with an apt pin - a pin lives in a config
file that can be edited, overridden or forgotten, and the failure mode is
silent.

`Depends: tachyon-firmware` records where the blobs really come from.

### Why the version is 9999.0.0

It used to be `(= 1.0.0+20260126)`, matching what `qcom-fastrpc1` asked for at
the time. That is a trap: the dependency is `>=`, so the moment fastrpc is
rebuilt against a newer firmware release the Provides no longer satisfies it,
apt resolves the dependency by installing the real package, and wifi
disappears. Nothing warns first.

An unversioned `Provides` does not fix this - per Debian policy it satisfies
only unversioned dependencies, so it would fail against the `>=` immediately.
A version high enough to outlast any real release is what keeps the shim
working.

The cost is that a genuine future need for newer firmware would also go
unnoticed. That is the right trade here: this board does not take its DSP
firmware from this package in the first place.

## The proper fix, which is not ours to make

`tachyon-firmware` already provides the blobs and is the natural place for
these two lines. It is a Particle package (`Maintainer: Andrey Tolstoy`) and
not in this repository, so it cannot be changed here. If those fields are ever
added upstream, this package can be dropped.

## Checking it is doing its job

```sh
dpkg -s linux-firmware-dragonwing 2>/dev/null | grep -q "install ok installed" \
    && echo "PROBLEM: the real package is installed"
apt-get install -s qcom-fastrpc1 | grep -i dragonwing   # must propose nothing
ls -l /lib/firmware/updates/ath11k/QCA6698AQ/hw2.1/     # must be symlinks into /vendor/wlan
```

`install-camx-stack.sh` runs the first of these before touching anything, and
stops if the real package is present - installing the stack in the wrong order
is how wifi gets lost.
