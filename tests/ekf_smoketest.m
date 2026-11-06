%% EKF Playground Smoke Test
% Exercises the custom vertical EKF on a synthetic constant-altitude
% trajectory (flat-pad hold) so we can confirm the filter converges.
% Run from any directory; adds matlab/ekf/ to the path automatically.

ekf_path = fullfile(fileparts(mfilename('fullpath')), '..', 'matlab', 'ekf');
addpath(ekf_path);

%% Simulation parameters
rng(0);
dt      = 0.05;          % 20 Hz baro
N       = 200;           % 10 seconds
z_true  = 100;           % [m] constant altitude (pad hold)
ba_true = 0.3;           % [m/s^2] accel bias

%% Measurement noise
r_baro  = 8^2;           % baro variance [m^2]

%% Initial conditions
x0 = [90; 0; 0];         % z, vz, ba — poor initial guess
P0 = diag([2500, 900, 25]);

%% EKF config
q_vz_psd = 4.0;
q_ba_psd = 0.05^2;
min_dt   = 1e-3;
max_dt   = 5.0;
vfloor   = 1e-9;
sym_enf  = true;
gate_on  = false;
gate_ns  = 3.0;
p0_pa    = 101325;

%% Storage
x_log = zeros(3, N);
P_log = zeros(3, N);

x = x0;  P = P0;

for k = 1:N
    % Predict (zero acceleration input after removing bias)
    u_k = ba_true;
    [x, P] = ekf_predict(x, P, u_k, dt, ...
        q_vz_psd, q_ba_psd, min_dt, max_dt, vfloor, sym_enf);

    % Baro measurement (linear altitude update)
    z_meas = z_true + sqrt(r_baro) * randn;
    [x, P, uinfo] = ekf_update_baro(x, P, z_meas, r_baro, vfloor, sym_enf, gate_on, gate_ns);

    x_log(:, k) = x;
    P_log(:, k) = diag(P);
end

%% Results
final_err_z  = abs(x(1) - z_true);
final_std_z  = sqrt(P_log(1, end));
final_std_vz = sqrt(P_log(2, end));
final_std_ba = sqrt(P_log(3, end));

fprintf('--- EKF Smoke Test Results ---\n');
fprintf('True altitude:       %.1f m\n', z_true);
fprintf('Final estimate z:    %.4f m  (error: %.4f m)\n', x(1), final_err_z);
fprintf('Final sigma_z:       %.4f m\n', final_std_z);
fprintf('Final sigma_vz:      %.4f m/s\n', final_std_vz);
fprintf('Final sigma_ba:      %.6f m/s^2\n', final_std_ba);
fprintf('Last update used:    %s\n', string(uinfo.used));
fprintf('------------------------------\n');

assert(final_err_z < 3 * final_std_z, 'z estimate outside 3-sigma — filter may have diverged');
assert(final_std_z < 2.5, 'sigma_z did not converge (> 2.5 m) in 10 s of 20 Hz baro');
fprintf('All assertions passed.\n');
