function cleaning_manifest = run_cleaning_pipeline(varargin)
% run_cleaning_pipeline
% Generate cleaned data from normalized flight streams.
%
% Name-Value options:
%   'normalized_dir'     - Input normalized directory (default: ../_data_normalized)
%   'cleaned_dir'        - Output cleaned directory (default: ../_data_clean)
%   'overwrite_outputs'  - true/false:
%                          false => skip flights with existing cleaned outputs
%                          true  => regenerate cleaned outputs
%   'selected_flights'   - Cellstr of flight ids to process (default: all)
%   'verbose'            - Print progress (default: true)
%   'rules'              - Cleaning rules struct (default: internal defaults)

options = struct(...
    'normalized_dir', '', ...
    'cleaned_dir', '', ...
    'overwrite_outputs', false, ...
    'selected_flights', {{}}, ...
    'verbose', true, ...
    'rules', struct());

options = apply_name_value(options, varargin{:});

this_dir = fileparts(mfilename('fullpath'));
matlab_dir = fileparts(this_dir);

if isempty(options.normalized_dir)
    options.normalized_dir = fullfile(matlab_dir, '_data_normalized');
end
if isempty(options.cleaned_dir)
    options.cleaned_dir = fullfile(matlab_dir, '_data_clean');
end
if isempty(fieldnames(options.rules))
    options.rules = default_cleaning_rules();
end

normalized_flights_dir = fullfile(options.normalized_dir, 'flights');
if ~isfolder(normalized_flights_dir)
    error('Normalized flights directory does not exist: %s', normalized_flights_dir);
end

if options.overwrite_outputs && isfolder(options.cleaned_dir)
    rmdir(options.cleaned_dir, 's');
end

cleaned_flights_dir = fullfile(options.cleaned_dir, 'flights');
if ~isfolder(cleaned_flights_dir)
    mkdir(cleaned_flights_dir);
end

entries = dir(normalized_flights_dir);
entries = entries([entries.isdir]);
entries = entries(~ismember({entries.name}, {'.', '..'}));

if ~isempty(options.selected_flights)
    selected = string(options.selected_flights);
    mask = ismember(string({entries.name}), selected);
    entries = entries(mask);
end

rows = cell(numel(entries), 14);
processed_count = 0;
failed_count = 0;
skipped_count = 0;

for i = 1:numel(entries)
    flight_id = entries(i).name;
    input_flight_dir = fullfile(normalized_flights_dir, flight_id);

    skip_existing = false;
    if ~options.overwrite_outputs
        [skip_existing, result] = build_existing_clean_skip_result(flight_id, input_flight_dir, cleaned_flights_dir);
    end

    if ~skip_existing
        result = clean_one_flight(input_flight_dir, cleaned_flights_dir, options.rules);
    end

    if options.verbose
        status_label = result.status;
        if strcmp(result.status, 'skipped') && contains(lower(result.message), 'already exists')
            status_label = 'skipped_exists';
        end
        fprintf('[%d/%d] %s (%s)\n', i, numel(entries), flight_id, status_label);
    end

    rows(i, :) = { ...
        result.flight_id, ...
        result.status, ...
        result.message, ...
        result.imu_rows_in, ...
        result.imu_rows_out, ...
        result.baro_rows_in, ...
        result.baro_rows_out, ...
        result.gps_rows_in, ...
        result.gps_rows_out, ...
        result.baro_dropped_nonfinite, ...
        result.baro_dropped_out_of_range, ...
        result.baro_dropped_step, ...
        result.output_dir, ...
        char(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss"))};

    if strcmp(result.status, 'processed')
        processed_count = processed_count + 1;
    elseif strcmp(result.status, 'failed')
        failed_count = failed_count + 1;
    else
        skipped_count = skipped_count + 1;
    end
end

cleaning_manifest = cell2table(rows, 'VariableNames', {...
    'flight_id', 'status', 'message', ...
    'imu_rows_in', 'imu_rows_out', ...
    'baro_rows_in', 'baro_rows_out', ...
    'gps_rows_in', 'gps_rows_out', ...
    'baro_dropped_nonfinite', 'baro_dropped_out_of_range', 'baro_dropped_step', ...
    'output_dir', 'generated_at'});

manifest_path = fullfile(options.cleaned_dir, 'cleaning_manifest.csv');
writetable(cleaning_manifest, manifest_path);

rules_path = fullfile(options.cleaned_dir, 'cleaning_rules.json');
fid = fopen(rules_path, 'w');
if fid ~= -1
    cleanup_guard = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(options.rules));
    clear cleanup_guard;
end

if options.verbose
    fprintf('\nCleaning complete.\n');
    fprintf('Processed: %d\n', processed_count);
    fprintf('Skipped:   %d\n', skipped_count);
    fprintf('Failed:    %d\n', failed_count);
    fprintf('Manifest:  %s\n', manifest_path);
end
end

function [skip_existing, result] = build_existing_clean_skip_result(flight_id, input_flight_dir, cleaned_flights_dir)
skip_existing = false;
result = struct();

output_flight_dir = fullfile(cleaned_flights_dir, flight_id);
output_imu = fullfile(output_flight_dir, 'imu.csv');
output_baro = fullfile(output_flight_dir, 'baro.csv');
if ~isfolder(output_flight_dir) || ~isfile(output_imu) || ~isfile(output_baro)
    return;
end

[drop_nonfinite, drop_out_of_range, drop_step] = get_existing_drop_counts(output_flight_dir);

skip_existing = true;
result = struct(...
    'flight_id', flight_id, ...
    'status', 'skipped', ...
    'message', 'cleaned output already exists; set overwrite_outputs=true to regenerate.', ...
    'imu_rows_in', safe_table_height(fullfile(input_flight_dir, 'imu.csv')), ...
    'imu_rows_out', safe_table_height(output_imu), ...
    'baro_rows_in', safe_table_height(fullfile(input_flight_dir, 'baro.csv')), ...
    'baro_rows_out', safe_table_height(output_baro), ...
    'gps_rows_in', safe_table_height(fullfile(input_flight_dir, 'gps.csv')), ...
    'gps_rows_out', safe_table_height(fullfile(output_flight_dir, 'gps.csv')), ...
    'baro_dropped_nonfinite', drop_nonfinite, ...
    'baro_dropped_out_of_range', drop_out_of_range, ...
    'baro_dropped_step', drop_step, ...
    'output_dir', output_flight_dir);
end

function [drop_nonfinite, drop_out_of_range, drop_step] = get_existing_drop_counts(output_flight_dir)
drop_nonfinite = 0;
drop_out_of_range = 0;
drop_step = 0;

dropped_path = fullfile(output_flight_dir, 'baro_dropped.csv');
if ~isfile(dropped_path)
    return;
end

try
    dropped = readtable(dropped_path);
    if ismember('reason_nonfinite', dropped.Properties.VariableNames)
        drop_nonfinite = sum(logical(dropped.reason_nonfinite));
    end
    if ismember('reason_out_of_range', dropped.Properties.VariableNames)
        drop_out_of_range = sum(logical(dropped.reason_out_of_range));
    end
    if ismember('reason_step', dropped.Properties.VariableNames)
        drop_step = sum(logical(dropped.reason_step));
    end
catch
    drop_nonfinite = 0;
    drop_out_of_range = 0;
    drop_step = 0;
end
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

function rules = default_cleaning_rules()
rules = struct();
rules.min_pressure_pa = 20000;
rules.max_pressure_pa = 120000;
rules.enable_pressure_step_filter = false;
rules.max_pressure_step_pa = 5000;
rules.rebase_time_after_clean = false;
end
