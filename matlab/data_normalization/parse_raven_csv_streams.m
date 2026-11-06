function streams = parse_raven_csv_streams(file_path)
% parse_raven_csv_streams
% Parse Raven CSV schema (Time@... headers).

[headers, ~] = read_csv_header(file_path);
headers_l = lower(headers);

idx_acc_t = find(strcmp(headers_l, lower('Time@Axial Accel (Gs)')), 1, 'first');
idx_acc_v = find(strcmp(headers_l, lower('Axial Accel (Gs)')), 1, 'first');
idx_baro_t = find(strcmp(headers_l, lower('Time@Baro (Atm)')), 1, 'first');
idx_baro_v = find(strcmp(headers_l, lower('Baro (Atm)')), 1, 'first');
idx_alt_ft_agl = find(strcmp(headers_l, lower('[Altitude (Baro-Ft-AGL)]')), 1, 'first');

if isempty(idx_acc_t) || isempty(idx_acc_v) || isempty(idx_baro_t) || isempty(idx_baro_v)
    error('Missing required Raven columns in %s', file_path);
end

data = readmatrix(file_path, 'NumHeaderLines', 1, 'OutputType', 'double');
if isempty(data)
    error('No numeric data rows found in %s', file_path);
end

row_raw = (1:size(data, 1)).';

acc_t = data(:, idx_acc_t);
acc_g = data(:, idx_acc_v);

baro_t = data(:, idx_baro_t);
baro_atm = data(:, idx_baro_v);

baro_alt_m_raw = NaN(size(baro_atm));
if ~isempty(idx_alt_ft_agl) && idx_alt_ft_agl <= size(data, 2)
    baro_alt_m_raw = data(:, idx_alt_ft_agl) * 0.3048;
end

streams = struct();
streams.imu = struct(...
    't_raw', acc_t, ...
    'value_raw', acc_g * 9.80665, ...
    'source_row_raw', row_raw);

streams.baro = struct(...
    't_raw', baro_t, ...
    'pressure_raw', baro_atm * 101325.0, ...
    'alt_raw', baro_alt_m_raw, ...
    'source_row_raw', row_raw);

streams.gps = [];
end
