function streams = parse_emulation_csv_streams(file_path)
% parse_emulation_csv_streams
% Parse emulation CSV schema with SI units and pressure altitude.

[headers, ~] = read_csv_header(file_path);
headers_l = lower(headers);

data = readmatrix(file_path, 'NumHeaderLines', 1, 'OutputType', 'double');
if isempty(data)
    error('No numeric data rows found in %s', file_path);
end

row_raw = (1:size(data, 1)).';

idx_t = find(strcmp(headers_l, lower('Time[s]')), 1, 'first');
idx_acc_z = find(strcmp(headers_l, lower('Acceleration z [m/s^2]')), 1, 'first');
idx_alt_m = find(strcmp(headers_l, lower('Pressure altitude [m]')), 1, 'first');
idx_gps_alt = find(strcmp(headers_l, lower('GPS altitude [m]')), 1, 'first');
idx_gps_valid = find(strcmp(headers_l, lower('GPS Valid')), 1, 'first');

if isempty(idx_t) || isempty(idx_acc_z) || isempty(idx_alt_m)
    error('Missing required emulation columns in %s', file_path);
end

if any([idx_t idx_acc_z idx_alt_m] > size(data, 2))
    error('Detected required columns exceed matrix width in %s', file_path);
end

t = data(:, idx_t);
acc_z = data(:, idx_acc_z);
baro_alt_m = data(:, idx_alt_m);
baro_pa = pressure_from_altitude_m(baro_alt_m);

streams = struct();
streams.imu = struct(...
    't_raw', t, ...
    'value_raw', acc_z, ...
    'source_row_raw', row_raw);

streams.baro = struct(...
    't_raw', t, ...
    'pressure_raw', baro_pa, ...
    'alt_raw', baro_alt_m, ...
    'source_row_raw', row_raw);

streams.gps = [];
if ~isempty(idx_gps_alt) && idx_gps_alt <= size(data, 2)
    gps_alt = data(:, idx_gps_alt);
    if ~isempty(idx_gps_valid) && idx_gps_valid <= size(data, 2)
        gps_valid = data(:, idx_gps_valid);
        gps_alt(gps_valid <= 0) = NaN;
    end

    streams.gps = struct(...
        't_raw', t, ...
        'lat_raw', NaN(size(t)), ...
        'lon_raw', NaN(size(t)), ...
        'alt_raw', gps_alt, ...
        'sats_raw', NaN(size(t)), ...
        'source_row_raw', row_raw);
end
end

function pressure_pa = pressure_from_altitude_m(altitude_m)
p0 = 101325.0;
scale_height_m = 8434.5;

pressure_pa = p0 * exp(-altitude_m ./ scale_height_m);
pressure_pa(~isfinite(pressure_pa)) = NaN;
end
