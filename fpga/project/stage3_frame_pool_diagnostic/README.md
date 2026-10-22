# Stage 3 frame-pool diagnostic project

This isolated PDS project was generated from the Stage 2 RGBX8888 inputs and
then integrated with the Stage 3 capture-to-display RTL. Stage 2 and the
original Stage 3 project are separate and are not modified by this script.

The four added diagnostic LEDs latch these milestones after DDR reset:

| LED | Meaning |
| --- | --- |
| LED4 | Raw HDMI input DE has occurred |
| LED5 | At least one pixel passed `capture_pixel_gate` into `wr_buf` |
| LED6 | At least one complete frame was published by the capture pool |
| LED7 | The display consumer took a frame and `display_valid` became true |

Interpret the LEDs cumulatively. LED4 on and LED5 off points to input polarity
or capture gating. LED5 on with LED6 off points to frame completeness or DDR
write drain. LED6 on with LED7 off points to output VS/frame-take scheduling.
All four on with a black image points to DDR readback, slot addressing, or
pixel output formatting. These are sticky milestones, so reset the board before
each observation. LED0..LED3 retain their existing heartbeat and initialization
meanings.

Build only in this directory. The bitstream is written to
`generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`.