"""
ekf_deep_dive.py
Comprehensive quantitative analysis of all EKF results.
Reads all CSV tables from _report_artifacts/tables/ and runs:

  1. Per-family final_z statistics  (should be ~0 m for good families)
  2. NIS distribution analysis      (chi2(1) expectation: mean≈1, std≈√2≈1.41)
  3. Innovation bias check          (mean should be ~0 m)
  4. P_baba convergence check       (should reach near-zero; saturation means no observability)
  5. Raven post-apogee divergence   (expected, quantify magnitude)
  6. Covariance ceiling check       (P_zz_max=2500 = init ceiling never lowered?)
  7. b_a convergence magnitude      (final_ba_mps2 spread — large spread = tuning issue?)
  8. baro_update_ratio sanity       (should be 1.0 for all; gating disabled)
  9. Cross-flight consistency        (same-motor multi_time vs raven final_z spread)
  10. Overall EKF health scorecard
"""

import csv, math, statistics
from pathlib import Path
from collections import defaultdict

# matlab/ in this repository (script lives at archive/data_investigation/pipeline_check_2026_04_25/)
MATLAB_DIR = Path(__file__).resolve().parents[3] / "matlab"
TABLES = MATLAB_DIR / "_report_artifacts" / "tables"

def read_csv(name):
    rows = []
    with open(TABLES / name, newline="") as f:
        for row in csv.DictReader(f):
            rows.append(row)
    return rows

def f(v):
    try: return float(v)
    except: return float('nan')

per = read_csv("final_per_flight_metrics.csv")
diag = read_csv("diagnostics_summary.csv")

# Build lookup by flight_id
diag_by_id = {r["flight_id"]: r for r in diag}

# ── family classification ──────────────────────────────────────────────────
def family(fid):
    if fid.startswith("emulation"): return "emulation"
    if fid.startswith("multi_time"): return "multi_time"
    if fid.startswith("raven"): return "raven"
    if fid.startswith("trimmed"): return "trimmed_txt"
    return "unknown"

def SEP(title=""):
    print(f"\n{'═'*70}")
    if title: print(f"  {title}")
    print('═'*70)

# ══════════════════════════════════════════════════════════════════════════
SEP("1. FINAL_Z BY FAMILY (expect ≈ 0 m for non-raven, post-apogee drift for raven)")
# ══════════════════════════════════════════════════════════════════════════
fam_z = defaultdict(list)
fam_vz = defaultdict(list)
for r in per:
    fam = family(r["flight_id"])
    fz = f(r["final_z_m"])
    fv = f(r["final_vz_mps"])
    fam_z[fam].append((r["flight_id"], fz))
    fam_vz[fam].append(fv)

for fam in ["emulation", "multi_time", "trimmed_txt", "raven"]:
    entries = fam_z[fam]
    zvals = [z for _, z in entries]
    if not zvals: continue
    print(f"\n  [{fam}]  n={len(zvals)}  mean={statistics.mean(zvals):+.1f}m  "
          f"std={statistics.stdev(zvals) if len(zvals)>1 else 0:.1f}m  "
          f"range=[{min(zvals):+.1f}, {max(zvals):+.1f}]")
    for fid, z in entries:
        flag = ""
        if fam != "raven" and abs(z) > 20: flag = " ← LARGE"
        if fam == "raven" and abs(z) < 50: flag = " ← SUSPICIOUSLY SMALL (good?)"
        print(f"    {fid.split('_',2)[2][:45]:<45}  final_z={z:+8.1f}m{flag}")

# ══════════════════════════════════════════════════════════════════════════
SEP("2. NIS STATISTICS (chi2(1): expect mean≈1.0, std≈1.41)")
SEP_NIS_WARN = 3.0   # mean NIS > this is suspect
# ══════════════════════════════════════════════════════════════════════════
print(f"\n  {'flight_id':<50} {'nis_mean':>9} {'nis_std':>9}  status")
for r in diag:
    nm = f(r["nis_mean"]); ns = f(r["nis_std"])
    fam = family(r["flight_id"])
    if math.isnan(nm): continue
    if nm < 0.1: status = "WARN: filter overconfident"
    elif nm < 0.5: status = "slightly overconfident"
    elif nm <= SEP_NIS_WARN: status = "ok"
    else: status = f"WARN: NIS inflated (mean={nm:.1f})"
    short = r["flight_id"].replace("multi_time_csv_","mt_").replace("trimmed_txt_","tt_").replace("raven_csv_","r_").replace("emulation_csv_","em_")
    print(f"  {short:<50} {nm:>9.3f} {ns:>9.3f}  {status}")

