# Data Sources to Cut or Annotate

Status: reference  
Last updated: 2026-04-25  
Context: Audit of all 30 URLs currently in `data_fetch/source_data.m` to identify sources
that are dead weight, unreliable, or require explicit caveats in the report.

---

## Overview

| Category | Count | Disposition |
|---|---|---|
| GPS/tracker logs — no IMU or baro | 5 | Remove from `source_data.m` |
| Unparseable format — no v1 normalizer | 7 | Remove from `source_data.m` |
| EKF-producing but results unreliable (BASE loggers) | 2 | Remove from EKF results; keep source or remove |
| EKF-producing, ascent valid, post-apogee diverges (Raven) | 5 | Keep; annotate as ascent-only |

---

## 1. Remove — GPS / Tracker Logs (no IMU or baro)

These files contain only GPS positional data (latitude, longitude, altitude from GPS).
They have no accelerometer stream and no barometric pressure stream.
The EKF state vector requires both IMU and baro; these files are completely unusable for it.
The v1 normalizer correctly classifies them as `gps_csv` or `tracker_csv` and skips them with the
message *"Family X is not part of v1 EKF normalization"* — they produce no `_data_normalized` flight.

They add no value to the source list and should be removed.

| File | Family assigned by normalizer | Note |
|---|---|---|
| `20210417_Adventurer_J510W_1_GPS.csv` | `gps_csv` | Featherweight GPS tracker; same-day as J510W Raven |
| `20210417_Adventurer_J530_1_GPS.csv` | `gps_csv` | Featherweight GPS tracker; same-day as J530 Raven |
| `2021-04-17-Log_GPS.csv` | `tracker_csv` | Ground-station GPS log |
| `20210205_Vulcanite_G78_GPS_Log.csv` | `tracker_csv` | Vulcanite G78 GPS tracker log |
| `2021-04-10-Log.csv` | `tracker_csv` | Combined tracker log (Vulcanite + DX3 Apr-2021 flights); GPS only |

**Report language:** These five files were retained in the source list during initial data collection
but were found to contain only GPS positional data with no onboard IMU or barometric pressure
stream. The EKF estimator requires both accelerometer input and pressure measurements; GPS
altitude alone cannot drive the state update without coupling to the full navigation equations.
All five are skipped automatically by the normalization pipeline and never produce EKF-eligible
flights.

---

## 2. Remove — Unparseable Formats (no v1 normalizer)

These files either use a proprietary or unknown file format, or are Excel workbooks for which no
normalizer exists in the v1 pipeline. They are silently skipped at normalization and produce no
`_data_normalized` flight.

### 2a. xlsx Workbooks (6 files)

The xlsx files appear to be OpenRocket simulation export sheets or post-processed summary
workbooks rather than raw sensor recordings. Even if a parser were written, the schema would need
independent verification before any EKF use. All six are skipped with family `xlsx`.

| File | Source group |
|---|---|
| `2022-06-09-Log.xlsx` | Adventurer J825R Jun-2022 |
| `2022-06-10-Log.xlsx` | Adventurer J570 Jun-2022 |
| `2022-06-10_Adventurere_J570_14-31-04.xlsx` | Adventurer J570 Jun-2022 |
| `2022-06-10_Adventurer_J530_17-33-38.xlsx` | Adventurer J530 Jun-2022 |
| `2022-06-11_Adventurer_J530_16-13-26.xlsx` | Adventurer J530 Jun-2022 |
| `VulcaniteG78-10G_Flight_Data.xlsx` | Vulcanite G78 Feb-2021 |

Note: the Jun-2022 Adventurer flights are already covered by the `trimmed_txt` versions
(`20220609`, `20220610`, `20220611`) which work correctly. These xlsx files are redundant even
if parsed.

### 2b. Unknown Extension (1 file)

| File | Family assigned | Note |
|---|---|---|
| `E190_9DEC2017_J150_BASE.xtra` | `empty` | Unknown proprietary extension; normalizer finds zero bytes or no recognised schema; the Dec-2017 J150 flight is already covered by the working `_OnBoard.csv` variant |

**Report language:** Six Excel workbooks and one file with an unrecognised `.xtra` extension were
present in the source list. None of these produce EKF-eligible flights: the workbooks appear to be
processed summary exports rather than raw time-series sensor data, and the `.xtra` file uses an
undocumented binary or text schema. All seven are skipped by the normalizer. The underlying
flights they correspond to are fully covered by the `.csv` and `.TXT` variants already in the
working set.

---

## 3. Remove from EKF Results — BASE Logger Recordings (2 flights)

These two files normalise successfully and pass cleaning validation, but the EKF estimation
results are not reliable due to the extremely sparse recording rate of the BASE data logger.

