function plot_info = plot_replay_timing(replay, varargin)
% plot_replay_timing
% Visualize merged event timing for one replay stream.
%
% Inputs:
%   replay - struct from build_replay_events
%
% Name-Value options:
%   'figure_visible' - true/false (default: true)
%   'title_prefix'   - custom title prefix (default: '')

options = struct( ...
    'figure_visible', true, ...
    'title_prefix', "");
options = apply_name_value(options, varargin{:});

if ~isstruct(replay) || ~isfield(replay, 'events')
    error('replay must be a struct from build_replay_events.');
end

events = replay.events;
t = events.t_flight_sec;
dt = events.dt_sec;
is_imu = events.event_type == 'imu';
is_baro = events.event_type == 'baro';

vis = 'on';
if ~options.figure_visible
    vis = 'off';
end
f = figure('Name', ['Replay Timing: ' replay.flight_id], 'Visible', vis, 'Color', 'w');
f.Units = 'inches';
f.Position = [0.5 0.5 7 9];
f.PaperUnits = 'inches';
f.PaperSize = [7 9];
f.PaperPosition = [0 0 7 9];
tiled = tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile;
plot(ax1, events.event_idx, t, '-', 'LineWidth', 1.4, 'Color', [0.00 0.45 0.74]);
grid(ax1, 'on');
xlabel(ax1, 'Event index', 'FontSize', 11);
ylabel(ax1, 'Time (s)', 'FontSize', 11);
set(ax1, 'Color', 'w', 'FontSize', 11, 'XColor', 'k', 'YColor', 'k');

t_end = max(t);
bin_edges = 0:1:ceil(t_end);
bin_centers = bin_edges(1:end-1) + 0.5;
imu_rate = histcounts(t(is_imu), bin_edges);
baro_rate = histcounts(t(is_baro), bin_edges);

ax2 = nexttile;
plot(ax2, bin_centers, imu_rate, '-', 'LineWidth', 1.4, 'Color', [0.00 0.45 0.74], 'DisplayName', 'IMU (events/s)');
hold(ax2, 'on');
plot(ax2, bin_centers, baro_rate, '-', 'LineWidth', 1.4, 'Color', [0.85 0.33 0.10], 'DisplayName', 'Baro (events/s)');
hold(ax2, 'off');
grid(ax2, 'on');
ylabel(ax2, 'Events/s', 'FontSize', 11);
leg2 = legend(ax2, 'Location', 'best', 'FontSize', 10);
leg2.Color = 'w'; leg2.TextColor = 'k';
set(ax2, 'Color', 'w', 'FontSize', 11, 'XColor', 'k', 'YColor', 'k');

ax3 = nexttile;
dt_vals = dt(dt > 0 & isfinite(dt));
dt_clip = prctile(dt_vals, 99.5);
histogram(ax3, dt_vals(dt_vals <= dt_clip), 60, 'FaceColor', [0.47 0.67 0.19], 'EdgeColor', 'none');
grid(ax3, 'on');
xlabel(ax3, 'Inter-event interval (s)', 'FontSize', 11);
ylabel(ax3, 'Count', 'FontSize', 11);
set(ax3, 'Color', 'w', 'FontSize', 11, 'XColor', 'k', 'YColor', 'k');

flight_label = flight_id_to_label(replay.flight_id);
base_title = sprintf('%s   |   %d events   dt [min/med/max] = %.4g / %.4g / %.4g s', ...
    flight_label, height(events), min(dt), median(dt), max(dt));
if strlength(options.title_prefix) > 0
    title(tiled, sprintf('%s   %s', options.title_prefix, base_title), 'Interpreter', 'none', 'FontSize', 11, 'Color', 'k');
else
    title(tiled, base_title, 'Interpreter', 'none', 'FontSize', 11, 'Color', 'k');
end

plot_info = struct();
plot_info.figure_handle = f;
plot_info.flight_id = replay.flight_id;
plot_info.total_events = height(events);
plot_info.dt_min_sec = min(dt);
plot_info.dt_median_sec = median(dt);
plot_info.dt_max_sec = max(dt);
end


