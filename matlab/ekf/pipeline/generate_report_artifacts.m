function out = generate_report_artifacts(cleaned_dir, report_tables_dir, report_figures_dir, ekf_config, varargin)
% generate_report_artifacts
% Rebuild report tables/figures from cleaned flights using current EKF config.
%
% Inputs:
%   cleaned_dir        - _data_clean root
%   report_tables_dir  - _report_artifacts/tables
%   report_figures_dir - _report_artifacts/figures
%   ekf_config         - EKF config struct from main.m
%
% Name-Value options:
%   'figure_flight_ids'                - explicit figure flight ids (default: empty)
%   'verbose'                          - print progress (default: true)
%
% Output fields:
%   flight_ids_processed
%   figure_flight_ids_used
%   tables_written
%   figures_written
%   per_flight_table
%   aggregate_table
%   figure_manifest_table

if nargin < 4
    error('Expected cleaned_dir, report_tables_dir, report_figures_dir, and ekf_config.');
end
if ~isstruct(ekf_config)
    error('ekf_config must be a struct.');
end
if ~isfolder(cleaned_dir)
    error('cleaned_dir not found: %s', cleaned_dir);
end

options = struct( ...
    'figure_flight_ids', strings(0, 1), ...
    'verbose', true);
options = apply_name_value(options, varargin{:});

if ~isfield(ekf_config, 'measurement_model') || isempty(ekf_config.measurement_model)
    ekf_config.measurement_model = 'altitude_linear';
end
if ~isfield(ekf_config, 'sea_level_pressure_pa') || ~isfinite(ekf_config.sea_level_pressure_pa)
    ekf_config.sea_level_pressure_pa = 101325;
end

if ~isfolder(report_tables_dir)
    mkdir(report_tables_dir);
end
if ~isfolder(report_figures_dir)
    mkdir(report_figures_dir);
end

ensure_plotting_path();

flight_ids = list_clean_flight_ids(cleaned_dir);
if isempty(flight_ids)
    error('No cleaned flights found in: %s', fullfile(cleaned_dir, 'flights'));
end

figure_flight_ids_used = normalize_figure_ids(options.figure_flight_ids, flight_ids);

n = numel(flight_ids);
replay_rows = cell(n, 8);
runtime_rows = cell(n, 8);
gate_rows = cell(n, 6);
diag_rows = cell(n, 9);
per_rows = cell(n, 15);

figure_rows = cell(max(1, numel(figure_flight_ids_used) * 4), 4);
figure_row_i = 0;

tables_written = {};
figures_written = {};

for i = 1:n
    fid = flight_ids(i);
    if options.verbose
        fprintf('[%d/%d] Report artifacts flight: %s\n', i, n, fid);
    end

    flight = load_clean_flight( ...
        'cleaned_dir', cleaned_dir, ...
        'flight_id', fid, ...
        'verbose', false);
    replay = build_replay_events(flight, ...
        'p0_pa', ekf_config.sea_level_pressure_pa, ...
        'verbose', false);
    rv = validate_replay_events(replay, ...
        'verbose', false);

    prep = prepare_measurements_for_ekf(replay, ekf_config, 'verbose', false);

    [x0, P0, u0] = build_initial_conditions(prep, ekf_config);
    run_result = run_vertical_ekf_replay(prep, x0, P0, u0, ekf_config, 'verbose', false);

    s = run_result.summary;
    log_tbl = run_result.log;

    replay_rows(i, :) = { ...
        char(fid), ...
        double(rv.is_valid), ...
        rv.message, ...
        rv.total_events, ...
        rv.imu_events, ...
        rv.baro_events, ...
        rv.dt_min_sec, ...
        rv.dt_max_sec};

    final_state_finite = double(all(isfinite([s.final_z_m, s.final_vz_mps, s.final_ba_mps2])));
    runtime_rows(i, :) = { ...
        char(fid), ...
        s.num_events, ...
        s.num_predict_steps, ...
        s.num_cov_floor_events, ...
        s.final_P_zz, ...
        s.final_P_vzvz, ...
        s.final_P_baba, ...
        final_state_finite};

    baro_gate_ratio = ratio_or_zero(s.num_baro_updates_gated, s.num_baro_events);
    gate_rows(i, :) = { ...
        char(fid), ...
        s.num_baro_events, ...
        s.num_baro_updates_used, ...
        s.num_baro_updates_gated, ...
        baro_gate_ratio, ...
        s.num_baro_nonfinite};

    used_nis = log_tbl.update_used & isfinite(log_tbl.nis);
    nis_vals = log_tbl.nis(used_nis);
    used_innov = log_tbl.update_used & isfinite(log_tbl.innovation_m);
    innov_vals = log_tbl.innovation_m(used_innov);
    diag_rows(i, :) = { ...
        char(fid), ...
        safe_mean(innov_vals), ...
        safe_std(innov_vals), ...
        safe_mean(nis_vals), ...
        safe_std(nis_vals), ...
        safe_min(log_tbl.P_zz), ...
        safe_max(log_tbl.P_zz), ...
        safe_min(log_tbl.P_vzvz), ...
        safe_max(log_tbl.P_vzvz)};

    peak_z_m = max(log_tbl.z_hat_m);
    baro_update_ratio = ratio_or_zero(s.num_baro_updates_used, s.num_baro_events);
    per_rows(i, :) = { ...
        char(fid), ...
        s.num_events, ...
        s.num_imu_events, ...
        s.num_baro_events, ...
        s.num_baro_updates_used, ...
        s.num_baro_updates_gated, ...
        baro_update_ratio, ...
        baro_gate_ratio, ...
        s.duration_sec, ...
        s.final_z_m, ...
        s.final_vz_mps, ...
        s.final_ba_mps2, ...
        s.final_P_zz, ...
        s.final_P_vzvz, ...
        peak_z_m};

    if any(strcmp(figure_flight_ids_used, string(fid)))
        [figure_rows, figure_row_i, figures_written] = save_figure_set( ...
            fid, run_result, report_figures_dir, figure_rows, figure_row_i, figures_written);
    end
