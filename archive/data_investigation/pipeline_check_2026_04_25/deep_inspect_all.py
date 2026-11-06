"""
deep_inspect_all.py
Comprehensive per-flight diagnostic across all 25 clean flights.
Tests applied (equal treatment, old and new):

 B1  Baro: single unambiguous pressure minimum (apogee)
 B2  Baro: clean pre-launch baseline (<50 Pa std over first 10s)
 B3  Baro: post-landing stability (<50 Pa std over last 10s)
 B4  Baro: apogee index not in first 5% or last 5% of record (wasn't truncated)
 B5  Baro: pressure drop to apogee >500 Pa (actually flew up)
 B6  Baro: final p vs start p drift — flag if |drift| > 100 Pa (>8m)
 B7  Baro: no large single-step discontinuities (>500 Pa between adjacent samples)

 I1  IMU: pre-launch accel_z ≈ +g (9.81±1.5 m/s²) — sensor upright, static
 I2  IMU: peak accel_z during boost > 20 m/s² (motor fired)
 I3  IMU: no hard-clipping (accel_z ≠ constant rail value for >50 consecutive samples)
 I4  IMU: rate consistency (<20% deviation from median inter-sample interval)

 T1  Timeline: baro and IMU t_flight_sec = 0 corresponds to pre-flight (p stable at ground)
 T2  Timeline: apogee occurs after at least 3s of flight (no instant truncation)

 X1  Cross-check: same-day/same-motor pairs agree on apogee altitude within 10%
"""

import csv, json, statistics, math
from pathlib import Path
from collections import defaultdict

# matlab/ in this repository (script lives at archive/data_investigation/pipeline_check_2026_04_25/)
MATLAB_DIR = Path(__file__).resolve().parents[3] / "matlab"
CLEAN_DIR = MATLAB_DIR / "_data_clean" / "flights"
NORM_DIR  = MATLAB_DIR / "_data_normalized" / "flights"

# Pairs of flights from same day / same motor that should agree on apogee
CROSS_CHECK_PAIRS = [
    ("multi_time_csv_e190_1jul2017_h148r_1_xtra",    "raven_csv_e190_1jul2017_h148r_1_raven",       "H148R 1Jul2017"),
    ("multi_time_csv_e190_8jul2017_j510w_1_xtra",    "raven_csv_e190_8jul2017_j510w_raven",          "J510W 8Jul2017"),
    ("multi_time_csv_e190_8jul2017_j510w_1_xtra_213","raven_csv_e190_8jul2017_j510w_raven",          "J510W 8Jul2017 (213)"),
    ("multi_time_csv_e190_9sep2017_j354_1_xtra",     "raven_csv_e190_9sep2017_j354_raven",           "J354 9Sep2017"),
    ("multi_time_csv_e190_7oct2017_j394_1_xtra",     "raven_csv_e190_7oct2017_j394_1_raven",         "J394 7Oct2017"),
    ("multi_time_csv_e190_9dec2017_j150_onboard",    "raven_csv_e190_9dec2017_j150_raven",           "J150 9Dec2017"),
    ("multi_time_csv_e190_9dec2017_j570w_onboard",   "raven_csv_e190_9dec2017_j570w_raven",          "J570W 9Dec2017"),
]

# ── helpers ────────────────────────────────────────────────────────────────

def read_col(path, col):
    vals = []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            try: vals.append(float(row[col]))
            except (ValueError, KeyError): pass
    return vals

def stdev_safe(vals):
    return statistics.stdev(vals) if len(vals) > 1 else 0.0

def median_safe(vals):
    return statistics.median(vals) if vals else float('nan')

def samples_in_window(t_col, val_col, t_lo, t_hi):
    return [v for t, v in zip(t_col, val_col) if t_lo <= t <= t_hi]

def apogee_pressure_index(p):
    """Return index of global pressure minimum."""
    mn = min(p)
    return p.index(mn)

def count_consecutive_constant(vals, threshold=0.01):
    """Return max run of consecutive values within threshold of each other."""
    max_run = 1; cur = 1
    for i in range(1, len(vals)):
        if abs(vals[i] - vals[i-1]) <= threshold:
            cur += 1; max_run = max(max_run, cur)
        else:
            cur = 1
    return max_run

def large_step(vals, threshold):
    """Return list of (index, step_size) where |diff| > threshold."""
    steps = []
    for i in range(1, len(vals)):
        d = abs(vals[i] - vals[i-1])
        if d > threshold:
            steps.append((i, vals[i] - vals[i-1]))
    return steps

def isa_alt_from_pressure_drop(dp_pa):
    """Rough altitude from pressure drop (Pa) using sea-level ISA gradient."""
    return dp_pa * 0.08326  # 1 Pa ≈ 0.0833 m at sea level

# ── per-flight diagnostics ─────────────────────────────────────────────────

results = {}  # flight_id -> list of (test_id, pass, detail)

