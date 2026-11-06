function flight = load_clean_flight(varargin)
% load_clean_flight
% Load one cleaned flight (`imu.csv`, `baro.csv`, optional `gps.csv`, meta).
%
% Name-Value options:
%   'cleaned_dir' - _data_clean root (default: project/matlab/_data_clean)
%   'flight_id'   - exact folder id or 'auto' (default: 'auto')
%   'verbose'     - print selected flight/path (default: true)

options = struct( ...
    'cleaned_dir', '', ...
    'flight_id', 'auto', ...
    'verbose', true);
options = apply_name_value(options, varargin{:});

this_dir = fileparts(mfilename('fullpath'));
matlab_dir = fileparts(fileparts(this_dir));
if isempty(options.cleaned_dir)
    options.cleaned_dir = fullfile(matlab_dir, '_data_clean');
end

flight_ids = list_clean_flight_ids(options.cleaned_dir);
if isempty(flight_ids)
    error('No cleaned flights available in: %s', fullfile(options.cleaned_dir, 'flights'));
end

flight_id = resolve_flight_id(options.flight_id, options.cleaned_dir, flight_ids);
flight_dir = fullfile(options.cleaned_dir, 'flights', flight_id);

imu_path = fullfile(flight_dir, 'imu.csv');
baro_path = fullfile(flight_dir, 'baro.csv');
gps_path = fullfile(flight_dir, 'gps.csv');
meta_path = fullfile(flight_dir, 'flight_meta.json');

if ~isfile(imu_path) || ~isfile(baro_path)
    error('Missing required cleaned files in %s (expected imu.csv and baro.csv).', flight_dir);
end

imu = readtable(imu_path);
baro = readtable(baro_path);
if isfile(gps_path)
    gps = readtable(gps_path);
else
    gps = table();
end

if isfile(meta_path)
    meta = jsondecode(fileread(meta_path));
else
    meta = struct();
end

require_cols(imu, {'t_flight_sec', 'accel_z_mps2'}, imu_path);
require_cols(baro, {'t_flight_sec', 'pressure_pa'}, baro_path);

assert_monotonic_nonnegative(imu.t_flight_sec, 'imu.t_flight_sec');
assert_monotonic_nonnegative(baro.t_flight_sec, 'baro.t_flight_sec');

flight = struct();
flight.flight_id = char(flight_id);
flight.flight_dir = flight_dir;
flight.imu = imu;
flight.baro = baro;
flight.gps = gps;
flight.meta = meta;

if options.verbose
    fprintf('Loaded cleaned flight: %s\n', flight.flight_id);
    fprintf('Directory: %s\n', flight.flight_dir);
    fprintf('Rows | IMU: %d | Baro: %d | GPS: %d\n', height(imu), height(baro), height(gps));
end
end

function flight_id = resolve_flight_id(requested_id, cleaned_dir, available_ids)
requested = string(requested_id);
if strlength(requested) == 0 || strcmpi(requested, "auto")
    from_manifest = first_processed_from_manifest(cleaned_dir);
    if strlength(from_manifest) > 0 && any(strcmp(available_ids, from_manifest))
        flight_id = from_manifest;
        return;
    end
    flight_id = available_ids(1);
    return;
end

if ~any(strcmp(available_ids, requested))
    error('Requested flight_id not found in _data_clean/flights: %s', requested);
end
flight_id = requested;
end

function selected = first_processed_from_manifest(cleaned_dir)
selected = "";
manifest_path = fullfile(cleaned_dir, 'cleaning_manifest.csv');
if ~isfile(manifest_path)
    return;
end

manifest = readtable(manifest_path);
required = {'flight_id', 'status'};
if ~all(ismember(required, manifest.Properties.VariableNames))
    return;
end

flight_col = string(manifest.flight_id);
status_col = string(manifest.status);
idx = find(strcmpi(status_col, "processed") & strlength(flight_col) > 0, 1, 'first');
if ~isempty(idx)
    selected = flight_col(idx);
end
end

function require_cols(tbl, required_cols, path_label)
for i = 1:numel(required_cols)
    if ~ismember(required_cols{i}, tbl.Properties.VariableNames)
        error('Missing column %s in %s', required_cols{i}, path_label);
    end
end
end

function assert_monotonic_nonnegative(t, label)
if ~all(isfinite(t))
    error('%s must be finite.', label);
end
dt = diff(t);
if ~all(isfinite(dt)) || any(dt < 0)
    error('%s must be monotonic nondecreasing.', label);
end
if any(t < -1e-9)
    error('%s must be nonnegative.', label);
end
end