# ══════════════════════════════════════════════════════════════════════════
SEP("3. INNOVATION BIAS (expect mean ≈ 0 m)")
# ══════════════════════════════════════════════════════════════════════════
print(f"\n  {'flight_id':<50} {'innov_mean':>11} {'innov_std':>10}  status")
for r in diag:
    im = f(r["innovation_mean"]); ist = f(r["innovation_std"])
    if math.isnan(im): continue
    if abs(im) > 5: status = f"WARN: biased ({im:+.1f} m)"
    elif abs(im) > 2: status = f"mild bias ({im:+.1f} m)"
    else: status = "ok"
    short = r["flight_id"].replace("multi_time_csv_","mt_").replace("trimmed_txt_","tt_").replace("raven_csv_","r_").replace("emulation_csv_","em_")
    print(f"  {short:<50} {im:>+11.3f} {ist:>10.3f}  {status}")

# ══════════════════════════════════════════════════════════════════════════
SEP("4. P_baba CONVERGENCE (expect <<1 when bias observable; 0.1 = good)")
SEP_PBABA_MAX_WARN = 0.5  # threshold for 'converged'
# ══════════════════════════════════════════════════════════════════════════
print(f"\n  Note: P_baba is NOT in diagnostics_summary; read from ekf_runtime_health")
runtime = read_csv("ekf_runtime_health.csv")
print(f"\n  {'flight_id':<50} {'final_P_baba':>13}  status")
for r in runtime:
    pb = f(r["final_P_baba"])
    if math.isnan(pb): continue
    if pb < SEP_PBABA_MAX_WARN: status = "converged"
    elif pb < 2.0: status = "partial convergence"
    else: status = f"WARN: not converged ({pb:.4f})"
    short = r["flight_id"].replace("multi_time_csv_","mt_").replace("trimmed_txt_","tt_").replace("raven_csv_","r_").replace("emulation_csv_","em_")
    print(f"  {short:<50} {pb:>13.6f}  {status}")

# ══════════════════════════════════════════════════════════════════════════
SEP("5. RAVEN DIVERGENCE MAGNITUDE (vs expected ~apogee altitude)")
# ══════════════════════════════════════════════════════════════════════════
print("\n  Raven flights diverge post-apogee — EKF correct through apogee, then")
print("  bias-driven. final_z should be large negative (below ground).")
print(f"\n  {'flight_id':<50} {'final_z':>9}  note")
for r in per:
    if not r["flight_id"].startswith("raven"): continue
    fz = f(r["final_z_m"])
    short = r["flight_id"].replace("raven_csv_","r_")
    # The divergence depth vs duration is the key metric
    dur = f(r["duration_sec"])
    print(f"  {short:<50} {fz:>+9.1f}m  dur={dur:.0f}s")

# ══════════════════════════════════════════════════════════════════════════
SEP("6. COVARIANCE CEILING CHECK (P_zz_max=2500 = init=50²; should drop after t=0)")
# ══════════════════════════════════════════════════════════════════════════
INIT_CEILING = 2500  # 50^2
print(f"\n  Init P_zz = {INIT_CEILING} (50² m²). If P_zz_max = {INIT_CEILING}, filter")
print(f"  never reduced altitude uncertainty above init — suspicious.\n")
print(f"  {'flight_id':<50} {'P_zz_min':>10} {'P_zz_max':>10}  status")
for r in diag:
    pmin = f(r["P_zz_min"]); pmax = f(r["P_zz_max"])
    if math.isnan(pmin): continue
    if pmax >= INIT_CEILING - 1:
        status = "WARN: hit ceiling (baro not reducing P_zz during pre-launch)"
    else:
        status = "ok"
    short = r["flight_id"].replace("multi_time_csv_","mt_").replace("trimmed_txt_","tt_").replace("raven_csv_","r_").replace("emulation_csv_","em_")
    print(f"  {short:<50} {pmin:>10.3f} {pmax:>10.1f}  {status}")

# ══════════════════════════════════════════════════════════════════════════
SEP("7. FINAL b_a MAGNITUDE & SPREAD (accel bias estimate at landing)")
# ══════════════════════════════════════════════════════════════════════════
print("\n  Physically: static accelerometer DC offset. Expect ±15 m/s² plausible.")
print("  Large spread between same-motor flights = bias not well-constrained.\n")
fam_ba = defaultdict(list)
for r in per:
    fam = family(r["flight_id"])
    ba = f(r["final_ba_mps2"])
    fam_ba[fam].append((r["flight_id"], ba))

for fam in ["emulation", "multi_time", "trimmed_txt", "raven"]:
    entries = fam_ba[fam]
    bavals = [v for _, v in entries]
    if not bavals: continue
    print(f"  [{fam}]  mean={statistics.mean(bavals):+.2f}  "
          f"std={statistics.stdev(bavals) if len(bavals)>1 else 0:.2f}  "
          f"range=[{min(bavals):+.1f}, {max(bavals):+.1f}]")
    for fid, ba in sorted(entries, key=lambda x: x[1]):
        flag = " ← LARGE" if abs(ba) > 20 else ""
        print(f"    {fid.split('_',2)[2][:45]:<45}  ba={ba:+.2f} m/s²{flag}")

