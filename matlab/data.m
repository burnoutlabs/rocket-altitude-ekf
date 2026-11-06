%[text] # Data Pipeline Workspace
%[text] This live script is the dedicated home for fetch, normalization, cleaning, and validation.
%[text] It prepares `_data_clean/` for downstream EKF notebooks (for example `main.m`).
%%
% Skip workspace reset when data.m is invoked from main.m.
if ~(exist('data_script_skip_clear', 'var') && data_script_skip_clear)
    clear; clc; close all;
else
    clear data_script_skip_clear;
end

% Resolve this folder robustly for editor-run and command-line run.
active_file = '';
if usejava('desktop')
    active_file = matlab.desktop.editor.getActiveFilename;
end
if ~isempty(active_file)
    here = fileparts(active_file);
else
    here = fileparts(mfilename('fullpath'));
    if isempty(here)
        here = pwd;
    end
end

% Core paths.
data_fetch_dir = fullfile(here, 'data_fetch');
download_script = fullfile(data_fetch_dir, 'download_source_data.m');
data_raw_dir = fullfile(here, '_data_raw');
data_normalized_dir = fullfile(here, '_data_normalized');
data_clean_dir = fullfile(here, '_data_clean');

data_normalization_dir = fullfile(here, 'data_normalization');
data_cleaning_dir = fullfile(here, 'data_cleaning');
plotting_dir = fullfile(here, 'plotting');
%%
%[text] ## Run Controls
%[text] Keep this script focused on data preparation only. EKF controls stay in `main.m`.
% Data fetch
download_data = true;
download_data_overwrite = false;

% Normalization + validation
normalize_data = true;
normalize_data_overwrite = false;

run_normalization_validation = true;
normalization_validation_strict = true;
normalization_min_finite_ratio = 0.95;

% Cleaning + validation
clean_data = true;
clean_data_overwrite = false;

run_clean_validation = true;
clean_validation_strict = true;

clean_validation_min_finite_ratio = 0.99;
clean_validation_min_pressure_pa = 20000;
clean_validation_max_pressure_pa = 120000;

% Optional quick cleaned-flight preview
run_clean_preview_plot = true;
preview_flight_id = "raven_csv_e190_8jul2017_j510w_raven";
%%
%[text] ## Data Fetch
%[text] Pulls source files defined by `data_fetch/source_data.m` into `_data_raw/`.
%[text] `download_data_overwrite=false` keeps existing files in place; `true` recreates `_data_raw/` for a clean refetch.
if download_data
    if ~isfolder(data_fetch_dir)
        error('Missing data-fetch module directory: %s', data_fetch_dir);
    end
    addpath(data_fetch_dir);
    if download_data_overwrite && isfolder(data_raw_dir)
        rmdir(data_raw_dir, 's');
    end
    if ~isfile(download_script)
        error('Missing downloader script: %s', download_script);
    end
    run(download_script);
end
%%
%[text] ## Normalization
%[text] Converts heterogeneous raw formats (`.csv`, `.txt`, `.xlsx`, legacy variants) into one canonical per-flight schema:
%[text] `_data_normalized/flights/<flight_id>/`
if ~isfolder(data_normalization_dir)
    error('Missing data-normalization module directory: %s', data_normalization_dir);
end
addpath(data_normalization_dir);

if normalize_data
    normalization_manifest = run_normalization_pipeline( ...
        'raw_dir', data_raw_dir, ...
        'normalized_dir', data_normalized_dir, ...
        'overwrite_outputs', normalize_data_overwrite, ...
        'verbose', true);
end
%%
%[text] ## Normalization Validation
%[text] Validates schema contract and basic signal integrity: required columns, finite-ratio threshold, nonnegative/monotonic time behavior, and alias consistency.
if run_normalization_validation
    normalization_validation_report = validate_normalized_data( ...
        'normalized_dir', data_normalized_dir, ...
        'strict', normalization_validation_strict, ...
        'min_finite_ratio', normalization_min_finite_ratio, ...
        'verbose', true);
end
%%
%[text] ## Cleaning
%[text] Applies conservative quality filtering to produce EKF-ready inputs in `_data_clean/` while preserving traceability fields.
if ~isfolder(data_cleaning_dir)
    error('Missing data-cleaning module directory: %s', data_cleaning_dir);
end
addpath(data_cleaning_dir);

if clean_data
    cleaning_manifest = run_cleaning_pipeline( ...
        'normalized_dir', data_normalized_dir, ...
        'cleaned_dir', data_clean_dir, ...
        'overwrite_outputs', clean_data_overwrite, ...
        'verbose', true);
end
%%
%[text] ## Cleaning Validation
%[text] Re-checks cleaned schema plus pressure plausibility bounds used by this project.
if run_clean_validation
    clean_validation_report = validate_clean_data( ...
        'cleaned_dir', data_clean_dir, ...
        'strict', clean_validation_strict, ...
        'min_finite_ratio', clean_validation_min_finite_ratio, ...
        'min_pressure_pa', clean_validation_min_pressure_pa, ...
        'max_pressure_pa', clean_validation_max_pressure_pa, ...
        'verbose', true);
end
%%
%[text] ## Clean Data Quick Plot
%[text] Plots one cleaned flight for fast manual QA.
if run_clean_preview_plot
    if ~isfolder(plotting_dir)
        error('Missing plotting module directory: %s', plotting_dir);
    end
    addpath(plotting_dir);
    clean_plot_info = plot_clean_flight_overview( ...
        'cleaned_dir', data_clean_dir, ...
        'flight_id', preview_flight_id, ...
        'verbose', true);
end
%%
%[text] ## Run Summary
fprintf('\nData pipeline execution complete.\n');
fprintf('Raw dir:        %s\n', data_raw_dir);
fprintf('Normalized dir: %s\n', data_normalized_dir);
fprintf('Cleaned dir:    %s\n', data_clean_dir);

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"onright"}
%---
