function result = clean_one_flight(input_flight_dir, output_flights_dir, rules)
% clean_one_flight
% Clean one normalized flight directory into _data_clean flight output.

flight_id = string(split(input_flight_dir, filesep));
flight_id = char(flight_id(end));

result = struct(...
    'flight_id', flight_id, ...
    'status', 'failed', ...
    'message', '', ...
    'imu_rows_in', 0, ...
    'imu_rows_out', 0, ...
    'baro_rows_in', 0, ...
    'baro_rows_out', 0, ...
    'gps_rows_in', 0, ...
    'gps_rows_out', 0, ...
    'baro_dropped_nonfinite', 0, ...
    'baro_dropped_out_of_range', 0, ...
    'baro_dropped_step', 0, ...
    'output_dir', '');

imu_path = fullfile(input_flight_dir, 'imu.csv');
baro_path = fullfile(input_flight_dir, 'baro.csv');
gps_path = fullfile(input_flight_dir, 'gps.csv');
meta_path = fullfile(input_flight_dir, 'flight_meta.json');

if ~isfile(imu_path) || ~isfile(baro_path)
    result.status = 'failed';
    result.message = 'Missing required imu.csv or baro.csv in normalized flight.';
    return;
end

imu = readtable(imu_path);
baro = readtable(baro_path);

result.imu_rows_in = height(imu);
result.baro_rows_in = height(baro);

if isfile(gps_path)
    gps = readtable(gps_path);
    result.gps_rows_in = height(gps);
else
    gps = table();
end

required_imu = {'t_flight_sec', 't_sensor_raw_sec', 't_sec', 'accel_z_mps2', 'source_family', 'source_file', 'source_row'};
required_baro = {'t_flight_sec', 't_sensor_raw_sec', 't_sec', 'pressure_pa', 'baro_alt_m_raw', 'source_family', 'source_file', 'source_row'};

if ~all(ismember(required_imu, imu.Properties.VariableNames))
    result.status = 'failed';
    result.message = 'imu.csv missing required columns.';
    return;
end
if ~all(ismember(required_baro, baro.Properties.VariableNames))
    result.status = 'failed';
    result.message = 'baro.csv missing required columns.';
    return;
end

% ---- Baro cleaning masks ----
p = baro.pressure_pa;
t = get_primary_time(baro);
mask_nonfinite = ~isfinite(p) | ~isfinite(t);
mask_out_of_range = (p < rules.min_pressure_pa) | (p > rules.max_pressure_pa);
mask_step = false(size(p));

if rules.enable_pressure_step_filter && numel(p) > 1
    dp = [0; abs(diff(p))];
    mask_step = dp > rules.max_pressure_step_pa;
end

mask_drop = mask_nonfinite | mask_out_of_range | mask_step;
mask_keep = ~mask_drop;

result.baro_dropped_nonfinite = sum(mask_nonfinite);
result.baro_dropped_out_of_range = sum(mask_out_of_range);
result.baro_dropped_step = sum(mask_step);

baro_clean = baro(mask_keep, :);
imu_clean = imu;

gps_clean = gps;

if height(imu_clean) == 0
    result.status = 'failed';
    result.message = 'IMU stream became empty during cleaning.';
    return;
end
if height(baro_clean) == 0
    result.status = 'failed';
    result.message = 'Baro stream became empty during cleaning.';
    return;
end

if rules.rebase_time_after_clean
    imu_clean = rebase_time_to_zero(imu_clean);
    baro_clean = rebase_time_to_zero(baro_clean);
    if ~isempty(gps_clean)
        if ismember('t_sec', gps_clean.Properties.VariableNames)
            gps_clean = rebase_time_to_zero(gps_clean);
        end
    end
end

output_flight_dir = fullfile(output_flights_dir, flight_id);
if isfolder(output_flight_dir)
    rmdir(output_flight_dir, 's');
end
mkdir(output_flight_dir);

writetable(imu_clean, fullfile(output_flight_dir, 'imu.csv'));
writetable(baro_clean, fullfile(output_flight_dir, 'baro.csv'));

if ~isempty(gps_clean)
    writetable(gps_clean, fullfile(output_flight_dir, 'gps.csv'));
end

dropped = baro(mask_drop, :);
if height(dropped) > 0
    dropped.reason_nonfinite = mask_nonfinite(mask_drop);
    dropped.reason_out_of_range = mask_out_of_range(mask_drop);
    dropped.reason_step = mask_step(mask_drop);
    writetable(dropped, fullfile(output_flight_dir, 'baro_dropped.csv'));
end

meta_out = struct();
if isfile(meta_path)
    try
        meta_out = jsondecode(fileread(meta_path));
    catch
        meta_out = struct();
    end
end

meta_out.cleaning_version = 'v2_time_contract';
meta_out.cleaning_rules = rules;
meta_out.rows_in = struct('imu', height(imu), 'baro', height(baro), 'gps', result.gps_rows_in);
meta_out.rows_out = struct('imu', height(imu_clean), 'baro', height(baro_clean), 'gps', height(gps_clean));
meta_out.baro_dropped = struct(...
    'nonfinite', result.baro_dropped_nonfinite, ...
    'out_of_range', result.baro_dropped_out_of_range, ...
    'step', result.baro_dropped_step);

fid = fopen(fullfile(output_flight_dir, 'flight_meta.json'), 'w');
if fid == -1
    result.status = 'failed';
    result.message = 'Unable to write cleaned flight_meta.json.';
    return;
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(meta_out));

result.status = 'processed';
result.message = 'ok';
result.imu_rows_out = height(imu_clean);
result.baro_rows_out = height(baro_clean);
result.gps_rows_out = height(gps_clean);
result.output_dir = output_flight_dir;
end

function t = get_primary_time(tbl)
if ismember('t_flight_sec', tbl.Properties.VariableNames)
    t = tbl.t_flight_sec;
elseif ismember('t_sec', tbl.Properties.VariableNames)
    t = tbl.t_sec;
else
    error('Missing expected time column (t_flight_sec or t_sec).');
end
end

function tbl = rebase_time_to_zero(tbl)
if isempty(tbl) || height(tbl) == 0
    return;
end

if ismember('t_flight_sec', tbl.Properties.VariableNames)
    t0 = tbl.t_flight_sec(1);
    tbl.t_flight_sec = tbl.t_flight_sec - t0;
    if ismember('t_sec', tbl.Properties.VariableNames)
        tbl.t_sec = tbl.t_flight_sec;
    end
    return;
end

if ismember('t_sec', tbl.Properties.VariableNames)
    t0 = tbl.t_sec(1);
    tbl.t_sec = tbl.t_sec - t0;
    return;
end

error('Expected t_flight_sec or t_sec column for time rebase.');
end