# ══════════════════════════════════════════════════════════════════════════
SEP("8. BARO UPDATE RATIO (expect 1.0 — gating disabled)")
# ══════════════════════════════════════════════════════════════════════════
gate = read_csv("innovation_gate_counts.csv")
all_good = True
for r in gate:
    ratio = f(r["baro_updates_used"]) / max(f(r["baro_events"]), 1)
    if abs(ratio - 1.0) > 0.001:
        print(f"  FAIL: {r['flight_id']}  ratio={ratio:.4f}")
        all_good = False
if all_good:
    print(f"\n  All 25 flights: baro_update_ratio = 1.000  ✓")

# ══════════════════════════════════════════════════════════════════════════
SEP("9. SAME-MOTOR CONSISTENCY (multi_time vs raven, same motor)")
# ══════════════════════════════════════════════════════════════════════════
PAIRS = [
    ("multi_time_csv_e190_8jul2017_j510w_1_xtra",   "raven_csv_e190_8jul2017_j510w_raven",   "J510W 8Jul"),
    ("multi_time_csv_e190_9sep2017_j354_1_xtra",    "raven_csv_e190_9sep2017_j354_raven",    "J354 9Sep"),
    ("multi_time_csv_e190_7oct2017_j394_1_xtra",    "raven_csv_e190_7oct2017_j394_1_raven",  "J394 7Oct"),
    ("multi_time_csv_e190_9dec2017_j150_onboard",   "raven_csv_e190_9dec2017_j150_raven",    "J150 9Dec"),
    ("multi_time_csv_e190_9dec2017_j570w_onboard",  "raven_csv_e190_9dec2017_j570w_raven",   "J570W 9Dec"),
    ("multi_time_csv_e190_1jul2017_h148r_1_xtra",   "raven_csv_e190_1jul2017_h148r_1_raven", "H148R 1Jul"),
]
per_by_id = {r["flight_id"]: r for r in per}
print(f"\n  {'pair':<12} {'multi_z':>9} {'multi_ba':>9} {'raven_final_z':>14}  note")
for mt_id, rv_id, label in PAIRS:
    mt = per_by_id.get(mt_id, {}); rv = per_by_id.get(rv_id, {})
    mt_z = f(mt.get("final_z_m","nan")); rv_z = f(rv.get("final_z_m","nan"))
    mt_ba = f(mt.get("final_ba_mps2","nan"))
    note = "raven diverged (expected)" if abs(rv_z) > 200 else "raven ok"
    print(f"  {label:<12} {mt_z:>+9.1f} {mt_ba:>+9.2f} {rv_z:>+14.1f}  {note}")

# ══════════════════════════════════════════════════════════════════════════
SEP("10. OVERALL EKF HEALTH SCORECARD")
# ══════════════════════════════════════════════════════════════════════════
issues = []
warnings = []

for r in per:
    fid = r["flight_id"]; fz = f(r["final_z_m"]); dur = f(r["duration_sec"])
    if not fid.startswith("raven"):
        if abs(fz) > 20: issues.append(f"ISSUE: {fid}: final_z={fz:+.1f}m (>20m from ground)")
    d = diag_by_id.get(fid, {})
    nm = f(d.get("nis_mean","nan"))
    if not math.isnan(nm):
        if nm > 5: issues.append(f"ISSUE: {fid}: NIS mean={nm:.2f} (>>1, filter inconsistent)")
        elif nm > 3: warnings.append(f"WARN:  {fid}: NIS mean={nm:.2f} (elevated)")
        elif nm < 0.1: warnings.append(f"WARN:  {fid}: NIS mean={nm:.3f} (overconfident)")
    im = f(d.get("innovation_mean","nan"))
    if not math.isnan(im) and abs(im) > 5:
        issues.append(f"ISSUE: {fid}: innovation bias={im:+.1f}m")

# P_baba check
for r in runtime:
    pb = f(r["final_P_baba"])
    if not math.isnan(pb) and pb > 2.0:
        warnings.append(f"WARN:  {r['flight_id']}: P_baba={pb:.4f} (not converged)")

if issues:
    print(f"\n  ISSUES ({len(issues)}):")
    for x in issues: print(f"    {x}")
else:
    print(f"\n  No hard issues found.")

if warnings:
    print(f"\n  WARNINGS ({len(warnings)}):")
    for x in warnings: print(f"    {x}")
else:
    print(f"\n  No warnings.")

print(f"\n  Non-raven flights with |final_z| < 5m  : "
      f"{sum(1 for r in per if not r['flight_id'].startswith('raven') and abs(f(r['final_z_m']))<5)}"
      f"/{sum(1 for r in per if not r['flight_id'].startswith('raven'))}")
print(f"  Raven flights (expected divergence)    : "
      f"{sum(1 for r in per if r['flight_id'].startswith('raven'))}")
print(f"  Baro update ratio = 1.0 on all flights : {'yes' if all_good else 'NO'}")
