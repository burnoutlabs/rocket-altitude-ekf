# Available DOFPro Data Not Yet in Source List

Cross-reference of `current.md` (what is in `source_data.m`) against the full
DOFPro Flight Data Archive (`FlightData.html`).

Legend:
- **Likely compatible** — format matches an existing parser (raven_csv, multi_time_csv, trimmed_txt)
- **Unknown format** — need to inspect headers before adding a parser
- **GPS/ref only** — no onboard IMU/baro; GPS or processed data only; not useful for EKF
- **Shredded / bad data** — noted in source documentation

---

## 1. 38mm Prototype — Aerotech H148R (1 Jul 2017)

Not in current list at all. Same recorder hardware as J510W/J570W flights already in use.

| File | URL | Format guess | Notes |
|---|---|---|---|
| E190_1JUL2017_H148R_1_BASE.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_1JUL2017_H148R_1_BASE.csv | **multi_time_csv** | Low-rate BASE recording |
| E190_1JUL2017_H148R_1_XTRA.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_1JUL2017_H148R_1_XTRA.csv | **multi_time_csv** | High-rate XTRA recording — preferred |
| E190_1JUL2017_H148R_1_Raven.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_1JUL2017_H148R_1_Raven.csv | **raven_csv** | Raven altimeter data |

Motor: H148R. Weather: not documented for this flight.

---

## 2. 38mm Prototype — CTI J354 (9 Sep 2017)

Not in current list at all.

| File | URL | Format guess | Notes |
|---|---|---|---|
| E190_9SEP2017_J354_1_BASE.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_9SEP2017_J354_1_BASE.csv | **multi_time_csv** | Low-rate BASE |
| E190_9SEP2017_J354_1_XTRA.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_9SEP2017_J354_1_XTRA.csv | **multi_time_csv** | High-rate XTRA — preferred |
| E190_9SEP2017_J354_Raven.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_9SEP2017_J354_Raven.csv | **raven_csv** | Raven altimeter |

Motor: J354. Weather: 75°F, 60% humidity, 5mph winds.

---

## 3. 38mm Prototype — CTI J394 (7 Oct 2017)

Not in current list at all.

| File | URL | Format guess | Notes |
|---|---|---|---|
| E190_7OCT2017_J394_1_BASE.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_7OCT2017_J394_1_BASE.csv | **multi_time_csv** | Low-rate BASE |
| E190_7OCT2017_J394_1_XTRA.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_7OCT2017_J394_1_XTRA.csv | **multi_time_csv** | High-rate XTRA — preferred |
| E190_7OCT2017_J394_1_Raven.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_7OCT2017_J394_1_Raven.csv | **raven_csv** | Raven altimeter |

Motor: J394. Weather: 66°F, 18% humidity, 5mph winds.

---

## 4. 38mm Prototype — Aerotech J500G (8 Jul 2017)

Not in current list. Same date as the J510W flight already in use. No XTRA file listed.

| File | URL | Format guess | Notes |
|---|---|---|---|
| E190_8JUL2017_J500G_1_BASE.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_8JUL2017_J500G_1_BASE.csv | **multi_time_csv** | Low-rate BASE only |
| E190_8JUL2017_J500G_Raven.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/E190_8JUL2017_J500G_Raven.csv | **raven_csv** | Raven altimeter |

Motor: J500G. Weather: 78°F, 33% humidity, 1mph wind (same day as J510W).

---

## 5. 38mm Prototype — J510W reference spreadsheet

| File | URL | Format | Notes |
|---|---|---|---|
| J510W_T_P_vs_altitude.xlsx | https://dofprobucket2.s3.us-east-2.amazonaws.com/E190_Prototype/J510W_T_P_vs_altitude.xlsx | **GPS/ref only** | Temperature/pressure vs altitude lookup — not raw flight data, not EKF-useful |

---

## 6. LOC Dual Deploy Vulcanite (2023)

Entirely new rocket not in current dataset.

