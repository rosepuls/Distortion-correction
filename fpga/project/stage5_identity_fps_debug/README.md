# Stage 5 FPS diagnostic project

Independent copy of stage5_identity_ddr. It adds saturating counters for
published input frames and output frames acquired by the display, then inserts
the same 256-channel Fabric DebugCore bus layout used by the earlier Stage 3
diagnostic project. The processor remains the DDR-backed identity algorithm.

Build this project separately. Program its own `.sbit` and import its matching
`.fic` in Pango Fabric Debugger. The Stage 3 `.sbit`/`.fic` pair cannot measure
the Stage 5 processor. See README_JTAG.md for channel mapping and procedure.

PDS 2022.2-SP6.4 completed the full flow with DebugCore insertion and `All
Constraints Met`. Worst 125 MHz DDR setup slack is +0.622 ns. The matching
files are:

- `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit` — SHA-256
  `65E369284448C066BF31C1D7003FD3CEE41E066B9F570286E7C056C94FCD2CF6`.
- `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic` — SHA-256
  `75238CA445B2684E35A16E4364A69EB8E04D31BDA685E78D9481FAC6DD5DCB97`.

This pair awaits physical JTAG measurement. The source image should be a
moving frame-number pattern because three rising counters alone cannot prove
that every displayed source image is distinct.
