function result = run_vertical_ekf_replay(prep, x0, P0, u0, ekf_config, varargin)
% run_vertical_ekf_replay
% Run vertical-channel EKF on merged replay events.
%
% Inputs:
%   prep       - struct from prepare_measurements_for_ekf
%   x0         - 3x1 initial state [z; vz; b_a]
%   P0         - 3x3 initial covariance
%   u0         - initial held acceleration input
%   ekf_config - config struct from main.m
%
% Name-Value options:
%   'verbose' - true/false (default: true)

if ~isstruct(prep) || ~isfield(prep, 'events')
    error('prep must be a struct from prepare_measurements_for_ekf.');
end
if ~isnumeric(x0) || ~isequal(size(x0), [3, 1])
    error('x0 must be a 3x1 vector.');
end
if ~isnumeric(P0) || ~isequal(size(P0), [3, 3])
    error('P0 must be a 3x3 matrix.');
end
if ~isstruct(ekf_config)
    error('ekf_config must be a struct.');
end

options = struct('verbose', true);
options = apply_name_value(options, varargin{:});

measurement_model = lower(string(ekf_config.measurement_model));
if ~(measurement_model == "altitude_linear" || measurement_model == "pressure_nonlinear")
    error('measurement_model must be ''altitude_linear'' or ''pressure_nonlinear''.');
end

events = prep.events;
n = height(events);
if n == 0
    error('prep.events is empty.');
end

% Pre-extract columns from event table to plain arrays for fast loop indexing.
is_imu = events.event_type == 'imu';
is_baro = events.event_type == 'baro';
t = double(events.t_flight_sec);         % Absolute flight time [s] at each event
dt = double(events.dt_sec);              % Inter-event interval; fed to ekf_predict each step
u_event = double(events.accel_u_z_mps2); % Gravity-compensated IMU accel (u_z = a_IMU - g)
baro_z = double(events.baro_z_m);        % Launch-relative baro altitude (altitude_linear model)
baro_pressure = double(events.pressure_pa); % Raw barometric pressure (pressure_nonlinear model)

% Launch-site elevation offset for ISA model: converts launch-relative z to absolute altitude.
% z_abs = z_hat + z_ref_m is passed to the pressure model and Jacobian.
z_ref_m = 0;
if isfield(prep, 'use_launch_relative_baro') && prep.use_launch_relative_baro && ...
        isfield(prep, 'launch_ref_alt_m') && isfinite(prep.launch_ref_alt_m)
    z_ref_m = double(prep.launch_ref_alt_m);
end

% --- Initialize filter state ---
x = x0;       % [z; vz; b_a]
P = P0;       % 3x3 initial covariance
u_hold = u0;  % Zero-order-hold on last received IMU input (updated only on IMU events)

% Pre-allocate output history arrays.
z_hat = nan(n, 1);     % Estimated altitude [m]
vz_hat = nan(n, 1);    % Estimated vertical velocity [m/s]
ba_hat = nan(n, 1);    % Estimated accelerometer bias [m/s^2]
P_zz = nan(n, 1);      % Altitude variance [m^2]
P_vzvz = nan(n, 1);    % Velocity variance [(m/s)^2]
P_baba = nan(n, 1);    % Bias variance [(m/s^2)^2]
innovation = nan(n, 1); % Altitude-equivalent residual [m] (for plotting)
nis = nan(n, 1);        % Normalized Innovation Squared (chi^2(1) for consistent filter)
update_used = false(n, 1); % True if baro update was applied at this event
gated_out = false(n, 1);   % True if baro update was rejected by innovation gate
u_used = nan(n, 1);        % Control input held at this event (for diagnostics)

% Counters for summary diagnostics.
num_predict_steps = 0;
num_baro_updates = 0;
num_baro_gated = 0;
num_nonfinite_baro = 0;
num_cov_floor_events = 0;

