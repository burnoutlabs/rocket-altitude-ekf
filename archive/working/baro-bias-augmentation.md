# Barometer Bias Augmentation — Assessment

*Written 2026-04-26. Decision needed before report submission.*

---

## What b_b Is

Add a 4th state representing slow barometric altitude offset:

$$\mathbf{x} = \begin{bmatrix} z & v_z & b_a & b_b \end{bmatrix}^\top$$

Dynamics: $\dot{b}_b = w_{bb}$ (random walk, new PSD parameter `q_bb_psd`)

Measurement model (linear): $y = z + b_b + v$  
Measurement model (nonlinear): $h(x) = p_0\left(1-\frac{z + z_{ref}}{H}\right)^\beta$ — `b_b` enters as an additive altitude bias before the pressure conversion

---

## What b_b Would Model

Sources of barometric bias that *could* be tracked:

| Source | Description | In-flight relevance |
|--------|-------------|-------------------|
| Static calibration offset | Fixed pressure offset from sensor manufacturing | **Cancelled** by launch-reference `z_ref` |
| Temperature drift | Sensor reading shifts as temperature changes through ascent | Possible; 0.1–1 m scale |
| Atmospheric pressure change | Synoptic front moves ambient pressure during flight | J394 case: 14 m over 220 s |
| Dynamic (ram) pressure | Body creates positive pressure at static port at high speed | Correlated with $v_z$, not a random walk |

---

## Observability Analysis — The Critical Constraint

With one baro sensor, the filter cannot independently observe $z$ and $b_b$ simultaneously.

**What the filter sees at each baro update:**
- Innovation = $(z_{true} + b_b) - (z_{hat} + b_{b,hat})$

The filter can only observe the **sum** $z + b_b$. The IMU dynamics give it a second lever: IMU integrates $v_z$, which propagates $z$ forward. The coupling is:

- During **pad phase** (z fixed, z_dot ≈ 0): baro measures $0 + b_b$ directly → $b_b$ is observable
- During **flight** (z changing rapidly): innovation encodes $\Delta z + \Delta b_b$; filter can partially separate them if $b_b$ is assumed slow (small `q_bb_psd`)

This works — *in theory*. In practice, the pre-launch pad window that multi_time and trimmed_txt flights have (30–120 s of pad data before ignition) is where $b_b$ would actually converge. Once launch happens and $v_z$ spikes, $b_b$ estimation stalls because the IMU acceleration dominates.

**Raven flights have no pad window** — $b_b$ would stay at its initial value throughout, giving zero benefit.

---

## Data Evidence: Is There Observable Baro Drift?

Current `final_z` for clean flights (without known physical causes):

| Flight | Duration | final_z | Note |
|--------|----------|---------|------|
| j570w_onboard | 275 s | −0.23 m | Near-zero drift |
| j354_xtra | 296 s | −2.86 m | Small residual |
| j510w_xtra | 322 s | −2.18 m | Dominated by shutdown spike |
| j150_onboard | 297 s | −0.70 m | Near-zero |
| trimmed_txt (6 flights) | 180–600 s | −2.3 to +2.4 m | All tight |

**Conclusion:** residuals are already ±3 m without $b_b$. The drift is not detectable above the noise floor of the current estimator. A baro bias state would not improve these flights.

**The J394 case (+14.2 m):** This is a 1.7 hPa frontal passage over 220 s → drift rate ≈ 0.006 m/s. A $b_b$ random walk *could* track this if `q_bb_psd` is set appropriately (~3.6 × 10⁻⁵ m²/s). However: $z$ also changes at up to 100 m/s during ascent. The filter cannot distinguish "baro reading climbed because altitude climbed" from "baro reading climbed because pressure dropped." The J394 error would be **partially** reduced but not eliminated — estimate: improvement from 14 m to ~6–10 m. Whether that's worth the added complexity and new hyperparameter is the core trade-off.

**Dynamic pressure effects:** ram pressure bias is correlated with $v_z$, not a random walk. $b_b$ as a random walk will not capture this correctly — it would just smear the estimate.

---

## Code Change Scope

If implemented, these files require non-trivial changes:

| File | Change | Risk |
|------|--------|------|
| `ekf_predict.m` | 3×3 → 4×4 matrices; expand F, Qd to include $b_b$ row/col | Medium — matrix dim bug if missed anywhere |
| `ekf_update_baro.m` | H = [1 0 0] → [1 0 0 1] | Low |
| `ekf_update_baro_pressure.m` | H = [dh/dz 0 0 dh/dbb]; expand K, KH | Medium |
| `run_vertical_ekf_replay.m` | x0 4×1, P0 4×4; add `bb_hat` log column; update summary struct | High — many size-sensitive lines |
| `main.m` | Add `init_var_bb`, `q_bb_psd` | Low |
| `generate_report_artifacts.m` | Add `final_bb_m` column to per_rows | Low |
| `ekf-reference.md` | Update equations, parameter table | Low |
| `dataset-and-results.md` | Update results tables | Low |

**Estimated effort:** 4–6 hours for clean implementation + validation across all 25 flights. Non-trivial matrix size bugs are the main risk.

---

## What It Would Add to the Report

**Value to report:** moderate to high *if* implemented cleanly.

1. Shows understanding of filter state augmentation
2. Provides observability analysis discussion (pad window → $b_b$ convergence → flight)
3. The J394 result marginally improves (but doesn't fully resolve — you'd still need to explain why)
4. Can show $b_b$ trace converging from ~0 to small value during pad, then slowly varying during flight
5. Report can compare: with/without $b_b$ on the 3 figure flights


---

## Recommendation

**Do it if:** you have a clear 4–6 hour block, care about the stretch deliverable, and want to discuss state augmentation and observability in the report.

**Skip it if:** you'd rather spend that time on report writing. The current results (14/16 within ±5 m, all bias estimates converged, all health metrics clean) already tell a complete story. $b_b$ would not improve the 14 clean flights at all.

**The honest case for including it:** the J394 flight (+14.2 m) is the only one where $b_b$ could change a number that currently needs explanation. If you want that result to be better than "atmospheric drift, fundamental limitation" — $b_b$ is the path. Otherwise the current explanation is fully defensible.

---

## If You Proceed — Implementation Order

1. `ekf_predict.m` — expand to 4-state, test isolated on one flight
2. `ekf_update_baro.m` — trivial H extension
3. `ekf_update_baro_pressure.m` — H and R_eff update (b_b enters linearly even in pressure domain because $\partial h / \partial b_b = \partial h / \partial z$ — same Jacobian term)
4. `run_vertical_ekf_replay.m` — dimension changes + log
5. `main.m` — add two parameters, verify all 25 flights pass
6. `generate_report_artifacts.m` — add column
7. Update docs

Add `q_bb_psd` to the options struct in `run_vertical_ekf_replay.m` with a default of `(0.01)^2 = 1e-4` m²/s (≈ 1 cm/s random walk in baro altitude). This is small enough not to disturb clean flights but responsive enough to track slow drift.
