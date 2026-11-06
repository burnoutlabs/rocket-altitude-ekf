function result = normalize_one_file(raw_file_path, flights_dir, parser_config, overwrite_outputs)
% normalize_one_file
% Normalize one raw input file into canonical imu/baro/gps streams.

if nargin < 3 || isempty(parser_config) || isempty(fieldnames(parser_config))
    parser_config = default_parser_config();
end
if nargin < 4
    overwrite_outputs = false;
end

[raw_parent, raw_stem, raw_ext] = fileparts(raw_file_path);
raw_name = [raw_stem raw_ext];

result = struct(...
    'family', '', ...
    'status', 'failed', ...
    'message', '', ...
    'processed', false, ...
    'flight_id', '', ...
    'imu_rows', 0, ...
    'baro_rows', 0, ...
    'gps_rows', 0, ...
    'output_dir', '');

family = detect_schema_family(raw_file_path);
result.family = family;

skip_families = ["empty", "xtra", "xlsx", "manifest_csv", "gps_csv", "tracker_csv", "unknown_csv", "unsupported_txt", "unsupported"];
if any(string(family) == skip_families)
    result.status = 'skipped';
    result.message = sprintf('Family %s is not part of v1 EKF normalization.', family);
    return;
end

flight_id = sanitize_flight_id(sprintf('%s_%s', family, raw_stem));
flight_dir = fullfile(flights_dir, flight_id);
result.flight_id = flight_id;
result.output_dir = flight_dir;

if ~overwrite_outputs && is_existing_normalized_flight(flight_dir)
    result.status = 'skipped';
    result.message = 'normalized output already exists; set overwrite_outputs=true to regenerate.';
    result.imu_rows = safe_table_height(fullfile(flight_dir, 'imu.csv'));
    result.baro_rows = safe_table_height(fullfile(flight_dir, 'baro.csv'));
    result.gps_rows = safe_table_height(fullfile(flight_dir, 'gps.csv'));
    return;
end

