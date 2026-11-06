%[text] # Project: Vertical Flight Reconstruction of Sounding Rocket
%[text] *ECE9203: Random Signals*
%[text] ## Purpose
%[text] This live script is the EKF and reporting notebook that consumes prepared data from \_`data_clean/`. It processes 25 cleaned flights across four source families (`multi_time_csv`, `trimmed_txt`, `raven_csv`, `emulation_csv`), runs a single-flight EKF for interactive inspection, and generates report-ready figure and table artifacts. Data preparation lives in `data.m` and only needs to be run once.
%[text] ## Stochastic Process Framing
%[text] The rocket trajectory is modeled as a latent random process observed through noisy sensors. In state-space form:
%[text] $x\_{k+1} = f(x\_k, u\_k, \\Delta t\_k) + w\_k, \\quad w\_k \\sim \\mathcal{N}(0, Q\_k)$
%[text] $y\_k = h(x\_k) + v\_k, \\quad v\_k \\sim \\mathcal{N}(0, R)$
%[text] where process noise captures unmodeled dynamics (thrust variation, aerodynamic effects, sensor bias drift), and measurement noise captures barometer uncertainty.
%[text] Under linear-Gaussian assumptions, the Kalman filter is the minimum mean-square-error (MMSE) estimator for this model class. Here the barometric pressure measurement function $h(z)$ follows the nonlinear ISA pressure-altitude model, so a plain linear KF cannot be applied directly. The Extended Kalman Filter linearizes $h$ around the current predicted state at each update step, yielding an approximate MMSE estimator suited to this problem class.
%[text] ## Vertical EKF Model Used Here
%[text] State vector:
%[text] $x = \[z, v\_z, b\_a\]^T$
%[text] where $z$ \[m\] is altitude above the launch pad (launch-relative), $v\_z$ \[m/s\] is vertical velocity (positive upward), and $b\_a$ \[m/s²\] is accelerometer bias modeled as a random walk with constant power spectral density.
%[text] with
%[text] $\\dot{z} = v\_z$
%[text] $\\dot{v}\_z = u\_z - b\_a + w\_v$
%[text] $\\dot{b}\_a = w\_b$
%[text] and two selectable measurement models:
%[text] Linear altitude form: $y\_z = z + v$, $v \\sim \\mathcal{N}(0,R)$
%[text] Nonlinear pressure form (true EKF update): $y\_p = h(z) + v\_p$, with
%[text] $h(z) = p\_0\\left(1 - \\frac{z\_{abs}}{44330}\\right)^{5.25588}$ and Jacobian
%[text] $H\_k = \\left\[\\frac{\\partial h}{\\partial z}, 0, 0\\right\]$.
%[text] **Interpretation:** The process model is linear in this project phase; EKF behavior comes from the nonlinear pressure measurement linearization when `ekf_measurement_model="pressure_nonlinear"`.
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
data_workspace_script = fullfile(here, 'data.m');
data_clean_dir = fullfile(here, '_data_clean');
plotting_dir = fullfile(here, 'plotting');

ekf_dir = fullfile(here, 'ekf');
ekf_pipeline_dir = fullfile(ekf_dir, 'pipeline');

report_figures_dir = fullfile(here, '_report_artifacts', 'figures');
report_tables_dir = fullfile(here, '_report_artifacts', 'tables');
%%
%[text] ## Run Controls
%[text] This notebook is EKF-focused. Data fetch, normalize, and clean steps live in `data.m` — run it once to populate `_data_clean/`, after which this notebook runs independently.
%[text] **Tier-1 (T1) flights** are the four flights selected as primary report representatives, one per source family: T1-A (multi\_time J570W, apogee 3409 m, cross-validated 1.2%); T1-B (trimmed\_txt Vulcanite J270W, 1834 m, 600 s record); T1-C (Raven J530, best Raven NIS 0.57, illustrates cold-start tracking); T1-D (multi\_time J394, apogee 3669 m, documents +14.2 m drift from synoptic pressure passage). Set `active_flight_index` (1\u20134) to inspect each in turn.
% Optional convenience hook: run data.m before EKF when needed.
run_data_workspace_first = false;