| File | URL | Format guess | Notes |
|---|---|---|---|
| 2023-02-11_(TkSpjutVul)_20-07-29.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/DDVulcanite/2023-02-11_(TkSpjutVul)_20-07-29.csv | **Unknown** | Need to inspect headers — likely multi_time_csv or similar |
| 2023-07-08_DDVulcanite_J270_14-37-34.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/DDVulcanite/2023-07-08_DDVulcanite_J270_14-37-34.csv | **Unknown** | Need to inspect headers |

Motors: I140W-14 (Feb), J270W-14 (Jul). Weather: fair, ~65°F. Dual-deploy system — rocket is recovered nose-up via drogue + main. May not have the raven post-apogee flip problem if altimeter is belly-mounted.

---

## 7. Madcow Mini DX3 — First Flight (trimmed TXT flights)

Same trimmed_txt format as Adventurer/Vulcanite files already in use.

| File | URL | Format | Notes |
|---|---|---|---|
| 20210205_MiniDX3_G77-10R-L_trimmed.TXT | https://dofprobucket2.s3.us-east-2.amazonaws.com/First_Flight_DX3/20210205_MiniDX3_G77-10R-L_trimmed.TXT | **trimmed_txt** | G77-10R motor |
| 20210205_MiniDX3_G79-10W-L_trimmed.TXT | https://dofprobucket2.s3.us-east-2.amazonaws.com/First_Flight_DX3/20210205_MiniDX3_G79-10W-L_trimmed.TXT | **trimmed_txt** | G79-10W motor |
| 20210410_MiniDX3_H128W-14_Trimmed.TXT | https://dofprobucket2.s3.us-east-2.amazonaws.com/First_Flight_DX3/20210410_MiniDX3_H128W-14_Trimmed.TXT | **trimmed_txt** | H128W-14 motor |
| 20210410_MiniDX3_G138T-14_Trimmed.TXT | https://dofprobucket2.s3.us-east-2.amazonaws.com/First_Flight_DX3/20210410_MiniDX3_G138T-14_Trimmed.TXT | **trimmed_txt** | **Shredded at Max-Q** — rocket destroyed; data may be corrupt/truncated |

Note: Feb-2021 flights used G77-10R/L and G79-10W-L motors. Apr-2021 flights: H128W-14 (ok) and G138T-14 (shredded). Weather: Feb: no wind, 66°F, 37% RH. Apr: 9mph winds, 67°F, 24% RH.

---

## 8. Madcow Mini DX3 — GPS/Log files (GPS or ref only)

| File | URL | Format | Notes |
|---|---|---|---|
| 20191115_DX3_F67-9W_1_GPS.TXT … _8_GPS.TXT | https://dofprobucket2.s3.us-east-2.amazonaws.com/First_Flight_DX3/20191115_DX3_F67-9W_N_GPS.TXT | **GPS/ref only** | 8 GPS TXT files from Nov 2019; uses ParseTeensyLoggerEggfinder.m — different schema, no IMU |
| 20210205_MiniDX3_G77_and_G79_GPS_Log.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/First_Flight_DX3/20210205_MiniDX3_G77_and_G79_GPS_Log.csv | **GPS/ref only** | GPS log file |
| 2021-04-10-Log.csv (DX3 copy) | https://dofprobucket2.s3.us-east-2.amazonaws.com/First_Flight_DX3/2021-04-10-Log.csv | **GPS/ref only** | Contains both Vulcanite + Mini DX3; already have Vulcanite copy |
| 2021-04-10_(E178_TK_01/02) csv files | (URLs in HTML have malformed anchors) | **GPS/ref only** | Tracker log files |

---

## 9. Madcow Mini DX3 Modified — FIP/FIPa flights

Unknown recorder format (FIP = likely a different custom logger).

