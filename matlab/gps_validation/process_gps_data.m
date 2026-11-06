% process_gps_data.m
%
% Reads the downloaded Featherweight GPS CSV files, extracts peak
% launch-relative altitude for each flight, and compares against the
% EKF apogee from the main pipeline results.
%
% Output: gps_validation/gps_comparison.txt  (human-readable summary)
%
% Run after download_gps_data.m has populated _gps_raw/.
%
% Notes on GPS file format:
%   - Columns: UTCTIME, UNIXTIME, ALT, LAT, LON, #SATS, FIX, HORZV, VERTV, ...
%   - ALT is in feet MSL (integer)
%   - FIX = 3 means a valid 3-D GPS fix
%   - Rows are in RF receive order, NOT chronological — must sort by UNIXTIME
%   - Ground baseline derived from the last 30 sorted samples (post-landing
%     static window at end of record)

clear; clc;

here = fileparts(mfilename('fullpath'));
if isempty(here)
    here = pwd;
end

addpath(here);
addpath(fullfile(here, '..', 'ekf', 'pipeline'));  % for path resolution only

gps_raw_dir     = fullfile(here, '_gps_raw');
ekf_metrics_csv = fullfile(here, '..', '_report_artifacts', 'tables', 'final_per_flight_metrics.csv');
out_txt         = fullfile(here, 'gps_comparison.txt');

FT_TO_M = 0.3048;

% -----------------------------------------------------------------------
% Load EKF metrics (for cross-referencing)
% -----------------------------------------------------------------------
if ~isfile(ekf_metrics_csv)
    error('EKF metrics not found: %s\nRun main.m first.', ekf_metrics_csv);
end
ekf = readtable(ekf_metrics_csv, 'TextType', 'string');

% -----------------------------------------------------------------------
% Flight definitions (from gps_data.m)
% -----------------------------------------------------------------------
entries = gps_data();

% -----------------------------------------------------------------------
% Open output file
% -----------------------------------------------------------------------
fid = fopen(out_txt, 'w');
if fid < 0
    error('Cannot open output file: %s', out_txt);
end

