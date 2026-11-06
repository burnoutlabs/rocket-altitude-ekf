function plot_info = plot_clean_flight_overview(varargin)
% plot_clean_flight_overview
% Quick-look plotting for one cleaned flight in _data_clean/flights/.
%
% Name-Value options:
%   'cleaned_dir' - Cleaned data root (default: ../_data_clean from plotting dir)
%   'flight_id'   - 'auto' or exact flight folder id (default: 'auto')
%   'verbose'     - Print selected flight and path (default: true)

options = struct( ...
    'cleaned_dir', '', ...
    'flight_id', 'auto', ...
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

manifest_path = fullfile(options.cleaned_dir, 'cleaning_manifest.csv');
manifest = table();
if isfile(manifest_path)
    manifest = readtable(manifest_path);
end

flight_id = resolve_flight_id(options.flight_id, flights_dir, manifest);
flight_dir = fullfile(flights_dir, flight_id);
if ~isfolder(flight_dir)
    error('Requested cleaned flight directory not found: %s', flight_dir);
end

imu_path = fullfile(flight_dir, 'imu.csv');
baro_path = fullfile(flight_dir, 'baro.csv');
gps_path = fullfile(flight_dir, 'gps.csv');

if ~isfile(imu_path) || ~isfile(baro_path)
    error('Expected imu.csv and baro.csv in %s', flight_dir);
end

imu = readtable(imu_path);
baro = readtable(baro_path);
has_gps = isfile(gps_path);
if has_gps
    gps = readtable(gps_path);
else
    gps = table();
end

require_columns(imu, {'accel_z_mps2'}, imu_path);
require_columns(baro, {'pressure_pa'}, baro_path);

t_imu = select_plot_time(imu, imu_path);
t_baro = select_plot_time(baro, baro_path);

[rows_in, rows_out, dropped] = manifest_counts_for_flight(manifest, flight_id);

figure('Name', ['Clean Flight Overview: ' flight_id]);
tiled = tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
plot(t_imu, imu.accel_z_mps2, 'LineWidth', 1.0);
grid on;
ylabel('accel\_z\_mps2');

nexttile;
plot(t_baro, baro.pressure_pa, 'LineWidth', 1.0);
grid on;
ylabel('pressure\_pa');

nexttile;
if ismember('baro_alt_m_raw', baro.Properties.VariableNames)
    plot(t_baro, baro.baro_alt_m_raw, 'LineWidth', 1.0);
    ylabel('baro\_alt\_m\_raw');
else
    plot(t_baro, nan(size(t_baro)), 'LineWidth', 1.0);
    ylabel('baro\_alt\_m\_raw (missing)');
end
grid on;
xlabel('t\_flight\_sec');

title_text = sprintf('%s | IMU %d | Baro %d | GPS %d | Baro Dropped %d', ...
    flight_id, height(imu), height(baro), height(gps), dropped);
if ~isnan(rows_in) && ~isnan(rows_out)
    title_text = sprintf('%s | Manifest Baro %d->%d', title_text, rows_in, rows_out);
end
title(tiled, title_text, 'Interpreter', 'none');

if options.verbose
    fprintf('Plotted cleaned flight: %s\n', flight_id);
    fprintf('Directory: %s\n', flight_dir);
end

plot_info = struct();
plot_info.flight_id = flight_id;
plot_info.flight_dir = flight_dir;
plot_info.imu_rows = height(imu);
plot_info.baro_rows = height(baro);
plot_info.gps_rows = height(gps);
plot_info.baro_rows_in_manifest_in = rows_in;
plot_info.baro_rows_in_manifest_out = rows_out;
plot_info.baro_dropped_in_manifest = dropped;
end

function flight_id = resolve_flight_id(requested_id, flights_dir, manifest)
dirs = dir(flights_dir);
dirs = dirs([dirs.isdir]);
dirs = dirs(~ismember({dirs.name}, {'.', '..'}));
available = string({dirs.name});

if isempty(available)
    error('No cleaned flight directories found in: %s', flights_dir);
end

requested_id = string(requested_id);
if strlength(requested_id) == 0 || strcmpi(requested_id, "auto")
    from_manifest = first_processed_flight_from_manifest(manifest);
    if strlength(from_manifest) > 0 && any(strcmp(available, from_manifest))
        flight_id = char(from_manifest);
        return;
    end
    available = sort(available);
    flight_id = char(available(1));
    return;
end

if any(strcmp(available, requested_id))
    flight_id = char(requested_id);
    return;
end

error('Requested flight_id not found in _data_clean/flights: %s', requested_id);
end

function selected = first_processed_flight_from_manifest(manifest)
selected = "";
if isempty(manifest)
    return;
end
required = {'flight_id', 'status'};
if ~all(ismember(required, manifest.Properties.VariableNames))
    return;
end

flight_col = string(manifest.flight_id);
status_col = string(manifest.status);
mask = strcmpi(status_col, "processed") & strlength(flight_col) > 0;
idx = find(mask, 1, 'first');
if ~isempty(idx)
    selected = flight_col(idx);
end
end

function [baro_in, baro_out, dropped] = manifest_counts_for_flight(manifest, flight_id)
baro_in = NaN;
baro_out = NaN;
dropped = 0;

if isempty(manifest)
    return;
end
required = {'flight_id', 'baro_rows_in', 'baro_rows_out'};
if ~all(ismember(required, manifest.Properties.VariableNames))
    return;
end

flight_col = string(manifest.flight_id);
idx = find(strcmp(flight_col, string(flight_id)), 1, 'first');
if isempty(idx)
    return;
end

baro_in = manifest.baro_rows_in(idx);
baro_out = manifest.baro_rows_out(idx);
if ismember('baro_dropped_nonfinite', manifest.Properties.VariableNames) && ...
        ismember('baro_dropped_out_of_range', manifest.Properties.VariableNames) && ...
        ismember('baro_dropped_step', manifest.Properties.VariableNames)
    dropped = manifest.baro_dropped_nonfinite(idx) + ...
        manifest.baro_dropped_out_of_range(idx) + ...
        manifest.baro_dropped_step(idx);
else
    dropped = max(0, baro_in - baro_out);
end
end

function require_columns(tbl, required_cols, path_label)
for i = 1:numel(required_cols)
    if ~ismember(required_cols{i}, tbl.Properties.VariableNames)
        error('Missing column %s in %s', required_cols{i}, path_label);
    end
end
end

function t = select_plot_time(tbl, path_label)
if ismember('t_flight_sec', tbl.Properties.VariableNames)
    t = tbl.t_flight_sec;
elseif ismember('t_sec', tbl.Properties.VariableNames)
    t = tbl.t_sec;
else
    error('Missing time column in %s (expected t_flight_sec or t_sec)', path_label);
end
end
