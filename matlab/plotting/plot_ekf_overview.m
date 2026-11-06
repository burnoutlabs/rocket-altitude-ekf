function plot_info = plot_ekf_overview(result, varargin)
% plot_ekf_overview
% High-level per-flight EKF diagnostic: altitude, velocity, bias.
%
% Inputs:
%   result - struct from run_vertical_ekf_replay (requires non-empty log)
%
% Name-Value options:
%   'figure_visible' - true/false (default: true)
%   'title_prefix'   - custom title prefix (default: '')

options = struct( ...
    'figure_visible', true, ...
    'title_prefix', "");
options = apply_name_value(options, varargin{:});

if ~isstruct(result) || ~isfield(result, 'log') || isempty(result.log)
    error('result.log is required and must be non-empty.');
end

log_tbl = result.log;
is_baro = log_tbl.event_type == 'baro';
baro_t = log_tbl.t_flight_sec(is_baro);
baro_z = log_tbl.baro_z_m(is_baro);
[~, idx_apogee] = max(log_tbl.z_hat_m);
t_apogee = log_tbl.t_flight_sec(idx_apogee);

vis = 'on';
if ~options.figure_visible
    vis = 'off';
end
f = figure('Name', ['EKF Overview: ' result.flight_id], 'Visible', vis, 'Color', 'w');
f.Units = 'inches';
f.Position = [0.5 0.5 7 9];
f.PaperUnits = 'inches';
f.PaperSize = [7 9];
f.PaperPosition = [0 0 7 9];
tiled = tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile;
plot(baro_t, baro_z, '.', 'MarkerSize', 5, 'Color', [0.55 0.55 0.80], 'DisplayName', 'Barometer');
hold on;
plot(log_tbl.t_flight_sec, log_tbl.z_hat_m, 'Color', [0.85 0.33 0.10], 'LineWidth', 1.6, 'DisplayName', 'EKF Estimate');
xline(t_apogee, '--', 'Color', [0.3 0.3 0.3], 'LineWidth', 0.8, 'HandleVisibility', 'off');
hold off;
grid on;
ylabel('Altitude (m)', 'FontSize', 11);
leg1 = legend('Location', 'best', 'FontSize', 10);
leg1.Color = 'w'; leg1.TextColor = 'k';
set(ax1, 'Color', 'w', 'FontSize', 11, 'XTickLabel', {}, 'XColor', 'k', 'YColor', 'k');

ax2 = nexttile;
plot(log_tbl.t_flight_sec, log_tbl.vz_hat_mps, 'Color', [0.47 0.67 0.19], 'LineWidth', 1.6);
hold on;
xline(t_apogee, '--', 'Color', [0.3 0.3 0.3], 'LineWidth', 0.8, 'HandleVisibility', 'off');
yline(0, ':', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.8, 'HandleVisibility', 'off');
hold off;
grid on;
ylabel('Velocity (m/s)', 'FontSize', 11);
set(ax2, 'Color', 'w', 'FontSize', 11, 'XTickLabel', {}, 'XColor', 'k', 'YColor', 'k');

ax3 = nexttile;
plot(log_tbl.t_flight_sec, log_tbl.ba_hat_mps2, 'Color', [0.49 0.18 0.56], 'LineWidth', 1.6);
grid on;
xlabel('Time (s)', 'FontSize', 11);
ylabel('Accel. Bias (m/s^{2})', 'FontSize', 11);
set(ax3, 'Color', 'w', 'FontSize', 11, 'XColor', 'k', 'YColor', 'k');
linkaxes([ax1, ax2, ax3], 'x');

flight_label = flight_id_to_label(result.flight_id);
title_text = sprintf('%s   |   %d IMU + %d baro events', ...
    flight_label, sum(log_tbl.event_type == 'imu'), sum(is_baro));
if strlength(options.title_prefix) > 0
    title_text = sprintf('%s   %s', options.title_prefix, title_text);
end
title(tiled, title_text, 'Interpreter', 'none', 'FontSize', 11, 'Color', 'k');

plot_info = struct();
plot_info.figure_handle = f;
plot_info.flight_id = result.flight_id;
plot_info.baro_points = numel(baro_t);
end



