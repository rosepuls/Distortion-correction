# Distortion Internal Format Scan

Frame: 1280x720; raster stride: 8; every border pixel included.
Limits: max error <= 0.062500 pixel; mean error <= 0.015625 pixel; coord_valid mismatches = 0.

| Candidate | Camera | Max error (pixel) | Mean error (pixel) | RMSE (pixel) | coord_valid mismatches | Selected |
|---|---|---:|---:|---:|---:|---|
| narrow-q12-q22 | identity | 0.046100616 | 0.019826008 | 0.023530251 | 0 |  |
| narrow-q12-q22 | barrel | 0.032739639 | 0.015638953 | 0.017994317 | 0 |  |
| narrow-q12-q22 | pincushion | 0.064077377 | 0.023173950 | 0.028215744 | 1 |  |
| medium-q12-q24 | identity | 0.011819839 | 0.005071918 | 0.006019423 | 0 | yes |
| medium-q12-q24 | barrel | 0.008451462 | 0.003994467 | 0.004595571 | 0 | yes |
| medium-q12-q24 | pincushion | 0.016311646 | 0.005928257 | 0.007217167 | 0 | yes |
| wide-q14-q24 | identity | 0.011819839 | 0.005071918 | 0.006019423 | 0 |  |
| wide-q14-q24 | barrel | 0.008451462 | 0.003994467 | 0.004595571 | 0 |  |
| wide-q14-q24 | pincushion | 0.016311646 | 0.005928257 | 0.007217167 | 0 |  |

## Candidate formats

- `narrow-q12-q22`: centered S25.Q12; inverse S24.Q22; normalized S26.Q22; coefficient S24.Q20; radius S28.Q22; radial S26.Q22; distorted S26.Q22; focal S25.Q12
- `medium-q12-q24`: centered S25.Q12; inverse S26.Q24; normalized S28.Q24; coefficient S26.Q22; radius S30.Q24; radial S28.Q24; distorted S28.Q24; focal S25.Q12
- `wide-q14-q24`: centered S27.Q14; inverse S26.Q24; normalized S28.Q24; coefficient S26.Q22; radius S30.Q24; radial S28.Q24; distorted S28.Q24; focal S27.Q14

## Selection

SELECTED_FORMAT = `medium-q12-q24`

centered S25.Q12; inverse S26.Q24; normalized S28.Q24; coefficient S26.Q22; radius S30.Q24; radial S28.Q24; distorted S28.Q24; focal S25.Q12
