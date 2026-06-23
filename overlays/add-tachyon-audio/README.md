# add-tachyon-audio

This overlay installs the minimal audio configuration for the
`qcm6490-tachyon-snd-card`: UCM2, the WirePlumber policy, and the `tplg.bin`
firmware.

Includes:

- `HiFi`
  - `Headphones` -> `hw:0,0`
  - `Mic` -> `hw:0,2`

Install destinations:

- `lib/firmware/qcom/qcm6490/`
- `usr/share/alsa/ucm2/conf.d/qcm6490/`
- `usr/share/alsa/ucm2/Qualcomm/qcm6490-tachyon/`
- `etc/wireplumber/main.lua.d/`

Just reboot the system after the overlay is applied to the rootfs.

Verification:

```bash
alsaucm listcards
runuser -u particle -- env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus wpctl status
```

Notes:

- `qcm6490-tachyon-snd-card-tplg.bin` is installed to `lib/firmware/qcom/qcm6490/`,
  providing the topology firmware this sound card needs.
- `qcm6490.conf` and `qcm6490-tachyon-snd-card.conf` are both installed under
  `ucm2/conf.d/qcm6490/`, matching this board's card-lookup path.
- The WirePlumber rule makes the desktop prefer UCM instead of falling back to
  the ACP `off` / `Dummy Output`.
- It also disables persistent restore of the device route / default sink, to
  avoid carrying over stale state from a previous boot after HDMI/DP cable
  changes.
- `HiFi.conf` carries the basic playback/capture route directly in `SectionVerb`,
  so ACP/WirePlumber can open `hw:0,0` and `hw:0,2` on the first probe of the
  `HiFi` profile at boot.
- The `EnableSequence` for `Headphones` / `Mic` is kept, to re-apply the same
  mixer settings when a route is explicitly enabled, keeping runtime state
  consistent.
- `SectionDevice."HDMI"` continues to expose `hw:0,3` for shared DP/HDMI display
  audio.
- If an old image left WirePlumber state such as `auto_null`, you can clear the
  user-space cache once after upgrading, but later boots no longer depend on
  those state files.
