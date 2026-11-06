"""
diagnose_flags.py
Targets the three categories that fired on every flight:
  - I3  "no-clipping" — fired on ALL 25 flights. Need to verify it's sensor rail, not real clipping.
  - B2/B3 "prelaunch/postlanding stable" — ALL raven flights failed. Verify it's known handling behavior.
  - B7  "no-baro-steps" — Vulcanite G78 had 116 steps (alarming). Others had 1-6.
        Need to see where steps occur and whether they are during flight or at edges.
"""

import csv, statistics
from pathlib import Path

# matlab/ in this repository (script lives at archive/data_investigation/pipeline_check_2026_04_25/)
MATLAB_DIR = Path(__file__).resolve().parents[3] / "matlab"
CLEAN_DIR = MATLAB_DIR / "_data_clean" / "flights"

def read_cols(flight_id, filename, *cols):
    path = CLEAN_DIR / flight_id / filename
    out = {c: [] for c in cols}
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            for c in cols:
                try: out[c].append(float(row[c]))
                except (ValueError, KeyError): pass
    return out

# ═══════════════════════════════════════════════════════════════════════════
# 1. I3 — is it sensor saturation or actual clipping?
#    Check: what is the accel_z rail value per family? Is it the same number?
#    How long are the constant runs, and when do they occur in the flight?
# ═══════════════════════════════════════════════════════════════════════════
print("═"*70)
print("I3 DIAGNOSIS — Sensor rail vs actual clipping")
print("═"*70)

SAMPLE_FLIGHTS = {
    "trimmed_txt (Vulcanite J270)": "trimmed_txt_20210410_vulcanite_j270w_14a_trimmed",
    "trimmed_txt (MiniDX3 G77)":    "trimmed_txt_20210205_minidx3_g77_10r_l_trimmed",
    "multi_time_csv (J510W XTRA)":  "multi_time_csv_e190_8jul2017_j510w_1_xtra",
    "raven_csv (J510W)":            "raven_csv_e190_8jul2017_j510w_raven",
    "emulation_csv":                "emulation_csv_e190_8jul2017_j510w_emulationdata",
}

for label, fid in SAMPLE_FLIGHTS.items():
    d = read_cols(fid, "imu.csv", "t_flight_sec", "accel_z_mps2")
    t, az = d["t_flight_sec"], d["accel_z_mps2"]
    az_max = max(az); az_min = min(az)
    # Find runs at max and min
    runs_hi = []; cur_start = None
    for i, v in enumerate(az):
        if abs(v - az_max) < 0.01:
            if cur_start is None: cur_start = i
        else:
            if cur_start is not None:
                runs_hi.append((cur_start, i-1, t[cur_start]))
                cur_start = None
    if cur_start: runs_hi.append((cur_start, len(az)-1, t[cur_start]))

    runs_lo = []; cur_start = None
    for i, v in enumerate(az):
        if abs(v - az_min) < 0.01:
            if cur_start is None: cur_start = i
        else:
            if cur_start is not None:
                runs_lo.append((cur_start, i-1, t[cur_start]))
                cur_start = None
    if cur_start: runs_lo.append((cur_start, len(az)-1, t[cur_start]))

    # find longest
    longest_hi = max(runs_hi, key=lambda x: x[1]-x[0]) if runs_hi else None
    longest_lo = max(runs_lo, key=lambda x: x[1]-x[0]) if runs_lo else None

    print(f"\n  {label}")
    print(f"    az rail: min={az_min:.3f}  max={az_max:.3f}  n={len(az)}")
    print(f"    runs at MAX ({az_max:.3f}): {len(runs_hi)} run(s)", end="")
    if longest_hi:
        length = longest_hi[1] - longest_hi[0] + 1
        print(f"  longest={length} samples at t={longest_hi[2]:.1f}s")
    else: print()
    print(f"    runs at MIN ({az_min:.3f}): {len(runs_lo)} run(s)", end="")
    if longest_lo:
        length = longest_lo[1] - longest_lo[0] + 1
        print(f"  longest={length} samples at t={longest_lo[2]:.1f}s")
    else: print()

    # what is the value distribution? If most of the record is at rail, that's bad.
    frac_at_max = sum(1 for v in az if abs(v - az_max) < 0.01) / len(az)
    frac_at_min = sum(1 for v in az if abs(v - az_min) < 0.01) / len(az)
    print(f"    frac at MAX: {frac_at_max*100:.1f}%   frac at MIN: {frac_at_min*100:.1f}%")