| Flight ID | Source file | Max Δt (sec) | Avg rate | final\_z\_m | final\_vz\_mps |
|---|---|---|---|---|---|
| `multi_time_csv_e190_8jul2017_j510w_1_base` | `E190_8JUL2017_J510W_1_BASE.csv` | 2.86 | ~0.6 Hz | −293 m | −10.1 m/s |
| `multi_time_csv_e190_9dec2017_j570w_base` | `E190_9DEC2017_J570W_BASE.csv` | 2.08 | ~0.9 Hz | −85 m | +29.1 m/s |

**Root cause:** The BASE logger records at approximately 0.6–1 Hz with irregular gaps of up to 2.86
seconds. At this rate, the EKF predict step integrates uncorrected IMU input for extended periods
between barometric updates. IMU integration error accumulates quadratically with time (O(Δt²) for
position), and the slow barometric correction rate cannot keep up. The bias state also receives
insufficient update information to converge. Both flights terminate far from z = 0 (−293 m and
−85 m respectively) compared to the ±2.3 m range of the working flights.

For context: the same-day flights recorded by the XTRA and OnBoard loggers on both dates work
correctly, with final altitudes of −2.2 m (J510W XTRA) and −0.2 m (J570W OnBoard). The physical
flight is not in question — only the BASE logger's recording rate makes it unsuitable for
continuous-time EKF replay.

**Disposition:** These two flight IDs should be excluded from the per-flight summary table and
figures in the report. They may remain in `source_data.m` as documentation of the data set, or be
removed to keep the source list clean. Do not include their metrics in any aggregate statistics.

**Report language:** Two flights recorded by the BASE data logger were excluded from the EKF
evaluation. The BASE logger records at approximately 0.6–1 Hz, leaving inter-sample gaps of up
to 2.86 seconds. Extended predict-only windows of this duration cause IMU integration drift
(O(Δt²) in position) that the barometric measurement updates at this rate cannot correct. Both
flights terminate far from the expected launch-relative altitude of zero, confirming the filter
diverges. The same-day flights from higher-rate loggers (XTRA at ~37 Hz, OnBoard at ~32 Hz)
process correctly, confirming the issue is the recording rate, not the physical flight.

---

## 4. Keep With Annotation — Raven CSV Post-Apogee Divergence (5 flights)

These flights are **not cut**. The ascent phase (launch to apogee) is estimated correctly and
should be included in the report. The issue is confined to the post-apogee descent phase.

| Flight ID | final\_z\_m | Approx apogee (sec) | NIS mean |
|---|---|---|---|
| `raven_csv_e190_8jul2017_j510w_raven` | −1763 | ~27 | elevated |
| `raven_csv_e190_9dec2017_j570w_raven` | −1484 | — | elevated |
| `raven_csv_e190_9dec2017_j150_raven` | −1158 | — | elevated |
| `raven_csv_20210417_adventurer_j510w_1_raven` | −1156 | — | elevated |
| `raven_csv_20210417_adventurer_j530_1_raven` | −1104 | — | elevated |

**Root cause:** The Raven altimeter CSV exports only axial (body-frame z) acceleration with no
attitude or orientation data. During powered ascent the rocket flies nose-up, so axial acceleration
aligns with the inertial vertical and the EKF input `u_z = a_axial − g` is correct. After apogee,
the rocket flips nose-down under the drogue parachute; the axial accelerometer now points
downward, and the EKF receives `u_z ≈ −9.81 − 9.81 = −19.6 m/s²` — an apparent 2g downward
acceleration sustained for the full ~190-second descent. The bias state `b_a` converges to values
of −4 to −11 m/s² but the random-walk model (`q_ba_psd = 0.0025`) is too slow to track a
near-instantaneous ~20 m/s² step at apogee. NIS statistics confirm filter inconsistency during
descent (NIS mean 2.0–6.2 vs 0.2–0.8 for working flights).

**Required action:**
1. Clip all Raven figures to the window `t ∈ [0, t_apogee + 10 s]` in `main.m` before generating
   report artifacts. Apogee can be detected as the time of minimum pressure in the baro stream.
2. State clearly in the report that Raven CSV files are valid for ascent-phase evaluation only and
   that full-flight reconstruction from body-frame IMU requires attitude estimation (e.g. a
   separate attitude filter or quaternion propagation from a 6/9-DOF IMU).
3. Do not include post-apogee divergence metrics from Raven flights in any aggregate goodness
   statistics.

**Report language (draft):** The Raven altimeter CSV format exports only axial (body-frame z)
accelerometer data without attitude information. This is sufficient during ascent when the rocket
flies nose-up and body-frame z aligns with the inertial vertical. After apogee the rocket
re-orients nose-down under the parachute, inverting the accelerometer reading relative to the
inertial frame. Without an attitude estimate the EKF cannot resolve this ambiguity and diverges
during descent. All five Raven flights are therefore reported for the ascent phase only; the
EKF estimate is clipped at apogee for all figures and tables involving these flights. This is an
inherent limitation of single-axis body-frame logging rather than a deficiency in the EKF
formulation — full-flight reconstruction would require a 6-DOF or 9-DOF IMU with attitude
propagation.
