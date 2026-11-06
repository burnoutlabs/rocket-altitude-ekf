function manifest_table = run_normalization_pipeline(varargin)
% run_normalization_pipeline
% Generate normalized EKF input streams from raw rocket-flight files.
%
% Name-Value options:
%   'raw_dir'            - Path to raw input directory (default: ../_data_raw)
%   'normalized_dir'     - Path to normalized output directory (default: ../_data_normalized)
%   'overwrite_outputs'  - true/false:
%                          false => skip files with existing normalized outputs
%                          true  => regenerate normalized outputs
%   'selected_files'     - cellstr of raw file names to process (default: all)
%   'verbose'            - true/false progress printing (default: true)
%   'parser_config'      - parser config struct (default: internal defaults)
%
% Output:
%   manifest_table       - table summary of processed/skipped files

options = struct(...
    'raw_dir', '', ...
    'normalized_dir', '', ...
    'overwrite_outputs', false, ...
    'selected_files', {{}}, ...
    'verbose', true, ...
    'parser_config', struct());

options = apply_name_value(options, varargin{:});

this_dir = fileparts(mfilename('fullpath'));
matlab_dir = fileparts(this_dir);

if isempty(options.raw_dir)
    options.raw_dir = fullfile(matlab_dir, '_data_raw');
end
if isempty(options.normalized_dir)
    options.normalized_dir = fullfile(matlab_dir, '_data_normalized');
end
if isempty(fieldnames(options.parser_config))
    options.parser_config = default_parser_config();
end

if ~isfolder(options.raw_dir)
    error('Raw data directory does not exist: %s', options.raw_dir);
end

if options.overwrite_outputs && isfolder(options.normalized_dir)
    rmdir(options.normalized_dir, 's');
end

flights_dir = fullfile(options.normalized_dir, 'flights');
if ~isfolder(flights_dir)
    mkdir(flights_dir);
end

all_entries = dir(options.raw_dir);
all_entries = all_entries(~[all_entries.isdir]);
all_names = {all_entries.name};

if ~isempty(options.selected_files)
    selected = string(options.selected_files);
    keep_mask = ismember(string(all_names), selected);
    all_entries = all_entries(keep_mask);
end

if isempty(all_entries)
    warning('No raw files selected in: %s', options.raw_dir);
end

rows = cell(numel(all_entries), 10);
processed_count = 0;
failed_count = 0;
skipped_count = 0;

for i = 1:numel(all_entries)
    raw_name = all_entries(i).name;
    raw_path = fullfile(options.raw_dir, raw_name);

    result = normalize_one_file( ...
        raw_path, ...
        flights_dir, ...
        options.parser_config, ...
        options.overwrite_outputs);

    if options.verbose
        status_label = result.status;
        if strcmp(result.status, 'skipped') && contains(lower(result.message), 'already exists')
            status_label = 'skipped_exists';
        end
        fprintf('[%d/%d] %s (%s)\n', i, numel(all_entries), raw_name, status_label);
    end

    rows(i, :) = { ...
        raw_name, ...
        result.family, ...
        result.status, ...
        result.message, ...
        result.processed, ...
        result.flight_id, ...
        result.imu_rows, ...
        result.baro_rows, ...
        result.gps_rows, ...
        result.output_dir};

    if result.processed
        processed_count = processed_count + 1;
    elseif strcmp(result.status, 'failed')
        failed_count = failed_count + 1;
    else
        skipped_count = skipped_count + 1;
    end
end

manifest_table = cell2table(rows, 'VariableNames', {...
    'raw_file', 'family', 'status', 'message', 'processed', ...
    'flight_id', 'imu_rows', 'baro_rows', 'gps_rows', 'output_dir'});

manifest_path = fullfile(options.normalized_dir, 'normalization_manifest.csv');
writetable(manifest_table, manifest_path);

if options.verbose
    fprintf('\nNormalization complete.\n');
    fprintf('Processed: %d\n', processed_count);
    fprintf('Skipped:   %d\n', skipped_count);
    fprintf('Failed:    %d\n', failed_count);
    fprintf('Manifest:  %s\n', manifest_path);
end
end

function out = apply_name_value(defaults, varargin)
out = defaults;
if mod(numel(varargin), 2) ~= 0
    error('Name-value arguments must be provided in pairs.');
end
for i = 1:2:numel(varargin)
    name = varargin{i};
    value = varargin{i + 1};
    if ~ischar(name) && ~isstring(name)
        error('Option names must be char or string.');
    end
    key = char(name);
    if ~isfield(out, key)
        error('Unknown option: %s', key);
    end
    out.(key) = value;
end
end

function config = default_parser_config()
config = struct();
config.trimmed_txt_default_axis = 'ya';
config.trimmed_txt_axis_overrides = struct('pattern', {}, 'axis', {});
end
