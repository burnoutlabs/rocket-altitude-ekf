%[text] # Demo: Vertical Flight Reconstruction Using an Extended Kalman Filter
%[text] *ECE9203: Random Signals — Cameron Brooks*
%[text] Interactive EKF demo. Assumes `data.m` has already been run to populate `_data_clean/`. Set `active_flight_index` (1-4) and run all sections. For model derivations see the project report.
%% Setup
clear; clc; close all;

% Resolve this folder robustly for editor-run and command-line run.
active_file = '';
if usejava('desktop')
    active_file = matlab.desktop.editor.getActiveFilename;
end
if ~isempty(active_file)
    here = fileparts(active_file);
else
    here = fileparts(mfilename('fullpath'));
    if isempty(here)
        here = pwd;
    end
end

% Core paths.
data_clean_dir = fullfile(here, '_data_clean');
plotting_dir = fullfile(here, 'plotting');

ekf_dir = fullfile(here, 'ekf');
ekf_pipeline_dir = fullfile(ekf_dir, 'pipeline');

if ~isfolder(data_clean_dir)
    error(['Missing cleaned data directory: %s\n' ...
        'Run data.m first to populate _data_clean/.'], data_clean_dir);
end
%%
%[text] ## Run Controls
%[text] Set `active_flight_index` (1–4) to select a T1 flight. Toggle `ekf_measurement_model` to compare the nonlinear pressure update against the linear altitude update.
% 1 = T1-A: multi_time J570W       (3409 m, cross-validated 0.2%, final_z = -0.2 m)
% 2 = T1-B: trimmed_txt J270W      (1834 m, NIS = 0.83, final_z = -0.2 m)
% 3 = T1-C: Raven J530             (~600 m ascent, post-apogee diverges)
% 4 = T1-D: multi_time J394        (3669 m, +14.2 m synoptic drift)
active_flight_index = 1;

% "pressure_nonlinear" (true EKF update) | "altitude_linear" (linear KF, for comparison)
ekf_measurement_model = "pressure_nonlinear";

demo_flight_ids = [ ...
     "multi_time_csv_e190_9dec2017_j570w_onboard", ...      % T1-A
     "trimmed_txt_20210410_vulcanite_j270w_14a_trimmed", ... % T1-B
     "raven_csv_20210417_adventurer_j530_1_raven", ...      % T1-C
     "multi_time_csv_e190_7oct2017_j394_1_xtra"];           % T1-D
%%
%[text] ## EKF Module Setup
%[text] Adds `ekf/`, `ekf/pipeline/`, and `plotting/` to the MATLAB path and declares all estimator parameters. The process model is linear (kinematic constant-acceleration + random-walk bias); the EKF linearization applies only at the barometric measurement update when using `pressure_nonlinear`.
if ~isfolder(ekf_dir)
    error('Missing EKF module directory: %s', ekf_dir);
end
addpath(ekf_dir);
if ~isfolder(ekf_pipeline_dir)
    error('Missing EKF pipeline directory: %s', ekf_pipeline_dir);
end
addpath(ekf_pipeline_dir);
if ~isfolder(plotting_dir)
    error('Missing plotting module directory: %s', plotting_dir);
end
addpath(plotting_dir);
%[text] ### Physical Model Conventions
%[text] IMU measures specific force: $u\_z = a\_{IMU} - g$ (≈ 0 on pad, positive during thrust). Baro altitude is launch-relative; reference = median of first 200 samples.
% Physical model conventions.
ekf_config = struct();
ekf_config.gravity_mps2 = 9.80665;
ekf_config.accel_is_specific_force = true;
ekf_config.sea_level_pressure_pa = 101325;
ekf_config.use_launch_relative_baro = true;
ekf_config.launch_ref_max_time_sec = 0.5;   % time-window for launch-pad baro reference [s]
ekf_config.launch_ref_max_samples = 200;     % fallback sample cap (used only if time param absent)
ekf_config.launch_ref_method = 'median';
%[text] ### Initial State and Uncertainty
%[text] Filter starts from rest: $x\_0 = \[z\_0, 0, 0\]^T$, $P\_0 = \\text{diag}(50^2, 30^2, 5^2)$. Broad velocity prior ($\\sigma\_{v\_z} = 30$ m/s) covers Raven flights that start recording at motor ignition.
% Initial state (z overridden to first baro sample below).
ekf_config.init_z_m = 0;
ekf_config.init_vz_mps = 0;
ekf_config.init_ba_mps2 = 0;
ekf_config.init_var_z = 50^2;
ekf_config.init_var_vz = 30^2;
ekf_config.init_var_ba = 5^2;
%[text] ### Process Noise and Measurement Noise
%[text] PSDs chosen by physical reasoning. `r_baro_var = 64` m² ($\\sigma = 8$ m) is conservative across the heterogeneous sensor set; corresponds to ~94 Pa in the pressure domain.
% Process noise PSDs.
ekf_config.q_vz_psd = 4.0;
ekf_config.q_ba_psd = 0.05^2;
% Measurement noise.
ekf_config.r_baro_var = 8.0^2;
ekf_config.measurement_model = char(ekf_measurement_model);
%[text] ### Numerical Safeguards
%[text] `max_dt_sec = 5.0` clamps predict steps on data gaps. Innovation gating is disabled — a fixed NIS threshold consistently starves the filter of baro updates during high-dynamic boost across the four logger families.
% Numerical safeguards and gating.
ekf_config.max_dt_sec = 5.0;
ekf_config.min_dt_sec = 0.0;
ekf_config.min_variance_floor = 1e-9;
ekf_config.enable_innovation_gate = false;
ekf_config.innovation_gate_nsigma = 6.0;
ekf_config.initial_u_z_mps2 = 0.0;
ekf_config.enforce_covariance_symmetry = true;

