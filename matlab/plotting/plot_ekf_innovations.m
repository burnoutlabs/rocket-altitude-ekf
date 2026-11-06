function plot_info = plot_ekf_innovations(result, varargin)
% plot_ekf_innovations
% Plot innovation and NIS over baro-update events.

options = struct( ...
    'figure_visible', true, ...
    'title_prefix', "");
options = apply_name_value(options, varargin{:});

if ~isstruct(result) || ~isfield(result, 'log') || isempty(result.log)
    error('result.log is required and must be non-empty.');
end

log_tbl = result.log;
upd_mask = log_tbl.event_type == 'baro';
t = log_tbl.t_flight_sec(upd_mask);
innov = log_tbl.innovation_m(upd_mask);
nis = log_tbl.nis(upd_mask);
used = log_tbl.update_used(upd_mask);
gated = log_tbl.gated_out(upd_mask);

measurement_model = "altitude_linear";
if isfield(result, 'summary') && isfield(result.summary, 'measurement_model')
    measurement_model = string(result.summary.measurement_model);
end

vis = 'on';
if ~options.figure_visible
    vis = 'off';
end
f = figure('Name', ['EKF Innovations: ' result.flight_id], 'Visible', vis, 'Color', 'w');
f.Units = 'inches';
f.Position = [0.5 0.5 7 5.5];
f.PaperUnits = 'inches';
f.PaperSize = [7 5.5];
f.PaperPosition = [0 0 7 5.5];
tiled = tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile;
plot(t(used), innov(used), '.', 'MarkerSize', 4, 'Color', [0.00 0.45 0.74], 'DisplayName', 'Innovation (used)');
hold on;
if any(gated)
    plot(t(gated), innov(gated), 'x', 'MarkerSize', 6, 'LineWidth', 1.2, ...
        'Color', [0.85 0.33 0.10], 'DisplayName', 'Gated out');
end
yline(0, '-', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.8, 'HandleVisibility', 'off');
hold off;
grid on;
if measurement_model == "pressure_nonlinear"
    ylabel('Innovation, z-equiv (m)', 'FontSize', 11);
else
    ylabel('Innovation (m)', 'FontSize', 11);
end
leg1 = legend('Location', 'best', 'FontSize', 10);
leg1.Color = 'w'; leg1.TextColor = 'k';
set(ax1, 'Color', 'w', 'FontSize', 11, 'XTickLabel', {}, 'XColor', 'k', 'YColor', 'k');

ax2 = nexttile;
nis_used = nis(used);
nis_clip = max(prctile(nis_used, 99), 10);
nis_clipped = any(nis_used > nis_clip);
plot(t(used), nis_used, '.', 'MarkerSize', 4, 'Color', [0.47 0.67 0.19], 'DisplayName', 'NIS');
hold on;
yline(3.84, '--r', 'LineWidth', 1.2, 'DisplayName', '\chi^2_1(0.95) = 3.84');
hold off;
grid on;
if nis_clipped
    ylim([-0.1 * nis_clip, nis_clip * 1.05]);
else
    ylim([-1, max(max(nis_used) * 1.1, 5)]);
end
xlabel('Time (s)', 'FontSize', 11);
ylabel('NIS (1-DOF)', 'FontSize', 11);
leg2 = legend('Location', 'best', 'FontSize', 10);
leg2.Color = 'w'; leg2.TextColor = 'k';
set(ax2, 'Color', 'w', 'FontSize', 11, 'XColor', 'k', 'YColor', 'k');
linkaxes([ax1, ax2], 'x');

flight_label = flight_id_to_label(result.flight_id);
title_text = sprintf('%s   |   %d baro updates, %d gated   [%s]', ...
    flight_label, sum(used), sum(gated), measurement_model);
if strlength(options.title_prefix) > 0
    title_text = sprintf('%s   %s', options.title_prefix, title_text);
end
title(tiled, title_text, 'Interpreter', 'none', 'FontSize', 11, 'Color', 'k');

plot_info = struct();
plot_info.figure_handle = f;
plot_info.flight_id = result.flight_id;
plot_info.baro_events = numel(t);
plot_info.used_updates = sum(used);
plot_info.gated_updates = sum(gated);
plot_info.nis_mean = mean(nis(used), 'omitnan');
end