% Shared flight selector for replay build and single-flight EKF.
%
% Set active_flight_index to pick from report_figure_flight_ids by position:
%   1 = T1-A: multi_time J570W
%   2 = T1-B: trimmed_txt Vulcanite J270W
%   3 = T1-C: Raven Adventurer J530
%   4 = T1-D: multi_time J394 (frontal passage)
%
% Or override with an explicit ID string (set active_flight_index = 0 to use it):
%   active_flight_id_override = "raven_csv_e190_8jul2017_j510w_raven";
active_flight_index = 1;
active_flight_id_override = "";  % only used when active_flight_index = 0

% EKF behavior
% Measurement update model:
%   "pressure_nonlinear" (true EKF update in pressure domain)
%   "altitude_linear"    (legacy linear altitude update for A/B checks)
ekf_measurement_model = "pressure_nonlinear";

% Optional report artifact regeneration (all-flight tables + explicit figures).
run_generate_report_artifacts = true;
report_figures_all_flights = false; % true => generate figures for every flight (slow)

% Set report_figure_flight_ids to the explicit IDs to include in report figures.
% Use strings(0,1) for tables-only mode (no figure generation).
report_figure_flight_ids = [ ...
     "multi_time_csv_e190_9dec2017_j570w_onboard", ...      % T1-A: best multi_time, 3409 m, cross-validated 1.2%
     "trimmed_txt_20210410_vulcanite_j270w_14a_trimmed", ... % T1-B: best trimmed_txt, 1834 m, 600 s, tightest P_zz
     "raven_csv_20210417_adventurer_j530_1_raven", ...      % T1-C: best Raven NIS (0.56), shows cold-start + descent limit
     "multi_time_csv_e190_7oct2017_j394_1_xtra"];           % T1-D: frontal passage case (+14.2 m), documents baro limitation

%[text] ## Data Prerequisite
%[text] Data preparation (fetch/normalize/clean) is handled in `data.m`.
%[text] If `_data_clean/` is missing or stale, run `data.m` first, or set `run_data_workspace_first=true`.
if run_data_workspace_first
    if ~isfile(data_workspace_script)
        error('Missing data workspace script: %s', data_workspace_script);
    end
    data_script_skip_clear = true;
    run(data_workspace_script);
    if exist('data_script_skip_clear', 'var')
        clear data_script_skip_clear;
    end
end

if ~isfolder(data_clean_dir)
    error(['Missing cleaned data directory: %s\n' ...
        'Run data.m first, or set run_data_workspace_first=true.'], data_clean_dir);