fprintf(fid, 'GPS Validation — Featherweight On-Board GPS vs EKF Apogee\n');
fprintf(fid, 'Generated: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '%s\n\n', repmat('=', 1, 72));

results = struct('ekf_id', {}, 'gps_peak_m', {}, 't_at_peak', {}, ...
    'ground_m', {}, 'n_good', {}, 'duration_s', {});

for i = 1:numel(entries)
    e        = entries(i);
    csv_path = fullfile(gps_raw_dir, e.file_name);

    fprintf(fid, 'Flight: %s\n', e.ekf_id);
    fprintf(fid, 'Source: %s\n', e.notes);
    fprintf(fid, 'File  : %s\n', e.file_name);
    fprintf(fid, '%s\n', repmat('-', 1, 72));

    % -------------------------------------------------------------------
    % Load and parse GPS CSV
    % -------------------------------------------------------------------
    if ~isfile(csv_path)
        fprintf(fid, '  ERROR: file not found — run download_gps_data.m\n\n');
        continue;
    end

    % Read file manually — readtable chokes on '#' and '>' in the header.
    % Known column layout (1-indexed, comma-delimited):
    %   1:UTCTIME  2:UNIXTIME  3:ALT  4:LAT  5:LON  6:#SATS  7:FIX  ...
    try
        lines = readlines(csv_path);       % MATLAB R2020b+
    catch
        fid2 = fopen(csv_path, 'r');
        raw_text = textscan(fid2, '%s', 'Delimiter', '\n', 'WhiteSpace', '');
        fclose(fid2);
        lines = string(raw_text{1});
    end

    % Strip empty lines and the header row
    lines = lines(strtrim(lines) ~= "");
    if isempty(lines)
        fprintf(fid, '  ERROR: file is empty\n\n');
        continue;
    end
    header = lines(1);
    data_lines = lines(2:end);

    % Detect column positions from header
    hdr_parts = strsplit(header, ',');
    unixtime_col = find(strcmpi(strtrim(hdr_parts), 'UNIXTIME'), 1);
    alt_col      = find(strcmpi(strtrim(hdr_parts), 'ALT'),      1);
    fix_col      = find(strcmpi(strtrim(hdr_parts), 'FIX'),      1);

    if isempty(unixtime_col) || isempty(alt_col) || isempty(fix_col)
        fprintf(fid, '  ERROR: required columns missing in header.\n');
        fprintf(fid, '  Header: %s\n\n', header);
        continue;
    end

    % Parse each data line
    n_lines = numel(data_lines);
    t_unix  = nan(n_lines, 1);
    alt_ft  = nan(n_lines, 1);
    fix     = nan(n_lines, 1);

    for li = 1:n_lines
        parts = strsplit(data_lines(li), ',');
        if numel(parts) < max([unixtime_col, alt_col, fix_col])
            continue;
        end
        t_unix(li) = str2double(parts(unixtime_col));
        alt_ft(li) = str2double(parts(alt_col));
        fix(li)    = str2double(parts(fix_col));
    end

    % -------------------------------------------------------------------
    % Filter: valid 3-D fix only, finite values
    % -------------------------------------------------------------------
    good = fix == 3 & isfinite(t_unix) & isfinite(alt_ft);
    if sum(good) < 10
        fprintf(fid, '  WARNING: fewer than 10 valid fix=3 samples (%d total, %d good)\n', ...
            height(raw), sum(good));
    end

    t_good   = t_unix(good);
    alt_good = alt_ft(good);

    fprintf(fid, '  Total rows     : %d\n', n_lines);
    fprintf(fid, '  Rows fix=3     : %d\n', sum(good));

    % -------------------------------------------------------------------
    % Sort chronologically
    % -------------------------------------------------------------------
    [t_sorted, idx] = sort(t_good);
    alt_sorted_ft   = alt_good(idx);
    alt_sorted_m    = alt_sorted_ft * FT_TO_M;

    t_elapsed = t_sorted - t_sorted(1);   % seconds from first sample
    duration_s = t_elapsed(end);

    fprintf(fid, '  Duration       : %.1f s\n', duration_s);
    fprintf(fid, '  Time span      : %.3f to %.3f (Unix)\n', t_sorted(1), t_sorted(end));
    fprintf(fid, '  ALT range      : %.0f to %.0f ft  (%.1f to %.1f m MSL)\n', ...
        min(alt_sorted_ft), max(alt_sorted_ft), ...
        min(alt_sorted_m),  max(alt_sorted_m));

    % -------------------------------------------------------------------
    % Ground baseline: median of last 30 samples (post-landing static window)
    % -------------------------------------------------------------------
    n_baseline = min(30, floor(numel(alt_sorted_m) * 0.15));
    baseline_samples = alt_sorted_m(end - n_baseline + 1 : end);
    ground_m = median(baseline_samples);
    ground_ft = ground_m / FT_TO_M;

    fprintf(fid, '  Ground baseline: %.1f ft  (%.1f m MSL)  [median of last %d samples]\n', ...
        ground_ft, ground_m, n_baseline);

    % Also report first-10 baseline for comparison
    first_baseline_m = median(alt_sorted_m(1 : min(10, numel(alt_sorted_m))));
    fprintf(fid, '  First-10 median: %.1f ft  (%.1f m MSL)  [sanity check]\n', ...
        first_baseline_m / FT_TO_M, first_baseline_m);

    % -------------------------------------------------------------------
    % Launch-relative altitude time series
    % -------------------------------------------------------------------
    alt_relative_m = alt_sorted_m - ground_m;

    [peak_rel_m, peak_idx] = max(alt_relative_m);
    peak_msl_m    = alt_sorted_m(peak_idx);
    t_at_peak     = t_elapsed(peak_idx);

    fprintf(fid, '  GPS peak (MSL) : %.1f ft  (%.1f m)\n', ...
        peak_msl_m / FT_TO_M, peak_msl_m);
    fprintf(fid, '  GPS apogee AGL : %.1f m  (%.0f ft)  at t=%.1f s\n', ...
        peak_rel_m, peak_rel_m / FT_TO_M, t_at_peak);

    % -------------------------------------------------------------------
    % Compare with EKF result
    % -------------------------------------------------------------------
    ekf_row = ekf(ekf.flight_id == e.ekf_id, :);
    fprintf(fid, '\n  --- EKF comparison ---\n');

    if isempty(ekf_row)
        fprintf(fid, '  EKF ID %s not found in metrics table.\n', e.ekf_id);
    else
        % EKF peak altitude: not directly stored, but we can note final_z and duration
        final_z    = double(ekf_row.final_z_m);
        duration   = double(ekf_row.duration_sec);
        n_events   = double(ekf_row.num_events);
        baro_ratio = double(ekf_row.baro_update_ratio);

        fprintf(fid, '  EKF final_z    : %.2f m\n', final_z);
        fprintf(fid, '  EKF duration   : %.1f s\n', duration);
        fprintf(fid, '  EKF events     : %d  (baro ratio %.3f)\n', n_events, baro_ratio);

        % EKF peak altitude (peak_z_m column, added after Raven cold-start fix)
        if ismember('peak_z_m', ekf.Properties.VariableNames)
            ekf_peak_m = double(ekf_row.peak_z_m);
            abs_diff_m = abs(ekf_peak_m - peak_rel_m);
            agree_pct  = abs_diff_m / max(ekf_peak_m, peak_rel_m) * 100;
            fprintf(fid, '\n');
            fprintf(fid, '  GPS apogee AGL : %.1f m\n', peak_rel_m);
            fprintf(fid, '  EKF peak_z_m   : %.1f m\n', ekf_peak_m);
            fprintf(fid, '  Abs difference : %.1f m\n', abs_diff_m);
            fprintf(fid, '  Agreement      : %.2f%%\n', agree_pct);
        else
            fprintf(fid, '\n');
            fprintf(fid, '  GPS peak AGL   : %.1f m\n', peak_rel_m);
            fprintf(fid, '  EKF final_z    : %.2f m  (peak_z_m column not found)\n', final_z);
        end
    end

    % -------------------------------------------------------------------
    % Print a coarse altitude profile (10-point summary)
    % -------------------------------------------------------------------
    fprintf(fid, '\n  Coarse altitude profile (10 equal time steps):\n');
    fprintf(fid, '  %8s  %10s  %10s\n', 't_elapsed', 'ALT_ft', 'AGL_m');
    n = numel(t_elapsed);
    step_idx = unique(round(linspace(1, n, 10)));
    for si = step_idx
        fprintf(fid, '  %8.1f  %10.0f  %10.1f\n', ...
            t_elapsed(si), alt_sorted_ft(si), alt_relative_m(si));
    end

    fprintf(fid, '\n\n');

    % Store for summary
    results(i).ekf_id      = e.ekf_id;
    results(i).gps_peak_m  = peak_rel_m;
    results(i).t_at_peak   = t_at_peak;
    results(i).ground_m    = ground_m;
    results(i).n_good      = sum(good);
    results(i).duration_s  = duration_s;
end

% -----------------------------------------------------------------------
% Summary table
% -----------------------------------------------------------------------
fprintf(fid, '%s\n', repmat('=', 1, 72));
fprintf(fid, 'SUMMARY\n');
fprintf(fid, '%s\n', repmat('=', 1, 72));
fprintf(fid, '%-55s  %10s  %8s\n', 'flight_id', 'GPS_peak_m', 't_apex_s');
for i = 1:numel(results)
    if ~isfield(results(i), 'ekf_id') || isempty(results(i).ekf_id)
        continue;
    end
    fprintf(fid, '%-55s  %10.1f  %8.1f\n', ...
        results(i).ekf_id, results(i).gps_peak_m, results(i).t_at_peak);
end
fprintf(fid, '\n');
fprintf(fid, 'GPS altitude accuracy note:\n');
fprintf(fid, '  Consumer-grade GPS (Featherweight) vertical accuracy: approx. +/-10-30 m.\n');
fprintf(fid, '  GPS peak AGL should be interpreted as an independent order-of-magnitude\n');
fprintf(fid, '  check on the EKF apogee estimate, not a precision ground truth.\n');

fclose(fid);

% -----------------------------------------------------------------------
% Also print summary to console
% -----------------------------------------------------------------------
fprintf('\n');
type(out_txt);
fprintf('\nOutput written to: %s\n', out_txt);


