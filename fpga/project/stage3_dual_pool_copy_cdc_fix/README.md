# Stage 3 dual frame-pool copy: registered display pointer

Status: PDS build passed; user reports a normal board image with LED4 and LED5 off. The 30-minute motion-video acceptance is still pending, so this is the latest board-tested candidate, not yet the long-term accepted baseline.

The preceding `stage3_dual_pool_copy_recovery` bitstream `88CA1504...` failed
on the board with repeated partial-frame blacking. Its display consumer
counter was converted to Gray by combinational XOR before crossing clocks.
Unequal binary-counter propagation delays can therefore create a false
buffer-distance fault even when unread data is available.

This project registers the Gray result in the pixel clock domain before the
existing two DDR-domain synchronizer stages. Only `source/rtl/rd_buf.v` differs
from that recovery project's source tree. Prefetch and the LED map are retained.
The project was generated with `New-Stage3DualPoolCopyProject.ps1`, then its
diagnostic `fram_buf.v` was copied from the recovery project.

Validation:

- The old source fails a test with 0.1 ns low-bit and 2.1 ns MSB counter delays:
  actual consumption is 512, synchronized consumption becomes 0, and the
  adapter blocks despite 480 unread beats.
- The fixed source completes two 720-line frames with and without that skew.
  Both runs check 230,400 returned beats and all 14,400 burst addresses.
- The PDS full flow succeeds with all constrained paths met. Slow-corner
  DDR-domain setup margin: +0.798 ns.
- `cdc-netlist-audit.txt` records all ten source Gray flop paths and the two
  destination synchronizer flops. No combinational logic lies between them.
  Maximum slow-corner source CK-Q plus first-stage input route: 0.855 ns.

Bitstream: `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`

SHA-256: `F332443546E9CDA0E2EE2CF346D7FC71988B35B42642E664718070BB33B884FB`

Size: 9,188,552 bytes.

LED4–LED7:

- LED4: display-adapter cumulative error is nonzero (sticky).
- LED5: read-arbiter cumulative error is nonzero (sticky).
- LED6: current display output gate is open (live).
- LED7: output DE has carried a nonzero RGB pixel (sticky).

After a fresh configuration, a stable healthy image should have LED4/5 off
and LED6/7 on. The user reports that this bitstream restored a normal image
and LED4/5 were off. A 30-minute motion-video run has not been recorded for
this project. The earlier `stage3_frame_pool_gate_fix` remains the long-term
accepted fallback; simulation does not certify actual image data.
