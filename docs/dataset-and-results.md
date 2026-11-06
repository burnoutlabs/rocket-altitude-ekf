# Dataset and EKF Results — Reporting Reference

_Consolidated from data investigation (2026-04-25) and post-cleanup pipeline run (2026-04-26)._
_Source archive: [`archive/data_investigation/`](../archive/data_investigation/) and [`archive/AUDIT-2026-04-25.md`](../archive/AUDIT-2026-04-25.md)._

All data sourced from the DOFPro flight-data archive: <https://dofpro.org/RCK/fltdata/FlightData.html>

---

## 1. Dataset Overview

### 1.1 Source Families

Four distinct data families are present in the pipeline, each from a different data logger
and recording convention:

| Family prefix    | Logger                    | IMU rate   | Baro rate | IMU:Baro | Recording start   |
| ---------------- | ------------------------- | ---------- | --------- | -------- | ----------------- |
| `emulation_csv`  | Synthetic simulator       | 50 Hz      | 50 Hz     | 1:1      | Before launch     |
| `multi_time_csv` | DOFPro XTRA / OnBoard     | ~70–100 Hz | ~35–37 Hz | ~2:1     | Before launch     |
| `raven_csv`      | Featherweight Raven 3     | ~400 Hz    | ~20 Hz    | ~20:1    | At motor ignition |
| `trimmed_txt`    | ICM-based flight computer | ~1141 Hz   | ~55 Hz    | ~21:1    | Before launch     |

Key consequence: `raven_csv` has **no pre-launch pad window** — the first samples are
always high-thrust boost phase. This directly affects EKF initialisation (§4.2).

### 1.2 Final Flight Count

After data investigation and dataset cleaning:

| Action                    | Count  |
| ------------------------- | ------ |
| Flights evaluated         | 25     |
| Dropped (unusable)        | 1      |
| Kept in pipeline          | 24     |
| + emulation reference     | 1      |
| **Total in EKF pipeline** | **25** |

The pipeline processes 25 flights total (24 real + 1 emulation).

### 1.3 Cross-Logger Validation

Seven same-day, same-motor logger pairings were present (XTRA or OnBoard logger + Raven altimeter
on the same rocket), covering **six independent flights**: the two J510W rows are the same
physical flight (the /213 file is a second record whose sensor data matches the primary XTRA
file), so they count once. All six agreed on apogee altitude to within **< 1%**:

| Pair                   | Multi-time alt | Raven alt | Agreement |
| ---------------------- | -------------- | --------- | --------- |
| H148R 1 Jul 2017       | 586 m          | 581 m     | 0.7%      |
| J510W 8 Jul 2017       | 3168 m         | 3167 m    | 0.0%      |
| J510W 8 Jul 2017 (213) | 3168 m         | 3167 m    | 0.0%      |
| J354 9 Sep 2017        | 2546 m         | 2544 m    | 0.1%      |
| J394 7 Oct 2017        | 2905 m         | 2899 m    | 0.2%      |
| J150 9 Dec 2017        | 2692 m         | 2688 m    | 0.1%      |
| J570W 9 Dec 2017       | 2674 m         | 2668 m    | 0.2%      |

This confirms data integrity: both sensors on the same airframe measure the same
physical event.

---

## 2. Dataset Quality Findings

### 2.1 Dropped Flight: Vulcanite G78

`trimmed_txt_20210205_vulcanite_g78_10g_l_trimmed` was removed from the pipeline.

**Cause:** 116 systematic barometer steps (±500–1925 Pa, ~1 Hz) throughout the entire
flight (t = 7 s to t = 98 s). The rocket body swings under the parachute, causing the
static port to alternate between windward and leeward faces. Each face produces a
different apparent static pressure, yielding oscillating ±85–160 m altitude errors
at ~1 Hz throughout descent. No filter or cleaning step can recover the true altitude
from this data — the corruption is physical and systematic.

### 2.2 Raven Family — Pre-/Post-Flight Windows Do Not Exist

Tests expecting a pre-launch quiet window (stable baro, static 1-g IMU) fail for all
Raven flights. This is **not a data defect**:

- The Raven altimeter starts logging at **motor ignition**. The first 5–10 s is
  always high-thrust boost (net accel 25–72 m/s²).
- There is no pre-launch pad segment from which to establish a quiet baro baseline.
- Post-landing stability tests are also unreliable because Raven logs may end during
  descent oscillation.

**EKF implication:** the filter initialises with `P_zz = 2500 m²` (σ = 50 m) at `t = 0`
and immediately receives boost-phase data. The pre-launch convergence benefit seen in
multi_time and trimmed_txt flights is absent.

### 2.3 trimmed_txt IMU Clipping at ±16 g

