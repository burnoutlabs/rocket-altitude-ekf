function report_table = validate_normalized_data(varargin)
% validate_normalized_data
% Validate normalized flight outputs produced by run_normalization_pipeline.
%
% Name-Value options:
%   'normalized_dir'   - normalized output root (default: ../_data_normalized)
%   'strict'           - throw error if any flight invalid (default: true)
%   'min_finite_ratio' - required finite ratio for key value columns (default: 0.95)
%   'verbose'          - print summary (default: true)

options = struct(...
    'normalized_dir', '', ...
    'strict', true, ...
    'min_finite_ratio', 0.95, ...
    'verbose', true);

options = apply_name_value(options, varargin{:});

this_dir = fileparts(mfilename('fullpath'));
matlab_dir = fileparts(this_dir);
if isempty(options.normalized_dir)
    options.normalized_dir = fullfile(matlab_dir, '_data_normalized');
end

flights_dir = fullfile(options.normalized_dir, 'flights');
if ~isfolder(flights_dir)
    error('Flights directory not found: %s', flights_dir);
end

entries = dir(flights_dir);
entries = entries([entries.isdir]);
entries = entries(~ismember({entries.name}, {'.', '..'}));

rows = cell(numel(entries), 11);
valid_count = 0;

for i = 1:numel(entries)
    flight_id = entries(i).name;
    flight_dir = fullfile(flights_dir, flight_id);

    [is_valid, message, imu_rows, baro_rows, gps_rows, imu_ratio, baro_ratio, imu_mono, baro_mono, imu_t0_ok, baro_t0_ok] = ...
        validate_flight_dir(flight_dir, options.min_finite_ratio);

    rows(i, :) = { ...
        flight_id, ...
        is_valid, ...
        message, ...
        imu_rows, ...
        baro_rows, ...
        gps_rows, ...
        imu_ratio, ...
        baro_ratio, ...
        imu_mono, ...
        baro_mono, ...
        imu_t0_ok && baro_t0_ok};

    if is_valid
        valid_count = valid_count + 1;
    end
end

report_table = cell2table(rows, 'VariableNames', {...
    'flight_id', 'is_valid', 'message', ...
    'imu_rows', 'baro_rows', 'gps_rows', ...
    'imu_finite_ratio', 'baro_finite_ratio', ...
    'imu_time_monotonic', 'baro_time_monotonic', 'time_starts_at_zero'});

report_path = fullfile(options.normalized_dir, 'normalization_validation_report.csv');
writetable(report_table, report_path);

if options.verbose
    fprintf('Validation complete: %d/%d flights valid\n', valid_count, numel(entries));
    fprintf('Report: %s\n', report_path);
end

if options.strict && any(~report_table.is_valid)
    invalid_flights = report_table.flight_id(~report_table.is_valid);
    error('Validation failed for flights: %s', strjoin(invalid_flights, ', '));
end
end

function [is_valid, message, imu_rows, baro_rows, gps_rows, imu_ratio, baro_ratio, imu_mono, baro_mono, imu_t0_ok, baro_t0_ok] = ...
    validate_flight_dir(flight_dir, min_finite_ratio)

imu_path = fullfile(flight_dir, 'imu.csv');
baro_path = fullfile(flight_dir, 'baro.csv');
gps_path = fullfile(flight_dir, 'gps.csv');

is_valid = true;
issues = {};

imu_rows = 0;
baro_rows = 0;
gps_rows = 0;
imu_ratio = 0;
baro_ratio = 0;
imu_mono = false;
baro_mono = false;
imu_t0_ok = false;
baro_t0_ok = false;

if ~isfile(imu_path)
    is_valid = false;
    issues{end + 1} = 'missing imu.csv';
else
    [ok, msg, imu_rows, imu_ratio, imu_mono, imu_t0_ok] = check_stream_file(imu_path, 'accel_z_mps2', min_finite_ratio);
    if ~ok
        is_valid = false;
        issues{end + 1} = ['imu: ' msg];
    end
end

if ~isfile(baro_path)
    is_valid = false;
    issues{end + 1} = 'missing baro.csv';
else
    [ok, msg, baro_rows, baro_ratio, baro_mono, baro_t0_ok] = check_stream_file(baro_path, 'pressure_pa', min_finite_ratio);
    if ~ok
        is_valid = false;
        issues{end + 1} = ['baro: ' msg];
    end
end

if isfile(gps_path)
    gps_tbl = readtable(gps_path);
    gps_rows = height(gps_tbl);
end

if isempty(issues)
    message = 'ok';
else
    message = strjoin(issues, '; ');
end
end

function [ok, msg, n_rows, finite_ratio, t_monotonic, t0_ok] = check_stream_file(csv_path, value_col, min_finite_ratio)
ok = true;
msg = 'ok';

tbl = readtable(csv_path);
n_rows = height(tbl);

required_cols = {'t_flight_sec', 't_sensor_raw_sec', 't_sec', value_col, 'source_row'};
for i = 1:numel(required_cols)
    if ~ismember(required_cols{i}, tbl.Properties.VariableNames)
        ok = false;
        msg = ['missing column ' required_cols{i}];
        finite_ratio = 0;
        t_monotonic = false;
        t0_ok = false;
        return;
    end
end

if n_rows == 0
    ok = false;
    msg = 'empty file';
    finite_ratio = 0;
    t_monotonic = false;
    t0_ok = false;
    return;
end

t = tbl.t_flight_sec;
v = tbl.(value_col);

finite_ratio = mean(isfinite(v));
t_finite = all(isfinite(t));
dt = diff(t);
t_monotonic = t_finite && all(isfinite(dt)) && all(dt >= 0);
t0_ok = t_finite && abs(t(1)) <= 1e-9;
t_nonnegative = t_finite && all(t >= -1e-9);

% Enforce legacy compatibility alias consistency.
alias_ok = all(isfinite(tbl.t_sec)) && all(abs(tbl.t_sec - tbl.t_flight_sec) <= 1e-9);
if ~alias_ok
    ok = false;
    msg = 't_sec alias does not match t_flight_sec';
    return;
end

if ~t_monotonic
    ok = false;
    msg = 't_flight_sec must be finite and monotonic nondecreasing';
    return;
end

if ~t_nonnegative
    ok = false;
    msg = 't_flight_sec must be nonnegative';
    return;
end

if finite_ratio < min_finite_ratio
    ok = false;
    msg = sprintf('finite ratio %.4f < %.4f', finite_ratio, min_finite_ratio);
    return;
end
end

function out = apply_name_value(defaults, varargin)
out = defaults;
if mod(numel(varargin), 2) ~= 0
    error('Name-value arguments must be provided in pairs.');
end
for i = 1:2:numel(varargin)
    name = varargin{i};
    value = varargin{i + 1};
    if ~ischar(name) && ~isstring(name)
        error('Option names must be char or string.');
    end
    key = char(name);
    if ~isfield(out, key)
        error('Unknown option: %s', key);
    end
    out.(key) = value;
end
end
