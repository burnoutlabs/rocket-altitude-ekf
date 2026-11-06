"""
inspect_new_flights.py
Quick inspection of the 10 new flights added in source_data.m revision 2.
Checks: duration, IMU/baro rates, baro shape (peak present?), accel range.
Run from anywhere - uses absolute path.
"""

import csv
import os
import json
from pathlib import Path

# matlab/ in this repository (script lives at archive/data_investigation/pipeline_check_2026_04_25/)
MATLAB_DIR = Path(__file__).resolve().parents[3] / "matlab"
CLEAN_DIR = MATLAB_DIR / "_data_clean" / "flights"

NEW_FLIGHTS = [
    "multi_time_csv_e190_1jul2017_h148r_1_xtra",
    "raven_csv_e190_1jul2017_h148r_1_raven",
    "multi_time_csv_e190_9sep2017_j354_1_xtra",
    "raven_csv_e190_9sep2017_j354_raven",
    "multi_time_csv_e190_7oct2017_j394_1_xtra",
    "raven_csv_e190_7oct2017_j394_1_raven",
    "raven_csv_e190_8jul2017_j500g_raven",
    "trimmed_txt_20210205_minidx3_g77_10r_l_trimmed",
    "trimmed_txt_20210205_minidx3_g79_10w_l_trimmed",
    "trimmed_txt_20210410_minidx3_h128w_14_trimmed",
]

def read_csv_col(path, col):
    vals = []
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                vals.append(float(row[col]))
            except (ValueError, KeyError):
                pass
    return vals

def summarise(flight_id):
    fdir = CLEAN_DIR / flight_id
    meta_path = fdir.parent.parent.parent / "_data_normalized" / "flights" / flight_id / "flight_meta.json"

    # baro
    baro_path = fdir / "baro.csv"
    imu_path  = fdir / "imu.csv"

    baro_t = read_csv_col(baro_path, "t_flight_sec")
    baro_p = read_csv_col(baro_path, "pressure_pa")
    imu_t  = read_csv_col(imu_path,  "t_flight_sec")
    imu_az = read_csv_col(imu_path,  "accel_z_mps2")

    if not baro_t:
        print(f"  !! no baro data"); return

    duration    = max(baro_t) - min(baro_t)
    baro_rate   = len(baro_t) / duration if duration > 0 else 0
    imu_rate    = len(imu_t)  / duration if duration > 0 else 0

    # pressure stats — look for a clear minimum (apogee)
    p_min       = min(baro_p)
    p_max       = max(baro_p)
    p_start     = baro_p[0]
    p_end       = baro_p[-1]
    idx_min     = baro_p.index(p_min)
    t_apogee    = baro_t[idx_min]
    p_drop_pa   = p_start - p_min          # pressure drop to apogee (positive = went up)

    # ISA approx: 1 Pa ≈ 0.083 m at sea level
    alt_gain_m  = p_drop_pa * 0.083

    # IMU accel range
    az_min = min(imu_az) if imu_az else float('nan')
    az_max = max(imu_az) if imu_az else float('nan')

    # GPS
    gps_path = fdir / "gps.csv"
    gps_rows = 0
    if gps_path.exists():
        gps_t = read_csv_col(gps_path, "t_flight_sec")
        gps_rows = len(gps_t)

    print(f"\n{'='*60}")
    print(f"  {flight_id}")
    print(f"  Duration:       {duration:.1f} s  (t={min(baro_t):.1f} → {max(baro_t):.1f})")
    print(f"  Baro rate:      {baro_rate:.1f} Hz   ({len(baro_t)} samples)")
    print(f"  IMU rate:       {imu_rate:.1f} Hz   ({len(imu_t)} samples)")
    print(f"  GPS rows:       {gps_rows}")
    print(f"  Pressure:       start={p_start:.0f} Pa  min={p_min:.0f} Pa  end={p_end:.0f} Pa")
    print(f"  Apogee est:     t={t_apogee:.1f} s  (idx {idx_min}/{len(baro_t)})")
    print(f"  Alt gain (ISA): ~{alt_gain_m:.0f} m AGL")
    print(f"  Accel_z range:  {az_min:.2f} to {az_max:.2f} m/s²")
    print(f"  Baro p_end vs p_start delta: {p_end - p_start:+.0f} Pa  ({(p_end-p_start)*0.083:+.1f} m)")

for fid in NEW_FLIGHTS:
    summarise(fid)

print("\n\nDone.")
