# Tachyon CamX camera (experimental)

Runs the IMX519 through the QCM6490 **hardware ISP** instead of the RAW-only
upstream camss path. AE, AWB, AF and lens shading all work. The kernel is
unmodified — the Qualcomm camera KMD already ships in the Canonical tree, it
just was never loaded.

## What you get, and what you don't

**Working:** the HAL3 interface (`/usr/lib/hw/camera.qcom.so`), plus
`camx-capture` as a smoke-test client.

**Not working out of the box:** ordinary V4L2 applications. Cheese, ffmpeg,
OpenCV and GStreamer's `v4l2src` cannot see this camera — CamX exposes HAL3,
not a V4L2 capture node (`/dev/video0` here is `cam-req-mgr`, a control node
that does not implement the capture API).

`camx-capture` does contain a debug feeder path that writes frames into a
v4l2loopback node, but this package ships **no** v4l2loopback module, no
service and no stable device node, so it is a bring-up aid rather than a
supported interface. A proper HAL3-to-V4L2 bridge is a separate deliverable.

**Image quality:** tuning is borrowed from a different module and is not
calibrated for this one. Auto-exposure visibly hunts as a result — roughly
0.225 EV at 1.8 Hz, which reads as a slow flicker in video.

## Enabling it

The camera needs a device-tree overlay. **Installing the package does not
enable anything** — it never touches `/boot/dtb_a`, which is a separate boot
partition and yours to manage. Two overlays are staged for you to choose from:

```
/usr/share/tachyon/dtbo/combined-dtb-vendor-camera-imx519-csi1-4lane.dtbo
/usr/share/tachyon/dtbo/combined-dtb-vendor-camera-imx519-csi2-4lane.dtbo
```

Copy whichever matches your board and add its name to `overlays.txt`:

```sh
cp /usr/share/tachyon/dtbo/combined-dtb-vendor-camera-imx519-csi1-4lane.dtbo /boot/dtb_a/
vi /boot/dtb_a/overlays.txt
sync && reboot
```

`overlays.txt` is a single line of whitespace-separated names. The camera
overlays are independent components, so all of these are valid:

```sh
# CSI1 only
overlays=combined-dtb-vendor-camera-imx519-csi1-4lane.dtbo

# CSI2 only  (costs you the DSI panel, see below)
overlays=combined-dtb-vendor-camera-imx519-csi2-4lane.dtbo

# both connectors, two cameras at once (cameraId 0 and 1)
overlays=combined-dtb-vendor-camera-imx519-csi1-4lane.dtbo combined-dtb-vendor-camera-imx519-csi2-4lane.dtbo

# CSI1 camera plus a DSI panel
overlays=combined-dtb-wlk2802.dtbo combined-dtb-vendor-camera-imx519-csi1-4lane.dtbo
```

Two things to watch out for when editing that line:

**CSI2 and the DSI panel cannot coexist.** They share one connector, steered by
a mux on tlmm 68. The CSI2 overlay flips it to camera, so a panel on that
connector goes dark. CSI1 has no such conflict.

**Do not list an upstream camss camera overlay alongside these.** Both claim
the same CSIPHY/CSID/VFE registers, and listing both leaves you with no camera
at all — the failure looks like broken hardware rather than a bad config.
The two CamX overlays here are fine together; it is the camss ones that clash.

## Which connector is which

| Overlay | Connector | cameraId | CSIPHY | CCI |
|---|---|---|---|---|
| `…-csi1-4lane.dtbo` | CSI1 | 0 | 3 | cci1 master 0 |
| `…-csi2-4lane.dtbo` | CSI2 (shared with DSI) | 1 | 1 | cci0 master 1 |

Both expect a **4-lane IMX519 with an AK7375 VCM** — that is the only
combination validated so far. A 2-lane module fails in a particularly unhelpful
way: probe, acquire and start all report success, and only StreamOn comes up
with no frames. Behaviour with a fixed-focus module has not been tested.

To go back, remove the name from `overlays.txt` and reboot. A bad overlay is
skipped by the bootloader with the base device tree left intact, so nothing
here can brick the board.

## Checking it works

```sh
# Should list cam-req-mgr / cam_sync rather than the camss video2..18 set
for n in /sys/class/video4linux/video*/name; do printf '%s: %s\n' "$n" "$(cat "$n")"; done

camx-enum                       # cameras: 1  (or 2 with both overlays)
camx-capture 1920 1440          # writes /tmp/frame.nv21
```

Sanity-check the numbers rather than just the exit status: `non-zero Y` should
be close to 100% and the average should land somewhere sensible for the room —
a `max=255` alone is also what a blown-out or corrupt buffer looks like.

The output is **NV21** (V before U). Decoding it as NV12 swaps red and blue.

With both overlays enabled, pick the camera with `CAMX_CAM_ID` (CSI1 is 0,
CSI2 is 1; defaults to 0):

```sh
CAMX_CAM_ID=1 camx-capture 1920 1440 /tmp/csi2.nv21
```

`camx-capture` also takes per-request metadata overrides as trailing
`<hextag>=<value>` arguments, e.g. to pin the AF mode:

```sh
camx-capture 1920 1440 /tmp/f.nv21 10007=0     # ANDROID_CONTROL_AF_MODE = OFF
```

## Why one profile per connector

CamX identifies sensors by chip ID, and every IMX519 variant reports the same
`0x519` — so 2-lane vs 4-lane cannot be told apart at probe time. The profile
therefore has to state it, which is why each bin is pinned to one connector and
one lane count. Modules on *different* slots (different `cameraId`) coexist
fine; that is what makes the dual-camera configuration work.

Autofocus needs no such split — both profiles declare the same AK7375 VCM.
Its register encoding matters more than it looks: the vendor settings are
BIVCM / 10-bit / dataShift 6, and getting those wrong leaves every I2C write
ACKing while the lens never moves.

## Uninstalling

```sh
apt-get remove tachyon-camera-camx-qcm6490
```

This restores the stock `socid_map` that the package diverted, and removes the
`/usr/lib` layout symlinks. Remember to also revert `overlays.txt` and reboot,
otherwise the board comes up with a camera overlay whose userspace is gone.
