# Stage 3 frame-pool test project

This project is a tracked-input copy of the accepted Stage 2 RGBX8888 PDS
project. The Stage 2 directory is never modified by the generation script.

The video top keeps the accepted RGBX8888 HDMI and DDR datapath, but now
connects the capture pool to the real write and display slots. It gates pixel
writes by frame, uses the DDR IP write completion ID and pulse to decide when
a captured frame can be published, and displays the newest complete captured
frame. This is a capture-to-display test path. It has no copy engine or
processed-output pool in the live video datapath.
The write source busy signal includes synchronized line triggers, the pending
line request, and the legacy write controller's ready state. The admission
controller waits eight DDR clocks after VS before checking write drain.
The DDR IP has no standard AXI B response, so board readback is needed to
confirm the IP's completion pulse provides the intended visibility guarantee.
The four frame error LEDs now mean, from bit 3 to bit 0: read busy or write
protocol fault; write line busy; incomplete display frame; aborted capture
frame. The counters saturate and clear only on DDR reset.

`frame_pool_smoke.pds` selects `frame_pool_pair_smoke_top` for PDS synthesis
of two actual manager instances. It is a separate synthesis target; its
ports are test controls, not HDMI/DDR pins.

`frame_pipeline_smoke.pds` selects `frame_pipeline_smoke_top`. Its ownership
scheduler acquires one captured frame and one output slot together, then
publishes the output only after a successful copy completion. It is still a
test synthesis target without a DDR copy engine. It also instantiates the
read-burst arbiter with a synthetic return-data port. Capture admission is
connected to the scheduler, and pixel gating is connected to its permission.
The write drain tracker counts accepted Pango AW commands and corresponding
`axi_wusero_last` events by client ID. The smoke top supplies synthetic
write-side signals; the video top connects capture signals to the real DDR IP.

Run `../Run-FramePoolSmoke.ps1` to synthesize both managers with PDS. The
script checks the PDS log for errors and verifies both instances in the
generated netlist. The same synthesis top also includes the six-slot DDR word
address mapper.
Run `../Run-FramePoolSmoke.ps1 -Target pipeline` to synthesize the ownership
scheduler and address mapper with PDS.
Run `../Run-Stage3CaptureSynthesis.ps1` to synthesize the actual video top and
check that the capture pool, pixel gate, admission controller, and write
tracker are retained in its netlist.

The live video top also completed PDS 2022.2-SP6.4 place and route and
bitstream generation on 2026-10-20. The timing report says all constraints
met: the 125 MHz DDR clock has 1.736 ns setup WNS, and the 74.2501 MHz
HDMI input pixel clock has 5.527 ns setup WNS. The generated bitstream is
`generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`. These tool results do
not establish DDR write visibility or video stability on the board. Before
using Stage 3 as a new baseline, program that bitstream, inspect pure and
alternating colors plus moving video, read back DDR frame contents if
possible, and run at least 30 minutes while watching the four error LEDs.

Run `New-Stage3FramePoolTestProject.ps1` from `fpga/project/` to recreate this
directory from tracked Stage 2 inputs. The script refuses to overwrite an
existing directory.

`../../sim/frame_pool_manager_tb.v` exercises slot ownership, latest-frame
eviction, abort, and empty takes. Run it with
`../../sim/Run-FramePoolManager.ps1` in Vivado Simulator. The script uses
`VIVADO_HOME` and keeps simulator outputs under `../../sim/.work/`.
Run `../../sim/Run-FramePoolAddress.ps1` to check all six slot base addresses
and the active-frame word boundary.
Run `../../sim/Run-FramePipelineOwnership.ps1` to check copy-start handshake,
display ownership, latest-frame eviction, and failed-copy abort.
Run `../../sim/Run-DdrReadBurstArbiter.ps1` to check pre-reservation, response
routing, RLAST handling, and unexpected-response diagnostics.
Run `../../sim/Run-CaptureFrameControl.ps1` to check capture publication only
after an eight-cycle VS settling interval and write drain, plus whole-frame
pixel gating.
Run `../../sim/Run-DdrWriteDrainTracker.ps1` to check pending and completed
write bursts, per-client isolation, and fault handling.
