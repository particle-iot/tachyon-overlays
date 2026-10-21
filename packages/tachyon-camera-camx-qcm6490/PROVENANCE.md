# Provenance of the shipped binaries

Everything under `assets/` is produced by `./build-assets.sh`. This file records
where its inputs come from, so the package can be rebuilt and audited without
guessing. Hashes are SHA256.

## Inputs

| Input | SHA256 | Origin |
|---|---|---|
| `$CHICDK/oem/qcom/sensor/imx519/imx519_sensor.cpp` | — | chi-cdk source, Quectel r108 SDK (r1.0_00108.0); compiled by `build-assets.sh` |
| `vendor/com.qti.tuned.sunny_imx519.bin` | `56003d9d5323c57ff97946928646ca947176b107d80d4f4be4488ce8ed447737` | chi-cdk tuning project `tuning/sm8250_sunny_imx519` — see below |
| `ParameterParser` | `2724822ab1ce93089e050414ee1b85fa8eb0a45dcc1bb0face0c7b4a3a792be3` | `chi-cdk/tools/buildbins/linux64/`, V5.5.1 (2411131018) |
| `src/xml/*.xml`, `src/dts/*` | — | written here; the sensor register sequences derive from Quectel's `imx519_sensor.xml` |

**Neither the plugin nor the tuning comes from the PPA.** `qcom-chicdk-qcm6490` 1.0.6+repack2
ships eight sensor plugins — imx476, imx481, imx586, imx686, cmk_imx577,
ov9282, s5k3m5, max9296a_ar0231 — and seven tuning bins, all `kodiak_`-prefixed.
IMX519 appears in neither set. (It does ship
`com.qti.sensormodule.sunny_imx519.bin`, a *sensormodule* bin, which is a
different artifact and unused here.)

### The tuning binary

`chi-cdk/oem/qcom/buildbins/.../com.qti.tuned.sunny_imx519.mk` names its input
as the tuning project `tuning/sm8250_sunny_imx519`, run through
ParameterParser. So this data was calibrated for a **Sunny IMX519 module on
SM8250**, not for the module on this board. Known effects: a cyan cast
indoors, and the LSC mesh is calibrated for 4656x3496 and misaligns on binned
modes. (The auto-exposure flicker once blamed on it was the sensor plugin; see
below.)

Its exact build is **unconfirmed**: our copy hashes `56003d9d…`, while the two
copies in the Ubuntu 20.04 QTI tree hash `2b98f678…` (debug) and `ed3f73e9…`
(perf). All three are the same tuning project built at different times. This
matters only for byte-level reproducibility — replacing it with data calibrated
for this module is the real fix, and is tracked separately.

## The sensor plugin

`com.qti.sensor.imx519.so` is compiled from the chi-cdk source against the
chi-cdk headers. It must match the CamX it runs under: CamX passes it a
`SensorExposureRegInfo` and the plugin reads the exposure and gain register
addresses out of it by offset. `build-assets.sh` asserts the offsets this
CamX uses (exposure 824, analog gain 832, digital gain 840).

Up to 0.1~exp7 a prebuilt from the Ubuntu 20.04 QTI image was shipped. It was
never loaded, because CamX looks for `/usr/lib/camera/*.sensor.imx519.so.0`
and only `.so` was installed; CamX then used generic gain math
(`512 - 512/gain`) that gives this sensor about half the requested gain, so
auto-exposure kept chasing its target and the picture flickered. Given the
right name, it wrote exposure to 0x0000 and gain to the short-exposure
registers: its headers predate `preShutterLengthLinesAddr`, so every address
after it is one field off. Hence the rebuild, and the `.so.0` link `build.sh`
now installs.

Verified on hardware: register writes go to 0x0202 (exposure), 0x0204 (analog
gain, `1024 - 1024/gain`) and 0x020E (digital gain); auto-exposure settles in
about seven updates and then stops writing.

## Output hashes

Nothing in `assets/` is pinned. The bins, dtbos and plugin are regenerated
from `src/` and chi-cdk on every run; the tools are deterministic, but editing
the XML is a normal part of retargeting this package.

## Licensing — UNRESOLVED

**Redistribution rights have not been confirmed for anything in this section.**
Publishing this package outside the team needs that answered first.

Everything here traces back to Qualcomm-licensed material reaching us through
the Quectel R114 SDK — *not* through the Ubuntu QCOM PPA, whose terms would be
the easier case and do not apply to these files:

| Artifact | What it is |
|---|---|
| `assets/camera/com.qti.sensor.imx519.so` (generated) | compiled from Qualcomm proprietary source |
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
   compiled plugin and for every derived XML above.

The generated `.bin` files are outputs of a proprietary tool applied to
proprietary inputs; do not assume they are cleaner to ship than their sources.
