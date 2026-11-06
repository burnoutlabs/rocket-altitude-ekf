function plot_info = plot_ekf_covariance(result, varargin)
% plot_ekf_covariance
% Plot EKF covariance diagonal trends.

options = struct( ...
    'figure_visible', true, ...
    'title_prefix', "");
options = apply_name_value(options, varargin{:});

if ~isstruct(result) || ~isfield(result, 'log') || isempty(result.log)
    error('result.log is required and must be non-empty.');
end

log_tbl = result.log;
t = log_tbl.t_flight_sec;

vis = 'on';
if ~options.figure_visible
    vis = 'off';
end
f = figure('Name', ['EKF Covariance: ' result.flight_id], 'Visible', vis, 'Color', 'w');
f.Units = 'inches';
f.Position = [0.5 0.5 7 4.5];
f.PaperUnits = 'inches';
f.PaperSize = [7 4.5];
f.PaperPosition = [0 0 7 4.5];
ax = axes(f);
semilogy(ax, t, log_tbl.P_zz, 'LineWidth', 1.6, 'DisplayName', 'P_{zz} (m^2)');
hold(ax, 'on');
semilogy(ax, t, log_tbl.P_vzvz, 'LineWidth', 1.6, 'DisplayName', 'P_{v_z,v_z} (m^2 s^{-2})');
semilogy(ax, t, log_tbl.P_baba, 'LineWidth', 1.6, 'DisplayName', 'P_{b_a,b_a} (m^2 s^{-4})');
hold(ax, 'off');
grid(ax, 'on');
grid(ax, 'minor');
xlabel(ax, 'Time (s)', 'FontSize', 11);
ylabel(ax, 'Variance (log scale)', 'FontSize', 11);
leg = legend(ax, 'Location', 'best', 'FontSize', 10, 'Interpreter', 'tex');
leg.Color = 'w'; leg.TextColor = 'k';
set(ax, 'Color', 'w', 'FontSize', 11, 'XColor', 'k', 'YColor', 'k');

flight_label = flight_id_to_label(result.flight_id);
title_text = sprintf('%s   |   EKF covariance diagonal', flight_label);
if strlength(options.title_prefix) > 0
    title_text = sprintf('%s   %s', options.title_prefix, title_text);
end
title(ax, title_text, 'Interpreter', 'none', 'FontSize', 11, 'Color', 'k');

plot_info = struct();
plot_info.figure_handle = f;
plot_info.flight_id = result.flight_id;
plot_info.P_zz_min = min(log_tbl.P_zz, [], 'omitnan');
plot_info.P_zz_max = max(log_tbl.P_zz, [], 'omitnan');
end