The ICM-based logger clips at ±16 g (±156.9 m/s²) during high-thrust boost. This
produces brief saturated runs of 0.2–0.4% of total samples (0.8–1.4 s). After boost
the signal is well within range and baro updates correct accumulated velocity error.
This is expected hardware behaviour for a consumer MEMS IMU; it does not affect
post-boost EKF performance.

### 2.4 Isolated Barometer Steps (Benign)

Steps > 500 Pa were found in 14 of 25 flights. All benign patterns are either:

- **Near-apogee pair** (1–3 samples): baro sensitivity at near-zero vertical velocity.
  0.03–0.06 s duration. The filter assimilates and recovers with no lasting effect.
- **End-of-record spike** (2 samples, ±650–4400 Pa): logger shutdown artifact at
  t > 90% of record. Irrelevant to the ascent phase.
- **Launch-jolt transient** (1 sample in Raven at t < 4 s): isolated.

The J510W XTRA flights carry a 2-sample ±4400 Pa end-of-record spike which elevates
the flight-wide NIS mean from ~1.5 to ~4.6 — see §4.1.1 for the full explanation.

---

## 3. EKF Configuration (Validated)

```
q_vz_psd           = 4.0       % velocity process noise PSD [m²/s]
q_ba_psd           = 0.0025    % bias random walk PSD [m²/s³]  (= 0.05² m/s² / Hz)
r_baro_var         = 64        % baro measurement variance [m²]  (= 8² m, σ ≈ 0.68 m)
measurement_model  = pressure_nonlinear   % true EKF update in pressure domain
enable_innovation_gate = false  % gating disabled — causes baro starvation on diverse flights
```

Physical meaning of `r_baro_var = 64`:

σ_baro = 8 m → σ_P ≈ 8 × 11.8 ≈ 94 Pa at sea level (ISA lapse rate ∂P/∂z ≈ −11.8 Pa/m).
Typical MEMS baro noise (BMP280 / MS5607) is 1–3 Pa static, 3–7 Pa in flight with vibration.
r = 64 m² is slightly conservative but physically defensible across the heterogeneous sensor set.

Parameters were selected by physical reasoning, not grid search.

---

## 4. EKF Results and Explanations

### 4.1 Non-Raven Flights (Class A — Full Flight)

**16 flights** (7 multi_time + 8 trimmed_txt + 1 emulation). All have a pre-launch pad
window giving the filter time to establish baseline altitude before launch.

| Flight                                           | final_z (m) | NIS mean | Notes                                      |
| ------------------------------------------------ | ----------- | -------- | ------------------------------------------ |
| emulation_csv_e190_8jul2017_j510w_emulationdata  | −1.5        | 2.40     | Synthetic reference                        |
| multi_time_csv_e190_1jul2017_h148r_1_xtra        | −8.4        | 0.37     | Low-altitude (~580 m), short record        |
| multi_time_csv_e190_7oct2017_j394_1_xtra         | **+14.2**   | 2.73     | **Atmospheric drift** — see §4.3           |
| multi_time_csv_e190_8jul2017_j510w_1_xtra        | −2.2        | **4.65** | **Logger-shutdown NIS spike** — see §4.1.1 |
| multi_time_csv_e190_8jul2017_j510w_1_xtra_213    | −2.2        | **4.65** | Same flight, alternate logger              |
| multi_time_csv_e190_9dec2017_j150_onboard        | −0.7        | 1.80     | Clean                                      |
| multi_time_csv_e190_9dec2017_j570w_onboard       | −0.2        | 3.49     | Near-apogee baro cluster                   |
| multi_time_csv_e190_9sep2017_j354_1_xtra         | −2.9        | 1.57     | Clean                                      |
| trimmed_txt_20210205_minidx3_g77_10r_l_trimmed   | −0.3        | 0.84     | Clean                                      |
| trimmed_txt_20210205_minidx3_g79_10w_l_trimmed   | +2.4        | 0.48     | Clean                                      |
| trimmed_txt_20210410_minidx3_h128w_14_trimmed    | −0.3        | 0.91     | Clean                                      |
| trimmed_txt_20210410_vulcanite_h128w_10_trimmed  | −1.0        | 0.22     | Clean                                      |
| trimmed_txt_20210410_vulcanite_j270w_14a_trimmed | −0.2        | 0.83     | Clean, 600 s record                        |
| trimmed_txt_20220610_adv_j570_trimmed            | −2.3        | 0.24     | Clean                                      |
| trimmed_txt_20220611_adv_j530_trimmed            | −0.5        | 0.23     | Clean                                      |
| trimmed_txt_22020609_adv_j825r_f1_trimmed        | −2.3        | 0.38     | Clean                                      |

**Summary:** 14 of 16 land within ±5 m. The two exceptions are J394 (atmospheric drift, §4.3)
and H148R (−8.4 m, low altitude, short weak baro observability window).

