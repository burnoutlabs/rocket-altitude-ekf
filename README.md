# Offline rocket altitude EKF

An offline Extended Kalman Filter, in MATLAB, that reconstructs the vertical
flight of high-power rockets from logged onboard IMU and barometer data. The
state is `x = [z, v_z, b_a]`: launch-relative altitude, vertical velocity, and
an accelerometer bias modelled as a random walk.

The process model is constant-acceleration kinematics driven by
`u_z = a_axial - g`, held constant between IMU samples, with an exact state
transition `F` and a discrete process noise `Q_d(dt)` from exact integration,
including the bias-coupling terms (`matlab/ekf/ekf_predict.m`). The default
measurement is the nonlinear ISA tropospheric pressure model
`h(z) = p0 (1 - z_abs/H_T)^beta`, linearised at each update
(`matlab/ekf/ekf_update_baro_pressure.m`); a linear altitude update is kept as
a baseline (`matlab/ekf/ekf_update_baro.m`). The covariance update is
Joseph-form. An NIS innovation gate is implemented but disabled by default.

The IMU and barometer streams are merged and replayed as asynchronous events
in time order, with no resampling (`matlab/ekf/run_vertical_ekf_replay.m`).
Flight logs from several logger families are taken through a fetch, normalize
and clean pipeline before the filter sees them, and the results are plotted
and, for two flights, compared against GPS altitude.

## How to run

Requires MATLAB. The entry scripts are live scripts in `matlab/`:

1. `matlab/data.m` downloads the source flight logs and runs the normalize and
   clean pipelines into `matlab/_data_clean/`. Run it once.
2. `matlab/main.m` runs the EKF over the cleaned flights, shows a single
   flight interactively, and writes report figures and tables to
   `matlab/_report_artifacts/`.
3. `matlab/demo.m` is a shorter interactive EKF demo; it assumes `data.m` has
   already been run.

For the GPS comparison, run `matlab/gps_validation/download_gps_data.m`, then
`matlab/gps_validation/process_gps_data.m`, which writes
`matlab/gps_validation/gps_comparison.txt`.
`tests/ekf_smoketest.m` runs the filter on a synthetic constant-altitude
trajectory (linear altitude update only) and needs no downloaded data.
`tools/sync_figures.py` copies the report figures from
`matlab/_report_artifacts/figures/` into `report/figures/`.

## Layout

| Path | Contents |
| --- | --- |
| `matlab/` | Filter, data pipelines (`data_fetch/`, `data_normalization/`, `data_cleaning/`), plotting, GPS validation, entry scripts |
| `docs/` | Project spec, EKF reference, data-processing schema, dataset and results |
| `report/` | Report (`report.md`), presentation notes, slide text (`slides.txt`), figures |
| `archive/` | Working notes, the audit and data investigation from development |
| `tests/` | Smoke test on synthetic data |
| `tools/` | Figure sync helper |

## Data

All flight data comes from the [DOFPro flight-data archive](https://www.dofpro.org/).
None of it is the author's own flights. The logs are fetched at run time from
the URLs in `matlab/data_fetch/source_data.m` (and, for GPS,
`matlab/gps_validation/_gps_raw/gps_download_manifest.csv`) into gitignored
directories, and are not redistributed in this repository.

## Known limitations

- The accelerometer-bias state absorbs roughly 1 g of model error: recorded
  final `b_a` values are several m/s^2, far larger than a real MEMS
  accelerometer bias. Body-axis acceleration is used as vertical, and its sign
  flips after apogee.
- The report's numbers refer to 25 flights, while
  `matlab/data_fetch/source_data.m` lists 23 active sources, so the report's
  figures cannot be regenerated exactly from the committed source list.

## Course context

Developed as a graduate course project (Winter 2026); the report is in report/.

## Licence

Licence: not yet chosen.