% =========================================================================
% Main event loop — processes the merged, time-sorted IMU+baro event stream.
%
% Architecture (asynchronous replay):
%   - Every event: predict step advances state by dt_k.
%   - IMU events: update the held control input u_hold (zero-order-hold).
%   - Baro events: run measurement update using the held u_hold.
%
% There is no resampling or interpolation. Each sensor contributes events at
% its natural rate; variable-step Qd(dt) handles non-uniform intervals exactly.
% =========================================================================
for k = 1:n
    % --- Predict step (every event) ---
    % Advances x and P forward by dt(k) using held u_z and current bias estimate.
    [x, P, dt_used] = ekf_predict( ...
        x, P, u_hold, dt(k), ...
        ekf_config.q_vz_psd, ekf_config.q_ba_psd, ...
        ekf_config.min_dt_sec, ekf_config.max_dt_sec, ...
        ekf_config.min_variance_floor, ekf_config.enforce_covariance_symmetry);
    num_predict_steps = num_predict_steps + 1;

    % --- IMU event: update zero-order-hold on control input ---
    % u_hold remains constant until the next IMU event arrives.
    % IMU-before-baro tie-break on equal timestamps ensures u_hold is current
    % before any baro update that might share this timestamp.
    if is_imu(k) && isfinite(u_event(k))
        u_hold = u_event(k);
    end

    innov_k = nan;
    nis_k = nan;
    update_k = false;
    gated_k = false;

    % --- Baro event: measurement update ---
    if is_baro(k)
        if measurement_model == "altitude_linear"
            % Baseline linear KF update: y = z + v (altitude domain, constant H and R).
            [x, P, uinfo] = ekf_update_baro( ...
                x, P, baro_z(k), ...
                ekf_config.r_baro_var, ekf_config.min_variance_floor, ...
                ekf_config.enforce_covariance_symmetry, ...
                ekf_config.enable_innovation_gate, ekf_config.innovation_gate_nsigma);
        else
            % Nonlinear EKF pressure update: y = h(z) + v_p (pressure domain, altitude-dependent H and R_eff).
            [x, P, uinfo] = ekf_update_baro_pressure( ...
                x, P, baro_pressure(k), ...
                ekf_config.sea_level_pressure_pa, ekf_config.r_baro_var, z_ref_m, ...
                ekf_config.min_variance_floor, ekf_config.enforce_covariance_symmetry, ...
                ekf_config.enable_innovation_gate, ekf_config.innovation_gate_nsigma);
        end

        % innovation_m_equiv converts Pa residual back to metres via local dh/dz
        % for interpretable plots regardless of which measurement model was used.
        innov_k = uinfo.innovation;
        if isfield(uinfo, 'innovation_m_equiv')
            innov_k = uinfo.innovation_m_equiv;
        end
        nis_k = uinfo.nis;
        update_k = uinfo.used;
        gated_k = uinfo.gated_out;

        % Tally update outcomes for summary diagnostics.
        if uinfo.used
            num_baro_updates = num_baro_updates + 1;
        elseif uinfo.gated_out
            num_baro_gated = num_baro_gated + 1;
        else
            num_nonfinite_baro = num_nonfinite_baro + 1;
        end
    end

    % Detect covariance floor hits (diagnostic only — indicates near-degenerate steps).
    if any(diag(P) <= ekf_config.min_variance_floor + eps)
        num_cov_floor_events = num_cov_floor_events + 1;
    end

    % Store post-event state and diagnostics for log table.
    z_hat(k) = x(1);
    vz_hat(k) = x(2);
    ba_hat(k) = x(3);
    P_zz(k) = P(1, 1);
    P_vzvz(k) = P(2, 2);
    P_baba(k) = P(3, 3);
    innovation(k) = innov_k;
    nis(k) = nis_k;
    update_used(k) = update_k;
    gated_out(k) = gated_k;
    u_used(k) = u_hold;

    if ~isfinite(dt_used)
        error('Non-finite dt_used encountered at event %d.', k);
    end
end

summary = struct();
summary.flight_id = prep.flight_id;
summary.num_events = n;
summary.num_predict_steps = num_predict_steps;
summary.num_imu_events = sum(is_imu);
summary.num_baro_events = sum(is_baro);
summary.num_baro_updates_used = num_baro_updates;
summary.num_baro_updates_gated = num_baro_gated;
summary.num_baro_nonfinite = num_nonfinite_baro;
summary.num_cov_floor_events = num_cov_floor_events;
summary.duration_sec = t(end) - t(1);
summary.final_z_m = x(1);
summary.final_vz_mps = x(2);
summary.final_ba_mps2 = x(3);
summary.final_P_zz = P(1, 1);
summary.final_P_vzvz = P(2, 2);
summary.final_P_baba = P(3, 3);
summary.measurement_model = char(measurement_model);

log_table = table( ...
    (1:n)', t, dt, events.event_type, ...
    u_used, baro_z, baro_pressure, z_hat, vz_hat, ba_hat, ...
    P_zz, P_vzvz, P_baba, innovation, nis, ...
    update_used, gated_out, ...
    'VariableNames', {'event_idx', 't_flight_sec', 'dt_sec', 'event_type', ...
    'u_z_mps2', 'baro_z_m', 'pressure_pa', 'z_hat_m', 'vz_hat_mps', 'ba_hat_mps2', ...
    'P_zz', 'P_vzvz', 'P_baba', 'innovation_m', 'nis', ...
    'update_used', 'gated_out'});

result = struct();
result.flight_id = prep.flight_id;
result.summary = summary;
result.log = log_table;

if options.verbose
    fprintf(['EKF run complete: %s | mode=%s | events=%d | baro updates used=%d, gated=%d, ' ...
        'final [z,vz,ba]=[%.3f, %.3f, %.3f]\n'], ...
        prep.flight_id, char(measurement_model), n, num_baro_updates, num_baro_gated, x(1), x(2), x(3));
end
end
