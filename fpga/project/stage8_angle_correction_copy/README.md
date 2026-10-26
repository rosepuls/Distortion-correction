# Stage 8 angle correction

This is the independent PDS project for angle-correction work. It was seeded
from the committed `stage7_write_overlap_16x8` project, including its 16×8
tile cache, output-write overlap, DDR frame pools, pin constraints and vendor
IP. The Stage 7 working project's generated files and `data.wf` were not used
as the seed.

## Current state

The video path now selects `RADIAL_MAPPING=2`: output pixels enter a
Q16.16/Q2.30 homography mapper, then a calibrated fractional-coordinate Brown
mapper, then the existing DDR cache and bilinear sampler.
The homography uses a 1024-word reciprocal seed ROM and one pipelined Newton
step. Invalid or incomplete four-neighbor samples produce black pixels.
The parameter bank commits a complete nine-word set on an accepted output
frame start and the engine tags each pixel with that frame's version. An
explicit invalid-pose packet selects identity homography on the next frame.

The top-level packet inputs are currently tied low. After reset, Stage 8
therefore runs identity homography followed by the calibrated Brown map. The
mapper now normalizes coordinates with the calibration's `cx/cy/fx/fy` and
applies `k1/k2/p1/p2` in OpenCV camera coordinates; `k3` is not implemented.
The copy now includes a Fabric Debugger build for tracing the fixed +384-pixel
source-Y offset seen on the board. Its probes compare homography Y, Brown input
and output stages, per-stage pixel IDs, and the coordinate FIFO result. The
current `.sbit` and matching `.fic` were generated on 2026-10-26; post-route
timing met all constraints with +0.050 ns WNS on the 125 MHz `ddrphy_sysclk`
clock. A capture from this probe map will identify the first stage where the Y
value diverges.

The top-level packet inputs are currently tied low, so the project uses identity
homography followed by the calibrated Brown map. It does not respond to dynamic
angle packets. A validated UART packet receiver and numeric-range validator are
still needed to drive dynamic angles.

The mapping format, reciprocal candidate, frame-switch contract and remaining
integration points are in
[the Stage 8 design note](../../../docs/plan/2026-10-24-stage8-angle-mapping.md).
The software coefficient and integer-map model is
[`host/pose/export_pose_homography.py`](../../../host/pose/export_pose_homography.py).

## Parameter-bank simulation

From the repository root:

```powershell
.\fpga\project\stage8_angle_correction_copy\sim\Run-Stage8ParameterBank.ps1
```

The targeted simulation checks reset identity, pending replacement, atomic
frame commit, coincident commit and new packet, version tagging, and invalid
pose behavior. The inherited Stage 7 tile-fill and read-arbiter simulations
remain in `sim/` for baseline memory-path checks.

## Coordinate-chain simulation

From the repository root:

```powershell
.\fpga\project\stage8_angle_correction_copy\sim\Run-Stage8HomographyChain.ps1
```

The first test checks the composed homography/Brown path at integer and
half-pixel positions, unsupported numeric packets, metadata and ready/valid
stalls. The second checks both homography and Brown outputs at 60 points from
ten synthetic planar poses against the host integer model. The copy's Brown
reference vectors and the chain's expected coordinates now use the calibrated
camera intrinsics. The chain, 60-vector reference, and strict-border
simulations pass. The reference vectors can be regenerated after exporting the
ten synthetic poses with:

```powershell
python fpga\project\stage8_angle_correction_copy\sim\generate_homography_vectors.py `
  host\pose\output\pose_homography.jsonl
```

## PDS workflow

The project file is `HDMI_IN_DDR3_HDMI_OUT.pds`. `Build-AngleCorrection.ps1`
builds the project, checks that timing passes and that all 256 Fabric Debugger
channels match the coordinate and pixel probes, then copies the matching FIC
beside the bitstream. The channel definitions are listed in
[`README_JTAG.md`](README_JTAG.md).

The original `stage8_angle_correction` project has a separate routed baseline;
its timing numbers do not describe this copy.

