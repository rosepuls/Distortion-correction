# Distortion Core Timing Pipeline Design

## Goal

Refactor `distortion_core_optimized.sv` so the PGL50H implementation has short, explicit register-to-register arithmetic paths at the 100 MHz `ddrphy_clkin` clock. The mapper must remain bit-exact with the existing Q-format model, retain the existing module interface, and accept one coordinate every clock.

## Constraints

- Preserve every existing fixed-point shift, saturation point, sign extension, and Brown-Conrady equation.
- Preserve frame-stable parameter capture at `in_sof`, including the PDS `syn_preserve` attributes on Stage 0 calibration registers.
- Keep `in_valid`, `in_sof`, and `in_eol` aligned through bubbles and back-to-back inputs.
- Drive all output payload fields to zero whenever `out_valid` is low, matching current behavior.
- Put all generated XSim files below `xsim.dir`; do not create simulator artifacts in the project root.
- Do not change the external interface or downstream pixel-fetch protocol.

## Pipeline

The visible input-to-output latency is 13 rising clock edges:

| Edge | Registered work |
|---:|---|
| 1 | S0: coordinate and frame calibration capture |
| 2 | S1C: centered coordinates and inverse focal conversion |
| 3 | S1: normalization products and coefficient/intrinsic conversion |
| 4 | S2: `x^2`, `y^2`, `xy`, and `r^2` |
| 5 | S2H: Horner term `k1 + k2*r^2` |
| 6 | S3: radial gain `1 + r^2*Horner` |
| 7 | S4: radial products, `p1*xy`, `p2*xy`, and tangential bases |
| 8 | S5: tangential base products and term quantization |
| 9 | S6: tangential X/Y saturated sums |
| 10 | S7: distorted normalized X/Y saturated sums |
| 11 | S8: focal-length products |
| 12 | S9: principal-point addition and source Q19 coordinates |
| 13 | Output: coordinate split and registered output payload |

Each stage contains either parallel multipliers or a shallow add/shift/saturation layer. In particular, the former long chain from a tangential base through a coefficient multiply, two sums, focal multiply, principal-point add, and coordinate split is cut by registers. Center subtraction/quantization is also separated from the normalized-coordinate multiplier by S1C/S1 registers.

## Numeric Compatibility

The refactor does not move quantization boundaries:

- Normalized coordinates and coefficients remain S20.Q18.
- Horner, radial, tangential, and distorted terms retain their existing S21.Q18 saturation points.
- Focal and principal-point values remain S24.Q12 in the arithmetic pipeline.
- Focal products remain signed 45-bit values and are shifted by 11 before adding the principal point shifted by 7.
- `coordinate_split` still consumes signed 64-bit Q19 source coordinates.

Full-width products may be stored in registers between their original multiply and quantization operations. This changes latency only, not arithmetic results.

The tangential bases `r^2 + 2*x^2` and `r^2 + 2*y^2` use a signed 22-bit register. Their non-negative S20 inputs make 1,572,861 the largest possible integer representation, which fits signed 22 bits exactly. This removes the former redundant sign extension to 64 bits before the coefficient multiply without changing any reachable value.

## Verification

1. Golden-vector unit test checks the existing 25 bit-accurate vectors at 13-cycle latency.
2. A dedicated streaming test drives back-to-back coordinates, bubbles, SOF/EOL markers, and two frame configurations to prove one-coordinate-per-clock operation and metadata alignment.
3. The image-level `mes50hp_top` simulation must still reproduce its golden image.
4. The board-top compile simulation must elaborate and complete.
5. PDS Stage 0 preservation check must continue to find all protected registers after the user's next synthesis run.
