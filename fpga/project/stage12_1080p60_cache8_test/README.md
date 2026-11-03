# Stage 12 1080p60 cache 16x8 candidate

This independent project copies the working Stage 12 1080p60 HDMI scanout
configuration. The input remains 1280x720 at 60 Hz and the output raster remains
1920x1080 at 60 Hz. The only processing-path change is increasing the 32x4
pixel tile cache from 16 sets x 4 ways to 16 sets x 8 ways. The output still
uses bilinear scaling with adaptive edge sharpening. It may repeat processed
frames when the processing rate is below the 60 Hz HDMI scanout rate.

The full-frame ideal-DDR simulation passes with 2,073,600 output pixels and
16,200 output bursts. It reports 28,800 tile-row reads and 3,099,473 cycles
at 125 MHz, versus 86,008 reads and 3,802,249 cycles for the 16x4 baseline.
The test does not model concurrent live HDMI display reads or real DDR latency.

The current build adds a 128-channel Fabric Debugger core for processing-time
profiling. PDS 2022.2-SP6.4 reports `All Constraints Met`: the 125 MHz DDR
processing clock has +0.218 ns setup slack, and the 148.5 MHz HDMI output
clock has +1.676 ns setup slack. Program
`generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit` (SHA-256
`D5569DE79092D9B9F2F6684762CAD438E01CAD914ADE3E4CBEC2E4538451F2CD`)
and import the paired `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic`
(SHA-256 `EACDA7FEFF6D7457C89F89E7E63A3BB3DC17BB97AA2BD05216B570BD4DE60501`).
See [README_JTAG.md](README_JTAG.md) for the channel map and measurement
procedure. The earlier frame-rate-only diagnostic pair remains under
`generate_bitstream/baseline_frame_rate/`.
