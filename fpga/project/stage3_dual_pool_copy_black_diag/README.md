# Stage 3 dual frame-pool copy project

This project is generated from the board-accepted `stage3_frame_pool_gate_fix`
project. It is an independent checkout for the input-pool to output-pool frame
copy path. The generator refuses to overwrite an existing destination and
omits PDS build outputs, bitstreams, and local logs.

Regenerate with `New-Stage3DualPoolCopyProject.ps1` from `fpga/project/`.
The video top publishes captured frames to the input pool and directs display
reads to the separate output pool. The read and write burst arbiters connect
the raw frame-copy engine to DDR. Verify simulation, physical timing, and
board operation before treating its bitstream as accepted.

This is a black-screen diagnostic variant of the candidate. The video path is
unchanged; the four `frame_error_led` outputs and sticky fault-cause
instrumentation in the diagnostic copy of `display_read_adapter.v` differ:

Current diagnostic bitstream SHA-256: `CCFB3405039EF6B37DEBD5DC54DFE237DDEA5BDD319A32ACA01D966C27963846`.

- LED4: pixel-side consumption passed DDR returned data (buffer underrun).
- LED5: output VS arrived while a display line/burst was still outstanding.
- LED6: unexpected RLAST/R response, or a zero-beat line request.
- LED7: at least one nonzero RGB pixel was observed while output DE was high.

All four indicators latch until DDR reset. This mapping identifies the display
adapter failure category. On the latest reported board run, LED5 and LED6 were
off while the other indicators were in their normal states: LED4 recorded a
pixel-side buffer underrun, LED7 recorded at least one nonzero RGB pixel, and
the frame-boundary and DDR response/length fault indicators remained clear.
LED7 only proves that some nonzero pixel occurred; it does not prove that a
complete, visible frame was delivered.
