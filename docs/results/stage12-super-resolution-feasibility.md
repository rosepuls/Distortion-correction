# Stage 12 720p-to-1080p30 feasibility results

Date: 2026-10-29. Project: [`stage12_720p_to_1080p30_bilinear_adaptive_sharpen_test`](../../fpga/project/stage12_720p_to_1080p30_bilinear_adaptive_sharpen_test/README.md).

## Design under evaluation

- Input capture: RGBX8888, 1280×720.
- Output: RGBX8888, 1920×1080p30, 74.25 MHz pixel clock, 2200×1125 total timing.
- Sampling: center-aligned 3:2 mapping, `src=(dst+0.5)×2/3−0.5`, followed by the existing 2×2 DDR tile-cache bilinear sampler.
- Edge compensation: independently per RGB channel, enable at 2×2 contrast range ≥12; add `(bilinear−neighbor_mean)/4`; clamp to local minimum/maximum. No extra DDR neighbor reads.
- Stage12 does not include Brown distortion, angle correction, Stage 11 image enhancement, or UART. The input MS7200 EDID remains 720p60; the FPGA output raster is configured independently.

## Functional and throughput simulation

Vivado Simulator 2020.2 directed tests passed for 3:2 coordinate mapping, reset/metadata/backpressure behavior, high-contrast edge compensation, and low-contrast protection.

