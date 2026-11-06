function plot_info = plot_ekf_event_timeline(result, varargin)
% plot_ekf_event_timeline
% Plot event timeline and dt distribution for EKF run log.

options = struct( ...
    'figure_visible', true, ...
    'title_prefix', "");
options = apply_name_value(options, varargin{:});

if ~isstruct(result) || ~isfield(result, 'log') || isempty(result.log)
    error('result.log is required and must be non-empty.');
end

log_tbl = result.log;
is_imu = log_tbl.event_type == 'imu';
is_baro = log_tbl.event_type == 'baro';

vis = 'on';
if ~options.figure_visible
    vis = 'off';
end
f = figure('Name', ['EKF Event Timeline: ' result.flight_id], 'Visible', vis, 'Color', 'w');
f.Units = 'inches';
f.Position = [0.5 0.5 7 5.5];
f.PaperUnits = 'inches';
f.PaperSize = [7 5.5];
f.PaperPosition = [0 0 7 5.5];
tiled = tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

t_end = max(log_tbl.t_flight_sec);
bin_edges = 0:1:ceil(t_end);
bin_centers = bin_edges(1:end-1) + 0.5;
imu_rate = histcounts(log_tbl.t_flight_sec(is_imu), bin_edges);
baro_rate = histcounts(log_tbl.t_flight_sec(is_baro), bin_edges);

ax1 = nexttile;
plot(ax1, bin_centers, imu_rate, '-', 'LineWidth', 1.4, 'Color', [0.00 0.45 0.74], 'DisplayName', 'IMU (events/s)');
hold on;
plot(ax1, bin_centers, baro_rate, '-', 'LineWidth', 1.4, 'Color', [0.85 0.33 0.10], 'DisplayName', 'Baro (events/s)');
hold off;
grid on;
ylabel('Events/s', 'FontSize', 11);
leg1 = legend('Location', 'best', 'FontSize', 10);
leg1.Color = 'w'; leg1.TextColor = 'k';
set(ax1, 'Color', 'w', 'FontSize', 11, 'XTickLabel', {}, 'XColor', 'k', 'YColor', 'k');

ax2 = nexttile;
dt_vals = log_tbl.dt_sec(log_tbl.dt_sec > 0 & isfinite(log_tbl.dt_sec));
dt_clip = prctile(dt_vals, 99.5);
histogram(ax2, dt_vals(dt_vals <= dt_clip), 60, 'FaceColor', [0.47 0.67 0.19], 'EdgeColor', 'none');
grid on;
xlabel('Inter-event interval (s)', 'FontSize', 11);
ylabel('Count', 'FontSize', 11);
set(ax2, 'Color', 'w', 'FontSize', 11, 'XColor', 'k', 'YColor', 'k');

flight_label = flight_id_to_label(result.flight_id);
title_text = sprintf('%s   |   %d total events (%d IMU, %d baro)', ...
    flight_label, height(log_tbl), sum(is_imu), sum(is_baro));
if strlength(options.title_prefix) > 0
    title_text = sprintf('%s   %s', options.title_prefix, title_text);
end
title(tiled, title_text, 'Interpreter', 'none', 'FontSize', 11, 'Color', 'k');

plot_info = struct();
plot_info.figure_handle = f;
plot_info.flight_id = result.flight_id;
plot_info.dt_min_sec = min(log_tbl.dt_sec);
plot_info.dt_max_sec = max(log_tbl.dt_sec);
end


