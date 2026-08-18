# tachyon-gst-pipewire-camfix

Replaces `libgstpipewire.so` with a build of PipeWire 1.0.5 that has
`always-copy` on by default.

## What it fixes

Stopping a recording in GNOME Snapshot faults the app:

```
__memcpy_generic
gst_video_frame_copy_plane
gst_video_frame_copy
libgstvideofilter.so          <- videoflip
gst_proxy_pad_chain_default
libgstcoreelements.so         <- multiqueue
```

`pipewiresrc` passes PipeWire's own mapping downstream (`gst_memory_share`) and
leans on `parent_buffer_meta` to keep the pool buffer alive. That keeps the
`GstBuffer` object alive but not the mapping under it, so when PipeWire
withdraws its buffers anything still reading pixels faults. The core dump shows
the source pointer in an unmapped gap while the destination is a healthy heap
page — the frame being read from is what went away, not the one being written.

`always-copy` makes the source copy each frame inside `pipewiresrc`, while
PipeWire's loop lock is still held, so downstream holds ordinary memory that
PipeWire cannot take back.

Measured on this board, recording then stopping:

| | crashes |
|---|---|
| stock plugin | 18 / 20 |
| this package | 0 / 20 |

Cost: one full-frame copy per frame, about 3% of one core at 1920x1440
(0.8% → 3.9% measured on `pipewiresrc` alone).

## Why the default has to move

`always-copy` is a normal element property, but Snapshot builds its
`pipewiresrc` inside aperture's device provider — there is no place to pass a
property in. Changing what the element defaults to is the only lever.

## Retiring this package

Upstream fixed the same defect in commit `bb1bb07f6` ("gstpipewiresrc: Handle
stream being disconnected"), which sends a flush-start downstream before
removing buffers. It first appears in PipeWire 1.5.81. When the archive carries
that or later, remove this package — the diversion is undone on removal and the
distribution's plugin comes back.

Note the upstream fix does not need `always-copy` and so does not pay the
per-frame copy.

## Where the binary comes from

`assets/libgstpipewire.so` is built from the upstream PipeWire tree at tag
`1.0.5`, taking the eight `.c` files under `src/gst/` with one line changed:
`DEFAULT_ALWAYS_COPY` in `gstpipewiresrc.c`, `false` → `true`.

Upstream rather than Ubuntu's `1.0.5-1ubuntu3.3` source package, which would
normally be a problem — distribution patches would be silently dropped. It is
not one here, and that was checked rather than assumed. The Ubuntu package
carries eighteen patches, all of them in systemd unit handling and snap
permission support; `grep -rl src/gst debian/patches/` returns nothing, so
`src/gst/` is byte-identical to upstream at this version.

Worth re-checking if this is ever rebuilt against a newer Ubuntu revision.

## Rebuilding the plugin

`build-plugin.sh` builds it in an arm64 container. Two things it gets right
that are easy to get wrong by hand:

- `--network host` is required. On the default bridge network the container's
  DNS is captured by the VPN and `ports.ubuntu.com` is unreachable.
- `HAVE_GSTREAMER_DEVICE_PROVIDER` must be defined in the generated
  `config.h`. Without it `pipewiredeviceprovider` is not registered and
  Snapshot reports "no camera found" — the crash is traded for a worse
  symptom.

The only source change is `DEFAULT_ALWAYS_COPY` in `gstpipewiresrc.c`.

## Checking it took

```sh
gst-inspect-1.0 pipewiresrc | grep -A2 always-copy   # Default: true
gst-inspect-1.0 pipewire | grep pipewiredeviceprovider
```

Both must pass. The second is what makes the camera visible at all.
