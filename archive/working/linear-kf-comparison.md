# Linear KF vs EKF Comparison — Decision Document

*Written 2026-04-26. Decide and act before report submission.*

---

## Current State

### What is implemented

- `ekf_update_baro.m` — fully implemented linear baro update: $y = z + v$, $H = [1\ 0\ 0]$
- `ekf_measurement_model = "altitude_linear"` toggle in `main.m` — swapping this runs the full pipeline through the linear path with no other changes
- `ekf_measurement_model = "pressure_nonlinear"` — default; true EKF update in pressure domain via ISA Jacobian
- `generate_report_artifacts.m` line 40 — uses `altitude_linear` only as a silent fallback if no model is set; does **not** run both models

### What is missing

1. **Comparison table** — no CSV exists showing `final_z` and `NIS` from both modes on the same flights side-by-side
2. **Comparison figure** — no plot overlays both trajectories on the same flight
3. **Report text** — no written analysis of what the difference is and why `pressure_nonlinear` was chosen

---

## Why This Matters for the Report

The spec (Evaluation Plan, "Better" level) lists multi-flight comparison and robustness.
The spec (Evaluation Plan, "Stretch" level) lists EKF vs linear KF baseline.

At < 3 km altitude the ISA pressure-altitude relationship is nearly linear. The expected result is:

- `final_z` difference between modes: < 1 m on most flights
- NIS difference: modest; `pressure_nonlinear` slightly higher because it operates in Pa and maps back, introducing a small Jacobian mismatch at high dynamics
- No divergence difference: both modes converge on all 25 flights

**The comparison is worth including because the conclusion is the interesting part:** the nonlinear model is architecturally the correct choice (it directly assimilates the raw sensor output without an intermediate altitude conversion), but at these altitudes it yields nearly identical accuracy — demonstrating the design is conservative and robust. That's a stronger justification than just asserting the EKF is better.

---

## Options

### Option A — Report-only (no new code, ~15 min)

1. In `main.m`, set `ekf_measurement_model = "altitude_linear"` and `run_generate_report_artifacts = true`
2. Run MATLAB, copy `final_per_flight_metrics.csv` to a separate file (e.g., `_report_artifacts/tables/final_per_flight_metrics_linear.csv`)
3. Reset `ekf_measurement_model = "pressure_nonlinear"`, rerun
4. Manually build a 3-row comparison table for the report figure flights in the report document

**Pros:** zero new code, done in one MATLAB run  
**Cons:** manual, not reproducible from `main.m` alone, numbers need to be transcribed by hand

---

### Option B — Standalone comparison script (~45 min)

Create `matlab/run_model_comparison.m`:

1. Runs both `altitude_linear` and `pressure_nonlinear` on all 25 flights (or just the 3 report figure flights)
2. Writes `_report_artifacts/tables/model_comparison.csv` with columns:
   `flight_id, final_z_linear, final_z_nonlinear, delta_z, nis_mean_linear, nis_mean_nonlinear`
3. Saves a side-by-side figure for one representative flight (e.g., `j570w_onboard`):
   - top: `z_hat` from both modes + raw baro
   - bottom: NIS from both modes

**Pros:** reproducible, self-contained, can be run once and committed  
**Cons:** new script to maintain; figures won't be part of the main `generate_report_artifacts` flow

---

### Option C — Integrate into generate_report_artifacts (~2 hr)

Add dual-run logic inside `generate_report_artifacts.m`:

1. After the primary run, re-run EKF on the figure flights using `altitude_linear`
2. Write `model_comparison_table.csv` automatically every artifact run
3. Save comparison figure alongside existing EKF figures

**Pros:** fully integrated, comparison is always up-to-date when artifacts regenerate  
**Cons:** most work; complicates `generate_report_artifacts.m` which is currently clean and simple

---

## Recommendation

**Option B.** One self-contained script, fully reproducible, output lands in the standard artifact directory. The comparison is a one-time analysis for the report — not something that needs to be regenerated automatically on every run (Option C overkill). Option A produces the same numbers but leaves them as manual transcription (error-prone).

Expected output from Option B for the 3 report figure flights:

| Flight | final_z linear (m) | final_z nonlinear (m) | Δz (m) |
|--------|-------------------|----------------------|--------|
| j570w_onboard | ~−0.2 | −0.2 | ~0 |
| j270w_14a_trimmed | ~−0.2 | −0.2 | ~0 |
| j530_raven | ~−1104 | −1104 | ~0 |

(Numbers approximate — run to confirm. Raven divergence is IMU-driven, not measurement-model-driven, so both modes diverge equally.)

---

## Files to create (Option B)

```
matlab/
  run_model_comparison.m          <- new standalone script
  _report_artifacts/
    tables/
      model_comparison.csv        <- generated output
    figures/
      model_comparison_<flight_id>.png  <- generated output
```

No changes to `main.m`, `generate_report_artifacts.m`, or any existing EKF files.
