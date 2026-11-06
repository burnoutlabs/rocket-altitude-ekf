# DATA-PROCESSING-SCHEMA

Status: active baseline for data ingestion, normalization, and cleaning.

This is the single source of truth for the MATLAB data pipeline that feeds EKF work.

## Goals

- Keep the pipeline simple, reproducible, and easy to audit.
- Preserve sensor traceability from raw files to cleaned outputs.
- Lock one consistent time contract before estimator implementation.

## Directory Contract

- `_data_raw/`: downloaded source files only.
- `_data_normalized/`: schema-normalized per-flight streams.
- `_data_clean/`: quality-filtered per-flight streams, preserving normalized schema.

## Processing Stages

1. Download

- Entry: `data_fetch/download_source_data.m`
- Source list: `data_fetch/source_data.m`
- Output: files in `_data_raw/` and `_data_raw/download_manifest.csv`

2. Normalize

- Entry: `data_normalization/run_normalization_pipeline.m`
- Validation: `data_normalization/validate_normalized_data.m`
- Output:
  - `_data_normalized/flights/<flight_id>/imu.csv`
  - `_data_normalized/flights/<flight_id>/baro.csv`
  - optional `_data_normalized/flights/<flight_id>/gps.csv`
  - `_data_normalized/flights/<flight_id>/flight_meta.json`
  - `_data_normalized/normalization_manifest.csv`
  - `_data_normalized/normalization_validation_report.csv`

3. Clean

- Entry: `data_cleaning/run_cleaning_pipeline.m`
- Validation: `data_cleaning/validate_clean_data.m`
- Output:
  - `_data_clean/flights/<flight_id>/imu.csv`
  - `_data_clean/flights/<flight_id>/baro.csv`
  - optional `_data_clean/flights/<flight_id>/gps.csv`
  - optional `_data_clean/flights/<flight_id>/baro_dropped.csv`
  - `_data_clean/flights/<flight_id>/flight_meta.json`
  - `_data_clean/cleaning_manifest.csv`
  - `_data_clean/clean_validation_report.csv`
  - `_data_clean/cleaning_rules.json`

## Time Contract (Locked)

Every normalized and cleaned stream must carry:

- `t_sensor_raw_sec`: sensor-native timestamp after stream cleanup/sort/dedup.
- `t_flight_sec`: common flight timeline where flight origin is earliest sample across streams in that flight.
- `t_sec`: compatibility alias of `t_flight_sec` (same values).

Rules:

- `t_flight_sec` is measured on a common per-flight timeline whose origin is the earliest sample time across all streams in that flight.
- Per stream, `t_flight_sec` must be finite, monotonic nondecreasing, and nonnegative.
- One or more streams may start at `0`; some streams may start later (`> 0`) when asynchronous sensors begin after flight origin.
- `t_sec` must match `t_flight_sec` exactly (within numeric tolerance).
- `t_sensor_raw_sec` is never modified in cleaning.
- Cleaning defaults to no time rebase.

## Stream Schema

`imu.csv` required columns:

- `t_flight_sec`
- `t_sensor_raw_sec`
- `t_sec`
- `accel_z_mps2`
- `source_family`
- `source_file`
- `source_row`

`baro.csv` required columns:

- `t_flight_sec`
- `t_sensor_raw_sec`
- `t_sec`
- `pressure_pa`
- `baro_alt_m_raw`
- `source_family`
- `source_file`
- `source_row`

`gps.csv` (optional) columns:

- `t_flight_sec`
- `t_sensor_raw_sec`
- `t_sec`
- `gps_alt_m`
- `lat_deg`
- `lon_deg`
- `num_sats`
- `source_family`
- `source_file`
- `source_row`

## Cleaning Policy (v1)

- IMU is passed through.
- Baro rows are dropped when:
  - non-finite pressure or time
  - pressure outside `[20000, 120000]` Pa
  - optional step filter (off by default)
- Dropped baro rows are written to `baro_dropped.csv` with reason flags.

## Validation Policy

Normalized and cleaned validators enforce:

- required files/columns
- finite ratio thresholds for key value columns
- monotonic nonnegative flight time
- alias consistency (`t_sec == t_flight_sec`)
- pressure range compliance in cleaned baro

Validator reporting notes:

- `time_starts_at_zero` is informational only in normalized/clean reports.
- strict failure is based on required files/columns, monotonicity/nonnegativity, alias consistency, finite-ratio thresholds, and configured pressure limits.

## Script Wiring

`data.m` controls data preparation stages with run flags:

- fetch
- normalize
- normalize validation
- clean
- clean validation
- optional quick plot from `plotting/plot_clean_flight_overview.m`

`main.m` is EKF-focused and consumes `_data_clean/` as input.

## Change Control

Keep this stable unless explicitly re-approved:

- directory names
- required column names
- time contract semantics
- cleaning default pressure range

If a breaking change is required, update:

- this document
- validators
- migration notes in commit message
