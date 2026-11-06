function streams = parse_multi_time_csv_streams(file_path)
% parse_multi_time_csv_streams
% Parse CSV schemas with repeated 'time' columns (OnBoard/BASE/XTRA-like).

[headers, ~] = read_csv_header(file_path);
headers_l = lower(headers);

data = readmatrix(file_path, 'NumHeaderLines', 1, 'OutputType', 'double');
if isempty(data)
    error('No numeric data rows found in %s', file_path);
end

row_raw = (1:size(data, 1)).';

idx_acc_v = find(strcmp(headers_l, 'acceleration'), 1, 'first');
idx_baro_v = find(strcmp(headers_l, 'pressure'), 1, 'first');

if isempty(idx_acc_v) || isempty(idx_baro_v)
    error('Missing acceleration or pressure column in %s', file_path);
end

idx_acc_t = find_time_column_before(headers_l, idx_acc_v);
idx_baro_t = find_time_column_before(headers_l, idx_baro_v);

if isempty(idx_acc_t) || isempty(idx_baro_t)
    error('Missing paired time columns in %s', file_path);
end

if idx_acc_t > size(data, 2) || idx_acc_v > size(data, 2) || idx_baro_t > size(data, 2) || idx_baro_v > size(data, 2)
    error('Detected required columns exceed matrix width in %s', file_path);
end

acc_t = data(:, idx_acc_t);
acc_g = data(:, idx_acc_v);

baro_t = data(:, idx_baro_t);
baro_pa = data(:, idx_baro_v);

baro_alt_m_raw = NaN(size(baro_pa));
idx_pressure_agl = find(strcmp(headers_l, 'pressure agl'), 1, 'first');
if ~isempty(idx_pressure_agl) && idx_pressure_agl <= size(data, 2)
    baro_alt_m_raw = data(:, idx_pressure_agl);
end

streams = struct();
streams.imu = struct(...
    't_raw', acc_t, ...
    'value_raw', acc_g * 9.80665, ...
    'source_row_raw', row_raw);

streams.baro = struct(...
    't_raw', baro_t, ...
    'pressure_raw', baro_pa, ...
    'alt_raw', baro_alt_m_raw, ...
    'source_row_raw', row_raw);

streams.gps = [];

idx_lat = find(strcmp(headers_l, 'lat'), 1, 'first');
idx_lon = find(strcmp(headers_l, 'long'), 1, 'first');
idx_gps_alt = find(strcmp(headers_l, 'gps msl'), 1, 'first');
idx_svs = find(strcmp(headers_l, 'svs'), 1, 'first');

if ~isempty(idx_lat) && ~isempty(idx_lon) && idx_lat <= size(data, 2) && idx_lon <= size(data, 2)
    idx_gps_t = find_time_column_before(headers_l, idx_lat);
    if ~isempty(idx_gps_t) && idx_gps_t <= size(data, 2)
        gps_alt = NaN(size(row_raw));
        if ~isempty(idx_gps_alt) && idx_gps_alt <= size(data, 2)
            gps_alt = data(:, idx_gps_alt);
        end

        gps_sats = NaN(size(row_raw));
        if ~isempty(idx_svs) && idx_svs <= size(data, 2)
            gps_sats = data(:, idx_svs);
        end

        streams.gps = struct(...
            't_raw', data(:, idx_gps_t), ...
            'lat_raw', data(:, idx_lat), ...
            'lon_raw', data(:, idx_lon), ...
            'alt_raw', gps_alt, ...
            'sats_raw', gps_sats, ...
            'source_row_raw', row_raw);
    end
end
end

function time_idx = find_time_column_before(headers_l, value_idx)
if isempty(value_idx) || value_idx <= 1
    time_idx = [];
    return;
end

candidate = find(strcmp(headers_l(1:(value_idx - 1)), 'time'), 1, 'last');
if isempty(candidate)
    time_idx = [];
else
    time_idx = candidate;
end
end