end
%%
%[text] ## EKF Module Setup
%[text] Adds the `ekf/`, `ekf/pipeline/`, and `plotting/` directories to the MATLAB path so all filter and plotting functions are resolvable, then declares all estimator parameters explicitly in this notebook for transparency. Parameters are organized into five groups: physical model conventions, initial state and uncertainty, process noise PSDs, measurement noise variance, and numerical safeguards.
%[text] Discrete-time process model implemented in prediction:
%[text] $z\_{k+1} = z\_k + v\_{z,k}\\,\\Delta t + \\frac{1}{2}(u\_{z,k} - b\_{a,k})\\,\\Delta t^2$
%[text] $v\_{z,k+1} = v\_{z,k} + (u\_{z,k} - b\_{a,k})\\,\\Delta t$
%[text] $b\_{a,k+1} = b\_{a,k}$
%[text] So
%[text] $F\_k = \\left\[\n\\begin{array}{ccc}\n1 & \\Delta t & -\\frac{1}{2}\\Delta t^2 \\\\\n0 & 1 & -\\Delta t \\\\\n0 & 0 & 1\n\\end{array}\n\\right\]$.
%[text] Process noise $Q\_d(\\Delta t)$ is computed from two continuous-time power spectral densities scaled by each inter-event interval, so the discretization is exact for variable-step replay. For velocity disturbance: $Q\_d^{vv} \\approx q\_{vz} \\cdot \\Delta t$; for bias random walk: $Q\_d^{bb} \\approx q\_{ba} \\cdot \\Delta t$. Cross-coupling terms between $z$ and $v\_z$ are included in the full expression but are dominated by the diagonal. Scaling by $\\Delta t$ ensures larger time steps accumulate proportionally more uncertainty, consistent with a continuous-time stochastic model.
%[text] Measurement noise variance is $R = r\_{baro}$.
%[text] Kalman recursion at each event:
%[text] $x^- = F x^+ + B u$, $P^- = F P^+ F^T + Q$
%[text] For `altitude_linear`, $H = \[1, 0, 0\]$.
%[text] For `pressure_nonlinear`, $H\_k = \\left\[\\frac{\\partial h}{\\partial z}, 0, 0\\right\]$ from the current predicted altitude.
%[text] $K = P^- H^T(HP^-H^T + R)^{-1}$ (with $H\_k$ for nonlinear pressure mode)
%[text] $x^+ = x^- + K\\nu$, where $\\nu = y - Hx^-$ for `altitude_linear`, or $\\nu = p\_{meas} - h(\\hat{z}^-)$ \[Pa\] for `pressure_nonlinear` (converted to altitude-equivalent via $H\_k$ for logging).
%[text] Covariance update uses the Joseph form for numerical stability: $P^+ = (I - KH)P^-(I-KH)^T + KRK^T$, which preserves symmetry and positive-definiteness under finite-precision arithmetic, unlike the simpler $(I-KH)P^-$ form.
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
%[text] `z_axis_positive_up = true` and `gravity_mps2 = 9.80665` set the sign and magnitude conventions. `accel_is_specific_force = true` means the IMU measures specific force: at rest on the pad it reads $+g$ upward, so the process model input is $u\_z = a\_{IMU,z} - g$ (zero on the pad, positive during thrust). `use_launch_relative_baro = true` expresses barometric altitude relative to the launch pad so $z\_0 \\approx 0$ regardless of absolute site elevation. The launch reference is the median of baro samples within `launch_ref_max_time_sec` of the first baro reading. This time-based window is critical for Raven flights, which begin logging at ignition with no pre-launch pad phase: a 200-sample window spans ~10 s of powered ascent and biases the reference ~1100 m above the pad. A 0.5 s window captures only ground-level samples regardless of logger family.
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
%[text] The filter starts from rest: $x\_0 = \[z\_0,; 0,; 0\]^T$. The initial covariance $P\_0 = \\text{diag}(50^2, 30^2, 5^2)$ encodes intentionally broad uncertainty: $\\sigma\_z = 50$ m, $\\sigma\_{v\_z} = 30$ m/s (accommodates flights where records begin mid-flight), $\\sigma\_{b\_a} = 5$ m/s². The actual $z\_0$ is overridden below to the first finite baro sample, aligning the state to the barometric reference before the filter loop begins.
% Initial state (z overridden to first baro sample below).
ekf_config.init_z_m = 0;
ekf_config.init_vz_mps = 0;
ekf_config.init_ba_mps2 = 0;
ekf_config.init_var_z = 50^2;
ekf_config.init_var_vz = 30^2;
ekf_config.init_var_ba = 5^2;
%[text] ### Process Noise Power Spectral Densities
%[text] `q_vz_psd = 4.0` m²/s³ models unmodeled vertical accelerations (aerodynamic drag variation, thrust uncertainty, wind gusts). `q_ba_psd = 0.05² = 0.0025` m²/s³ sets the bias random walk rate — small enough that bias is nearly constant over a typical 100–600 s flight, but non-zero to permit slow drift tracking. Both values were selected by physical reasoning, not grid search.
% Process noise PSDs.
ekf_config.q_vz_psd = 4.0;
ekf_config.q_ba_psd = 0.05^2;
%[text] ### Measurement Noise Variance
%[text] `r_baro_var = 8² = 64` m² sets the barometer noise variance ($\\sigma\_{baro} = 8$ m). Via the ISA pressure-altitude lapse rate $\\partial P / \\partial z \\approx -11.8$ Pa/m near sea level, this corresponds to $\\sigma\_P \\approx 94$ Pa — conservative relative to the 1–3 Pa static noise of a typical MEMS barometer, but defensible given vibration during boost and the heterogeneous sensor set across 25 flights.
% Measurement noise.
ekf_config.r_baro_var = 8.0^2;
ekf_config.measurement_model = char(ekf_measurement_model);
%[text] ### Numerical Safeguards and Innovation Gating
%[text] `max_dt_sec = 5.0` clamps any predict step longer than 5 s to prevent $Q\_d$ from growing unbounded on data gaps. `min_variance_floor = 1e-9` prevents diagonal covariance entries from reaching machine zero. Innovation gating is **disabled**: across 25 flights from four logger families, a single fixed threshold cannot accommodate all launch transients without causing baro starvation — rejecting legitimate measurements during the most dynamically active phase of flight.
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
%[text] Builds a deterministic asynchronous event stream from cleaned IMU and barometer samples. Three pipeline steps: (1) `load_clean_flight` reads the per-flight cleaned data from \_`data_clean/`; (2) `build_replay_events` merges the IMU and baro streams by timestamp into a single sorted event table, with IMU events taking priority on identical timestamps; (3) `validate_replay_events` checks that time is monotonically increasing, all `dt_sec` values are finite and non-negative, and no duplicate timestamps exist.
%[text] **Event semantics:** IMU events carry `accel_z_mps2`, held constant via zero-order hold until the next IMU event and used as the control input $u\_z$ in each predict step. Baro events carry raw `pressure_pa` and trigger a measurement update after the predict. The inter-event interval `dt_sec` drives the variable-step $Q\_d(\\Delta t)$ computation — for IMU events this is a pure predict; for baro events it is predict-then-update.
% Resolve active_flight_id from index or explicit override.
if active_flight_index >= 1 && active_flight_index <= numel(report_figure_flight_ids)
    active_flight_id = report_figure_flight_ids(active_flight_index);
