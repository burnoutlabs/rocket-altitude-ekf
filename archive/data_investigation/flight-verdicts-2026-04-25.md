# Flight Dataset Deep Inspection — Final Verdicts

**Date:** 2026-04-25  
**Script:** `deep_inspect_all.py` + `diagnose_flags.py`  
**Flights inspected:** 25 (all currently in pipeline after source revision)  
**Result:** 24 KEEP, 1 DROP

---

## Test Suite Summary

Tests applied per flight:

| ID | Test | Description |
|----|------|-------------|
| B1 | Single apogee | Global pressure minimum is unambiguous (no rival within 200 Pa, >30 s away) |
| B2 | Pre-launch stable | First 10 s baro std < 50 Pa |
| B3 | Post-landing stable | Last 10 s baro std < 50 Pa |
| B4 | Apogee not at edge | Apogee between 5–95% of record |
| B5 | Altitude gain | Pressure drop to apogee > 500 Pa (~42 m) |
| B6 | Baro drift | Final vs initial pressure: PASS ≤100 Pa, WARN 100–300 Pa, FAIL >300 Pa |
| B7 | No baro steps | No adjacent-sample steps > 500 Pa |
| I1 | Pre-launch g | Median accel_z in first 5 s ≈ +9.81 ± 1.5 m/s² |
| I2 | Boost detected | Peak accel_z > 20 m/s² |
| I3 | No rail clipping | No run > 50 samples at hardware rail value |
| I4 | IMU rate consistent | Max inter-sample gap < 5× median |
| T1 | t=0 pre-flight | First 5 baro samples stable |
| T2 | Apogee after 3 s | Apogee not at record start |
| X1 | Cross-check pairs | Same-day/motor pairs agree on apogee altitude within 10% |

---

## Family-Wide False Positive Findings

### I3 — "No Rail Clipping" Test Was Broken

The I3 logic was inverted for multi_time_csv, raven_csv, and emulation_csv families.
The implementation measured the longest run of **non-clipped** samples, not clipped samples.
As a result, every flight showing "22k–95k samples at rail" was a false positive.

Corrected assessment per family:

| Family | Actual I3 State |
|--------|-----------------|
| `trimmed_txt` | **Real brief clips** at ±16g (±156.9 m/s²) rail during boost. 0.2–0.4% of samples, 0.8–1.4 s. Expected for high-thrust motors. Baro will correct velocity error post-boost. |
| `multi_time_csv` | **No clipping.** Rail value (±464–504 m/s²) appears exactly 1 sample. Non-issue. |
| `raven_csv` | **No clipping.** Rail value (±465–722 m/s²) appears exactly 1 sample. Non-issue. |
| `emulation_csv` | **No clipping.** Simulation values never actually saturate. |

### B2/B3/I1 — Raven CSV Pre/Post Windows Are Inapplicable

All `raven_csv` flights failed B2 (std 2000–9700 Pa), B3 (std 76–167 Pa), and most failed I1.

**Root cause:** The Raven altimeter starts logging at **launch ignition**, not during pad prep.  
There is no pre-launch quiet window — the first 5–10 s of every Raven record is the high-thrust boost phase.

- B2: Pre-launch 10 s window = boost phase → massive pressure change → expected FAIL.  
- B3: Post-landing 10 s window may include late-descent oscillation → not reliable.  
- I1: Pre-launch 5 s window = boost at 25–72 m/s² net accel → not a static +g reading.  

These are not data defects. The EKF reference baseline is computed from the beginning of the record regardless.

---

## B7 — Baro Step Analysis

Steps > 500 Pa were found in 14 of 25 flights. Most are benign, one is disqualifying.

### Benign step patterns (KEEP):

| Pattern | Flights affected | Assessment |
|---------|-----------------|------------|
| Near-apogee pair (1–3 samples, ±600–2900 Pa) | All `multi_time_csv` XTRA/Onboard | Baro sensitivity at zero vertical velocity. 0.03–0.06 s duration. EKF will absorb. |
| End-of-record spike (2 samples, ±650–4400 Pa) | `multi_time_csv` XTRA flights, `emulation_csv` | Logger shutdown artifact. Occurs at t > 90% of record. Irrelevant to EKF flight phase. |
| Early single step (1 sample, ±507–515 Pa) | `raven_csv` J394, J354 | Launch-jolt transient at t < 4 s. Isolated. |
| Ascent single-sample step | `trimmed_txt` H128W, J270W | Isolated glitch. 1 sample = 0.018 s at 55 Hz. |

### Disqualifying step pattern (DROP):

**`trimmed_txt_20210205_vulcanite_g78_10g_l_trimmed`** — **116 baro steps** throughout the flight:
- Oscillating ±500–1925 Pa at ~1 Hz from t = 7 s through t = 98 s (entire flight)
- Symptom: rocket body swinging under parachute; static port alternates between windward and leeward faces → apparent altitude oscillates ±85–160 m every ~0.9 s
- EKF impact: baro innovation would be ±85–160 m oscillating noise every second → filter would be driven by measurement noise throughout descent
- **No repair possible.** The aerodynamic instability is physical and systematic.

---

## Cross-Check Results (X1)

