# Stage 8 angle correction

This is the independent PDS project for angle-correction work. It was seeded
from the committed `stage7_write_overlap_16x8` project, including its 16×8
tile cache, output-write overlap, DDR frame pools, pin constraints and vendor
IP. The Stage 7 working project's generated files and `data.wf` were not used
as the seed.

## Current state

The video path now selects `RADIAL_MAPPING=2`: output pixels enter a
Q16.16/Q2.30 homography mapper, then a fractional-coordinate version of the
Stage 7 trial Brown mapper, then the existing DDR cache and bilinear sampler.
The homography uses a 1024-word reciprocal seed ROM and one pipelined Newton
step. Invalid or incomplete four-neighbor samples produce black pixels.
The parameter bank commits a complete nine-word set on an accepted output
frame start and the engine tags each pixel with that frame's version. An
explicit invalid-pose packet selects identity homography on the next frame.

The top-level packet inputs are currently tied low. After reset, Stage 8
therefore runs identity homography followed by the **trial**, uncalibrated
Brown map; this bitstream does not respond to dynamic angle packets. A
validated UART packet receiver and numeric-range validator are still needed
to drive dynamic angles. The current design has a routed, constraint-clean
Stage 8 bitstream that can be programmed to the board for static video-path
bring-up; on-board behavior and throughput still need to be measured.

The mapping format, reciprocal candidate, frame-switch contract and remaining
integration points are in
[the Stage 8 design note](../../../docs/plan/2026-10-24-stage8-angle-mapping.md).
The software coefficient and integer-map model is
[`host/pose/export_pose_homography.py`](../../../host/pose/export_pose_homography.py).

## Parameter-bank simulation

From the repository root:

```powershell
.\fpga\project\stage8_angle_correction\sim\Run-Stage8ParameterBank.ps1
```

The targeted simulation checks reset identity, pending replacement, atomic
frame commit, coincident commit and new packet, version tagging, and invalid
pose behavior. The inherited Stage 7 tile-fill and read-arbiter simulations
remain in `sim/` for baseline memory-path checks.

## Coordinate-chain simulation

From the repository root:

```powershell
.\fpga\project\stage8_angle_correction\sim\Run-Stage8HomographyChain.ps1
```

The first test checks the composed homography/trial-Brown path at integer and
half-pixel positions, unsupported numeric packets, metadata and ready/valid
stalls. The second checks both homography and trial-Brown outputs at 60
points from ten synthetic planar poses against the host integer model. Both
passed in Vivado Simulator 2020.2 on 2026-10-24. The committed reference vectors can be
regenerated after exporting the ten synthetic poses with:

```powershell
python fpga\project\stage8_angle_correction\sim\generate_homography_vectors.py `
  host\pose\output\pose_homography.jsonl
```

## PDS workflow

The project file is `HDMI_IN_DDR3_HDMI_OUT.pds`. The first Stage 8 FIC
template was seeded from Stage 7's PDS FIC and remapped by
`configure_angle_correction.py` to the Stage 8 256-channel diagnostic map.
The generated Stage 8 FIC is used by `Build-AngleCorrection.ps1`, which builds
and verifies the bitstream/FIC pair. The copied channel definitions are
listed in [`README_JTAG.md`](README_JTAG.md).

PDS 2022.2-SP6.4 completed synthesis of the connected tree on 2026-10-24.
The latest SNR estimates 23,365 LUTs and 12,035 FFs and lists -0.006 ns as
the worst slack, on planner metadata writes to cache RAM. The Brown mapper
path has +0.042 ns slack. These are synthesis estimates, not post-route
timing. The top-level packet inputs are tied low, so dynamic homography cost
and timing are not represented until a validated configuration source is
connected. Inherited IP device-information mismatch and constant-probe
warnings remain.

## Routed bitstream

`Build-AngleCorrection.ps1` completed the full 2026-10-24 PDS flow, including
Fabric Debugger core insertion, place/route, post-route timing and bitstream
generation. The post-route report says `Design Summary : All Constraints
Met.` For the 125 MHz `ddrphy_sysclk`, setup WNS is +0.228 ns and hold WHS is
+0.103 ns, with zero failing endpoints.

The bitstream is
[`generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`](generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit),
9,188,552 bytes, SHA-256
`BD29230F6845FF5D7A3BB6E9D4E7CB2058AA4DDAFC047CE476DD01C8FE945BBB`.
The matching Fabric Debugger file is
[`generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic`](generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic),
SHA-256 `D1FDB7592A3BCF4979C8B4B0A9596ACB6E865D5F23BA1F6EF994263379A90DF7`.
The bitstream is suitable for static Stage 8 video-path bring-up; dynamic
angle correction remains disabled until validated UART configuration is
connected.

The latest timing pass added a registered cache replacement-metadata
snapshot, split vertical interpolation products and summation across elastic
stages, and simplified the display-adapter credit threshold. Targeted
interpolator, display-adapter, and five-frame cache replay simulations pass.
