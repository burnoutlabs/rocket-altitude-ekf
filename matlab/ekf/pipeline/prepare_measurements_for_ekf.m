function prep = prepare_measurements_for_ekf(replay, ekf_config, varargin)
% prepare_measurements_for_ekf
% Apply acceleration and barometric conventions before EKF processing.
%
% Inputs:
%   replay     - struct from build_replay_events
%   ekf_config - config struct from main.m
%
% Name-Value options:
%   'verbose' - print summary (default: true)

options = struct('verbose', true);
options = apply_name_value(options, varargin{:});

if ~isstruct(replay) || ~isfield(replay, 'events')
    error('replay must be a struct from build_replay_events.');
end
if ~isstruct(ekf_config)
    error('ekf_config must be a struct.');
end

if ~(strcmpi(ekf_config.launch_ref_method, 'median') || strcmpi(ekf_config.launch_ref_method, 'mean'))
    error('launch_ref_method must be ''median'' or ''mean''.');
end

events = replay.events;
is_imu = events.event_type == 'imu';
is_baro = events.event_type == 'baro';

accel_u_z = nan(height(events), 1);
if ekf_config.accel_is_specific_force
    accel_u_z(is_imu) = events.accel_z_mps2(is_imu) - ekf_config.gravity_mps2;
else
    accel_u_z(is_imu) = events.accel_z_mps2(is_imu);
end

baro_alt_abs = nan(height(events), 1);
baro_alt_abs(is_baro) = altitude_from_pressure_pa( ...
    events.pressure_pa(is_baro), ...
    'p0_pa', ekf_config.sea_level_pressure_pa);

launch_ref_alt = 0;
baro_mask = is_baro & isfinite(baro_alt_abs);
baro_vals  = baro_alt_abs(baro_mask);
baro_t_ref = double(events.t_flight_sec(baro_mask));
if ~isempty(baro_vals)
    % Time-based window: use only samples within launch_ref_max_time_sec of
    % the first baro reading. This correctly handles Raven flights, which
    % begin logging at ignition with no pre-launch pad phase — a 200-sample
    % window would span ~10 s of powered ascent and bias the reference ~1100 m
    % above the launch pad. A 0.5 s window captures only ground-level samples
    % for all logger families. Falls back to sample-count if param is absent.
    if isfield(ekf_config, 'launch_ref_max_time_sec') && ekf_config.launch_ref_max_time_sec > 0
        in_window  = baro_t_ref <= (baro_t_ref(1) + ekf_config.launch_ref_max_time_sec);
        ref_slice  = baro_vals(in_window);
        if isempty(ref_slice)
            ref_slice = baro_vals(1);  % always include at least the first sample
        end
    else
        n_ref     = min(numel(baro_vals), ekf_config.launch_ref_max_samples);
        ref_slice = baro_vals(1:n_ref);
    end
    if strcmpi(ekf_config.launch_ref_method, 'mean')
        launch_ref_alt = mean(ref_slice, 'omitnan');
    else
        launch_ref_alt = median(ref_slice, 'omitnan');
    end
end

baro_z = nan(height(events), 1);
if ekf_config.use_launch_relative_baro
    baro_z(is_baro) = baro_alt_abs(is_baro) - launch_ref_alt;
else
    baro_z(is_baro) = baro_alt_abs(is_baro);
end

events.accel_u_z_mps2 = accel_u_z;
events.baro_alt_abs_m = baro_alt_abs;
events.baro_z_m = baro_z;

prep = struct();
prep.flight_id = replay.flight_id;
prep.events = events;
prep.launch_ref_alt_m = launch_ref_alt;
prep.use_launch_relative_baro = logical(ekf_config.use_launch_relative_baro);

if options.verbose
    accel_mode = 'direct_accel';
    if ekf_config.accel_is_specific_force
        accel_mode = 'specific_force_minus_g';
    end
    fprintf('Prepared measurements: %s | launch_ref_alt_m=%.3f | accel_mode=%s\n', ...
        replay.flight_id, launch_ref_alt, accel_mode);
end
end
