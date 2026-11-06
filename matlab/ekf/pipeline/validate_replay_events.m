function report = validate_replay_events(replay, varargin)
% validate_replay_events
% Validate merged replay events produced by build_replay_events.
%
% Name-Value options:
%   'verbose' - print summary (default: true)

options = struct('verbose', true);
options = apply_name_value(options, varargin{:});

if ~isstruct(replay) || ~isfield(replay, 'events')
    error('replay must be a struct from build_replay_events.');
end

events = replay.events;
required = {'event_idx', 't_flight_sec', 'dt_sec', 'event_type', ...
    'accel_z_mps2', 'pressure_pa', 'baro_alt_m', 'imu_row', 'baro_row'};
for i = 1:numel(required)
    if ~ismember(required{i}, events.Properties.VariableNames)
        error('Replay events missing required column: %s', required{i});
    end
end

t = events.t_flight_sec;
dt = events.dt_sec;
is_imu = events.event_type == 'imu';
is_baro = events.event_type == 'baro';

issues = strings(0, 1);
is_valid = true;

if any(~isfinite(t))
    is_valid = false;
    issues(end + 1) = "non-finite t_flight_sec";
end
if any(diff(t) < -1e-12)
    is_valid = false;
    issues(end + 1) = "t_flight_sec decreases";
end
if any(~isfinite(dt))
    is_valid = false;
    issues(end + 1) = "non-finite dt_sec";
end
if any(dt < -1e-12)
    is_valid = false;
    issues(end + 1) = "negative dt_sec";
end
if any(is_imu & ~isfinite(events.accel_z_mps2))
    is_valid = false;
    issues(end + 1) = "non-finite IMU accel";
end
if any(is_baro & ~isfinite(events.pressure_pa))
    is_valid = false;
    issues(end + 1) = "non-finite baro pressure";
end
if any(~(is_imu | is_baro))
    is_valid = false;
    issues(end + 1) = "invalid event_type";
end
if sum(is_imu) + sum(is_baro) ~= height(events)
    is_valid = false;
    issues(end + 1) = "event row accounting mismatch";
end

report = struct();
report.flight_id = replay.flight_id;
report.is_valid = is_valid;
if isempty(issues)
    report.message = 'ok';
else
    report.message = strjoin(cellstr(issues), '; ');
end
report.total_events = height(events);
report.imu_events = sum(is_imu);
report.baro_events = sum(is_baro);
report.dt_min_sec = min(dt);
report.dt_median_sec = median(dt);
report.dt_max_sec = max(dt);

if options.verbose
    fprintf('Replay validation: %s | valid=%d | %s\n', replay.flight_id, report.is_valid, report.message);
end

if ~report.is_valid
    error('Replay validation failed for %s: %s', replay.flight_id, report.message);
end
end

