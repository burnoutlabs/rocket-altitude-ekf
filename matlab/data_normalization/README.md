# Normalization Module

Standalone normalization pipeline for EKF inputs.

Primary entrypoints:

- `run_normalization_pipeline.m`
- `validate_normalized_data.m`

Default paths:

- raw input: `project/matlab/_data_raw/`
- normalized output: `project/matlab/_data_normalized/`

Run from MATLAB:

```matlab
cd('matlab');  % from the repository root
addpath(fullfile(pwd, 'data_normalization'));

manifest = run_normalization_pipeline('overwrite_outputs', true);
report = validate_normalized_data('strict', true);
```

Notes:

- This module is wired into `main.m` and can also be run standalone.
- v1 processes EKF-relevant schemas and skips GPS-only and XLSX-only sources.
- Time contract:
  - `t_sensor_raw_sec`: cleaned/deduped sensor-native timeline
  - `t_flight_sec`: common flight timeline (origin is earliest sample across all streams in that flight)
  - `t_sec`: compatibility alias of `t_flight_sec`
  - per stream, `t_flight_sec` must be finite, monotonic nondecreasing, and nonnegative
  - per-stream zero-start is not required (asynchronous streams may begin later than flight origin)

Validation note:

- `time_starts_at_zero` in `normalization_validation_report.csv` is informational and not a strict-fail criterion.
