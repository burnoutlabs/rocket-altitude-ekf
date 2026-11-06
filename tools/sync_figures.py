"""
sync_figures.py
---------------
Copies the 16 report-figure PNGs from
  matlab/_report_artifacts/figures/
into
  report/figures/
using short, readable destination names.

Run from anywhere (paths resolve from this file):
    python tools/sync_figures.py

Re-running is safe and idempotent — files that are already byte-identical
are reported as UNCHANGED and not re-copied.

Exit code: 0 if all source files were found; 1 if any were missing.
"""

import os
import shutil
import sys

# ---------------------------------------------------------------------------
# Paths (relative to the repository root, the parent of tools/)
# ---------------------------------------------------------------------------
_HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(_HERE, "matlab", "_report_artifacts", "figures")
DEST_DIR = os.path.join(_HERE, "report", "figures")

# ---------------------------------------------------------------------------
# Mapping: source filename -> destination filename
# T1-A: multi_time J570W  |  T1-B: trimmed_txt J270W Vulcanite
# T1-C: Raven J530        |  T1-D: multi_time J394 (frontal passage)
# ---------------------------------------------------------------------------
FIGURE_MAP = {
    # --- T1-A: multi_time_csv J570W ---
    "ekf_overview_multi_time_csv_e190_9dec2017_j570w_onboard.png":
        "overview_t1a_j570w.png",
    "ekf_innovations_multi_time_csv_e190_9dec2017_j570w_onboard.png":
        "innovations_t1a_j570w.png",
    "ekf_covariance_multi_time_csv_e190_9dec2017_j570w_onboard.png":
        "covariance_t1a_j570w.png",
    "ekf_event_timeline_multi_time_csv_e190_9dec2017_j570w_onboard.png":
        "events_t1a_j570w.png",
    # --- T1-B: trimmed_txt J270W Vulcanite ---
    "ekf_overview_trimmed_txt_20210410_vulcanite_j270w_14a_trimmed.png":
        "overview_t1b_j270w.png",
    "ekf_innovations_trimmed_txt_20210410_vulcanite_j270w_14a_trimmed.png":
        "innovations_t1b_j270w.png",
    "ekf_covariance_trimmed_txt_20210410_vulcanite_j270w_14a_trimmed.png":
        "covariance_t1b_j270w.png",
    "ekf_event_timeline_trimmed_txt_20210410_vulcanite_j270w_14a_trimmed.png":
        "events_t1b_j270w.png",
    # --- T1-C: raven_csv J530 Adventurer ---
    "ekf_overview_raven_csv_20210417_adventurer_j530_1_raven.png":
        "overview_t1c_j530.png",
    "ekf_innovations_raven_csv_20210417_adventurer_j530_1_raven.png":
        "innovations_t1c_j530.png",
    "ekf_covariance_raven_csv_20210417_adventurer_j530_1_raven.png":
        "covariance_t1c_j530.png",
    "ekf_event_timeline_raven_csv_20210417_adventurer_j530_1_raven.png":
        "events_t1c_j530.png",
    # --- T1-D: multi_time_csv J394 (frontal passage) ---
    "ekf_overview_multi_time_csv_e190_7oct2017_j394_1_xtra.png":
        "overview_t1d_j394.png",
    "ekf_innovations_multi_time_csv_e190_7oct2017_j394_1_xtra.png":
        "innovations_t1d_j394.png",
    "ekf_covariance_multi_time_csv_e190_7oct2017_j394_1_xtra.png":
        "covariance_t1d_j394.png",
    "ekf_event_timeline_multi_time_csv_e190_7oct2017_j394_1_xtra.png":
        "events_t1d_j394.png",
}


def _files_identical(path_a: str, path_b: str) -> bool:
    """Return True if both files exist and have the same size and bytes."""
    if not os.path.isfile(path_b):
        return False
    if os.path.getsize(path_a) != os.path.getsize(path_b):
        return False
    with open(path_a, "rb") as fa, open(path_b, "rb") as fb:
        return fa.read() == fb.read()


def main() -> int:
    os.makedirs(DEST_DIR, exist_ok=True)

    copied = 0
    unchanged = 0
    missing = 0

    for src_name, dst_name in FIGURE_MAP.items():
        src_path = os.path.join(SOURCE_DIR, src_name)
        dst_path = os.path.join(DEST_DIR, dst_name)

        if not os.path.isfile(src_path):
            print(f"  MISSING   {src_name}")
            missing += 1
            continue

        if _files_identical(src_path, dst_path):
            print(f"  UNCHANGED {dst_name}")
            unchanged += 1
        else:
            shutil.copy2(src_path, dst_path)
            print(f"  COPIED    {src_name}  ->  {dst_name}")
            copied += 1

    total = len(FIGURE_MAP)
    print()
    print(
        f"sync_figures: {copied} copied, {unchanged} unchanged, "
        f"{missing} missing  ({copied + unchanged}/{total} OK)"
    )

    return 1 if missing > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