| File | URL | Format | Notes |
|---|---|---|---|
| G69_22OCT2018_G69N-P_1_FIPa.csv … _5_FIPa.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/G69_Rocket/G69_22OCT2018_G69N-P_N_FIPa.csv | **Unknown** | Oct 2018, 5 flights, G69N-P motor; FIPa suffix unknown schema |
| G69_30JUN2017_G69N-P_1_FIP.csv … _6_FIP.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/G69_Rocket/G69_30JUN2017_G69N-P_N_FIP.csv | **Unknown** | Jun 2017, 6 flights, G69N-P motor; FIP suffix unknown schema |

Total: 11 flights across two dates.

---

## 10. Estes Top Shot

Unknown recorder format (likely multi_time_csv or similar, but needs verification).

| File | URL | Format | Notes |
|---|---|---|---|
| TopShot_14DEC2017_E12-6_1.csv … _6.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/Top_Shot/TopShot_14DEC2017_E12-6_N.csv | **Unknown** | Dec 2017, 6 normal flights, E12-6 motor |
| TopShot_14DEC2017_E9-6_7_cato.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/Top_Shot/TopShot_14DEC2017_E9-6_7_cato..csv | **Unknown** | **CATO (catastrophic failure)** — likely truncated/corrupt data |

Weather: 40°F, 17% humidity, 3mph winds.

---

## 11. Estes Emerald Streak

Unknown recorder format.

| File | URL | Format | Notes |
|---|---|---|---|
| Emerald_Streak_9MAR2017_C6-5_1.csv … _3.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/Emerald_Streak/Emerald_Streak_9MAR2017_C6-5_N.csv | **Unknown** | C6-5 motor, 3 flights |
| Emerald_Streak_9MAR2017_C6-7_1.csv … _3.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/Emerald_Streak/Emerald_Streak_9MAR2017_C6-7_N.csv | **Unknown** | C6-7 motor, 3 flights |
| Emerald_Streak_9MAR2017_D13-10W_1.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/Emerald_Streak/Emerald_Streak_9MAR2017_D13-10W_1.csv | **Unknown** | D13-10W motor, 1 flight |
| Emerald_Streak_9MAR2017_QC6-5_1.csv … _3.csv | https://dofprobucket2.s3.us-east-2.amazonaws.com/Emerald_Streak/Emerald_Streak_9MAR2017_QC6-5_N.csv | **Unknown** | QC6-5 motor, 3 flights |

Total: 10 flights, small low-power rocket.

---

## Summary by Priority for EKF Project

### High priority — likely compatible, same hardware family

| Source | New flights | Format | Adds |
|---|---|---|---|
| 38mm Prototype H148R (Jul 2017) | 3 | multi_time_csv + raven_csv | New motor profile, same rocket |
| 38mm Prototype J354 (Sep 2017) | 3 | multi_time_csv + raven_csv | New motor profile |
| 38mm Prototype J394 (Oct 2017) | 3 | multi_time_csv + raven_csv | New motor profile |
| 38mm Prototype J500G (Jul 2017) | 2 | multi_time_csv + raven_csv | Same-day as J510W |
| Mini DX3 trimmed TXT (3 good flights) | 3 | trimmed_txt | New rocket, ~same parser |

### Medium priority — new rocket/format, needs format inspection

| Source | New flights | Notes |
|---|---|---|
| LOC Dual Deploy Vulcanite (2023) | 2 | New rocket; dual-deploy may mean no nose-flip problem |
| Mini DX3 FIPa/FIP G69 flights | 11 | Unknown FIP schema — need header inspection |
| Estes Top Shot | 6 (+ 1 CATO) | Unknown schema — small motor, possibly interesting low-noise baseline |

### Low priority / not useful for EKF

| Source | Reason |
|---|---|
| DX3 Nov-2019 GPS TXT files | GPS-only, no IMU/baro, uses different parser |
| GPS log CSV files (Featherweight) | GPS-only |
| J510W_T_P_vs_altitude.xlsx | Reference spreadsheet, not raw flight data |
| Estes Emerald Streak | Unknown format; very small motor; likely low SNR |
| MiniDX3 G138T-14 CATO | Rocket shredded at Max-Q; data will be incomplete |
| Top Shot CATO flight | Catastrophic failure |