end

replay_table = cell2table(replay_rows, 'VariableNames', { ...
    'flight_id', 'is_valid', 'message', 'total_events', ...
    'imu_events', 'baro_events', 'dt_min_sec', 'dt_max_sec'});

runtime_table = cell2table(runtime_rows, 'VariableNames', { ...
    'flight_id', 'num_events', 'num_predict_steps', 'num_cov_floor_events', ...
    'final_P_zz', 'final_P_vzvz', 'final_P_baba', 'final_state_finite'});

gate_table = cell2table(gate_rows, 'VariableNames', { ...
    'flight_id', 'baro_events', 'baro_updates_used', 'baro_updates_gated', ...
    'baro_gate_ratio', 'baro_nonfinite'});

diagnostics_table = cell2table(diag_rows, 'VariableNames', { ...
    'flight_id', 'innovation_mean', 'innovation_std', ...
    'nis_mean', 'nis_std', 'P_zz_min', 'P_zz_max', 'P_vzvz_min', 'P_vzvz_max'});

per_flight_table = cell2table(per_rows, 'VariableNames', { ...
    'flight_id', 'num_events', 'num_imu_events', 'num_baro_events', ...
    'num_baro_updates_used', 'num_baro_updates_gated', ...
    'baro_update_ratio', 'baro_gate_ratio', 'duration_sec', ...
    'final_z_m', 'final_vz_mps', 'final_ba_mps2', 'final_P_zz', 'final_P_vzvz', ...
    'peak_z_m'});

aggregate_table = table();
aggregate_table.num_flights = height(per_flight_table);
aggregate_table.mean_num_events = mean(per_flight_table.num_events, 'omitnan');
aggregate_table.mean_baro_update_ratio = mean(per_flight_table.baro_update_ratio, 'omitnan');
aggregate_table.mean_baro_gate_ratio = mean(per_flight_table.baro_gate_ratio, 'omitnan');
aggregate_table.mean_duration_sec = mean(per_flight_table.duration_sec, 'omitnan');
aggregate_table.mean_final_abs_vz = mean(abs(per_flight_table.final_vz_mps), 'omitnan');

tables_written = write_table(replay_table, fullfile(report_tables_dir, 'replay_validation_summary.csv'), tables_written);
tables_written = write_table(runtime_table, fullfile(report_tables_dir, 'ekf_runtime_health.csv'), tables_written);
tables_written = write_table(gate_table, fullfile(report_tables_dir, 'innovation_gate_counts.csv'), tables_written);
tables_written = write_table(diagnostics_table, fullfile(report_tables_dir, 'diagnostics_summary.csv'), tables_written);
tables_written = write_table(per_flight_table, fullfile(report_tables_dir, 'final_per_flight_metrics.csv'), tables_written);
tables_written = write_table(aggregate_table, fullfile(report_tables_dir, 'final_aggregate_metrics.csv'), tables_written);

figure_manifest_table = build_figure_manifest_table(figure_rows, figure_row_i);
tables_written = write_table(figure_manifest_table, fullfile(report_tables_dir, 'report_figure_manifest.csv'), tables_written);

out = struct();
out.flight_ids_processed = flight_ids;
out.figure_flight_ids_used = figure_flight_ids_used;
out.tables_written = tables_written;
out.figures_written = figures_written;
out.per_flight_table = per_flight_table;
out.aggregate_table = aggregate_table;
out.figure_manifest_table = figure_manifest_table;

