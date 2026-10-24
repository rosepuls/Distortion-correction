# Stage 7 output write overlap, 16×8

This independent project starts from `stage7_cycle_profile_16x8`. It keeps
the fixed Brown trial mapper, bilinear interpolator, 16×8 tile cache, frame
pools and 125 MHz DDR interface. Its functional change is confined to
`source/rtl/memory/frame_identity_transform_engine.sv`: two 128-pixel output
burst buffers let the engine collect the next burst while the previous burst
is presented to DDR. A full buffer remains owned by the writer until its
last W handshake. The write burst address comes from the writer's separate
burst index; output publication still waits for every write handshake and
the physical drain signal. Faults retain fail-stop behavior.

The previous board measurement was 3,590 processed frames in a 60-second
log window, or about 59.83 fps. This candidate reduces active frame
cycles. The initial engineering target for future algorithms is at most
1,562,500 processing cycles per frame at 125 MHz, leaving 25% of the 60 fps
frame period as processing headroom. Board results are recorded below;
RTL simulation alone does not establish throughput.

Run the targeted and full-frame identity-path simulations from the repository
root:

```powershell
./fpga/sim/Run-Stage7WriteOverlap.ps1
./fpga/sim/Run-Stage7WriteOverlap.ps1 -FullFrame
./fpga/sim/Run-Stage7WriteOverlap.ps1 -Fault
```

The targeted simulation withholds the first write burst for 1,000 clocks.
It checks that the next output burst is collected during that stall, that
two consecutive frames preserve DDR addresses and every output beat, and
that `copy_done` follows physical write drain. The full-frame run checks all
7,200 AW addresses and 115,200 output beats for 1280×720 identity sampling.
The fault run supplies an incorrect `WLAST` and checks that no output frame
is published. These tests exercise burst ownership and write ordering; the
production project still uses the Brown trial mapping.

Run `python configure_write_overlap.py` after regenerating the FIC template,
then build with `./Build-WriteOverlap.ps1`. Program only this project's
generated `.sbit` and import its matching `.fic`. The 256-channel map and
board readout are described in [README_JTAG.md](README_JTAG.md).

PDS 2022.2-SP6.4 completed full routing and bitstream generation. The final
timing report says `All Constraints Met`; the 125 MHz DDR slow-corner setup
slack is **+0.032 ns**. The generated pair is:

| File | SHA-256 |
| --- | --- |
| `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit` | `D3E1127E621D959B1085D74C9CD713632BBBFFB0896024BE186F9CD98D686499` |
| `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic` | `D1FDB7592A3BCF4979C8B4B0A9596ACB6E865D5F23BA1F6EF994263379A90DF7` |

The route meets timing with narrow margin. Board Listing captures at
15:21:33 and 15:22:33 on 2026-10-24 show raw input +3,604 frames, complete
input publication +3,567, processing +3,566 and display takeover +3,567.
READY overwrite and error flags stayed zero. The latest completed frame was
1,849,511 cycles (14.796 ms at 125 MHz), down 235,090 cycles from the
previous serial-writer snapshot; the lifetime maximum completed frame was
1,853,524 cycles. Thus active processing has about 11.2% of a 60 fps frame
period left, but still exceeds the 1,562,500-cycle target by 287,011 cycles.
The sustained processed-new-frame rate was only about 59.43 fps because
complete input publication lagged raw VSYNC by 37 frames in this window.
This FIC does not expose `capture_rejected_count` or `capture_abort_count`,
so the source of that ingress gap is not yet established. See
[the throughput analysis](../../../docs/chat/720p60-throughput-analysis.md)
for the full counter table and next diagnostic step. Board image quality
still needs separate visual confirmation.
