function [x_pred, P_pred, dt_used] = ekf_predict( ...
    x, P, u_z, dt_sec, ...
    q_vz_psd, q_ba_psd, ...
    min_dt_sec, max_dt_sec, ...
    min_variance_floor, enforce_covariance_symmetry)
% ekf_predict
% One predict step for x = [z; vz; b_a] with control input u_z.
%
% Implements the kinematic constant-acceleration predict equations:
%   z_{k+1}  = z_k + vz_k*dt + 0.5*(u_z - b_a)*dt^2
%   vz_{k+1} = vz_k + (u_z - b_a)*dt
%   b_{a,k+1}= b_a_k  (bias held constant between updates)
%
% The state Jacobian F is exact (no linearization) because the process model
% is linear in state. The EKF approximation only enters at the measurement step.

% Clamp dt to [min_dt_sec, max_dt_sec] to guard against zero-length first steps
% and runaway uncertainty growth during data gaps.
dt = max(min_dt_sec, min(max_dt_sec, double(dt_sec)));
dt_used = dt;

% Unpack state for readability.
z = x(1);
vz = x(2);
ba = x(3);
% Effective kinematic acceleration: subtract bias from gravity-compensated IMU.
% u_z = a_IMU - g, so acc_eff ≈ 0 on pad, positive during motor burn.
acc_eff = u_z - ba;

% --- State prediction (Eq. 7-9 in report) ---
x_pred = [z + vz * dt + 0.5 * acc_eff * dt * dt; ...  % z: kinematic position update
    vz + acc_eff * dt; ...                              % vz: velocity += net accel * dt
    ba];                                                % b_a: bias modeled as constant (random walk driven by Qd)

% --- State Jacobian (Eq. 10 in report) ---
% F is the exact discrete-time linearization; no approximation is made here.
F = [1, dt, -0.5 * dt * dt; ...   % dz/d[z, vz, b_a]
    0, 1, -dt; ...                 % dvz/d[z, vz, b_a]
    0, 0, 1];                      % db_a/d[z, vz, b_a]

% --- Covariance prediction (Eq. 11 in report): P^- = F*P*F' + Qd ---
% Qd is scaled by dt so uncertainty accumulates proportionally to elapsed time.
Qd = discretize_process_noise(dt, q_vz_psd, q_ba_psd);
P_pred = F * P * F' + Qd;

% Enforce numerical symmetry: floating-point ops can introduce tiny asymmetry
% over thousands of steps; this costs one matrix op and guarantees P = P'.
if enforce_covariance_symmetry
    P_pred = 0.5 * (P_pred + P_pred');
end

% Variance floor: prevent diagonal entries from hitting exactly zero, which
% would cause division-by-zero in the Kalman gain. Activates only on degenerate steps.
for i = 1:3
    if ~isfinite(P_pred(i, i)) || P_pred(i, i) < min_variance_floor
        P_pred(i, i) = min_variance_floor;
    end
end
end

function Qd = discretize_process_noise(dt, q_vz_psd, q_ba_psd)
% discretize_process_noise
% Compute discrete-time process noise Qd(dt) from continuous-time PSDs.
%
% Derived by exact integration of Phi(tau)*Qc*Phi(tau)' over [0, dt].
% Two independent noise sources are combined:
%   Qv: velocity disturbance (q_vz_psd) — models unmodeled thrust, aero, wind.
%   Qb: bias random walk (q_ba_psd) — models slow IMU bias drift.
%
% Polynomial dt terms arise from integrating powers of the state transition matrix:
%   Qd_zz  ~ dt^3/3  (velocity disturbance double-integrates into position)
%   Qd_zvz ~ dt^2/2  (velocity disturbance integrates into position)
%   Qd_vzvz~ dt      (velocity disturbance acts directly)
%   Qd_bb  ~ dt      (bias random walk acts directly)
% Scaling by dt (not fixed Q) is correct for variable-step asynchronous replay.
Qd = zeros(3, 3);
if dt <= 0
    return;
end

% Precompute powers of dt to avoid repeated multiplication.
dt2 = dt * dt;
dt3 = dt2 * dt;
dt4 = dt3 * dt;
dt5 = dt4 * dt;

% Qv: contribution from velocity disturbance w_vz.
% Rows/cols: [z, vz, b_a]. Bias row/col is zero — w_vz does not drive b_a.
Qv = q_vz_psd * [dt3 / 3, dt2 / 2, 0; ...
    dt2 / 2, dt, 0; ...
    0, 0, 0];

% Qb: contribution from bias random walk w_b.
% Bias noise propagates into z and vz through the kinematic coupling, producing
% cross-terms and higher-order dt polynomials.
Qb = q_ba_psd * [dt5 / 20, dt4 / 8, -dt3 / 6; ...
    dt4 / 8, dt3 / 3, -dt2 / 2; ...
    -dt3 / 6, -dt2 / 2, dt];

% Symmetrize analytically to cancel any floating-point asymmetry from Qv + Qb.
Qd = 0.5 * (Qv + Qb + Qv' + Qb');
end