try
    switch family
        case 'raven_csv'
            streams = parse_raven_csv_streams(raw_file_path);
        case 'multi_time_csv'
            streams = parse_multi_time_csv_streams(raw_file_path);
        case 'emulation_csv'
            streams = parse_emulation_csv_streams(raw_file_path);
        case 'trimmed_txt'
            streams = parse_trimmed_txt_streams(raw_file_path, parser_config);
        otherwise
            result.status = 'skipped';
            result.message = sprintf('Unsupported schema family: %s', family);
            return;
    end

    imu_norm = normalize_numeric_stream(streams.imu.t_raw, streams.imu.value_raw, streams.imu.source_row_raw);
    baro_norm = normalize_numeric_stream(streams.baro.t_raw, streams.baro.pressure_raw, streams.baro.source_row_raw);

    if isempty(imu_norm.t_sensor_raw_sec)
        result.status = 'failed';
        result.message = 'IMU stream is empty after normalization.';
        return;
    end
    if isempty(baro_norm.t_sensor_raw_sec)
        result.status = 'failed';
        result.message = 'Baro stream is empty after normalization.';
        return;
    end

    baro_alt_m_raw = NaN(numel(baro_norm.t_sensor_raw_sec), 1);
    if isfield(streams.baro, 'alt_raw') && numel(streams.baro.alt_raw) == numel(streams.baro.t_raw)
        baro_alt_m_raw = streams.baro.alt_raw(baro_norm.kept_input_indices);
    end

    gps_norm = struct('t_sensor_raw_sec', [], 'lat_deg', [], 'lon_deg', [], 'gps_alt_m', [], 'num_sats', [], 'source_row', []);
    if isfield(streams, 'gps') && ~isempty(streams.gps)
        gps_norm = normalize_gps_stream(streams.gps);
    end

    % Canonical time contract:
    % - t_sensor_raw_sec: sensor timeline after cleanup/sort/dedup
    % - t_flight_sec: common flight timeline based on earliest stream time
    % - t_sec: compatibility alias to t_flight_sec
    time_starts = [imu_norm.t_sensor_raw_sec(1); baro_norm.t_sensor_raw_sec(1)];
    if ~isempty(gps_norm.t_sensor_raw_sec)
        time_starts(end + 1, 1) = gps_norm.t_sensor_raw_sec(1);
    end
    flight_t0_sec = min(time_starts);

    imu_t_flight = imu_norm.t_sensor_raw_sec - flight_t0_sec;
    baro_t_flight = baro_norm.t_sensor_raw_sec - flight_t0_sec;
    gps_t_flight = gps_norm.t_sensor_raw_sec - flight_t0_sec;

    if isfolder(flight_dir)
        rmdir(flight_dir, 's');
    end
    mkdir(flight_dir);

    n_imu = numel(imu_norm.t_sensor_raw_sec);
    n_baro = numel(baro_norm.t_sensor_raw_sec);
    n_gps = numel(gps_norm.t_sensor_raw_sec);

    imu_tbl = table(...
        imu_t_flight, ...
        imu_norm.t_sensor_raw_sec, ...
        imu_t_flight, ...
        imu_norm.value, ...
        repmat({family}, n_imu, 1), ...
        repmat({raw_name}, n_imu, 1), ...
        imu_norm.source_row, ...
        'VariableNames', {'t_flight_sec', 't_sensor_raw_sec', 't_sec', 'accel_z_mps2', 'source_family', 'source_file', 'source_row'});

    baro_tbl = table(...
        baro_t_flight, ...
        baro_norm.t_sensor_raw_sec, ...
        baro_t_flight, ...
        baro_norm.value, ...
        baro_alt_m_raw, ...
        repmat({family}, n_baro, 1), ...
        repmat({raw_name}, n_baro, 1), ...
        baro_norm.source_row, ...
        'VariableNames', {'t_flight_sec', 't_sensor_raw_sec', 't_sec', 'pressure_pa', 'baro_alt_m_raw', 'source_family', 'source_file', 'source_row'});

    writetable(imu_tbl, fullfile(flight_dir, 'imu.csv'));
    writetable(baro_tbl, fullfile(flight_dir, 'baro.csv'));

    if n_gps > 0
        gps_tbl = table(...
            gps_t_flight, ...
            gps_norm.t_sensor_raw_sec, ...
            gps_t_flight, ...
            gps_norm.gps_alt_m, ...
            gps_norm.lat_deg, ...
            gps_norm.lon_deg, ...
            gps_norm.num_sats, ...
            repmat({family}, n_gps, 1), ...
            repmat({raw_name}, n_gps, 1), ...
            gps_norm.source_row, ...
            'VariableNames', {'t_flight_sec', 't_sensor_raw_sec', 't_sec', 'gps_alt_m', 'lat_deg', 'lon_deg', 'num_sats', 'source_family', 'source_file', 'source_row'});
        writetable(gps_tbl, fullfile(flight_dir, 'gps.csv'));
    end

    meta = struct();
    meta.flight_id = flight_id;
    meta.family = family;
    meta.raw_file = raw_name;
    meta.raw_dir = raw_parent;
    meta.imu_rows = n_imu;
    meta.baro_rows = n_baro;
    meta.gps_rows = n_gps;
    meta.flight_time_origin_sec = flight_t0_sec;
    meta.time_contract = struct(...
        'primary_time_col', 't_flight_sec', ...
        'sensor_time_col', 't_sensor_raw_sec', ...
        'legacy_time_alias', 't_sec');
    meta.parser_version = 'v2_time_contract';
    meta.notes = 'Generated by run_normalization_pipeline';

    meta_path = fullfile(flight_dir, 'flight_meta.json');
    fid = fopen(meta_path, 'w');
    if fid == -1
        error('Unable to write metadata file: %s', meta_path);
    end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(meta));

    result.status = 'processed';
    result.message = 'ok';
    result.processed = true;
    result.imu_rows = n_imu;
    result.baro_rows = n_baro;
    result.gps_rows = n_gps;

catch ME
    result.status = 'failed';
    result.message = ME.message;
end
end

function config = default_parser_config()
config = struct();
config.trimmed_txt_default_axis = 'ya';
config.trimmed_txt_axis_overrides = struct('pattern', {}, 'axis', {});
end

function out = normalize_numeric_stream(t_raw, value_raw, source_row_raw)
out = struct(...
    't_sensor_raw_sec', [], ...
    'value', [], ...
    'source_row', [], ...
    'kept_input_indices', [], ...
    'dropped_count', 0);

if isempty(t_raw) || isempty(value_raw)
    return;
end

t = t_raw(:);
v = value_raw(:);

if nargin < 3 || isempty(source_row_raw)
    r = (1:numel(t)).';
else
    r = source_row_raw(:);
end

n = numel(t);
valid = isfinite(t) & isfinite(v);
kept = find(valid);

t = t(valid);
v = v(valid);
r = r(valid);

if isempty(t)
    out.dropped_count = n;
    return;
