# Provenance of the shipped binaries

Everything under `assets/` is produced by `./build-assets.sh`. This file records
where its inputs come from, so the package can be rebuilt and audited without
guessing. Hashes are SHA256.

## Inputs

| Input | SHA256 | Origin |
|---|---|---|
| `vendor/com.qti.sensor.imx519.so` | `124ec7e85ec82a6d90779ab1de5a1ea725c38f7373ca5af19eedc74e2b0dd824` | Qualcomm chi-cdk prebuilt, Quectel R114 SDK |
| `vendor/com.qti.tuned.sunny_imx519.bin` | `56003d9d5323c57ff97946928646ca947176b107d80d4f4be4488ce8ed447737` | chi-cdk tuning project `tuning/sm8250_sunny_imx519` — see below |
| `ParameterParser` | `2724822ab1ce93089e050414ee1b85fa8eb0a45dcc1bb0face0c7b4a3a792be3` | `chi-cdk/tools/buildbins/linux64/`, V5.5.1 (2411131018) |
| `src/xml/*.xml`, `src/dts/*` | — | written here; the sensor register sequences derive from Quectel's `imx519_sensor.xml` |

**Neither binary comes from the PPA.** `qcom-chicdk-qcm6490` 1.0.6+repack2
ships eight sensor plugins — imx476, imx481, imx586, imx686, cmk_imx577,
ov9282, s5k3m5, max9296a_ar0231 — and seven tuning bins, all `kodiak_`-prefixed.
IMX519 appears in neither set. (It does ship
`com.qti.sensormodule.sunny_imx519.bin`, a *sensormodule* bin, which is a
different artifact and unused here.)

### The tuning binary

`chi-cdk/oem/qcom/buildbins/.../com.qti.tuned.sunny_imx519.mk` names its input
as the tuning project `tuning/sm8250_sunny_imx519`, run through
ParameterParser. So this data was calibrated for a **Sunny IMX519 module on
SM8250**, not for the module on this board — which is the direct cause of two
known defects: auto-exposure hunts (~0.225 EV at 1.8 Hz), and the LSC mesh is
calibrated for 4656x3496 and misaligns on binned modes.

Its exact build is **unconfirmed**: our copy hashes `56003d9d…`, while the two
copies in the Ubuntu 20.04 QTI tree hash `2b98f678…` (debug) and `ed3f73e9…`
(perf). All three are the same tuning project built at different times. This
matters only for byte-level reproducibility — replacing it with data calibrated
for this module is the real fix, and is tracked separately.

### Identifying the plugin build

It carries no `.note.gnu.build-id`; it is a Yocto/OE build that uses
`.gnu_debuglink` instead, pointing at `com.qti.sensor.imx519_cam1.so`
(CRC `5984a84a`). The same code appears in the Ubuntu 20.04 QTI robotics image
under that original name — a different link of the same sources (whole-file
hash `53efafa6…`, debuglink CRC `e7ceeeb8…`), whose `.text` is byte-identical
to ours. That shared `.text` hash is what pins the code identity:

    .text  97ffea788e76af547fd024aa28508bf6c48b41a780902bfadc97127322e6c005

## The one edit applied to a vendor binary

`build-assets.sh` runs exactly one:

    patchelf --remove-needed libsync.so.0 com.qti.sensor.imx519.so

**Why.** The recorded `DT_NEEDED libsync.so.0` has no provider on this platform
and no referencing symbol in the plugin — `nm -D --undefined-only` matches zero
`sync_*`/`fence` symbols. The CamX build put `-lsync` into `CMAKE_CXX_FLAGS`
ahead of `--as-needed`, so the linker recorded a dependency nothing uses. None
of the eight plugins that *do* ship in `qcom-chicdk-qcm6490` carry it, which
places the defect in this particular OE recipe rather than in CamX.

**What it changes.** 92 bytes, all inside `.dynamic` (file offsets 7545–7977).
File size, section count, section layout and `.gnu_debuglink` are unchanged;
`.text` matches the hash above; the seven exported symbols are unchanged
(`GetSensorLibraryAPIs`, `CalculateExposure`, `FillExposureSettings`,
`GetLineCount`, `NormalizeLineCount`, `ParseSensorMetaData`,
`VerifyAnalogGain`). Symbolised debugging still works — it resolves through
`.gnu_debuglink`, which this edit does not touch. `build-assets.sh` asserts the
input hash, the unchanged `.text`, the absence of libsync and the presence of
`GetSensorLibraryAPIs`, and `build.sh` re-checks the last two at package time.

Verified on hardware with libsync absent from the whole system: `camx-enum`
reports `cameras: 1`, `camx-capture` writes a frame with 2764800/2764800
non-zero luma samples.

**Preferred long-term fix:** rebuild the plugin from chi-cdk sources without
`-lsync`, and drop both `vendor/` and the patch step.

## Output hashes

Reproduced by `./build-assets.sh`:

| Output | SHA256 |
|---|---|
| `assets/camera/com.qti.sensor.imx519.so` | `c2a77eda3837d08150155c1f7bc88fae6616904620682af5498dd28c304ce5a4` |

The sensormodule/socid_map bins and the dtbos are regenerated from `src/` on
every run; the parser and dtc are deterministic, but the hashes are not pinned
here because editing the XML is a normal part of retargeting this package.

## Licensing — UNRESOLVED

**Redistribution rights have not been confirmed for anything in this section.**
Publishing this package outside the team needs that answered first.

Everything here traces back to Qualcomm-licensed material reaching us through
the Quectel R114 SDK — *not* through the Ubuntu QCOM PPA, whose terms would be
the easier case and do not apply to these files:

| Artifact | What it is |
|---|---|
| `vendor/com.qti.sensor.imx519.so` | Qualcomm proprietary binary |
| `vendor/com.qti.tuned.sunny_imx519.bin` | Qualcomm proprietary tuning data |
| `src/xml/tachyon_imx519_sensor.xml` | derived from Quectel's `imx519_sensor.xml` — register sequences are the substance of the file |
| `src/xml/tachyon_ak7375_actuator.xml` | derived from the R114 `ak7377_actuator.xml` |
| `src/xml/tachyon_imx519_csi{1,2}_module.xml` | written here, but against Qualcomm's module schema and validated by their XSD |
| `src/xml/tachyon_socid_map.xml` | same — the schema and the soc_id semantics are Qualcomm's |
| `src/dts/qcm6490-camera.dtsi` | CLO reference device tree, ~2500 lines, carried nearly verbatim |
| `assets/camera/*.bin` (generated) | produced by Qualcomm's ParameterParser from the XML above |

Two separate questions, and a "yes" to the first does not imply the second:

1. May these files be **redistributed**?
2. May they be **modified and then redistributed**? This matters for the
   patchelf step and for every derived XML above.

The generated `.bin` files are outputs of a proprietary tool applied to
proprietary inputs; do not assume they are cleaner to ship than their sources.