for fdir in sorted(CLEAN_DIR.iterdir()):
    if not fdir.is_dir(): continue
    fid = fdir.name

    baro_t = read_col(fdir / "baro.csv", "t_flight_sec")
    baro_p = read_col(fdir / "baro.csv", "pressure_pa")
    imu_t  = read_col(fdir / "imu.csv",  "t_flight_sec")
    imu_az = read_col(fdir / "imu.csv",  "accel_z_mps2")

    if not baro_t or not imu_t:
        results[fid] = [("LOAD", False, "missing baro or imu")]
        continue

    dur = max(baro_t) - min(baro_t)
    n   = len(baro_p)
    apo_idx = apogee_pressure_index(baro_p)
    apo_t   = baro_t[apo_idx]
    apo_p   = baro_p[apo_idx]
    p_start = baro_p[0]
    p_end   = baro_p[-1]
    p_drop  = p_start - apo_p
    drift   = p_end - p_start

    tests = []

    # ── B1: single unambiguous minimum ──────────────────────────────────────
    # Count secondary minima that come within 200 Pa of the global min
    # but are at a different time (>30s away)
    rivals = [i for i, p in enumerate(baro_p)
              if abs(p - apo_p) < 200 and abs(baro_t[i] - apo_t) > 30]
    b1_ok = len(rivals) == 0
    tests.append(("B1-single-apogee", b1_ok,
                  f"rivals={len(rivals)}" if not b1_ok else f"ok (apo={apo_p:.0f}Pa at t={apo_t:.1f}s)"))

    # ── B2: pre-launch baro baseline ────────────────────────────────────────
    pre_p = samples_in_window(baro_t, baro_p, baro_t[0], baro_t[0] + 10)
    b2_std = stdev_safe(pre_p)
    b2_ok  = b2_std < 50
    tests.append(("B2-prelaunch-stable", b2_ok, f"std={b2_std:.1f} Pa in first 10s"))

    # ── B3: post-landing baro stability ─────────────────────────────────────
    post_p = samples_in_window(baro_t, baro_p, baro_t[-1] - 10, baro_t[-1])
    b3_std = stdev_safe(post_p)
    b3_ok  = b3_std < 50
    tests.append(("B3-postland-stable", b3_ok, f"std={b3_std:.1f} Pa in last 10s"))

    # ── B4: apogee not at record edges ──────────────────────────────────────
    frac = apo_idx / n
    b4_ok = 0.05 < frac < 0.95
    tests.append(("B4-apogee-not-edge", b4_ok, f"apogee at {frac*100:.1f}% of record"))

    # ── B5: meaningful altitude gain ────────────────────────────────────────
    b5_ok = p_drop > 500
    tests.append(("B5-altitude-gain", b5_ok,
                  f"p_drop={p_drop:.0f} Pa (~{isa_alt_from_pressure_drop(p_drop):.0f} m AGL)"))

    # ── B6: barometric drift ────────────────────────────────────────────────
    b6_ok = abs(drift) <= 100
    tests.append(("B6-baro-drift", b6_ok,
                  f"drift={drift:+.0f} Pa ({drift*0.0833:+.1f} m) over {dur:.0f}s"))

    # ── B7: no large baro steps ─────────────────────────────────────────────
    steps = large_step(baro_p, 500)
    b7_ok = len(steps) == 0
    tests.append(("B7-no-baro-steps", b7_ok,
                  f"{len(steps)} step(s)>500Pa" if not b7_ok else "ok"))

    # ── I1: pre-launch IMU accel_z ≈ +g ─────────────────────────────────────
    # Use first 5s of imu (before any motion)
    pre_az = samples_in_window(imu_t, imu_az, imu_t[0], imu_t[0] + 5)
    pre_az_med = median_safe(pre_az)
    i1_ok = abs(pre_az_med - 9.81) < 1.5
    tests.append(("I1-prelaunch-g", i1_ok,
                  f"median_az={pre_az_med:.3f} m/s² (expect ~9.81)"))

    # ── I2: boost detected ──────────────────────────────────────────────────
    # Peak accel_z in full record
    az_max = max(imu_az)
    az_min = min(imu_az)
    i2_ok = az_max > 20  # definitely more than 2g
    tests.append(("I2-boost-detected", i2_ok, f"peak_az={az_max:.1f} m/s²"))

    # ── I3: no hard clipping ────────────────────────────────────────────────
    # Check for long runs at max or min value
    max_run_hi = count_consecutive_constant([1 if abs(v - az_max) < 0.5 else 0 for v in imu_az], 0.5)
    max_run_lo = count_consecutive_constant([1 if abs(v - az_min) < 0.5 else 0 for v in imu_az], 0.5)
    clip_run = max(max_run_hi, max_run_lo)
    i3_ok = clip_run < 50
    tests.append(("I3-no-clipping", i3_ok,
                  f"longest const run at rail={clip_run} samples"))

    # ── I4: IMU rate consistency ─────────────────────────────────────────────
    diffs = [imu_t[i+1] - imu_t[i] for i in range(min(500, len(imu_t)-1))]
    diffs = [d for d in diffs if d > 0]
    if diffs:
        med_dt = median_safe(diffs)
        max_dt = max(diffs)
        i4_ok  = max_dt < med_dt * 5  # no gap > 5× median
        tests.append(("I4-imu-rate-ok", i4_ok,
                      f"med_dt={med_dt*1000:.2f}ms  max_dt={max_dt*1000:.2f}ms"))
    else:
        tests.append(("I4-imu-rate-ok", False, "no diffs computed"))

    # ── T1: t=0 is pre-flight ────────────────────────────────────────────────
    # p at t=0 should be within 500 Pa of p_start (basic: just check first sample exists)
    t1_ok = abs(baro_p[0] - baro_p[min(5, n-1)]) < 200  # first few samples stable
    tests.append(("T1-t0-preflight", t1_ok,
                  f"p[0]={baro_p[0]:.0f} p[5]={baro_p[min(5,n-1)]:.0f} Pa"))

    # ── T2: apogee after 3s ─────────────────────────────────────────────────
    t_apo_rel = apo_t - baro_t[0]
    t2_ok = t_apo_rel > 3.0
    tests.append(("T2-apogee-after-3s", t2_ok, f"t_apogee={t_apo_rel:.1f}s after record start"))

    results[fid] = tests

