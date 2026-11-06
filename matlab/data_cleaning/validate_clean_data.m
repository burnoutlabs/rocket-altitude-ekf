function report_table = validate_clean_data(varargin)
% validate_clean_data
% Validate cleaned flight streams in _data_clean.
%
% Name-Value options:
%   'cleaned_dir'         - Cleaned data root (default: ../_data_clean)
%   'strict'              - Throw on any invalid flight (default: true)
%   'min_finite_ratio'    - Minimum finite ratio for key columns (default: 0.99)
%   'min_pressure_pa'     - Minimum allowed pressure (default: 20000)
%   'max_pressure_pa'     - Maximum allowed pressure (default: 120000)
%   'verbose'             - Print summary (default: true)

options = struct(...
    'cleaned_dir', '', ...
    'strict', true, ...
    'min_finite_ratio', 0.99, ...
    'min_pressure_pa', 20000, ...
    'max_pressure_pa', 120000, ...
    'verbose', true);

options = apply_name_value(options, varargin{:});

this_dir = fileparts(mfilename('fullpath'));
matlab_dir = fileparts(this_dir);
if isempty(options.cleaned_dir)
    options.cleaned_dir = fullfile(matlab_dir, '_data_clean');
end

flights_dir = fullfile(options.cleaned_dir, 'flights');
if ~isfolder(flights_dir)
    error('Cleaned flights directory not found: %s', flights_dir);
end

entries = dir(flights_dir);
entries = entries([entries.isdir]);
entries = entries(~ismember({entries.name}, {'.', '..'}));

rows = cell(numel(entries), 13);
valid_count = 0;

for i = 1:numel(entries)
    flight_id = entries(i).name;
    flight_dir = fullfile(flights_dir, flight_id);

    [is_valid, message, imu_rows, baro_rows, gps_rows, imu_ratio, baro_ratio, imu_mono, baro_mono, imu_t0_ok, baro_t0_ok, baro_range_ok] = ...
        validate_one_clean_flight(flight_dir, options);

    rows(i, :) = { ...
        flight_id, is_valid, message, ...
        imu_rows, baro_rows, gps_rows, ...
        imu_ratio, baro_ratio, ...
        imu_mono, baro_mono, ...
        imu_t0_ok, baro_t0_ok, baro_range_ok};

    if is_valid
        valid_count = valid_count + 1;
    end
end

report_table = cell2table(rows, 'VariableNames', {...
    'flight_id', 'is_valid', 'message', ...
    'imu_rows', 'baro_rows', 'gps_rows', ...
    'imu_finite_ratio', 'baro_finite_ratio', ...
    'imu_time_monotonic', 'baro_time_monotonic', ...
    'imu_starts_at_zero', 'baro_starts_at_zero', 'baro_range_ok'});

report_path = fullfile(options.cleaned_dir, 'clean_validation_report.csv');
writetable(report_table, report_path);

if options.verbose
    fprintf('Clean validation complete: %d/%d flights valid\n', valid_count, numel(entries));
    fprintf('Report: %s\n', report_path);
end

if options.strict && any(~report_table.is_valid)
    bad = report_table.flight_id(~report_table.is_valid);
    error('Clean validation failed for flights: %s', strjoin(bad, ', '));
end
end

function [is_valid, message, imu_rows, baro_rows, gps_rows, imu_ratio, baro_ratio, imu_mono, baro_mono, imu_t0_ok, baro_t0_ok, baro_range_ok] = ...
    validate_one_clean_flight(flight_dir, options)

imu_path = fullfile(flight_dir, 'imu.csv');
baro_path = fullfile(flight_dir, 'baro.csv');
gps_path = fullfile(flight_dir, 'gps.csv');

is_valid = true;
issues = {};

imu_rows = 0; baro_rows = 0; gps_rows = 0;
imu_ratio = 0; baro_ratio = 0;
imu_mono = false; baro_mono = false;
imu_t0_ok = false; baro_t0_ok = false;
baro_range_ok = false;

if ~isfile(imu_path)
    is_valid = false;
    issues{end+1} = 'missing imu.csv';
else
    [ok, msg, imu_rows, imu_ratio, imu_mono, imu_t0_ok] = check_stream_file(imu_path, 'accel_z_mps2', options.min_finite_ratio);
    if ~ok
        is_valid = false;
        issues{end+1} = ['imu: ' msg];
    end
end

if ~isfile(baro_path)
    is_valid = false;
    issues{end+1} = 'missing baro.csv';
else
    [ok, msg, baro_rows, baro_ratio, baro_mono, baro_t0_ok] = check_stream_file(baro_path, 'pressure_pa', options.min_finite_ratio);
    if ~ok
        is_valid = false;
        issues{end+1} = ['baro: ' msg];
    end

    baro_tbl = readtable(baro_path);
    p = baro_tbl.pressure_pa;
    baro_range_ok = all(p >= options.min_pressure_pa & p <= options.max_pressure_pa);
    if ~baro_range_ok
        is_valid = false;
        issues{end+1} = 'baro pressure out of configured range';
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

required_cols = {'t_flight_sec', 't_sensor_raw_sec', 't_sec', value_col};
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