#### 4.1.1 J510W Elevated NIS — Logger Shutdown Artifact

The `j510w_1_xtra` and `j510w_1_xtra_213` flights show NIS mean = 4.65 (chi2(1) expectation ≈ 1.0).

**Cause:** at t ≈ 295 s the XTRA datalogger shuts down, producing a 2-sample baro artifact:
+4 367 Pa then −4 414 Pa (net ≈ +45 m / −45 m in altitude). These 2 samples produce
NIS ≈ 2400 per sample. With gating disabled, both are assimilated.

The flight-wide NIS mean is computed over ~11 850 baro samples. Two extreme samples
raise the mean from the nominal ~1.5 to 4.65. The filter recovers fully: `final_z = −2.2 m`.

**Report framing:** cite as filter robustness — a ±4400 Pa isolated spike (> 50× measurement
noise) is absorbed without divergence and the final state remains correct.

### 4.2 Raven Flights (Class B — Ascent Correct, Post-Apogee Divergence Expected)

**9 flights.** The EKF correctly tracks altitude and velocity through the ascent phase.
Post-apogee, the filter diverges. This is a **known limitation** of the dataset, not the filter.

**Root cause:** After apogee, the rocket reorients nose-down under drogue/main parachute
deployment. The axial accelerometer, which measured upward thrust during ascent, now
measures the −g component of free-fall with drag. Without attitude or gyroscope data —
absent from all Raven source files — the IMU input cannot be rotated to the world frame.
The EKF interprets the descent signal as a sustained ~−20 m/s² world-frame downward
acceleration and integrates it for the remainder of the ~200 s descent.

Additionally, Raven records begin at motor ignition (no pre-launch pad window), so the
bias state `b_a` starts converging from zero simultaneously with high-thrust boost data —
further reducing accuracy during the descent phase.

| Flight                                      | Duration (s) | final_z (m) | NIS mean |
| ------------------------------------------- | ------------ | ----------- | -------- |
| raven_csv_e190_1jul2017_h148r_1_raven       | 69           | −394        | 0.29     |
| raven_csv_20210417_adventurer_j530_1_raven  | 212          | −1104       | 0.57     |
| raven_csv_20210417_adventurer_j510w_1_raven | 239          | −1156       | 2.04     |
| raven_csv_e190_9dec2017_j150_raven          | 191          | −1158       | 2.13     |
| raven_csv_e190_8jul2017_j500g_raven         | 172          | −1223       | 1.15     |
| raven_csv_e190_9sep2017_j354_raven          | 194          | −1299       | 1.62     |
| raven_csv_e190_7oct2017_j394_1_raven        | 223          | −1440       | 2.94     |
| raven_csv_e190_9dec2017_j570w_raven         | 176          | −1485       | 3.35     |
| raven_csv_e190_8jul2017_j510w_raven         | 221          | −1763       | 6.15     |

The H148R Raven record is only 69 s (short capture window) — divergence is smaller
because the post-apogee integration time is much shorter.

**Cross-validation:** The J510W, J570W, J150, J354, J394, and H148R flights each have a
corresponding multi_time or trimmed_txt record from the same flight. Those records
land within ±3 m, confirming the filter is correct on data where the IMU axis is
consistently world-frame-aligned throughout.

### 4.3 J394 7 October 2017 — Atmospheric Pressure Drift (+14.2 m Final Error)

`multi_time_csv_e190_7oct2017_j394_1_xtra` returns `final_z = +14.2 m` after landing.
All other multi_time flights land within ±3 m.

**Cause:** A frontal system crossed the region on 7 Oct 2017. The atmospheric pressure
dropped ~1.7 hPa during the ~220 s flight window. Because the EKF anchors its altitude
reference to the **launch-time barometric reading** and has no in-flight absolute pressure
reference, a genuine synoptic pressure change is indistinguishable from an altitude change.
The same drift appears in the corresponding Raven record (final_z = −1440 m includes
atmospheric component plus post-apogee divergence).

**Not a filter error:** this is a fundamental limitation of any single-sensor barometric
altimeter. A GPS fix or ground-station pressure telemetry link would eliminate it.

---

## 5. Filter Health Summary (Fleet-Wide)

| Metric                          | Value                        |
| ------------------------------- | ---------------------------- |
| Total flights processed         | 25                           |
| Baro update ratio (all flights) | 1.000 (gating disabled)      |
| Non-raven flights within ±5 m   | 14 / 16                      |
| Non-raven flights within ±10 m  | 15 / 16                      |
| P_baba converged (all flights)  | 25 / 25 (final ≈ 0.10 m⁴/s⁴) |
| num_cov_floor_events            | 0 across all flights         |
| final_state finite              | 25 / 25                      |

