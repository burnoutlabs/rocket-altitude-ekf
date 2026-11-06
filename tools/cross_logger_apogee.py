"""
cross_logger_apogee.py
----------------------
Recomputes the cross-logger apogee table (docs/dataset-and-results.md §1.3,
report/report.md §6.3) from the raw DOFPro logs.

Each log's barometer stream is processed the way the MATLAB pipeline does it:

  1. Pressure column: `pressure` [Pa] for XTRA/OnBoard (multi_time_csv) logs,
     with the last `time` column before it; `Baro (Atm)` x 101325 for Raven
     logs, with `Time@Baro (Atm)`.
  2. Drop non-finite rows, sort by time, keep the last sample of each
     duplicated timestamp (normalize_one_file.m), and drop pressures outside
     20 000-120 000 Pa (run_cleaning_pipeline.m).
  3. ISA troposphere altitude with p0 = 101325 Pa (altitude_from_pressure_pa.m).
  4. Launch reference: median ISA altitude of the samples within 0.5 s of the
     first baro sample (prepare_measurements_for_ekf.m, main.m settings).
  5. Apogee AGL = max ISA altitude - launch reference.

As an independent check it also prints each logger's own AGL altitude column:
max(`Pressure AGL`) [m] for XTRA/OnBoard and max(`[Altitude (Baro-Ft-AGL)]`)
x 0.3048 for Raven.

The logs are not redistributed. Fetch them with matlab/data.m (into
matlab/_data_raw/), or download the URLs in matlab/data_fetch/source_data.m
into any directory and pass it:

    python tools/cross_logger_apogee.py [LOG_DIR]

Standard library only.
"""

import csv
import math
import os
import statistics
import sys

_HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DIR = os.path.join(_HERE, "matlab", "_data_raw")

P0_PA = 101325.0
P_MIN_PA, P_MAX_PA = 20000.0, 120000.0
LAUNCH_REF_SEC = 0.5

# (label, multi_time_csv log, raven_csv log)
PAIRS = [
    ("H148R 1 Jul 2017", "E190_1JUL2017_H148R_1_XTRA.csv", "E190_1JUL2017_H148R_1_Raven.csv"),
    ("J510W 8 Jul 2017", "E190_8JUL2017_J510W_1_XTRA.csv", "E190_8JUL2017_J510W_Raven.csv"),
    ("J510W 8 Jul 2017 (213)", "E190_8JUL2017_J510W_1_XTRA_213.csv", "E190_8JUL2017_J510W_Raven.csv"),
    ("J354 9 Sep 2017", "E190_9SEP2017_J354_1_XTRA.csv", "E190_9SEP2017_J354_Raven.csv"),
    ("J394 7 Oct 2017", "E190_7OCT2017_J394_1_XTRA.csv", "E190_7OCT2017_J394_1_Raven.csv"),
    ("J150 9 Dec 2017", "E190_9DEC2017_J150_OnBoard.csv", "E190_9DEC2017_J150_Raven.csv"),
    ("J570W 9 Dec 2017", "E190_9DEC2017_J570W_OnBoard.csv", "E190_9DEC2017_J570W_Raven.csv"),
]


def isa_alt_m(p_pa):
    """ISA troposphere altitude, as in matlab/ekf/altitude_from_pressure_pa.m."""
    t0, lapse, g0, r = 288.15, 0.0065, 9.80665, 287.05287
    return (t0 / lapse) * (1.0 - (p_pa / P0_PA) ** (r * lapse / g0))


def _num(s):
    try:
        v = float(s)
    except (TypeError, ValueError):
        return math.nan
    return v


def read_log(path):
    with open(path, newline="") as f:
        rows = csv.reader(f)
        header = [h.strip().lower() for h in next(rows)]
        data = list(rows)
    return header, data


def column(data, idx):
    return [_num(r[idx]) if idx < len(r) else math.nan for r in data]


def baro_stream(header, data, raven):
    if raven:
        it = header.index("time@baro (atm)")
        ip = header.index("baro (atm)")
        scale = 101325.0
    else:
        ip = header.index("pressure")
        it = max(i for i in range(ip) if header[i] == "time")
        scale = 1.0
    t = column(data, it)
    p = [v * scale for v in column(data, ip)]
    samples = {}
    for ti, pi in sorted((ti, pi) for ti, pi in zip(t, p)
                         if math.isfinite(ti) and math.isfinite(pi)):
        samples[ti] = pi  # sorted, so a duplicated timestamp keeps the last
    return [(ti, pi) for ti, pi in sorted(samples.items())
            if P_MIN_PA <= pi <= P_MAX_PA]


def logger_agl_max_m(header, data, raven):
    if raven:
        idx, scale = header.index("[altitude (baro-ft-agl)]"), 0.3048
    else:
        idx, scale = header.index("pressure agl"), 1.0
    return max(v for v in column(data, idx) if math.isfinite(v)) * scale


def apogee(path, raven):
    header, data = read_log(path)
    baro = baro_stream(header, data, raven)
    t_first = baro[0][0]
    alt = [isa_alt_m(p) for _, p in baro]
    ref = statistics.median(a for (t, _), a in zip(baro, alt)
                            if t <= t_first + LAUNCH_REF_SEC)
    return max(alt) - ref, logger_agl_max_m(header, data, raven)


def agreement_pct(a, b):
    return abs(a - b) / max(a, b) * 100.0


def main(argv):
    log_dir = argv[1] if len(argv) > 1 else DEFAULT_DIR
    print("| Pair | Multi-time alt | Raven alt | Agreement |"
          " Multi-time logger AGL | Raven logger AGL |")
    print("| --- | --- | --- | --- | --- | --- |")
    for label, mt, rv in PAIRS:
        a_mt, own_mt = apogee(os.path.join(log_dir, mt), raven=False)
        a_rv, own_rv = apogee(os.path.join(log_dir, rv), raven=True)
        print(f"| {label} | {a_mt:.0f} m | {a_rv:.0f} m | "
              f"{agreement_pct(a_mt, a_rv):.1f}% | {own_mt:.0f} m | {own_rv:.0f} m |")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