elseif active_flight_index == 0 && strlength(active_flight_id_override) > 0
    active_flight_id = active_flight_id_override;
else
    error('active_flight_index=%d is out of range (1-%d). Set to 0 and use active_flight_id_override for custom IDs.', ...
        active_flight_index, numel(report_figure_flight_ids));
end
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
%[text] This figure verifies replay integrity before estimation: event time progression, `dt_sec` distribution, and where IMU versus baro events occur on the shared timeline.
%[text] Use it to spot timing irregularities or sparse regions that could bias predict/update behavior.
replay_timing_info = plot_replay_timing(replay_data, ...
    'figure_visible', true);
%%
%[text] ## Single-Flight EKF Run
%[text] Runs one complete estimation pass on the selected replay:
%[text] Innovation gating uses normalized innovation squared (NIS):
%[text] $\\text{NIS} = \\frac{\\nu^2}{S}$, with gate threshold $n\_{gate}^2$.
ekf_prep = prepare_measurements_for_ekf(replay_data, ekf_config, 'verbose', true);

[x0, P0, u0] = build_initial_conditions(ekf_prep, ekf_config);

ekf_result = run_vertical_ekf_replay(ekf_prep, x0, P0, u0, ekf_config, 'verbose', true);
%[text] This plot confirms measurement conventions entering the filter: raw pressure, absolute vs launch-relative baro altitude, and raw IMU acceleration vs model input `u_z`.
%[text] It is a sign/offset sanity check for launch reference handling and gravity compensation.
plot_measurement_conventions(ekf_prep, 'figure_visible', true);
%[text] ### EKF State Overview
%[text] Main plausibility check. **Altitude panel:** EKF line should closely track the baro dots throughout; large persistent gaps indicate misconfigured noise or a failed update. **Velocity panel:** `vz_hat` should cross zero near apogee; pre-launch is flat near zero. **Bias panel:** `ba_hat` converges within the first ~30 s on flights with a pad window; on Raven flights (no pad) convergence begins simultaneously with high-thrust boost.
plot_ekf_overview(ekf_result, 'figure_visible', true);
%[text] ### Innovations and NIS
%[text] Residual consistency diagnostic. **Innovation panel:** residuals should scatter symmetrically around zero with no systematic drift; a persistent offset indicates a model or noise mismatch. **NIS panel:** under correctly specified noise, NIS $\\sim \\chi^2\_1$ with mean 1.0; the 3.84 threshold (red dashed) is the 95th percentile. NIS mean \>\> 1 suggests underestimated noise; NIS mean \<\< 1 suggests overestimated noise. Launch-transient spikes are expected on `multi_time` flights with long pad phases.
plot_ekf_innovations(ekf_result, 'figure_visible', true);
%[text] ### Covariance Diagonal
%[text] Uncertainty evolution on a log scale. **Healthy pattern:** all variances decrease (or stabilize) once measurements arrive; $P\_{zz}$ shows a two-phase drop on flights with a pad window (broad prior $\\rightarrow$ pad convergence $\\rightarrow$ tightening during flight). **Red flags:** any variance increasing sharply indicates numerical instability; $P\_{zz}$ that never drops below ~2500 m² means baro updates are not reaching the filter. Final $\\sqrt{P\_{zz}}$ is the filter's self-reported altitude std (typically 1.5–3 m for converged flights).
plot_ekf_covariance(ekf_result, 'figure_visible', true);
%[text] ### Event Timeline (post-run)
%[text] Event structure as seen by the filter. The rate panel shows IMU and baro sampling density over the flight — a step-up in IMU rate at launch is visible on most flights. The `dt` histogram shows inter-event interval distribution; two distinct peaks indicate healthy interleaved streams. A long right tail indicates infrequent large gaps that were clamped by `max_dt_sec`.
plot_ekf_event_timeline(ekf_result, 'figure_visible', true);
%%
%[text] ## Flight Results
%[text] Numerical summary of the single-flight EKF run. Healthy ranges for non-Raven flights: **final\_z** near 0 m (returns to launch-pad altitude); **NIS mean** near 1.0 (chi-squared(1) expectation); **baro update ratio** of 1.0 (every measurement accepted); **final** $\\sqrt{P\_{zz}}$ of 1–3 m (well-converged altitude std). Raven flights show large negative `final_z` due to post-apogee body-reorientation divergence — see T1-C in the table below.
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
%[text] **T1 reference values:**
%[text:table]
%[text] |  | T1-A J570W | T1-B J270W Vulcanite | T1-C J530 Raven | T1-D J394 |
%[text] | --- | --- | --- | --- | --- |
%[text] | Apogee (m) | 3409 | 1834 | 2721 | 3669 |
%[text] | NIS mean | 3\.49 | 0\.83 | 0\.57 | 2\.73 |
%[text] | final\_z (m) | −0.05 | −0.2 | −5.9 | \+14.2‡ |
%[text:table]
%[text] ‡ Synoptic frontal passage (+1.7 hPa over ~220 s active flight). All apogee values are EKF peak\_z\_m from final\_per\_flight\_metrics.csv.
%%
%[text] ## Report Artifact Generation
%[text] Regenerates all report-ready outputs. `tables/` receives a per-flight metrics CSV covering all 25 flights (apogee, final state, NIS mean, baro update ratio, final covariance diagonals). `figures/` receives four 300 dpi PNG files per flight in `report_figure_flight_ids`: overview, innovations, covariance, and event timeline.
%[text] Set `report_figures_all_flights = true` to generate figures for every flight. Set `report_figure_flight_ids = strings(0,1)` for tables-only mode.
if run_generate_report_artifacts
    if report_figures_all_flights
        resolved_figure_ids = list_clean_flight_ids(data_clean_dir);
    else
        resolved_figure_ids = report_figure_flight_ids;
    end
    report_artifacts_output = generate_report_artifacts( ...
        data_clean_dir, report_tables_dir, report_figures_dir, ekf_config, ...
        'figure_flight_ids', resolved_figure_ids, ...
        'verbose', true);
end
%%
%[text] ## Run Summary
%[text] Report artifacts in \_`report_artifacts/`: `tables/` contains per-flight metrics for all 25 flights; `figures/` contains four 300 dpi PNG plots per T1 flight (overview, innovations, covariance, event timeline). Re-run with `run_generate_report_artifacts = true` after any parameter or data change to refresh outputs.
fprintf('\n--- Main EKF Execution Complete ---\n');
fprintf('Active flight:  %s\n', active_flight_id);
fprintf('EKF mode:       %s\n', ekf_config.measurement_model);
if exist('apogee_z', 'var')
    fprintf('Flight summary: apogee=%.1f m, final_z=%+.2f m, NIS=%.2f\n', apogee_z, ekf_sum.final_z_m, nis_mean);
end
fprintf('Cleaned dir:    %s\n', data_clean_dir);
fprintf('Report figures: %s\n', report_figures_dir);
fprintf('Report tables:  %s\n', report_tables_dir);

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"onright","rightPanelPercent":40}
%---
