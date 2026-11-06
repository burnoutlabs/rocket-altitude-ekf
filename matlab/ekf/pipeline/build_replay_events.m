function replay = build_replay_events(flight, varargin)
% build_replay_events
% Merge cleaned IMU + baro streams into one deterministic event replay.
%
% Inputs:
%   flight   - struct from load_clean_flight (must include imu, baro, flight_id)
%
% Name-Value options:
%   'p0_pa'   - sea-level pressure for derived altitude (default: 101325)
%   'verbose' - print summary (default: true)
%
% Output struct fields:
%   replay.flight_id
%   replay.events table with columns:
%     event_idx, t_flight_sec, dt_sec, event_type, accel_z_mps2, pressure_pa,
%     baro_alt_m, imu_row, baro_row
%   replay.summary struct

options = struct( ...
    'p0_pa', 101325, ...
    'verbose', true);
options = apply_name_value(options, varargin{:});

if ~isstruct(flight) || ~isfield(flight, 'imu') || ~isfield(flight, 'baro')
    error('flight must be a struct returned by load_clean_flight.');
end

imu = flight.imu;
baro = flight.baro;

required_imu = {'t_flight_sec', 'accel_z_mps2'};
required_baro = {'t_flight_sec', 'pressure_pa'};
for i = 1:numel(required_imu)
    if ~ismember(required_imu{i}, imu.Properties.VariableNames)
        error('IMU missing required column: %s', required_imu{i});
    end
end
for i = 1:numel(required_baro)
    if ~ismember(required_baro{i}, baro.Properties.VariableNames)
        error('Baro missing required column: %s', required_baro{i});
    end
end

t_imu = double(imu.t_flight_sec);
t_baro = double(baro.t_flight_sec);
a_imu = double(imu.accel_z_mps2);
p_baro = double(baro.pressure_pa);

n_imu = numel(t_imu);
n_baro = numel(t_baro);
n_total = n_imu + n_baro;

baro_alt_source = nan(size(p_baro));
if ismember('baro_alt_m_raw', baro.Properties.VariableNames)
    baro_alt_source = double(baro.baro_alt_m_raw);
end
mask_missing_alt = ~isfinite(baro_alt_source);
if any(mask_missing_alt)
    baro_alt_source(mask_missing_alt) = altitude_from_pressure_pa(p_baro(mask_missing_alt), 'p0_pa', options.p0_pa);
end

event_idx = (1:n_total)';
t = zeros(n_total, 1);
event_type = strings(n_total, 1);
accel = nan(n_total, 1);
pressure = nan(n_total, 1);
baro_alt = nan(n_total, 1);
imu_row = nan(n_total, 1);
baro_row = nan(n_total, 1);

i = 1;
j = 1;
k = 1;
while i <= n_imu || j <= n_baro
    use_imu = false;
    if i <= n_imu && j <= n_baro
        if t_imu(i) <= t_baro(j)
            use_imu = true; % deterministic tie-break: IMU first
        end
    elseif i <= n_imu
        use_imu = true;
    end

    if use_imu
        t(k) = t_imu(i);
        event_type(k) = "imu";
        accel(k) = a_imu(i);
        imu_row(k) = i;
        i = i + 1;
    else
        t(k) = t_baro(j);
        event_type(k) = "baro";
        pressure(k) = p_baro(j);
        baro_alt(k) = baro_alt_source(j);
        baro_row(k) = j;
        j = j + 1;
    end
    k = k + 1;
end

dt = [0; diff(t)];
dt(~isfinite(dt)) = 0;
dt(dt < 0) = 0; % guard against numeric epsilon

events = table( ...
    event_idx, ...
    t, ...
    dt, ...
    categorical(event_type, {'imu', 'baro'}), ...
    accel, ...
    pressure, ...
    baro_alt, ...
    imu_row, ...
    baro_row, ...
    'VariableNames', {'event_idx', 't_flight_sec', 'dt_sec', 'event_type', ...
    'accel_z_mps2', 'pressure_pa', 'baro_alt_m', 'imu_row', 'baro_row'});

summary = struct();
summary.flight_id = flight.flight_id;
summary.total_events = n_total;
summary.imu_events = n_imu;
summary.baro_events = n_baro;
summary.t_start_sec = t(1);
summary.t_end_sec = t(end);
summary.duration_sec = t(end) - t(1);
summary.dt_min_sec = min(dt);
summary.dt_median_sec = median(dt);
summary.dt_max_sec = max(dt);

replay = struct();
replay.flight_id = flight.flight_id;
replay.events = events;
replay.summary = summary;

if options.verbose
    fprintf('Replay built: %s | events=%d (imu=%d, baro=%d) | t=[%.3f, %.3f] s\n', ...
        flight.flight_id, n_total, n_imu, n_baro, summary.t_start_sec, summary.t_end_sec);
end
end