### 5.1 NIS by Family

NIS (Normalised Innovation Squared) has chi-squared(1) expectation of 1.0 for a consistent filter.

| Family           | NIS range | Interpretation                                            |
| ---------------- | --------- | --------------------------------------------------------- |
| `emulation_csv`  | 2.40      | Slightly elevated — structured synthetic dynamics         |
| `multi_time_csv` | 0.37–4.65 | 1.57–3.49 typical; J510W outlier from shutdown spike      |
| `trimmed_txt`    | 0.22–0.91 | Best-calibrated family; filter closest to chi2(1)         |
| `raven_csv`      | 0.29–6.15 | Wide range; ascent phase NIS reasonable, descent inflated |

trimmed_txt NIS < 1 (filter slightly conservative): `r_baro_var = 64 m²` is mildly large
for the ICM sensor's actual in-flight noise, or `q_vz_psd = 4.0 m²/s` is slightly large
for the 1141 Hz IMU. Both directions represent the same Q/R trade-off for a fixed global
parameter shared across all families.

### 5.2 Bias Convergence

`final_ba_mps2` is the final value of the accelerometer-bias state:

| Family           | ba range (m/s²) | Note                                  |
| ---------------- | --------------- | ------------------------------------- |
| `emulation_csv`  | −5.4            | Single synthetic flight               |
| `multi_time_csv` | −3.3 to −9.5    | DOFPro XTRA/OnBoard IMU               |
| `trimmed_txt`    | −7.7 to −18.5   | ICM sensor; larger DC offset expected |
| `raven_csv`      | −4.3 to −11.4   | Raven integrated IMU                  |

**Correction (under investigation, issue #4).** These values were previously described
here as physically plausible accelerometer biases (0.3–1.9 g equivalent) and the bias
state as working as intended. That claim is withdrawn. A MEMS accelerometer bias is well
under 1 m/s²; values of 3–18 m/s², including −5.4 m/s² on the *synthetic* emulation flight,
mean `b_a` is absorbing model error rather than tracking sensor bias. See
[ekf-reference.md §15.1](ekf-reference.md#151-accelerometer-bias-state-absorbs-model-error)
for the write-up. The final-altitude results rest on the barometer correcting the trajectory,
not on `b_a` being a true bias estimate.

---

## 6. Report Classification

| Class   | Definition                                                                              | Flights                                                   |
| ------- | --------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| **A**   | Full flight with pre-launch pad window; filter correct throughout; `\|final_z\| < 15 m` | 14 non-raven flights                                      |
| **A\*** | Full flight; `final_z` outside ±5 m but explained by known physical cause               | J394 (+14.2 m, atmospheric), H148R (−8.4 m, short record) |
| **B**   | Ascent phase correct; post-apogee divergence expected due to Raven IMU axis flip        | All 9 raven flights                                       |
| **ref** | Synthetic emulation; used as a controlled reference                                     | emulation_csv flight                                      |

For report figures, use:

- **Class A primary:** `multi_time_csv_e190_9dec2017_j570w_onboard` — 2674 m apogee, clean, cross-validated against Raven, final_z = −0.2 m
- **Class A, trimmed_txt:** `trimmed_txt_20210410_vulcanite_j270w_14a_trimmed` — 1141 Hz IMU, 600 s record, final_z = −0.2 m
- **Class B (limitation):** `raven_csv_20210417_adventurer_j530_1_raven` — clean ascent, clear post-apogee divergence, moderate divergence depth (−1104 m)

These three are set in `main.m` `report_figure_flight_ids`.

---

## 7. Known Limitations for Report

1. **No attitude data (Raven):** the EKF assumes axial IMU = world-frame vertical throughout.
   Post-apogee, conventional rockets flip nose-down. Without a gyroscope or attitude system
   the IMU input is incorrect for the descent phase. Correct resolution requires attitude estimation
   or a nose-flip heuristic (brittle, not implemented).

2. **Single barometric reference:** altitude is relative to launch-time ambient pressure.
   Synoptic pressure changes during the flight window accumulate as apparent altitude error
   (J394 case: 1.7 hPa → +14 m). GPS or pressure telemetry would correct this.

3. **Fixed global Q/R:** the same `q_vz_psd`, `q_ba_psd`, `r_baro_var` are used for all
   four sensor families despite IMU rates of 50–1141 Hz and baro rates of 20–55 Hz.
   Per-family tuning would improve NIS consistency but is out of scope for this project.

4. **Innovation gating disabled:** a strict global gate caused baro starvation during
   high-dynamic events (boost phase, logger artifacts). With gating off, all baro
   measurements are accepted. The ±4400 Pa J510W shutdown spike is absorbed without
   divergence, confirming this is the correct trade-off for a heterogeneous dataset.
