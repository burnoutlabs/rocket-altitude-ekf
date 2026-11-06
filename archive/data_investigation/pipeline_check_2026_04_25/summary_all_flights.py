"""
summary_all_flights.py
Print a compact summary table of all 25 normalised+cleaned flights.
Compares new vs existing, flags key characteristics.
"""

import csv
from pathlib import Path

# matlab/ in this repository (script lives at archive/data_investigation/pipeline_check_2026_04_25/)
MATLAB_DIR = Path(__file__).resolve().parents[3] / "matlab"
CLEAN_DIR = MATLAB_DIR / "_data_clean" / "flights"

# Classifications from prior audit + new analysis
OLD_GOOD = {
    "emulation_csv_e190_8jul2017_j510w_emulationdata",
    "multi_time_csv_e190_8jul2017_j510w_1_xtra",
    "multi_time_csv_e190_8jul2017_j510w_1_xtra_213",
    "multi_time_csv_e190_9dec2017_j150_onboard",
    "multi_time_csv_e190_9dec2017_j570w_onboard",
    "trimmed_txt_20210205_vulcanite_g78_10g_l_trimmed",
    "trimmed_txt_20210410_vulcanite_h128w_10_trimmed",
    "trimmed_txt_20210410_vulcanite_j270w_14a_trimmed",
    "trimmed_txt_20220610_adv_j570_trimmed",
    "trimmed_txt_20220611_adv_j530_trimmed",
    "trimmed_txt_22020609_adv_j825r_f1_trimmed",
}
OLD_RAVEN = {
    "raven_csv_e190_8jul2017_j510w_raven",
    "raven_csv_e190_9dec2017_j570w_raven",
    "raven_csv_e190_9dec2017_j150_raven",
    "raven_csv_20210417_adventurer_j510w_1_raven",
    "raven_csv_20210417_adventurer_j530_1_raven",
}
NEW_IDS = {
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
}

def read_baro(flight_id):
    path = CLEAN_DIR / flight_id / "baro.csv"
    t, p = [], []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            try:
                t.append(float(row["t_flight_sec"]))
                p.append(float(row["pressure_pa"]))
            except (ValueError, KeyError):
                pass
    return t, p

def read_imu_count(flight_id):
    path = CLEAN_DIR / flight_id / "imu.csv"
    count = 0
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for _ in reader:
            count += 1
    return count

def read_gps_count(flight_id):
    path = CLEAN_DIR / flight_id / "gps.csv"
    if not path.exists():
        return 0
    count = 0
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for _ in reader:
            count += 1
    return count

rows = []
for fdir in sorted(CLEAN_DIR.iterdir()):
    if not fdir.is_dir():
        continue
    fid = fdir.name
    t, p = read_baro(fid)
    if not t:
        continue
    dur  = max(t) - min(t)
    rate = len(t) / dur if dur > 0 else 0
    imu_n = read_imu_count(fid)
    imu_rate = imu_n / dur if dur > 0 else 0
    gps_n = read_gps_count(fid)
    p_start = p[0]; p_end = p[-1]
    p_min   = min(p)
    drift   = p_end - p_start
    alt_est = (p_start - p_min) * 0.083

    status = "old-good" if fid in OLD_GOOD else \
             "old-raven" if fid in OLD_RAVEN else \
             "new"

    rows.append({
        "flight_id": fid,
        "status": status,
        "dur_s": dur,
        "baro_hz": rate,
        "imu_hz": imu_rate,
        "gps_n": gps_n,
        "alt_m": alt_est,
        "drift_pa": drift,
        "drift_m": drift * 0.083,
    })

# Print table
hdr = f"{'Status':<12} {'Dur':>6} {'Baro':>6} {'IMU':>6} {'GPS':>5} {'Alt':>6} {'Drift':>8}  Flight ID"
print(hdr)
print("-" * len(hdr))
for r in rows:
    flag = " <-- BARO DRIFT" if abs(r["drift_m"]) > 10 else ""
    print(f"{r['status']:<12} {r['dur_s']:>6.0f} {r['baro_hz']:>6.1f} {r['imu_hz']:>6.0f} "
          f"{r['gps_n']:>5} {r['alt_m']:>6.0f} {r['drift_m']:>+7.1f}m  {r['flight_id']}{flag}")

print(f"\nTotal: {len(rows)} flights")
print(f"  old-good:  {sum(1 for r in rows if r['status']=='old-good')}")
print(f"  old-raven: {sum(1 for r in rows if r['status']=='old-raven')}")
print(f"  new:       {sum(1 for r in rows if r['status']=='new')}")
print(f"  with GPS:  {sum(1 for r in rows if r['gps_n'] > 0)}")