# ═══════════════════════════════════════════════════════════════════════════
# 2. B2/B3 — Raven pre/post stability: is it handling noise?
#    Show the first 15 and last 15 baro samples for two raven flights.
# ═══════════════════════════════════════════════════════════════════════════
print("\n\n" + "═"*70)
print("B2/B3 DIAGNOSIS — Raven pre-launch and post-landing baro samples")
print("═"*70)

for fid in ["raven_csv_e190_8jul2017_j510w_raven", "raven_csv_20210417_adventurer_j510w_1_raven"]:
    d = read_cols(fid, "baro.csv", "t_flight_sec", "pressure_pa")
    t, p = d["t_flight_sec"], d["pressure_pa"]
    apo_idx = p.index(min(p))
    print(f"\n  {fid}")
    print(f"  Total baro: {len(t)} samples  duration={max(t)-min(t):.1f}s  apogee_idx={apo_idx}")
    print(f"  First 12 samples (pre-launch):")
    for i in range(min(12, len(t))):
        print(f"    [{i:3d}] t={t[i]:8.3f}  p={p[i]:.0f} Pa")
    print(f"  Last 12 samples (post-landing):")
    for i in range(max(0, len(t)-12), len(t)):
        print(f"    [{i:3d}] t={t[i]:8.3f}  p={p[i]:.0f} Pa")

# ═══════════════════════════════════════════════════════════════════════════
# 3. B7 — WHERE are the baro steps?
#    Show all steps >500 Pa for every flight that failed B7, with timestamps.
# ═══════════════════════════════════════════════════════════════════════════
print("\n\n" + "═"*70)
print("B7 DIAGNOSIS — Baro step locations (>500 Pa) and flight phase")
print("═"*70)

B7_FLIGHTS = [
    "emulation_csv_e190_8jul2017_j510w_emulationdata",
    "multi_time_csv_e190_1jul2017_h148r_1_xtra",
    "multi_time_csv_e190_7oct2017_j394_1_xtra",
    "multi_time_csv_e190_8jul2017_j510w_1_xtra",
    "multi_time_csv_e190_8jul2017_j510w_1_xtra_213",
    "multi_time_csv_e190_9dec2017_j150_onboard",
    "multi_time_csv_e190_9dec2017_j570w_onboard",
    "multi_time_csv_e190_9sep2017_j354_1_xtra",
    "raven_csv_e190_7oct2017_j394_1_raven",
    "raven_csv_e190_8jul2017_j500g_raven",
    "raven_csv_e190_9sep2017_j354_raven",
    "trimmed_txt_20210205_vulcanite_g78_10g_l_trimmed",
    "trimmed_txt_20210410_minidx3_h128w_14_trimmed",
    "trimmed_txt_20210410_vulcanite_j270w_14a_trimmed",
]

for fid in B7_FLIGHTS:
    d = read_cols(fid, "baro.csv", "t_flight_sec", "pressure_pa")
    t, p = d["t_flight_sec"], d["pressure_pa"]
    apo_idx = p.index(min(p))
    t_apo = t[apo_idx]
    t_start = t[0]; t_end = t[-1]; dur = t_end - t_start

    steps = []
    for i in range(1, len(p)):
        d_p = p[i] - p[i-1]
        if abs(d_p) > 500:
            # Classify phase
            t_i = t[i]
            if t_i < t_start + 0.1 * dur:
                phase = "pre/early"
            elif t_i < t_apo:
                phase = "ascent"
            elif t_i < t_apo + 0.1 * dur:
                phase = "near-apogee"
            elif t_i > t_end - 0.1 * dur:
                phase = "post/late"
            else:
                phase = "descent"
            steps.append((i, t_i, p[i-1], p[i], d_p, phase))

    print(f"\n  {fid}  (apogee t={t_apo:.1f}s)")
    if not steps:
        print("    No steps found (B7 false alarm)")
    for idx, ti, p_prev, p_cur, dp, phase in steps:
        print(f"    idx={idx:5d}  t={ti:8.2f}s  {p_prev:.0f}→{p_cur:.0f} Pa  Δ={dp:+.0f}  phase={phase}")
