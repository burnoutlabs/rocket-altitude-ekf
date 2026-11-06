"""
inspect_anomalies.py
Investigates two specific anomalies found in inspect_new_flights.py:
1. H148R XTRA: baro starts at t=0, apogee at t=111.9s — is t=0 actually launch?
2. J394 XTRA + Raven: p_end vs p_start = -186/-178 Pa (-15m) — barometric drift or real?
Also checks H148R XTRA vs Raven cross-reference for apogee consistency.
"""

import csv
import json
from pathlib import Path

# matlab/ in this repository (script lives at archive/data_investigation/pipeline_check_2026_04_25/)
MATLAB_DIR = Path(__file__).resolve().parents[3] / "matlab"
CLEAN_DIR = MATLAB_DIR / "_data_clean" / "flights"
NORM_DIR  = MATLAB_DIR / "_data_normalized" / "flights"

def read_baro(flight_id, src="clean"):
    base = CLEAN_DIR if src == "clean" else NORM_DIR
    path = base / flight_id / "baro.csv"
    rows = []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            try:
                rows.append({
                    "t": float(row["t_flight_sec"]),
                    "p": float(row["pressure_pa"]),
                })
            except (ValueError, KeyError):
                pass
    return rows

def read_imu_head(flight_id, n=5):
    path = CLEAN_DIR / flight_id / "imu.csv"
    rows = []
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader):
            if i >= n: break
            rows.append({k: row[k] for k in ["t_flight_sec","accel_z_mps2"] if k in row})
    return rows

def read_meta(flight_id):
    path = NORM_DIR / flight_id / "flight_meta.json"
    with open(path) as f:
        return json.load(f)

def baro_around(baro, t_center, window=10):
    return [(r["t"], r["p"]) for r in baro if abs(r["t"] - t_center) < window]

# ─────────────────────────────────────────────────────────────
# 1. H148R XTRA: where is t=0?
# ─────────────────────────────────────────────────────────────
print("=" * 60)
print("1. H148R XTRA — timeline investigation")
fid = "multi_time_csv_e190_1jul2017_h148r_1_xtra"
meta = read_meta(fid)
print(f"   flight_time_origin_sec: {meta.get('flight_time_origin_sec')}")
print(f"   notes: {meta.get('notes')}")

baro = read_baro(fid)
print(f"\n   First 5 baro samples (should be near ground if pre-launch):")
for r in baro[:5]:
    print(f"     t={r['t']:.4f} s   p={r['p']:.1f} Pa")

print(f"\n   Baro around t=0 (launch window ±5s):")
near_zero = baro_around(baro, 0, window=5)
for t, p in near_zero[:10]:
    print(f"     t={t:.4f}   p={p:.1f} Pa")

# find where pressure first drops significantly (>200 Pa drop from start)
p_start = baro[0]["p"]
for i, r in enumerate(baro):
    if (p_start - r["p"]) > 200:
        print(f"\n   First >200 Pa drop from start: t={r['t']:.2f}s  p={r['p']:.1f} Pa  (idx {i})")
        break

print(f"\n   Baro around t=111.9s (reported apogee):")
for t, p in baro_around(baro, 111.9, window=5)[:10]:
    print(f"     t={t:.4f}   p={p:.1f} Pa")

# Cross-check with Raven: apogee at t=12.2s
print(f"\n   H148R Raven reports apogee at t=12.2s (20Hz baro, 69s total)")
print(f"   → Raven t_flight_sec=0 is also launch-relative")
print(f"   → If H148R Raven apogee is at t=12.2s, XTRA apogee should be near t=12s too")
print(f"   → XTRA reporting t=111.9s suggests its t_flight_sec=0 is NOT launch")

# What is baro around t=12s in the XTRA?
print(f"\n   XTRA baro around t=12s (what Raven says is apogee time):")
for t, p in baro_around(baro, 12, window=5)[:10]:
    print(f"     t={t:.4f}   p={p:.1f} Pa")

# Estimate: what is the pressure minimum in the XTRA and what does t=0 actually mean?
p_min_val = min(r["p"] for r in baro)
t_min     = next(r["t"] for r in baro if r["p"] == p_min_val)
print(f"\n   XTRA pressure minimum: {p_min_val:.1f} Pa at t={t_min:.2f}s")
# Check what pressure is at t≈12s vs t≈111.9s
p_at_12 = next((r["p"] for r in baro if abs(r["t"] - 12) < 0.1), None)
print(f"   XTRA pressure at t≈12s: {p_at_12}")

# Hypothesis: H148R XTRA t_flight_sec=0 is recording start, not launch
# If apogee is actually at ~12s after launch, and launch is at ~99.7s in XTRA time,
# then launch_offset = 111.9 - 12.2 = 99.7s
launch_offset_guess = t_min - 12.2
print(f"\n   Estimated recording-start → launch offset: {launch_offset_guess:.1f}s")
print(f"   (= XTRA apogee time {t_min:.1f}s − Raven apogee time 12.2s)")

# ─────────────────────────────────────────────────────────────
# 2. J394: p_end < p_start by ~186 Pa (-15m)
# ─────────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print("2. J394 XTRA and Raven — baro drift check")

for fid in ["multi_time_csv_e190_7oct2017_j394_1_xtra", "raven_csv_e190_7oct2017_j394_1_raven"]:
    baro = read_baro(fid)
    p_start = baro[0]["p"]
    p_end   = baro[-1]["p"]
    t_start = baro[0]["t"]
    t_end   = baro[-1]["t"]
    drift   = p_end - p_start
    print(f"\n   {fid}")
    print(f"   p_start={p_start:.1f} Pa  (t={t_start:.1f}s)")
    print(f"   p_end  ={p_end:.1f} Pa  (t={t_end:.1f}s)")
    print(f"   drift  ={drift:+.1f} Pa  ({drift*0.083:+.1f} m)")
    # Check last 20 baro samples — are they stable (rocket on ground)?
    print(f"   Last 10 baro samples:")
    for r in baro[-10:]:
        print(f"     t={r['t']:.2f}  p={r['p']:.1f}")
    # Compare with J510W which has near-zero drift
    print(f"   → Expected ~0 drift if rocket settled on ground")
    print(f"   → {drift*0.083:+.1f} m offset: likely real barometric trend (weather) over {t_end-t_start:.0f}s")

print("\nDone.")
