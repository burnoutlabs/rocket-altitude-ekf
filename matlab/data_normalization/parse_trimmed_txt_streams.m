function streams = parse_trimmed_txt_streams(file_path, parser_config)
% parse_trimmed_txt_streams
% Parse trimmed TXT record streams (ICM/MS5 tokens).

if nargin < 2 || isempty(parser_config) || isempty(fieldnames(parser_config))
    parser_config = default_parser_config();
end

axis_key = select_trimmed_axis(file_path, parser_config);

imu_t_us = [];
imu_axis_mg = [];
imu_rows = [];

baro_t_us = [];
baro_p_pa = [];
baro_rows = [];

fid = fopen(file_path, 'r');
if fid == -1
    error('Unable to open TXT file: %s', file_path);
end
cleanup = onCleanup(@() fclose(fid));

line_no = 0;
while true
    line = fgetl(fid);
    if ~ischar(line)
        break;
    end
    line_no = line_no + 1;

    if strncmp(line, 'ICM,', 4)
        [t_us, axis_val] = extract_icm_fields(line, axis_key);
        if isfinite(t_us) && isfinite(axis_val)
            imu_t_us(end + 1, 1) = t_us; %#ok<AGROW>
            imu_axis_mg(end + 1, 1) = axis_val; %#ok<AGROW>
            imu_rows(end + 1, 1) = line_no; %#ok<AGROW>
        end

    elseif strncmp(line, 'MS5,', 4)
        [t_us, p_pa] = extract_ms5_fields(line);
        if isfinite(t_us) && isfinite(p_pa)
            baro_t_us(end + 1, 1) = t_us; %#ok<AGROW>
            baro_p_pa(end + 1, 1) = p_pa; %#ok<AGROW>
            baro_rows(end + 1, 1) = line_no; %#ok<AGROW>
        end
    end
end

if isempty(imu_t_us)
    error('No usable ICM records found in %s', file_path);
end
if isempty(baro_t_us)
    error('No usable MS5 records found in %s', file_path);
end

streams = struct();
streams.imu = struct(...
    't_raw', imu_t_us * 1e-6, ...
    'value_raw', (imu_axis_mg / 1000.0) * 9.80665, ...
    'source_row_raw', imu_rows);

streams.baro = struct(...
    't_raw', baro_t_us * 1e-6, ...
    'pressure_raw', baro_p_pa, ...
    'alt_raw', NaN(size(baro_p_pa)), ...
    'source_row_raw', baro_rows);

streams.gps = [];
end

function config = default_parser_config()
config = struct();
config.trimmed_txt_default_axis = 'ya';
config.trimmed_txt_axis_overrides = struct('pattern', {}, 'axis', {});
end

function axis_key = select_trimmed_axis(file_path, parser_config)
axis_key = lower(strtrim(parser_config.trimmed_txt_default_axis));
if ~isfield(parser_config, 'trimmed_txt_axis_overrides')
    return;
end

overrides = parser_config.trimmed_txt_axis_overrides;
if isempty(overrides)
    return;
end

name_l = lower(file_path);
for i = 1:numel(overrides)
    if contains(name_l, lower(overrides(i).pattern))
        axis_key = lower(strtrim(overrides(i).axis));
        return;
    end
end
end

function [t_us, axis_val] = extract_icm_fields(line, axis_key)
t_us = NaN;
axis_val = NaN;

parts = strsplit(line, ',');
for i = 2:2:(numel(parts) - 1)
    key = strtrim(parts{i});
    val = str2double(strtrim(parts{i + 1}));

    if strcmp(key, 't')
        t_us = val;
    elseif strcmpi(key, axis_key)
        axis_val = val;
    end
end
end

function [t_us, p_pa] = extract_ms5_fields(line)
t_us = NaN;
p_pa = NaN;

parts = strsplit(line, ',');
for i = 2:2:(numel(parts) - 1)
    key = strtrim(parts{i});
    val = str2double(strtrim(parts{i + 1}));

    if strcmp(key, 't')
        t_us = val;
    elseif strcmpi(key, 'p')
        p_pa = val;
    end
end
end
