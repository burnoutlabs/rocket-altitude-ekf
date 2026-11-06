# Cleaning Module

This module generates `_data_clean/` from `_data_normalized/`.

Scope (v1):

- Keep IMU stream as-is.
- Clean barometric pressure stream with conservative physical-range rules.
- Preserve row-level traceability through `source_row` and optional `baro_dropped.csv`.
- Preserve normalization time contract columns:
  - `t_sensor_raw_sec` (sensor timeline)
  - `t_flight_sec` (common flight timeline from normalized stage)
  - `t_sec` (legacy alias of `t_flight_sec`)

Time contract notes:

- `t_flight_sec` remains finite, monotonic nondecreasing, and nonnegative per stream.
- Per-stream zero-start is not required; asynchronous streams may start later than flight origin.
- Cleaning defaults to no time rebase (`rebase_time_after_clean=false`).

Primary entrypoints:

- `run_cleaning_pipeline.m`
- `validate_clean_data.m`

Default paths:

- input normalized: `project/matlab/_data_normalized/`
- output cleaned: `project/matlab/_data_clean/`

Example:

```matlab
cd('matlab');  % from the repository root
addpath(fullfile(pwd, 'data_cleaning'));

cleaning_manifest = run_cleaning_pipeline('overwrite_outputs', true);
clean_report = validate_clean_data('strict', true);
```
