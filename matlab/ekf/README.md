# EKF Module

Minimal helper set for the notebook walkthrough in `main.m`.

Root utilities (`ekf/`):

1. `apply_name_value.m`
2. `altitude_from_pressure_pa.m`
3. `ekf_predict.m`
4. `ekf_update_baro.m`
5. `run_vertical_ekf_replay.m`

Pipeline helpers (`ekf/pipeline/`):

1. `list_clean_flight_ids.m`
2. `load_clean_flight.m`
3. `build_replay_events.m`
4. `validate_replay_events.m`
5. `prepare_measurements_for_ekf.m`
6. `generate_report_artifacts.m`