%%
%[text] ## Replay Build
%[text] Merges IMU and baro streams by timestamp into one sorted event stream. IMU events update the held $u\_z$ (zero-order hold); baro events trigger a measurement update after each predict. Variable-step $Q\_d(\\Delta t)$ handles non-uniform inter-event intervals without resampling.
% Resolve active flight ID.
if active_flight_index < 1 || active_flight_index > numel(demo_flight_ids)
    error('active_flight_index=%d is out of range (1-%d).', active_flight_index, numel(demo_flight_ids));
end
active_flight_id = demo_flight_ids(active_flight_index);
fprintf('Active flight: [%d] %s\n', active_flight_index, active_flight_id);

replay_flight = load_clean_flight( ...
    'cleaned_dir', data_clean_dir, ...
    'flight_id', active_flight_id, ...
    'verbose', true);

replay_data = build_replay_events(replay_flight, ...
    'p0_pa', ekf_config.sea_level_pressure_pa, ...
    'verbose', true);

replay_validation = validate_replay_events(replay_data, ...
    'verbose', true);
%%
%[text] ## EKF Run
%[text] Runs one complete forward pass on the selected replay.
ekf_prep = prepare_measurements_for_ekf(replay_data, ekf_config, 'verbose', true);

[x0, P0, u0] = build_initial_conditions(ekf_prep, ekf_config);

ekf_result = run_vertical_ekf_replay(ekf_prep, x0, P0, u0, ekf_config, 'verbose', true);
%[text] ### State Overview
%[text] Altitude should track baro closely throughout. Velocity crosses zero at apogee. Bias converges during the pre-launch pad window (or from first update for Raven cold-start flights).
plot_ekf_overview(ekf_result, 'figure_visible', true);
%[text] ### Innovations and NIS
%[text] Residuals should scatter symmetrically about zero. NIS mean near 1.0 indicates a well-calibrated noise model ($\\chi^2(1)$ expectation; 95th-percentile threshold = 3.84 shown dashed).
plot_ekf_innovations(ekf_result, 'figure_visible', true);
%[text] ### Covariance Diagonal
%[text] All variances should decrease once measurements arrive. Final $\\sqrt{P\_{zz}}$ is the filter's altitude standard deviation (typically 1.5–3 m for converged flights).
plot_ekf_covariance(ekf_result, 'figure_visible', true);
%[text] ### Event Timeline
%[text] Two distinct peaks in the $\\Delta t$ histogram confirm healthy interleaved IMU and baro streams.
plot_ekf_event_timeline(ekf_result, 'figure_visible', true);
%%
%[text] ## Results
%[text] Healthy metrics (non-Raven): **final\_z** near 0 m; **NIS mean** near 1.0; **baro update ratio** = 1.0; **final** $\\sqrt{P\_{zz}}$ 1–3 m. Raven flights show large negative `final_z` due to post-apogee body-reorientation — ascent phase is correct.
ekf_sum = ekf_result.summary;
[apogee_z, idx_ap] = max(ekf_result.log.z_hat_m);
t_apogee = ekf_result.log.t_flight_sec(idx_ap);
used_nis = ekf_result.log.nis(ekf_result.log.update_used);
nis_mean = mean(used_nis(isfinite(used_nis)), 'omitnan');
update_ratio = ekf_sum.num_baro_updates_used / max(ekf_sum.num_baro_events, 1);
fprintf('\n--- Flight Results: %s ---\n', ekf_sum.flight_id);
fprintf('  Duration:          %.1f s\n', ekf_sum.duration_sec);
fprintf('  Events:            %d total (%d IMU, %d baro)\n', ekf_sum.num_events, ekf_sum.num_imu_events, ekf_sum.num_baro_events);
fprintf('  Apogee:            %.1f m  at  t = %.1f s\n', apogee_z, t_apogee);
fprintf('  Final z:           %+.2f m  (expect ~0 for non-Raven)\n', ekf_sum.final_z_m);
fprintf('  Final vz:          %+.2f m/s\n', ekf_sum.final_vz_mps);
fprintf('  NIS mean:          %.2f  (chi2(1) expectation = 1.0)\n', nis_mean);
fprintf('  Baro update ratio: %.3f  (1.0 = all accepted)\n', update_ratio);
fprintf('  Final sigma_z:     %.2f m  (sqrt P_zz)\n', sqrt(ekf_sum.final_P_zz));
fprintf('  Cov floor hits:    %d\n', ekf_sum.num_cov_floor_events);
%%
%[text] ## Summary
fprintf('\n--- Demo Complete ---\n');
fprintf('Active flight:  %s\n', active_flight_id);
fprintf('EKF mode:       %s\n', ekf_config.measurement_model);
if exist('apogee_z', 'var')
    fprintf('Flight summary: apogee=%.1f m, final_z=%+.2f m, NIS=%.2f\n', apogee_z, ekf_sum.final_z_m, nis_mean);
end

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"onright"}
%---