The full-frame engine simulation completed 2,073,600 output pixels and 16,200 output bursts. The test log reports **86,008 source tile-row reads** and **344,032 source response beats** (four per read). It completed in **3,802,249 cycles** at 125 MHz, equivalent to approximately **32.87 fps** (the testbench's integer display rounds this to 32). It verified frame completion after write drain, source and output address bounds, output address progression, output count, RGBX low-byte format, and zero tile-read errors.

The simulated DDR responder returns each four-beat source row with minimal latency and does not include the real Pango DDR controller, display scanout read contention, or board-level arbitration. The result is close to the 30 fps requirement and has limited margin; real sustained frame rate remains unproven.

## PDS implementation results

Pango PDS 2022.2-SP6.4 completed compile, synthesis, device mapping, placement, routing, timing analysis, power analysis, netlist generation, and `.sbit` generation.

| Metric | Result |
| --- | ---: |
| Timing summary | All Constraints Met |
| DDR processing clock | 125 MHz requested; 131.63 MHz estimated maximum |
| DDR-clock WNS | +0.403 ns |
| DDR-clock TNS | 0 ns |
| DDR-clock failing setup endpoints | 0 / 32,384 |
| LUTs | 15,351 / 159,800 (9.61%) |
| Registers | 8,367 / 319,600 (2.62%) |
| DRM36K equivalents | 18 / 415 (4.34%) |
| APMs | 20 / 740 (2.70%) |

An intermediate 1080p30 build with AVI VIC 34 had SHA-256 `DB90B8ECC61DBADB9D23FED178AA95D202F3CABA06562255A15361E47B74216F`. The current artifact is recorded in the 1080p60 section below.

## HDMI monitor rejection investigation (2026-10-30)

The first Stage 12 bitstream (SHA-256 `B8D5F2EC67E2F89BCB791A6A7E9C1030E39FC20F0BEDC36524CB67545DBD21FE`) was programmed on the board. The user reported that the SANC M2753 monitor showed an unsupported-input message while the FPGA LEDs appeared as in the working projects. Monitor OSD timing details could not be retrieved.

The Stage 12 raster is 2200×1125 at 74.25 MHz, giving exactly 30 Hz, with 1920×1080 active video and positive sync. These parameters match CTA 1080p30 (VIC 34). The PDS project includes the Stage 12 source paths. The MS7210 initialization code was inherited unchanged from the vendor's 1080p60 example, including an AVI InfoFrame with VIC 0. Its original checksum was 0x06. The HDMI initialization LED only shows that the control state machine reached its final state; it does not test display lock or validate the output timing.

To test the AVI identification hypothesis, Stage 12 alone now transmits VIC 34 (0x22) in AVI PB4 and changes its checksum to 0xE4. A byte-sum check over the AVI header, checksum, and 13 payload bytes returns zero. PDS regenerated the bitstream and again reported `All Constraints Met`. This is a targeted test of one plausible cause, not confirmation that the monitor accepts 1080p30. If the monitor still rejects this bitstream, the next isolation step is an HDMI-only known-pattern output at 1080p30 and a scan of the monitor's EDID-supported modes; the DDR image algorithm cannot cause the sync generator's 30 Hz period to change.

## 1080p60 monitor-compatibility trial (2026-10-30)

The user reported that the monitor does not accept 1080p30 and requested a 1080p60 output trial, accepting repeated or dropped processed frames. Stage 12's output PLL was changed from 74.25 to 148.5 MHz using the vendor's 1080p60 PLL parameters. The 2200×1125 raster is unchanged, so HDMI scanout is 60 Hz. The MS7210 AVI InfoFrame now sends VIC 16 (0x10) and checksum 0xF6; its header and payload still sum to zero modulo 256. The 1280×720 input and 1920×1080 scaling engine are unchanged.

PDS 2022.2-SP6.4 generated the 1080p60 bitstream and reported `All Constraints Met`: output pixel clock 148.5001 MHz, output-clock WNS +1.583 ns, DDR processing-clock WNS +0.575 ns, TNS 0. Current bitstream: [`HDMI_IN_DDR3_HDMI_OUT_top.sbit`](../../fpga/project/stage12_720p_to_1080p30_bilinear_adaptive_sharpen_test/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit), SHA-256 `A756F93BAFCEC4A631377A94F2627382A4AB4F2D056CFD6BD5318717BBD6E32E`.

The 32.87 fps figure above concerns the idealized image-processing simulation only. It does not guarantee 60 distinct output frames per second or glitch-free HDMI display reads with real DDR contention. Monitor lock and visible image still require board testing.

The user subsequently confirmed that the 1080p60 bitstream displays on the SANC monitor. LED4 and LED5 are off, LED6 and LED7 are on, and the visible motion is subjectively around 15 fps. This is not a hardware-counter measurement. It confirms HDMI lock but indicates processing throughput well below the 60 Hz scanout rate.

## Independent 16x8 cache candidate (2026-10-30)

An independent project, [`stage12_1080p60_cache8_test`](../../fpga/project/stage12_1080p60_cache8_test/README.md), changes only the Stage 12 tile cache from 16 sets × 4 ways to 16 sets × 8 ways. The working 1080p60 bitstream above remains available for A/B comparison. A Stage 7 720p project previously measured a real improvement from the same cache enlargement, so this is a focused throughput candidate rather than a display-timing change.

The 1080p full-frame ideal-DDR simulation passes: 2,073,600 output pixels, 16,200 output bursts, **28,800** source tile-row reads (down from **86,008**), and **3,099,473** cycles (down from **3,802,249**). At 125 MHz these idealized cycles correspond to **40.33 fps** versus **32.87 fps**. The model omits live DDR and display traffic, so it cannot predict the real speedup from the user's roughly 15 fps visual estimate.

The first, non-debug cache candidate had bitstream SHA-256 `DD9E45719CAABC3C99B9DC2DCA580DF5F50CCBCFF0ABD8064EA04683D7493A07`; that file has been superseded in this project by the diagnostic build below.

To measure the real frame rate, the candidate now includes a 128-channel Fabric Debugger core. PDS 2022.2-SP6.4 completed core insertion and bitstream generation with `All Constraints Met`: DDR processing-clock WNS **+0.100 ns**, 148.5 MHz output-clock WNS **+1.676 ns**, TNS 0. The paired artifacts are the [diagnostic `.sbit`](../../fpga/project/stage12_1080p60_cache8_test/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit), SHA-256 `DD3908C09D55E4B89B869D3D19DD6EE4AC7BA4722AE4E185C95E532C3CA8294B`, and [diagnostic `.fic`](../../fpga/project/stage12_1080p60_cache8_test/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic), SHA-256 `F3D671A24B567B390D3B37F0946B04C3307CEE2FACD0AEAACF352CE7D57767F2`. The [JTAG instructions](../../fpga/project/stage12_1080p60_cache8_test/README_JTAG.md) map input-published, processed, and display-taken frame counters.

### Board measurement (2026-10-30)

The user programmed the frame-rate diagnostic bitstream and captured two Fabric Debugger snapshots, at 10:49:45 and 10:50:20 (35 s apart). Counter deltas:

| Counter | First | Second | Delta | Rate |
| --- | ---: | ---: | ---: | ---: |
| Input frames published | `0x1469` (5,225) | `0x1C82` (7,298) | 2,073 | **59.23 fps** |
| Processed frames completed | `0x06C1` (1,729) | `0x096F` (2,415) | 686 | **19.60 fps** |
| New frames taken by display | `0x06C1` (1,729) | `0x096F` (2,415) | 686 | **19.60 fps** |
| Capture frames dropped before processing | `0x0DA6` (3,494) | `0x1311` (4,881) | 1,387 | **39.63 frames/s** |
| Processed frames dropped before display | `0x0000` | `0x0000` | 0 | 0 |

The accounting is consistent: 2,073 input frames = 686 processed + 1,387 dropped before processing, and every completed frame was taken by the display. Thus the display receives a new image about **19.6 times per second** while scanning at 1080p60; the monitor repeats frames between updates. This confirms the user's low-motion observation and shows the bottleneck is processing throughput, not output-frame drops. It is below the 32.87 fps ideal 16x4 and 40.33 fps ideal 16x8 simulation estimates, as expected with real DDR/display traffic. This is a 35-second sample and should be treated as a measured operating point, not a long-run stability result.

## Conclusion and remaining validation

The algorithm and frame path are **implementation-feasible**, and the monitor accepts 1080p60 output. The measured 16x8 diagnostic build produces about **19.8 new display frames/s**, so it does not sustain 30 fps under this board workload, despite the idealized simulation estimate of 40.33 fps.

Still useful: repeat the measurement over a longer interval and compare 16x8 against the Stage 8 bilinear baseline using the same source. The current sample already establishes the live processing rate and confirms that frames are dropped before processing.

### Processing wait profile build (2026-10-30)

To separate pipeline/DDR backpressure from frame-write and arbitration time, the project now exposes the last completed frame's total transform cycles and cycles where a valid pixel request was blocked at the processing pipeline input. The original frame-rate-only diagnostic pair is preserved in `generate_bitstream/baseline_frame_rate/`. The profile pair is the [`.sbit`](../../fpga/project/stage12_1080p60_cache8_test/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit), SHA-256 `D5569DE79092D9B9F2F6684762CAD438E01CAD914ADE3E4CBEC2E4538451F2CD`, and [`.fic`](../../fpga/project/stage12_1080p60_cache8_test/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic), SHA-256 `EACDA7FEFF6D7457C89F89E7E63A3BB3DC17BB97AA2BD05216B570BD4DE60501`. PDS reports `All Constraints Met`, DDR clock WNS **+0.218 ns**, output clock WNS **+1.676 ns**. The [JTAG guide](../../fpga/project/stage12_1080p60_cache8_test/README_JTAG.md) explains the four 32-bit counters.

The user captured snapshots at 11:48:53 and 11:49:23 (30 s apart): input-published count increased from `0x1510` to `0x1C19` (**1,801 frames, 60.03 fps**); display-take count increased from `0x06F8` to `0x094B` (**595 frames, 19.83 fps**). The latest-frame cycle samples were 6,298,519 and 6,299,710 cycles, or **50.39 ms/frame** at 125 MHz (~19.84 fps). Request-stall samples were 3,522,258 and 3,523,613 cycles, about **55.9%** of total transform cycles. This strongly implicates upstream backpressure in the cache/DDR read path, though this counter does not separate DDR controller wait from cache-fill and pipeline-control bubbles. A direct per-row AR wait / R-response wait measurement would further isolate the DDR portion.

After the streaming line-buffer reference-count fix, the user confirmed the image recovered. Snapshots at 12:39:12 and 12:39:56 (about 44 seconds apart) show input-published increasing from `0x0DB9` to `0x1816` (**2,653 frames, about 60.3 fps**) and display-take increasing from `0x0A2D` to `0x11DD` (**1,968 frames, about 44.7 fps**). The latest transform took 2,812,289 cycles, or **22.50 ms/frame at 125 MHz** (~44.45 fps); request-stall cycles were 609 (~0.022%). The interval-derived rate is approximate because console timestamps have one-second resolution, while the per-frame cycle counter independently confirms throughput above 30 fps. This short sample meets the 30 fps target and is well above the prior cache8 diagnostic result; it remains below 1080p60 scanout, so some processed frames are repeated. Longer-run stability and same-source visual A/B comparison remain outstanding.

## Sequential line-buffer experiment (2026-10-30)

The user requested a separate test project copied from the 16x8 diagnostic project. [`stage12_1080p60_streaming_linebuffer_test`](../../fpga/project/stage12_1080p60_streaming_linebuffer_test/README.md) replaces its associative tile cache with three 8-bank source line buffers and sequential 16-beat DDR bursts. The existing 3:2 coordinate mapper, bilinear interpolation, adaptive edge sharpening, frame ownership, output writes, and 1080p60 HDMI timing are retained. A source row is 160 256-bit beats, fetched as ten bursts; the design can fill a third row while lookups use the other rows. Row reference counts prevent overwriting data still used by outstanding pixel requests.

The first board report was black video with HDMI sync and the display-taken/output-valid LEDs off. Inspection found a signedness bug in `streaming_linebuffer_reader.sv`: a 3-bit signed reference delta was mixed with a 16-bit unsigned row count. A negative decrement could be extended as a positive value, leaving source rows marked in use. Once all three line slots filled, the sequential DMA could wait indefinitely for a free slot and stop frame processing. The fix explicitly sign-extends the signed delta to 16 bits before addition. The user subsequently confirmed the fixed bitstream displays correctly; measured frame rate is recorded above.

After the fix, PDS 2022.2-SP6.4 completed core insertion, routing, timing analysis, and bitstream generation with `All Constraints Met`. DDR processing-clock WNS is **+0.711 ns**; 148.5 MHz output-clock WNS is **+1.207 ns**; TNS is zero. Resource summary: **24 DRM blocks**, **9,906 LUTs**, and **9,967 FFs**. The regenerated [`.sbit`](../../fpga/project/stage12_1080p60_streaming_linebuffer_test/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit) SHA-256 is `ED0C273E1DA8DF71958A64A8741278C77DFDA0C8DEC960F496EFB362420CBC33`; paired [`.fic`](../../fpga/project/stage12_1080p60_streaming_linebuffer_test/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic) SHA-256 remains `A9A129747ED49C53C5EC4FABC43241C6D73E664649CE76698F392953B2E5DEDD`. The user confirmed functional recovery on the board. The measured ~44.7 processed frames/s establishes that this sample exceeds 30 fps; see the measurement above. This remains a short-run result, not a long-term stability guarantee.
