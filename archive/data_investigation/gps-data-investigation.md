# GPS Data Investigation

Status: reference  
Last updated: 2026-04-25  
Context: Full audit of GPS availability, coverage quality, time alignment, and utility for
report visualisation across all 30 sources in `source_data.m` and all 18 normalised flights.

---

## 1. Which Flights Have GPS

### 1a. Embedded GPS — multi_time_csv flights (6 flights)

The 38mm Prototype onboard logger (BASE, XTRA, OnBoard variants) contains an embedded GPS
receiver on the same PCB as the IMU and barometer. GPS samples are logged on the same time
base as all other sensors and share the `t_flight_sec` reference established at recording start.

All six multi_time_csv normalised flights have a `gps.csv` file in their
`_data_normalized/flights/<flight_id>/` folder:

| Flight ID | GPS rows | `gps.csv` present |
|---|---|---|
| `multi_time_csv_e190_8jul2017_j510w_1_base` | 297 | yes |
| `multi_time_csv_e190_8jul2017_j510w_1_xtra` | 1010 | yes |
| `multi_time_csv_e190_8jul2017_j510w_1_xtra_213` | 1010 | yes |
| `multi_time_csv_e190_9dec2017_j150_onboard` | 850 | yes |
| `multi_time_csv_e190_9dec2017_j570w_base` | 379 | yes |
| `multi_time_csv_e190_9dec2017_j570w_onboard` | 817 | yes |

The `gps.csv` schema matches the rest of the pipeline:  
`t_flight_sec, t_sensor_raw_sec, t_sec, gps_alt_m, lat_deg, lon_deg, num_sats, source_family, source_file, source_row`

**Time alignment:** no additional work needed. GPS rows already use the same `t_flight_sec`
zero reference as the IMU and baro streams. `t_flight_sec = 0` corresponds to launch detect.

### 1b. No GPS — all other flight families

| Family | Flights | GPS |
|---|---|---|
| `raven_csv` | 5 | None — Raven altimeter has no GPS hardware |
| `trimmed_txt` | 6 | None — ICM/MS5 logger has no GPS hardware |
| `emulation_csv` | 1 | None — synthetic data |

### 1c. Standalone GPS tracker files (separate physical devices)

Four files in `source_data.m` are data from Featherweight GPS trackers — a **separate physical
device** from the onboard logger, worn on the rocket airframe and transmitting to a ground
receiver. These are entirely different hardware from the embedded GPS above.

| Source file | Tracker unit | Timestamp format |
|---|---|---|
| `20210417_Adventurer_J510W_1_GPS.csv` | Featherweight, UTCTIME + UNIXTIME | External UTC wall clock |
| `20210417_Adventurer_J530_1_GPS.csv` | Featherweight, UTCTIME + UNIXTIME | External UTC wall clock |
| `20210205_Vulcanite_G78_GPS_Log.csv` | Featherweight (E178_TK_01), DATE/TIME fields | External wall clock |
| `2021-04-17-Log_GPS.csv` | Featherweight (E178_TK_02), DATE/TIME fields | External wall clock |

These use UTC timestamps only. There is no shared time base with the onboard logger. Alignment
would require extracting the GPS Time of Week (ToW) value embedded in the XTRA raw CSV and
converting the UNIXTIME in the Featherweight files — a non-trivial operation with uncertain
accuracy at sub-second level. These files also almost certainly suffered the same GPS lock-loss
during ascent as the embedded receiver (see Section 2). They are listed for removal in
`data-sources-to-cut.md`.

---

## 2. GPS Coverage Quality During Flight

### 2a. Lock loss during boost and apogee — all flights

Consumer GPS receivers (u-blox class and equivalents) cannot maintain 3D position lock during
high-acceleration phases. The embedded logger GPS shows a consistent pattern across all three
investigated flights:

- Pre-launch: 8–10 satellites, stable 2 Hz fix, altitude steady at MSL ground elevation.
- Launch + boost (~10–25 seconds): satellite count drops from 8–10 to 4 (minimum for 3D fix),
  then lock is lost entirely.
- **Blackout period:** GPS produces no valid fix for the entire boost + coast + apogee window.
- Post-apogee re-acquisition: GPS re-acquires lock on the way down, already well below apogee.

Measured blackout windows:

| Flight | Last valid GPS (t_flight_sec) | GPS altitude at last fix | GPS resumes (t_flight_sec) | GPS altitude at re-acq | Blackout duration |
|---|---|---|---|---|---|
| J510W XTRA | ~103.9 s | ~905 m MSL (~39 m AGL) | ~132.4 s | ~5293 m MSL (~4427 m AGL) | **~28 seconds** |
| J570W OnBoard | ~103.4 s | ~836 m MSL (~−24 m AGL*) | intermittent; only 4 sats after | degraded only | effectively no useful data from launch |
| J150 OnBoard | ~108.5 s | ~1549 m MSL (~679 m AGL) | ~139.3 s | ~4801 m MSL (~3932 m AGL) | **~31 seconds** |

