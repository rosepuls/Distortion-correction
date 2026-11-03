# Stage13 Motion Stabilization Host Prototype Implementation Plan

**Goal:** Create an isolated Stage13 copy and a Python prototype that estimates global frame shake, distinguishes it from sustained translation heuristically, and encodes bounded dx/dy updates for UART.

**Architecture:** Preserve the stable Stage11 calibrated baseline as the immutable source; defer Stage12 super-resolution until its timing is improved. The Stage13 host detector uses sparse optical flow and robust translation consensus; a trajectory low-pass separates fast jitter from sustained movement. A UART helper reuses the Stage11 packet framing while assigning a Stage13 extension for fixed-point translation.

**Tech Stack:** Python, OpenCV, NumPy, pyserial, pytest/unittest.

## Global Constraints

- Keep `stage11_720p60hz_adaptive_image_enhancement_calibrated_baseline` unchanged.
- Use `stage13_720p60_motion_stabilization_test` as the independent FPGA project name.
- Default video source is OBS Virtual Camera index 2; default UART is COM7 at 115200 baud, 8-N-1.
- The first estimator only handles global x/y translation and does not claim to distinguish all intentional rapid motion from shake.
- Reject low-confidence estimates and clamp compensation before sending.

---

### Task 1: Duplicate and identify Stage12

**Files:**
- Create: `fpga/project/stage13_720p60_motion_stabilization_test/` as a full recursive copy.
- Modify: Stage13 `README.md` to identify its source and current host-prototype status.

- [x] Copy the full Stage11 calibrated baseline directory without changing it.
- [x] Update Stage13 README and rename its build wrapper/log to Stage13 identity.
- [x] Compare source and copy file manifests; both contain 640 files.

### Task 2: Test shake separation and packet encoding

**Files:**
- Create: `host/pose/tests/test_stage13_motion_stabilization.py`.
- Create: `host/pose/stage13_motion_stabilization.py`.

**Interfaces:**
- `ShakeOnlyCompensator(alpha, max_correction_px).update(dx, dy) -> (correction_x, correction_y, trend_x, trend_y)`.
- `make_stage13_request(sequence, homography_rows, profile_id, dx, dy, enabled=True) -> bytes` returns a 65-byte packet with the existing version/CRC and a bounded signed Q16.16 translation extension.

- [x] Test that translated image frames produce measured nonzero global displacement.
- [x] Test that a sustained constant pan converges to a constant spatial offset rather than ongoing per-frame counter-motion.
- [x] Test that alternating high-frequency movement produces bounded nonzero shake correction.
- [x] Test packet length, flags, extension values, reserved zeros, CRC, and signed Q16.16 values.
- [x] Run the tests before implementation and confirm the missing module fails import.
- [x] Implement only the behavior required by those tests.
- [x] Run tests and confirm they pass.

### Task 3: Add OBS/UART runner and instructions

**Files:**
- Modify: `host/pose/stage13_motion_stabilization.py`.
- Modify: `fpga/project/stage13_720p60_motion_stabilization_test/README.md`.
- Modify: `host/pose/README.md`.

- [x] Add camera/video source, serial port, profile, dry-run, flow confidence, trend response, and compensation limit arguments.
- [x] Log measured dx/dy, low-frequency trend, correction, confidence, encoded request, and UART ACK status.
- [x] Clear the pose-update flag so requests alter only translation and profile fields.
- [x] Document that Stage13 FPGA RTL packet reception is not yet implemented and copied RTL rejects nonzero extension bytes.
- [x] Run deterministic tests and a CLI dry-run against synthetic video; board operation remains unverified until RTL integration.
