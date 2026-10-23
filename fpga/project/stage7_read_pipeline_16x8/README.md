# Stage 7 read pipeline experiment (16x8 cache)

Independent throughput candidate based on the Stage 8 read-wait diagnostic
project. It retains the 16x8 cache and all four DDR read-wait counters. The
candidate permits up to four transform row bursts for one tile to be outstanding
and buffers the full 16-beat tile before cache writeback. Display reads retain
their own AXI ID and one-burst reservation path.

The cache refill FSM accepts all four rows after one tile request. This fixes
the first hardware revision, which deadlocked after its first row. The valid
bitstream has SHA-256 `1C76E121F392B1F459793E005C614E99E344DABCDCA298CDEA26E20119509913`.

Run `sim/Run-Stage7TileFill.ps1` and `sim/Run-Stage7ReadArbiter.ps1` for the
tile refill and concurrent read checks.

Build with `../Run-Stage7ReadPipeline.ps1`. Program this project's `.sbit` and
import the matching `.fic` from the same build. The FIC bus labels are corrected
for the Stage 8 diagnostic channel wiring.
