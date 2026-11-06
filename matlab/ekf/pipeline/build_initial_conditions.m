function [x0, P0, u0] = build_initial_conditions(prep, ekf_config)
% build_initial_conditions
% Construct initial state vector, covariance, and input from prep + config.
%
% Inputs:
%   prep       - struct from prepare_measurements_for_ekf
%   ekf_config - config struct from main.m
%
% Outputs:
%   x0 - 3x1 initial state [z; vz; b_a]
%   P0 - 3x3 initial covariance (diagonal)
%   u0 - initial held acceleration input

x0 = [ekf_config.init_z_m; ekf_config.init_vz_mps; ekf_config.init_ba_mps2];
if ekf_config.use_launch_relative_baro
    idx0 = find(isfinite(prep.events.baro_z_m), 1, 'first');
    if ~isempty(idx0)
        x0(1) = prep.events.baro_z_m(idx0);
    end
end
P0 = diag([ekf_config.init_var_z, ekf_config.init_var_vz, ekf_config.init_var_ba]);
u0 = ekf_config.initial_u_z_mps2;
end
