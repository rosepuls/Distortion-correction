# Stage 12 streaming line-buffer implementation plan

The user approved an isolated Stage 12 fixed-ratio line-buffer experiment and requested a paired FIC. Execute inline in `stage12_1080p60_streaming_linebuffer_test`; do not edit the cache8 baseline.

## Files

- Copy project scaffolding: `fpga/project/New-Stage12StreamingLinebufferProject.ps1`.
- New line-buffer DDR reader: `source/rtl/memory/streaming_linebuffer_reader.sv`.
- Replace the cache-reader instance in `source/rtl/correction/stage12_super_resolution_pipeline.sv` only in the new project.
- Add row-read and throughput probes to `source/rtl/fram_buf.v` and expose per-frame counters from `source/rtl/memory/frame_identity_transform_engine.sv`.
- Configure `synthesize/HDMI_IN_DDR3_HDMI_OUT_top_syn.fic`; ensure PDS widget points to it.
- Build with `Build-Stage12.ps1`, then copy FIC beside `.sbit`.
- Document interfaces, counters, build results, and board procedure in the new project's README and `docs/results/stage12-super-resolution-feasibility.md`.

## Implementation order

1. Copy only source/configuration/IP assets into the new Stage12-prefixed project; preserve a manifest/hash of the cache8 parent bitstream and leave its files untouched.
2. Implement a row-burst reader that issues ten 16-beat bursts per source row, stores each 256-bit beat as eight pixels in the selected free row slot, and exposes completed-row count.
3. Implement three tagged row slots and banked synchronous RAM reads for x0/x1 from y0/y1. Track input-accepted and response-returned references; allow replacement only when tag is below the next required y0 and outstanding reference count is zero.
4. Integrate the line reader behind the existing bilinear planner and sharpener. Preserve all metadata and ready/valid semantics.
5. Add per-frame elapsed/request-stall probes and cumulative frame counters. Generate a compact FIC with 128 or fewer channels and clear group names.
6. Update new-project build/README scripts and verify source isolation and FIC-to-bitstream pairing.
7. Run PDS from the copied project. Fix compile, mapping, routing, or timing issues without modifying cache8 baseline. Record exact WNS and hashes.
8. Report board steps and compare its measured FPS/stall counters to cache8; do not claim speedup until board data arrives.

## Verification gates

- Static RTL checks: width/range review for row addresses, slot tags, bank index and burst count; no line slot replacement while referenced.
- PDS: compile and routing complete, `Design Summary : All Constraints Met`, correct debug core insertion, `.sbit` and `.fic` hashes.
- Board: use identical moving input and monitor timing; capture two cumulative-counter snapshots 10-30 seconds apart and per-frame cycle/stall values.
