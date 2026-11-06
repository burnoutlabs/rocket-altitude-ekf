# EKF Implementation Reference (Unified)

Status: active  
Last updated: 2026-04-22  
Supersedes: `phase0_*` through `phase6_*` as the primary reference

## Purpose

Single-source reference for:

1. current EKF pipeline behavior
2. run controls in `data.m` and `main.m`
3. artifact-generation behavior and outputs
4. practical workflow for selecting report figure flight IDs

Use this document as the canonical implementation guide. Legacy phase docs are retained only as historical snapshots.

## Current End-to-End Flow

From [data.m](../../matlab/data.m) and [main.m](../../matlab/main.m):

1. `data.m`: fetch source data (`_data_raw/`)
2. `data.m`: normalize + validate (`_data_normalized/`)
3. `data.m`: clean + validate (`_data_clean/`)
4. `main.m`: run replay build + single-flight EKF diagnostics
5. `main.m`: optionally regenerate report artifacts (all-flight tables + selected figures)

Core modules:

1. EKF core: `ekf/`
2. replay/data pipeline helpers: `ekf/pipeline/`
3. plotting functions: `plotting/`

## Model and Conventions (Locked)

State and model:

1. state: `x = [z; vz; b_a]`
2. dynamics:
   - `z_dot = vz`
   - `vz_dot = u_z - b_a + w_v`
   - `b_a_dot = w_b`
3. baro measurement: `y = z + v`

Conventions:

1. `+z` is upward
2. accel default is specific force, converted via `u_z = accel_z_mps2 - g`
3. baro pressure is converted to altitude using ISA relation
4. default update uses launch-referenced baro altitude
5. replay merge is deterministic with IMU-before-baro tie-break

## Main Controls You’ll Use Most

In [main.m](../../matlab/main.m):

1. `active_flight_id = "auto"`  
Set explicit IDs here while exploring plots for different flights.
2. `run_generate_report_artifacts = true/false`  
Runs all-flight artifact table regeneration.
3. `report_figure_flight_ids = [...]`  
Explicit list for saved report figures only.

Practical workflow:

1. iterate `active_flight_id` to inspect flights manually
2. pick your final IDs
3. set `report_figure_flight_ids` to those IDs
4. enable `run_generate_report_artifacts`

## Report Artifact Generation (Current Behavior)

Entrypoint:

1. [generate_report_artifacts.m](../../matlab/ekf/pipeline/generate_report_artifacts.m)
2. called near end of [main.m](../../matlab/main.m)

Behavior:

1. tables are always generated across all cleaned flights
2. figures are generated only for explicit `report_figure_flight_ids`
3. empty figure list skips figure export but still writes a valid `report_figure_manifest.csv`
4. invalid figure IDs fail fast with clear error

## Canonical Artifacts

Tables (`_report_artifacts/tables/`):

1. `replay_validation_summary.csv`
2. `ekf_runtime_health.csv`
3. `innovation_gate_counts.csv`
4. `diagnostics_summary.csv`
5. `final_per_flight_metrics.csv`
6. `final_aggregate_metrics.csv`
7. `report_figure_manifest.csv`

Figures (`_report_artifacts/figures/`):

1. `replay_timing_<flight_id>.png`
2. `measurement_conventions_<flight_id>.png`
3. `ekf_overview_<flight_id>.png`
4. `ekf_innovations_<flight_id>.png`
5. `ekf_covariance_<flight_id>.png`
6. `ekf_event_timeline_<flight_id>.png`

## Legacy Phase Docs (Archive Only)

The following are retained for historical traceability, but this file is now the primary reference:

1. `phase0_contract_and_schema.md`
2. `phase1_replay_validation.md`
3. `phase2_model_assumptions_and_equations.md`
4. `phase3_filter_implementation_notes.md`
5. `phase4_diagnostics_summary.md`
6. `phase6_batch_results_and_report_map.md`
