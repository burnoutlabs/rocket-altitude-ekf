function plot_info = plot_measurement_conventions(prep, varargin)
% plot_measurement_conventions
% Visualize locked measurement conventions for one prepared replay.
%
% Inputs:
%   prep - struct from prepare_measurements_for_ekf
%
% Name-Value options:
%   'figure_visible' - true/false (default: true)
%   'title_prefix'   - custom title prefix (default: '')

options = struct( ...
    'figure_visible', true, ...
    'title_prefix', "");
options = apply_name_value(options, varargin{:});

if ~isstruct(prep) || ~isfield(prep, 'events')
    error('prep must be a struct from prepare_measurements_for_ekf.');
end

events = prep.events;
is_imu = events.event_type == 'imu';
is_baro = events.event_type == 'baro';

vis = 'on';
if ~options.figure_visible
    vis = 'off';
end

f = figure('Name', ['Measurement Conventions: ' prep.flight_id], 'Visible', vis, 'Color', 'w');
f.Units = 'inches';
f.Position = [0.5 0.5 7 9];
f.PaperUnits = 'inches';
f.PaperSize = [7 9];
f.PaperPosition = [0 0 7 9];
tiled = tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile;
plot(ax1, events.t_flight_sec(is_baro), events.pressure_pa(is_baro), '.', 'MarkerSize', 4, 'Color', [0.00 0.45 0.74]);
grid(ax1, 'on');
ylabel(ax1, 'Pressure (Pa)', 'FontSize', 11);
set(ax1, 'Color', 'w', 'FontSize', 11, 'XTickLabel', {}, 'XColor', 'k', 'YColor', 'k');

ax2 = nexttile;
plot(ax2, events.t_flight_sec(is_baro), events.baro_alt_abs_m(is_baro), '-', 'LineWidth', 1.6, 'DisplayName', 'Absolute altitude');
hold(ax2, 'on');
plot(ax2, events.t_flight_sec(is_baro), events.baro_z_m(is_baro), '-', 'LineWidth', 1.6, 'DisplayName', 'Launch-relative altitude (EKF input)');
hold(ax2, 'off');
grid(ax2, 'on');
ylabel(ax2, 'Altitude (m)', 'FontSize', 11);
leg2 = legend(ax2, 'Location', 'best', 'FontSize', 10);
leg2.Color = 'w'; leg2.TextColor = 'k';
set(ax2, 'Color', 'w', 'FontSize', 11, 'XTickLabel', {}, 'XColor', 'k', 'YColor', 'k');

ax3 = nexttile;
plot(ax3, events.t_flight_sec(is_imu), events.accel_z_mps2(is_imu), '-', 'LineWidth', 1.2, 'DisplayName', 'Raw accel z');
hold(ax3, 'on');
plot(ax3, events.t_flight_sec(is_imu), events.accel_u_z_mps2(is_imu), '-', 'LineWidth', 1.6, 'DisplayName', 'Specific force u_z (EKF input)');
hold(ax3, 'off');
grid(ax3, 'on');
xlabel(ax3, 'Time (s)', 'FontSize', 11);
ylabel(ax3, 'Acceleration (m/s^{2})', 'FontSize', 11);
leg3 = legend(ax3, 'Location', 'best', 'FontSize', 10);
leg3.Color = 'w'; leg3.TextColor = 'k';
set(ax3, 'Color', 'w', 'FontSize', 11, 'XColor', 'k', 'YColor', 'k');
linkaxes([ax1, ax2, ax3], 'x');

flight_label = flight_id_to_label(prep.flight_id);
title_text = sprintf('%s   |   launch ref alt = %.3f m', flight_label, prep.launch_ref_alt_m);
if strlength(options.title_prefix) > 0
    title_text = sprintf('%s   %s', options.title_prefix, title_text);
end
title(tiled, title_text, 'Interpreter', 'none', 'FontSize', 11, 'Color', 'k');

plot_info = struct();
plot_info.figure_handle = f;
plot_info.flight_id = prep.flight_id;
plot_info.launch_ref_alt_m = prep.launch_ref_alt_m;
end


