# Data Sources to Add

Status: reference  
Last updated: 2026-04-25  
Context: Candidate sources from the DOFPro archive that are not currently in `source_data.m`
and that are worth attempting to add to expand the EKF evaluation dataset.

This document is a filtered, actionable subset of `available-not-yet-added.md`. Sources that are
clearly unusable (GPS-only, CATO flights, unknown small-motor rockets with no parser) have been
omitted. The focus here is on sources with a realistic chance of producing valid EKF flights.

See `data-sources-to-cut.md` for the corresponding analysis of what to remove or annotate.

---

## Known Issue: BASE Logger Files

Before adding any new multi_time_csv source, note that the BASE logger variant is always
low-rate (~0.6–1 Hz) and produces unreliable EKF results (see `data-sources-to-cut.md` §3).
For every flight group below that includes a BASE file, the BASE URL is listed for completeness
but marked as **skip** — only the XTRA and Raven variants should be added to the working set.

---

## Tier 1 — High Confidence (existing parsers, same hardware)

These use parsers already proven on current flights. Addition should be drop-in: add URLs to
`source_data.m`, rerun `data.m`, then rerun `main.m`.

### 1a. 38mm Prototype — Aerotech H148R (1 Jul 2017)

Same rocket, same recorder hardware as the J510W and J570W flights already in the working set.
Motor: H148R (mid-power class H).

| File | URL | Parser | Add? |
|---|---|---|---|
| `E190_1JUL2017_H148R_1_BASE.csv` | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_1JUL2017_H148R_1_BASE.csv | `multi_time_csv` | **Skip** — BASE logger, low rate |
| `E190_1JUL2017_H148R_1_XTRA.csv` | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_1JUL2017_H148R_1_XTRA.csv | `multi_time_csv` | **Add** |
| `E190_1JUL2017_H148R_1_Raven.csv` | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_1JUL2017_H148R_1_Raven.csv | `raven_csv` | **Add** (ascent only) |

Expected new flights: 2 (1 multi_time_csv, 1 raven_csv).  
Weather: not documented.

---

### 1b. 38mm Prototype — CTI J354 (9 Sep 2017)

Same rocket family. Motor: J354 (high-power class J).  
Weather: 75°F, 60% humidity, 5 mph winds.

| File | URL | Parser | Add? |
|---|---|---|---|
| `E190_9SEP2017_J354_1_BASE.csv` | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_9SEP2017_J354_1_BASE.csv | `multi_time_csv` | **Skip** — BASE logger |
| `E190_9SEP2017_J354_1_XTRA.csv` | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_9SEP2017_J354_1_XTRA.csv | `multi_time_csv` | **Add** |
| `E190_9SEP2017_J354_Raven.csv` | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_9SEP2017_J354_Raven.csv | `raven_csv` | **Add** (ascent only) |

Expected new flights: 2.

---

### 1c. 38mm Prototype — CTI J394 (7 Oct 2017)

Same rocket family. Motor: J394 (high-power class J).  
Weather: 66°F, 18% humidity, 5 mph winds.

| File | URL | Parser | Add? |
|---|---|---|---|
| `E190_7OCT2017_J394_1_BASE.csv` | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_7OCT2017_J394_1_BASE.csv | `multi_time_csv` | **Skip** — BASE logger |
| `E190_7OCT2017_J394_1_XTRA.csv` | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_7OCT2017_J394_1_XTRA.csv | `multi_time_csv` | **Add** |
| `E190_7OCT2017_J394_1_Raven.csv` | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_7OCT2017_J394_1_Raven.csv | `raven_csv` | **Add** (ascent only) |

Expected new flights: 2.

---

### 1d. 38mm Prototype — Aerotech J500G (8 Jul 2017)

Same rocket and same launch day as the J510W flight already in the working set. No XTRA variant
available — only BASE and Raven.  
Motor: J500G. Weather: 78°F, 33% humidity, 1 mph winds (same conditions as J510W).

| File | URL | Parser | Add? |
|---|---|---|---|
| `E190_8JUL2017_J500G_1_BASE.csv` | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_8JUL2017_J500G_1_BASE.csv | `multi_time_csv` | **Skip** — BASE logger only; no XTRA variant for this motor |
| `E190_8JUL2017_J500G_Raven.csv` | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_8JUL2017_J500G_Raven.csv | `raven_csv` | **Add** (ascent only) |

Expected new flights: 1 (Raven ascent only; no high-rate logger variant available).  
Note: this gives less information per flight than the others due to the missing XTRA, but it adds
a distinct motor profile at the same launch conditions.

---

### 1e. Madcow Mini DX3 — First Flights (trimmed TXT)

New rocket platform (Mini DX3), same `trimmed_txt` ICM/MS5 format already used for the Adventurer
and Vulcanite flights. Two or three good flights available.

| File | URL | Parser | Add? |
|---|---|---|---|
| `20210205_MiniDX3_G77-10R-L_trimmed.TXT` | https://dofprobucket2.s3.us-east-2.amazonaws.com/First_Flight_DX3/20210205_MiniDX3_G77-10R-L_trimmed.TXT | `trimmed_txt` | **Add** |
| `20210205_MiniDX3_G79-10W-L_trimmed.TXT` | https://dofprobucket2.s3.us-east-2.amazonaws.com/First_Flight_DX3/20210205_MiniDX3_G79-10W-L_trimmed.TXT | `trimmed_txt` | **Add** |
| `20210410_MiniDX3_H128W-14_Trimmed.TXT` | https://dofprobucket2.s3.us-east-2.amazonaws.com/First_Flight_DX3/20210410_MiniDX3_H128W-14_Trimmed.TXT | `trimmed_txt` | **Add** |
| `20210410_MiniDX3_G138T-14_Trimmed.TXT` | https://dofprobucket2.s3.us-east-2.amazonaws.com/First_Flight_DX3/20210410_MiniDX3_G138T-14_Trimmed.TXT | `trimmed_txt` | **Skip** — rocket shredded at Max-Q; data will be truncated or corrupt |

