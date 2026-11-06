"""
inspect_minidx3_baro.py
The Mini DX3 trimmed TXT flights have very high row counts (~228k-308k IMU rows).
This script checks whether these are single flights or contain multiple concatenated flights,
and whether the baro signal shows a single clean peak or multiple events.
"""

import csv
from pathlib import Path

# matlab/ in this repository (script lives at archive/data_investigation/pipeline_check_2026_04_25/)
MATLAB_DIR = Path(__file__).resolve().parents[3] / "matlab"
CLEAN_DIR = MATLAB_DIR / "_data_clean" / "flights"

FLIGHTS = [
    "trimmed_txt_20210205_minidx3_g77_10r_l_trimmed",
    "trimmed_txt_20210205_minidx3_g79_10w_l_trimmed",
    "trimmed_txt_20210410_minidx3_h128w_14_trimmed",
]

# For comparison - known good single flights
REFERENCE = [
    ("trimmed_txt_20210205_vulcanite_g78_10g_l_trimmed",  "Vulcanite G78 (100s, known good)"),
    ("trimmed_txt_20220610_adv_j570_trimmed",             "Adventurer J570 (224s, known good)"),
]

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

def find_peaks_troughs(p, t, threshold_pa=500):
    """Very simple local minima finder — finds pressure troughs (apogees)."""
    minima = []
    window = 50  # samples
    for i in range(window, len(p) - window):
        local_min = min(p[i-window:i+window])
        if p[i] == local_min and (max(p[i-window:i]) - p[i]) > threshold_pa:
            minima.append((t[i], p[i]))
    # deduplicate within 30s
    deduped = []
    for m in minima:
        if not deduped or m[0] - deduped[-1][0] > 30:
            deduped.append(m)
    return deduped

def report(flight_id, label=None):
    t, p = read_baro(flight_id)
    if not t:
        print(f"  {flight_id}: NO DATA"); return

    duration = max(t) - min(t)
    rate     = len(t) / duration
    p_start  = p[0]
    p_min    = min(p)
    p_end    = p[-1]
    idx_min  = p.index(p_min)
    t_apo    = t[idx_min]

    apogees = find_peaks_troughs(p, t)

    name = label or flight_id
    print(f"\n{name}")
    print(f"  Duration: {duration:.1f} s  |  Baro rate: {rate:.1f} Hz  |  Samples: {len(t)}")
    print(f"  p_start={p_start:.0f}  p_min={p_min:.0f}  p_end={p_end:.0f} Pa")
    print(f"  Global min at t={t_apo:.1f} s  (idx {idx_min}/{len(t)})")
    print(f"  Apparent apogees (local pressure minima): {len(apogees)}")
    for i, (ta, pa) in enumerate(apogees):
        print(f"    [{i+1}] t={ta:.1f} s  p={pa:.0f} Pa  (~{(p_start-pa)*0.083:.0f} m AGL est)")
    print(f"  p_end vs p_start: {p_end-p_start:+.0f} Pa  ({(p_end-p_start)*0.083:+.1f} m)")

print("=== REFERENCE FLIGHTS ===")
for fid, label in REFERENCE:
    report(fid, label)

print("\n=== NEW MINI DX3 FLIGHTS ===")
for fid in FLIGHTS:
    report(fid)

print("\nDone.")