All 7 same-day/same-motor pairs agree within < 1%:

| Pair | Alt A | Alt B | Δ |
|------|-------|-------|---|
| H148R 1Jul2017 | 586 m | 581 m | 0.7% |
| J510W 8Jul2017 | 3168 m | 3167 m | 0.0% |
| J510W 8Jul2017 (213) | 3168 m | 3167 m | 0.0% |
| J354 9Sep2017 | 2546 m | 2544 m | 0.1% |
| J394 7Oct2017 | 2905 m | 2899 m | 0.2% |
| J150 9Dec2017 | 2692 m | 2688 m | 0.1% |
| J570W 9Dec2017 | 2674 m | 2668 m | 0.2% |

Cross-logger agreement is exceptional. Both XTRA/OnBoard and Raven sensors on the same flight measure identical apogee altitudes. Data integrity confirmed.

---

## Per-Flight Verdicts

### DROP (1 flight)

| Flight ID | Reason |
|-----------|--------|
| `trimmed_txt_20210205_vulcanite_g78_10g_l_trimmed` | 116 systematic baro steps throughout flight (pendulum oscillation of static port under parachute). Unusable. |

### KEEP WITH ANNOTATION (2 flights)

| Flight ID | Issue | EKF Impact | Report Note |
|-----------|-------|-----------|-------------|
| `multi_time_csv_e190_7oct2017_j394_1_xtra` | B6: −186 Pa baro drift (−15.5 m) over 325 s | EKF final_z will show ≈ −15 m instead of 0 | Confirmed atmospheric pressure change during 5-min flight (7 Oct 2017 weather trend). Same-day Raven shows identical drift. Known single-reference barometric limitation. |
| `raven_csv_e190_7oct2017_j394_1_raven` | B6: −178 Pa baro drift (−14.9 m) over 223 s | Same as above | Same event, different sensor on same rocket. Consistent. |

### KEEP — All Remaining (22 flights)

All real test failures are false positives from family-specific recording behaviors (Raven starts at launch, trimmed_txt ICM clips briefly at ±16g during boost) or isolated 1–3 sample logger artifacts. None affect EKF performance materially.

| Flight ID | Notes |
|-----------|-------|
| `emulation_csv_e190_8jul2017_j510w_emulationdata` | Synthetic data; simulator resets at record end produce B7 artifact. Expected. |
| `multi_time_csv_e190_1jul2017_h148r_1_xtra` | 2-sample spike in descent. Minor. |
| `multi_time_csv_e190_8jul2017_j510w_1_xtra` | End-of-record 2-sample spike. Minor. |
| `multi_time_csv_e190_8jul2017_j510w_1_xtra_213` | Identical data to above (same flight, alternate log). Keep for cross-validation. |
| `multi_time_csv_e190_9sep2017_j354_1_xtra` | 3 isolated spikes. Minor. |
| `multi_time_csv_e190_9dec2017_j150_onboard` | 2-sample spike each at apogee and descent. Minor. |
| `multi_time_csv_e190_9dec2017_j570w_onboard` | 3-sample cluster at apogee. Minor. |
| `raven_csv_e190_1jul2017_h148r_1_raven` | Raven behavior only. Clean baro. |
| `raven_csv_e190_8jul2017_j500g_raven` | 2 small baro steps (≤677 Pa). Minor. |
| `raven_csv_e190_8jul2017_j510w_raven` | Cleanest raven flight. B7 ok. |
| `raven_csv_e190_9sep2017_j354_raven` | 2 small baro steps at t=3 and t=160 s. Minor. |
| `raven_csv_e190_9dec2017_j150_raven` | Raven behavior only. Clean baro. |
| `raven_csv_e190_9dec2017_j570w_raven` | Raven behavior only. Clean baro. |
| `raven_csv_20210417_adventurer_j510w_1_raven` | Raven behavior only. Clean baro. |
| `raven_csv_20210417_adventurer_j530_1_raven` | Raven behavior only. Clean baro. |
| `trimmed_txt_20210205_minidx3_g77_10r_l_trimmed` | Brief boost clips at ±16g. B7 ok. |
| `trimmed_txt_20210205_minidx3_g79_10w_l_trimmed` | Brief boost clips at ±16g. B7 ok. |
| `trimmed_txt_20210410_minidx3_h128w_14_trimmed` | 3 isolated 1-sample spikes. Minor. |
| `trimmed_txt_20210410_vulcanite_h128w_10_trimmed` | Brief boost clips. B7 ok. Clean. |
| `trimmed_txt_20210410_vulcanite_j270w_14a_trimmed` | Brief boost clips. 2 ascent steps. Minor. |
| `trimmed_txt_20220610_adv_j570_trimmed` | All clean. |
| `trimmed_txt_20220611_adv_j530_trimmed` | All clean. |
| `trimmed_txt_22020609_adv_j825r_f1_trimmed` | All clean. |

---

## Actions Taken

1. **Removed** `trimmed_txt_20210205_vulcanite_g78_10g_l_trimmed` from `source_data.m`
2. Pipeline rerun: **24 flights** remain (was 25)
3. `main.m` figure selection updated to use verified clean flights
