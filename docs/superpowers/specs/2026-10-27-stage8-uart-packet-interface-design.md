# Stage 8 UART parameter packet interface design

## Goal

Extend the isolated `stage8_brown_y_uart_echo_test` project from byte echo to a UART parameter-packet test that matches the existing Stage 8 homography parameter-bank contract. The FPGA validates each packet, reports its status and decoded values to the PC, and emits the existing Stage 8 configuration signals only for accepted packets.

## Compatibility audit

- `stage8_brown_y_mul_fix_test` exposes the parameter-bank contract through `cfg_valid`, `cfg_pose_valid`, `cfg_words[287:0]`, and `cfg_version[15:0]`. The current top ties these inputs low; it has no UART packet parser or byte-level protocol.
- Stage 8 copies use the same bank interface. `stage8_brown_y_mul_fix_test_inplane_rotation` has a different reset pose, but accepts the same configuration fields.
- Stage 9 copies retain the same bank signal interface, but currently contain byte-level UART RX only. Their RX constraint and related documentation still say P14; the board manual and verified loopback project establish the CP2102 pins as RX=B24 and TX=C24.
- The Stage 8 contract specifies row-major coefficient order, fixed-point formats, and the numeric profile, but not UART framing, CRC parameters, or response framing. This document defines those missing wire details.

## UART framing

Both directions use fixed 45-byte frames:

| Offset | Size | Request field | Response field |
| ---: | ---: | --- | --- |
| 0 | 1 | `0xA5` sync byte 0 | `0xA5` sync byte 0 |
| 1 | 1 | `0x5A` sync byte 1 | `0x5A` sync byte 1 |
| 2 | 1 | protocol version `0x01` | protocol version `0x01` |
| 3 | 1 | type `0x01` (set pose) | type `0x81` (set-pose response) |
| 4–5 | 2 | sequence / parameter version, little-endian | echoed sequence, little-endian |
| 6 | 1 | flags: bit 0 is `pose_valid`; bits 7:1 must be zero | status code |
| 7–42 | 36 | nine 32-bit homography words | decoded words echoed in the same order |
| 43–44 | 2 | CRC-16, high byte first | CRC-16, high byte first |

The CRC is CRC-16/CCITT-FALSE: polynomial `0x1021`, initial value `0xFFFF`, no input/output reflection, and final XOR `0x0000`. It covers offsets 2 through 42 inclusive; the sync bytes and CRC field are excluded.

Each coefficient is sent little-endian within its 32-bit word. Word 0 is `h00` and occupies `cfg_words[31:0]`; word 8 is `h22` and occupies `cfg_words[287:256]`. The nine row-major words are `h00,h01,h02,h10,h11,h12,h20,h21,h22`. Rows 0 and 1 are signed Q16.16; row 2 is signed Q2.30. The sequence field is passed unchanged as `cfg_version`.

Response status codes are `0=accepted`, `1=unsupported protocol version`, `2=unsupported message type`, `3=reserved request flag set`, `4=CRC mismatch`, and `5=homography outside the Stage 8 numeric profile`. A complete frame receives a response even if validation fails; the response echoes its decoded sequence and 36 payload bytes so the PC can inspect exactly what the parser received. An incomplete frame produces no response and is discarded when a new sync pair is found.

## Validation and Stage 8 mapping

For a valid-pose request, validate the same Stage 8 profile documented in `docs/plan/2026-10-24-stage8-angle-mapping.md`:

- Require `h22 == 0x40000000`.
- At all four 1280×720 image corners, require `2^29 <= D_Q30 < 2^31`.
- At those corners require `abs(N_x_Q16) <= 2^30` and `abs(N_y_Q16) <= 2^30`.
- Use signed arithmetic wide enough to evaluate the documented corner expressions without overflow.

For a request with `pose_valid=0`, require a valid frame, supported version/type, zero reserved flags, and valid CRC, then accept it without checking the ignored coefficients. Emit `cfg_valid=1`, `cfg_pose_valid=0`, the received sequence in `cfg_version`, and identity words on `cfg_words`; the existing parameter bank stages identity and clears pose validity at its next frame boundary.

For an accepted valid-pose request, pulse `cfg_valid` for one parser clock and drive `cfg_pose_valid=1`, the validated row-major words, and the request sequence on `cfg_version`. For every rejection, keep `cfg_valid=0` and leave the parameter bank unchanged. The parameter-bank `frame_start` behavior remains unchanged: acceptance stages values and the active set changes only on an accepted output-frame start.

## Test-project behavior

- Keep the already verified board pin mapping: UART RX B24, UART TX C24, heartbeat LED2 C19, and receive-activity LED3 E18.
- Run the byte receiver and packet parser from the test top's 27 MHz `sys_clk`, using the matching clock parameter. The parser RTL stays clock-parameterized so a later Stage 8 instance can run in the 125 MHz parameter-bank clock domain and connect directly without a clock-domain crossing.
- Connect parser outputs to the same `homography_parameter_bank` interface used by Stage 8. In the standalone test top, use a 60 Hz synthetic `frame_start` only to exercise pending-to-active behavior; the production integration will use the real accepted frame-start pulse from `frame_identity_transform_engine`.
- Return one 45-byte response for each complete request. The PC should use stop-and-wait: send one packet and wait for its response before sending the next. This fits the 115200 baud loopback test and avoids requiring hardware flow control.
- Preserve the existing Stage 8 video projects. This task changes only the isolated UART test project and the protocol/design notes; it does not connect UART inputs to the main Stage 8 top.

## Verification criteria

- Valid identity and valid non-identity packets produce the expected `cfg_*` pulse, bank pending/active values, ACK status, echoed sequence and echoed coefficient words.
- Bad CRC, unsupported version/type, reserved flags, and each out-of-profile case produce the matching NACK and never pulse `cfg_valid`.
- An explicit invalid-pose request is accepted, stages identity, and clears pose validity at the synthetic frame boundary.
- Back-to-back request tests wait for response completion; malformed/incomplete input resynchronizes at the next sync pair.
- The FPGA PDS build completes with B24/C24 constraints, and the generated test bitstream supports serial-assistant verification at 115200 8-N-1.

## Known follow-up outside this test project

The audit found stale P14 UART RX constraints in the Stage 9 project copies and old P14/K19 UART statements in `docs/chat/new-algorithm.md` and the Stage 9 UART RX design note. They should be corrected when updating those Stage 9 projects; this packet-test change will not silently edit or copy the Stage 9 trees.