if options.verbose
    fprintf('Report artifacts complete: %d flights | tables=%d | figures=%d\n', ...
        numel(flight_ids), numel(tables_written), numel(figures_written));
    fprintf('Tables dir:  %s\n', report_tables_dir);
    fprintf('Figures dir: %s\n', report_figures_dir);
end
end

function ensure_plotting_path()
this_dir = fileparts(mfilename('fullpath'));
ekf_dir = fileparts(this_dir);
matlab_dir = fileparts(fileparts(this_dir));
if isfolder(this_dir)
    addpath(this_dir);
end
if isfolder(ekf_dir)
    addpath(ekf_dir);
end
plotting_dir = fullfile(matlab_dir, 'plotting');
if isfolder(plotting_dir)
    addpath(plotting_dir);
end
end

function ids = normalize_figure_ids(figure_flight_ids, valid_flight_ids)
ids = string(figure_flight_ids);
ids = ids(~ismissing(ids));
ids = strtrim(ids);
ids = ids(strlength(ids) > 0);
ids = unique(ids, 'stable');

if isempty(ids)
    return;
end
if any(strcmpi(ids, "auto"))
    error('figure_flight_ids must be explicit flight IDs; "auto" is not allowed.');
end

invalid_ids = ids(~ismember(ids, valid_flight_ids));
if ~isempty(invalid_ids)
    error('Invalid figure_flight_ids: %s', strjoin(cellstr(invalid_ids), ', '));
end
end

function [rows, row_i, written] = save_figure_set(flight_id, result, figures_dir, rows, row_i, written)
fid_char = char(flight_id);
[rows, row_i, written] = save_named_figure( ...
    rows, row_i, written, fid_char, 'plot_ekf_overview', ...
    fullfile(figures_dir, sprintf('ekf_overview_%s.png', fid_char)), ...
    @() plot_ekf_overview(result, 'figure_visible', false));

[rows, row_i, written] = save_named_figure( ...
    rows, row_i, written, fid_char, 'plot_ekf_innovations', ...
    fullfile(figures_dir, sprintf('ekf_innovations_%s.png', fid_char)), ...
    @() plot_ekf_innovations(result, 'figure_visible', false));

[rows, row_i, written] = save_named_figure( ...
    rows, row_i, written, fid_char, 'plot_ekf_covariance', ...
    fullfile(figures_dir, sprintf('ekf_covariance_%s.png', fid_char)), ...
    @() plot_ekf_covariance(result, 'figure_visible', false));

[rows, row_i, written] = save_named_figure( ...
    rows, row_i, written, fid_char, 'plot_ekf_event_timeline', ...
    fullfile(figures_dir, sprintf('ekf_event_timeline_%s.png', fid_char)), ...
    @() plot_ekf_event_timeline(result, 'figure_visible', false));
end

function [rows, row_i, written] = save_named_figure(rows, row_i, written, flight_id, figure_type, file_path, create_fn)
plot_info = create_fn();
if ~isstruct(plot_info) || ~isfield(plot_info, 'figure_handle') || ~ishandle(plot_info.figure_handle)
    error('%s did not return a valid figure_handle.', figure_type);
end

print(plot_info.figure_handle, file_path, '-dpng', '-r300');
close(plot_info.figure_handle);

row_i = row_i + 1;
rows(row_i, :) = {char(flight_id), figure_type, file_path, char(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss"))};
written{end + 1, 1} = file_path;
end

function figure_manifest_table = build_figure_manifest_table(rows, row_i)
if row_i == 0
    figure_manifest_table = table('Size', [0, 4], ...
        'VariableTypes', {'string', 'string', 'string', 'string'}, ...
        'VariableNames', {'flight_id', 'figure_type', 'file_path', 'generated_at'});
    return;
end

figure_manifest_table = cell2table(rows(1:row_i, :), 'VariableNames', ...
    {'flight_id', 'figure_type', 'file_path', 'generated_at'});
end

function tables_written = write_table(tbl, path, tables_written)
writetable(tbl, path);
tables_written{end + 1, 1} = path;
end

function out = ratio_or_zero(numerator, denominator)
out = 0;
if denominator > 0
    out = numerator / denominator;
end
end

function out = safe_mean(v)
if isempty(v)
    out = NaN;
else
    out = mean(v, 'omitnan');
end
end

function out = safe_std(v)
if isempty(v)
    out = NaN;
else
    out = std(v, 'omitnan');
end
end

function out = safe_min(v)
v = v(isfinite(v));
if isempty(v)
    out = NaN;
else
    out = min(v);
end
end

function out = safe_max(v)
v = v(isfinite(v));
if isempty(v)
    out = NaN;
else
    out = max(v);
end
end