# ── cross-check same-day pairs ─────────────────────────────────────────────
cross_results = []
for fid_a, fid_b, label in CROSS_CHECK_PAIRS:
    bp_a = read_col(CLEAN_DIR / fid_a / "baro.csv", "pressure_pa")
    bp_b = read_col(CLEAN_DIR / fid_b / "baro.csv", "pressure_pa")
    if not bp_a or not bp_b:
        cross_results.append((label, False, "missing data"))
        continue
    alt_a = isa_alt_from_pressure_drop(bp_a[0] - min(bp_a))
    alt_b = isa_alt_from_pressure_drop(bp_b[0] - min(bp_b))
    pct_diff = abs(alt_a - alt_b) / max(alt_a, alt_b) * 100
    ok = pct_diff < 10
    cross_results.append((label, ok, f"{fid_a.split('_',2)[2][:20]}: {alt_a:.0f}m  vs  {fid_b.split('_',2)[2][:20]}: {alt_b:.0f}m  diff={pct_diff:.1f}%"))

# ── print report ──────────────────────────────────────────────────────────

PASS = "PASS"
FAIL = "FAIL"
WARN = "WARN"

print("=" * 90)
print("DEEP FLIGHT INSPECTION — ALL 25 FLIGHTS")
print("=" * 90)

fail_summary = {}
warn_summary = {}

for fid in sorted(results.keys()):
    tests = results[fid]
    fails = [(t, d) for t, ok, d in tests if not ok]
    # B6 (drift) between 100–300 Pa is a WARN not FAIL
    b6 = next(((ok, d) for t, ok, d in tests if t == "B6-baro-drift"), None)
    drift_val = 0
    if b6:
        try: drift_val = float(b6[1].split("drift=")[1].split(" ")[0].replace("+",""))
        except: pass

    has_fail = any(not ok for t, ok, d in tests if not (t == "B6-baro-drift" and abs(drift_val) <= 300))
    has_warn = any(not ok for t, ok, d in tests if t == "B6-baro-drift" and 100 < abs(drift_val) <= 300)
    has_hard_fail = any(not ok for t, ok, d in tests if t != "B6-baro-drift")

    status = FAIL if has_hard_fail else (WARN if has_warn else PASS)

    print(f"\n{'─'*90}")
    print(f"  [{status}]  {fid}")
    for tid, ok, detail in tests:
        marker = "  ok " if ok else "FAIL "
        # re-classify B6 warnings
        if tid == "B6-baro-drift" and not ok:
            try:
                dv = float(detail.split("drift=")[1].split(" ")[0].replace("+",""))
                if abs(dv) <= 300:
                    marker = "WARN "
            except: pass
        print(f"    {marker} {tid:<28}  {detail}")

    if status != PASS:
        fail_summary[fid] = (status, fails)

print(f"\n\n{'='*90}")
print("CROSS-CHECK: SAME-DAY PAIRS — APOGEE ALTITUDE AGREEMENT")
print("="*90)
for label, ok, detail in cross_results:
    marker = "  ok " if ok else "FAIL "
    print(f"  {marker} {label:<25}  {detail}")

print(f"\n\n{'='*90}")
print("SUMMARY")
print("="*90)
passed = [f for f in results if f not in fail_summary]
warned = [f for f, (s, _) in fail_summary.items() if s == WARN]
failed = [f for f, (s, _) in fail_summary.items() if s == FAIL]
print(f"  PASS: {len(passed)}")
print(f"  WARN: {len(warned)}")
print(f"  FAIL: {len(failed)}")
if warned:
    print(f"\n  WARN flights:")
    for f in warned:
        _, fails = fail_summary[f]
        print(f"    {f}")
        for t, d in fails: print(f"      {t}: {d}")
if failed:
    print(f"\n  FAIL flights:")
    for f in failed:
        _, fails = fail_summary[f]
        print(f"    {f}")
        for t, d in fails: print(f"      {t}: {d}")