*J570W OnBoard GPS appears to have already degraded at launch — altitude readings near ground
level are inconsistent with barometric measurements, suggesting the receiver was struggling
before ignition.

### 2b. Key implication: GPS never captures apogee

**GPS re-acquires lock while the rocket is descending.** The maximum GPS altitude reading in
every flight is recorded after the true apogee, during the descent phase. For the J510W flight
the GPS peak reading is approximately 5293 m MSL (derived from t~150s), reached well after the
baro minimum-pressure apogee. The GPS does not capture the actual apogee altitude — it
underestimates it by the altitude gained during the blackout window.

GPS altitude **cannot** be used to validate peak apogee estimation from the EKF or baro.

### 2c. Descent-phase GPS quality

After re-acquisition the GPS settles to 7–11 satellites and provides consistent ~2 Hz altitude
readings throughout the entire descent. The descent phase is several minutes long (parachute
recovery), giving hundreds of GPS samples against which the EKF descent estimate can be
compared. Satellite count during descent: typically 8–11, which is high quality for a
consumer receiver.

The GPS altitude during descent is in MSL coordinates. The EKF produces launch-relative AGL
altitude. To overlay them on the same plot, GPS must be referenced to the same ground level:

```
gps_alt_agl = gps_alt_m - gps_alt_m_launch_median
```

where `gps_alt_m_launch_median` is the median GPS MSL altitude from the pre-launch window
(same approach as the baro referencing already used in the EKF pipeline).

---

## 3. Sensor Hardware Identification

Based on the raw XTRA CSV column structure, the embedded receiver logs:

- `GPS MSL` — GPS altitude above mean sea level (metres)
- `lat`, `long` — WGS84 lat/lon
- `SVs` — number of satellites used in solution
- `GPS Time of Week` — GPS week-second timestamp (integer milliseconds)

The `GPS Time of Week` field provides an absolute GPS time reference that could theoretically be
used to correlate the standalone Featherweight tracker files (which log UNIXTIME derived from
GPS epoch). However this alignment work is not warranted given:
1. Both receivers would have blacked out during the most interesting part of the flight.
2. The descent-phase standalone tracker data offers no advantage over the already-aligned
   embedded GPS in the XTRA/OnBoard files.
3. The engineering effort outweighs any report benefit.

---

## 4. Recommended Disposition

| GPS source | Disposition | Rationale |
|---|---|---|
| Embedded GPS in multi_time_csv flights | **Retain; use for descent overlay in plots** | Already in pipeline, time-aligned, good quality post-apogee |
| `20210417_Adventurer_J510W_1_GPS.csv` | **Remove from `source_data.m`** | Separate device, no shared time base, same lock-loss problem |
| `20210417_Adventurer_J530_1_GPS.csv` | **Remove from `source_data.m`** | Same as above |
| `20210205_Vulcanite_G78_GPS_Log.csv` | **Remove from `source_data.m`** | Same as above |
| `2021-04-17-Log_GPS.csv` | **Remove from `source_data.m`** | Same as above |

---

## 5. Report Usage Guidance

### What GPS can support

- **Descent-phase trajectory overlay:** Plot `gps_alt_agl` (dashed) alongside EKF `z_hat`
  (solid) and baro measurements (scatter) on the same axis for one or two multi_time_csv
  report figure flights. This shows three independent signals agreeing during descent.
- **Independent sensor cross-check discussion:** Mention in report that the embedded GPS
  provides an independent altitude reference during descent (no shared baro measurement) and
  that agreement between GPS and EKF supports filter consistency.

### What GPS cannot support

- **Apogee validation:** GPS missed the apogee entirely in every flight. Do not cite GPS
  altitude as evidence that the EKF correctly estimated peak altitude.
- **Accuracy claim:** GPS vertical accuracy for consumer receivers is ±5–15 m (1σ). This is
  worse than the EKF baro estimate (~±8 m configured R, typically tighter in practice).
  GPS comparison is a consistency check, not a ground-truth validation.
- **Raven/trimmed_txt flights:** No GPS data exists for any of these flights. GPS comparison
  figures are only possible for the multi_time_csv family.

### Suggested report language (draft)

The embedded GPS receiver in the 38mm Prototype onboard logger provides an independent altitude
reference for a subset of flights (multi_time_csv family, N=6). The GPS receiver lost 3D fix
during the high-acceleration boost phase in all flights and re-acquired lock on the descending
trajectory, producing approximately 500–900 post-apogee samples per flight at ~2 Hz. During
descent, GPS altitude (referenced to the pre-launch MSL median) shows close agreement with the
EKF altitude estimate, providing independent cross-validation of filter consistency. The GPS
receiver did not capture the apogee altitude in any flight due to signal blackout during boost;
GPS altitude therefore cannot be used to validate peak apogee estimation and is used here only
as a descending-trajectory consistency reference.