end

[t, order] = sort(t, 'ascend');
v = v(order);
r = r(order);
kept = kept(order);

[t_unique, ia] = unique(t, 'last');
v_unique = v(ia);
r_unique = r(ia);
kept_unique = kept(ia);

out.t_sensor_raw_sec = t_unique;
out.value = v_unique;
out.source_row = r_unique;
out.kept_input_indices = kept_unique;
out.dropped_count = n - numel(out.t_sensor_raw_sec);
end

function out = normalize_gps_stream(gps_raw)
out = struct(...
    't_sensor_raw_sec', [], ...
    'gps_alt_m', [], ...
    'lat_deg', [], ...
    'lon_deg', [], ...
    'num_sats', [], ...
    'source_row', []);

if isempty(gps_raw)
    return;
end

t = gps_raw.t_raw(:);
lat = gps_raw.lat_raw(:);
lon = gps_raw.lon_raw(:);

if isfield(gps_raw, 'alt_raw')
    alt = gps_raw.alt_raw(:);
else
    alt = NaN(size(t));
end

if isfield(gps_raw, 'sats_raw')
    sats = gps_raw.sats_raw(:);
else
    sats = NaN(size(t));
end

if isfield(gps_raw, 'source_row_raw')
    row_raw = gps_raw.source_row_raw(:);
else
    row_raw = (1:numel(t)).';
end

valid = isfinite(t) & isfinite(lat) & isfinite(lon);
t = t(valid);
lat = lat(valid);
lon = lon(valid);
alt = alt(valid);
sats = sats(valid);
row_raw = row_raw(valid);

if isempty(t)
    return;
end

[t, order] = sort(t, 'ascend');
lat = lat(order);
lon = lon(order);
alt = alt(order);
sats = sats(order);
row_raw = row_raw(order);

[t_unique, ia] = unique(t, 'last');
lat = lat(ia);
lon = lon(ia);
alt = alt(ia);
sats = sats(ia);
row_raw = row_raw(ia);

out.t_sensor_raw_sec = t_unique;
out.gps_alt_m = alt;
out.lat_deg = lat;
out.lon_deg = lon;
out.num_sats = sats;
out.source_row = row_raw;
end

function family = detect_schema_family(file_path)
family = 'unsupported';

if ~isfile(file_path)
    return;
end

info = dir(file_path);
if info.bytes == 0
    family = 'empty';
    return;
end

[~, ~, ext] = fileparts(file_path);
ext = lower(ext);

switch ext
    case '.txt'
        if contains(lower(file_path), 'trimmed')
            family = 'trimmed_txt';
        else
            family = 'unsupported_txt';
        end

    case '.xlsx'
        family = 'xlsx';

    case '.xtra'
        family = 'xtra';

    case '.csv'
        [~, header_line] = read_csv_header(file_path);
        h = lower(strtrim(header_line));

        if contains(h, 'time@axial accel (gs)') && contains(h, 'time@baro (atm)')
            family = 'raven_csv';
        elseif contains(h, 'time[s]') && contains(h, 'pressure altitude [m]')
            family = 'emulation_csv';
        elseif strcmp(h, 'url,file_name,status,bytes,message')
            family = 'manifest_csv';
        elseif contains(h, 'utctime,unixtime,alt,lat,lon')
            family = 'gps_csv';
        elseif startsWith(h, 'tracker,date,time,lat,lon,alt')
            family = 'tracker_csv';
        elseif contains(h, ',acceleration,') && contains(h, ',pressure,') && contains(h, 'time')
            family = 'multi_time_csv';
        else
            family = 'unknown_csv';
        end

    otherwise
        family = 'unsupported';
end
end

function flight_id = sanitize_flight_id(raw_name)
flight_id = lower(char(raw_name));
flight_id = regexprep(flight_id, '[^a-z0-9]+', '_');
flight_id = regexprep(flight_id, '_+', '_');
flight_id = regexprep(flight_id, '^_+|_+$', '');
if isempty(flight_id)
    flight_id = 'flight';
end
end

function tf = is_existing_normalized_flight(flight_dir)
imu_path = fullfile(flight_dir, 'imu.csv');
baro_path = fullfile(flight_dir, 'baro.csv');
tf = isfolder(flight_dir) && isfile(imu_path) && isfile(baro_path);
end

function n = safe_table_height(csv_path)
n = 0;
if ~isfile(csv_path)
    return;
end
try
    n = height(readtable(csv_path));
catch
    n = 0;
end
end