Expected new flights: 3.  
Weather: Feb-2021 (G77/G79): no wind, 66°F, 37% RH. Apr-2021 (H128W): 9 mph winds, 67°F, 24% RH.

---

### Tier 1 Summary

| Source | XTRA/TXT flights | Raven flights | Total new |
|---|---|---|---|
| 38mm Prototype H148R | 1 | 1 (ascent) | 2 |
| 38mm Prototype J354 | 1 | 1 (ascent) | 2 |
| 38mm Prototype J394 | 1 | 1 (ascent) | 2 |
| 38mm Prototype J500G | 0 (no XTRA) | 1 (ascent) | 1 |
| Mini DX3 trimmed TXT | 3 | 0 | 3 |
| **Total** | **6** | **4** | **10** |

Adding all Tier 1 sources would bring the working EKF set from 11 to approximately 17–21 flights
(accounting for the raven ascent-only caveat and potential parsing issues).

---

## Tier 2 — Unknown Format (inspect headers first)

These sources are from new rocket platforms with unknown or unverified file schemas.
They require a header inspection before any normalizer work can begin.
Do not add to `source_data.m` until the format is confirmed.

### 2a. LOC Dual Deploy Vulcanite (2023)

Entirely new rocket (dual-deploy configuration, likely different deployment geometry than the
standard Vulcanite already in the dataset). Two flights from different dates and motors.

The dual-deploy recovery system uses a drogue at apogee and a main at low altitude. Depending on
how the altimeter is mounted (belly vs nose cone), the post-apogee flip problem seen in Raven
flights may or may not apply.

| File | URL | Format | Action |
|---|---|---|---|
| `2023-02-11_(TkSpjutVul)_20-07-29.csv` | https://dofprobucket2.s3.us-east-2.amazonaws.com/DDVulcanite/2023-02-11_(TkSpjutVul)_20-07-29.csv | Unknown | Inspect headers |
| `2023-07-08_DDVulcanite_J270_14-37-34.csv` | https://dofprobucket2.s3.us-east-2.amazonaws.com/DDVulcanite/2023-07-08_DDVulcanite_J270_14-37-34.csv | Unknown | Inspect headers |

Motors: I140W-14 (Feb-2023), J270W-14 (Jul-2023).  
Expected new flights: 2 if schema is compatible.

---

### 2b. Madcow Mini DX3 Modified — FIP / FIPa Flights (G69 Rocket)

11 flights across two dates, using a G69N-P motor. These use an unknown `FIP` / `FIPa` schema.
If the schema is a simple time-series CSV with IMU and baro columns, a normalizer could be written;
if it is a heavily custom binary export, the effort may not be justified.

| Group | URL pattern | Flights | Notes |
|---|---|---|---|
| Jun-2017 FIP | https://dofprobucket2.s3.us-east-2.amazonaws.com/G69_Rocket/G69_30JUN2017_G69N-P_N_FIP.csv | 6 | Replace N with 1–6 |
| Oct-2018 FIPa | https://dofprobucket2.s3.us-east-2.amazonaws.com/G69_Rocket/G69_22OCT2018_G69N-P_N_FIPa.csv | 5 | Replace N with 1–5 |

Expected new flights: up to 11 if schema can be parsed.  
Decision gate: download one file, inspect columns, then decide.

---

## Not Pursued — Explicit Exclusions

The following categories from `available-not-yet-added.md` are not being added.
They are listed here so the rationale is on record for the report.

| Source | Reason |
|---|---|
| All GPS/tracker TXT and CSV files (Featherweight, etc.) | GPS-only; no IMU or baro; same reason as Section 1 of `data-sources-to-cut.md` |
| `J510W_T_P_vs_altitude.xlsx` | Reference lookup table, not raw sensor data |
| Mini DX3 Nov-2019 GPS TXT files (8 files) | GPS + different parser (Teensy/Eggfinder); no IMU compatible with EKF |
| `20210205_MiniDX3_G138T-14_Trimmed.TXT` | Rocket shredded at Max-Q; data corrupt/truncated |
| Top Shot CATO flight | Catastrophic failure; data will be truncated at failure |
| Estes Top Shot (6 flights, E12-6 motor) | Unknown schema; very small low-power motor (E class); likely low SNR and different flight dynamics than evaluation targets |
| Estes Emerald Streak (10 flights) | Unknown schema; C–D class motors; low-power; not representative of target flight envelope |

---

## Recommended Addition Order

1. **Tier 1 — do these first.** Minimal risk: same parsers, proven hardware. Add URLs to
   `source_data.m`, rerun `data.m`, confirm normalisation, rerun `main.m`.
   - Add XTRA + Raven for H148R, J354, J394.
   - Add Raven only for J500G (no XTRA available).
   - Add 3 Mini DX3 trimmed TXT files.

2. **Tier 2a (DDVulcanite) — worthwhile if Tier 1 succeeds.** Download one file, inspect, then
   decide whether to write a parser or map to an existing one.

3. **Tier 2b (FIP/FIPa) — lower priority.** 11 flights is a substantial return if the schema is
   simple, but the custom logger format is an unknown. Inspect one file before investing time.
