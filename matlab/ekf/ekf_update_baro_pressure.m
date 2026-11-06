function [x_upd, P_upd, info] = ekf_update_baro_pressure( ...
    x_pred, P_pred, pressure_meas_pa, ...
    p0_pa, r_baro_var_alt_m2, z_ref_m, ...
    min_variance_floor, enforce_covariance_symmetry, ...
    enable_innovation_gate, innovation_gate_nsigma)
% ekf_update_baro_pressure
% Pressure-domain nonlinear baro update — core EKF measurement step.
%
% This is where the EKF approximation enters. The barometer measures pressure
% (Pa), not altitude (m). The ISA tropospheric model h(z) is nonlinear, so the
% EKF linearizes it at the predicted state to obtain H_k = dh/dz, then performs
% a standard linear Kalman update in the pressure domain.
%
% State:
%   x = [z; vz; b_a], where z is launch-relative altitude [m].
%
% Measurement model (Eq. 14 in report):
%   y = h(x) + v_p,   v_p ~ N(0, R_eff)
%   h(x) = p0 * (1 - z_abs/H_T)^beta,   z_abs = z + z_ref
%
% Noise parameter convention (Eq. 16 in report):
%   r_baro_var_alt_m2 is tuned in altitude units [m^2] for interpretability.
%   It is mapped to pressure-domain variance at each call:
%       R_eff = (dh/dz)^2 * r_baro_var_alt_m2
%   This gives altitude-dependent measurement confidence: the filter trusts
%   baro more at low altitude (large |dh/dz|) and less near apogee (small |dh/dz|).

% --- Guard: skip update on invalid sensor input ---
% Non-positive or non-finite pressure means a dead or clipped sensor sample.
if ~isfinite(pressure_meas_pa) || pressure_meas_pa <= 0 || ~isfinite(p0_pa) || p0_pa <= 0
    x_upd = x_pred;
    P_upd = P_pred;
    info = struct('used', false, ...
        'innovation', nan, ...
        'innovation_raw', nan, ...
        'innovation_m_equiv', nan, ...
        'S', nan, 'K', [nan; nan; nan], ...
        'nis', nan, 'gated_out', false, ...
        'measurement_unit', 'Pa', ...
        'R_eff', nan, ...
        'reason', 'nonfinite or invalid pressure input');
    return;
end

% Fallback: if launch-site elevation is unknown, treat as sea level.
if ~isfinite(z_ref_m)
    z_ref_m = 0;
end

% --- Linearize h(z) at predicted altitude (EKF measurement Jacobian) ---
% z_abs = predicted launch-relative altitude + launch-site elevation.
% Returns: predicted pressure p_pred_pa, Jacobian dh/dz, and clamped flag.
[p_pred_pa, dh_dz, model_clamped] = pressure_model_and_jacobian(x_pred(1) + z_ref_m, p0_pa);
if ~isfinite(p_pred_pa) || ~isfinite(dh_dz) || abs(dh_dz) < eps
    x_upd = x_pred;
    P_upd = P_pred;
    info = struct('used', false, ...
        'innovation', nan, ...
        'innovation_raw', nan, ...
        'innovation_m_equiv', nan, ...
        'S', nan, 'K', [nan; nan; nan], ...
        'nis', nan, 'gated_out', false, ...
        'measurement_unit', 'Pa', ...
        'R_eff', nan, ...
        'reason', 'invalid pressure model linearization');
    return;
end

% --- Measurement Jacobian and effective noise (Eqs. 15-16 in report) ---
% H = [dh/dz, 0, 0]: only altitude state couples to pressure measurement.
% R_eff maps altitude-domain variance to pressure-domain variance at this altitude.
H = [dh_dz, 0, 0];
R_eff = (dh_dz * dh_dz) * r_baro_var_alt_m2;  % R_eff = H_k^2 * r_baro
if ~isfinite(R_eff) || R_eff < min_variance_floor
    R_eff = min_variance_floor;
end

% --- Innovation: residual between measured and predicted pressure (Eq. 17) ---
% Positive innovation => measured pressure higher than predicted => lower than expected altitude.
innovation_pa = pressure_meas_pa - p_pred_pa;
% Innovation covariance S = H*P^-*H' + R_eff (Eq. 18)
S = H * P_pred * H' + R_eff;

% --- Innovation gate (NIS test) ---
% NIS = nu^2 / S ~ chi^2(1) for a consistent filter. Gate is currently disabled
% globally; fixed thresholds starve the filter during high-dynamic boost.
gate = innovation_gate(innovation_pa, S, enable_innovation_gate, innovation_gate_nsigma);
if ~gate.accepted
    x_upd = x_pred;
    P_upd = P_pred;
    info = struct('used', false, ...
        'innovation', innovation_pa, ...
        'innovation_raw', innovation_pa, ...
        'innovation_m_equiv', innovation_pa / dh_dz, ...
        'S', S, 'K', [nan; nan; nan], ...
        'nis', gate.nis, 'gated_out', true, ...
        'measurement_unit', 'Pa', ...
        'R_eff', R_eff, ...
        'reason', gate_reject_reason(model_clamped));
    return;
end

% --- Kalman gain (Eq. 19): K = P^- * H' / S ---
% Scalar S so division is safe; no matrix inversion needed.
K = (P_pred * H') / S;
% --- State update (Eq. 20): x^+ = x^- + K * nu ---
x_upd = x_pred + K * innovation_pa;

% --- Joseph-form covariance update (Eq. 21 in report) ---
% Equivalent to (I-KH)*P^-*(I-KH)' + K*R*K' .
% Preferred over the simpler (I-KH)*P^- because it is symmetric by construction
% and preserves positive-definiteness under finite-precision arithmetic.
I = eye(3);
KH = K * H;
P_upd = (I - KH) * P_pred * (I - KH)' + K * R_eff * K';

% Symmetrize after Joseph form for the same reason as in ekf_predict.
if enforce_covariance_symmetry
    P_upd = 0.5 * (P_upd + P_upd');
end
% Variance floor on diagonal — same guard as in ekf_predict.
for i = 1:3
    if ~isfinite(P_upd(i, i)) || P_upd(i, i) < min_variance_floor
        P_upd(i, i) = min_variance_floor;
    end
end

% Return diagnostics for logging. innovation_m_equiv converts Pa back to metres
% via the local Jacobian slope for interpretable residual plots.
info = struct('used', true, ...
    'innovation', innovation_pa, ...
    'innovation_raw', innovation_pa, ...
    'innovation_m_equiv', innovation_pa / dh_dz, ...
    'S', S, 'K', K, ...
    'nis', gate.nis, 'gated_out', false, ...
    'measurement_unit', 'Pa', ...
    'R_eff', R_eff, ...
    'reason', success_reason(model_clamped));
end

function [p_pa, dp_dz, clamped] = pressure_model_and_jacobian(z_abs_m, p0_pa)
% pressure_model_and_jacobian
% Evaluate the ISA tropospheric pressure model and its altitude derivative.
%
% Model: p = p0 * (1 - z_abs/H_T)^beta
%   H_T  = T0/L ≈ 44330.77 m  (scale height at standard lapse rate)
%   beta = g0/(Rd*L) ≈ 5.25588  (barometric formula exponent)
%
% Jacobian: dp/dz = -p0 * (beta/H_T) * (1 - z_abs/H_T)^(beta-1)
%   Evaluated at the predicted altitude; this is H_k in the EKF update.
%   Magnitude decreases with altitude: ~12 Pa/m at sea level, ~9 Pa/m at 3000 m.

% ISA troposphere constants (ICAO Doc 7488)
T0 = 288.15;      % Sea-level standard temperature [K]
L = 0.0065;       % Temperature lapse rate [K/m]
g0 = 9.80665;     % Standard gravity [m/s^2]
R = 287.05287;    % Specific gas constant for dry air [J/(kg*K)]

H = T0 / L;               % Scale height ≈ 44330.77 m
beta = g0 / (R * L);      % Exponent ≈ 5.25588

% Normalized altitude term: (1 - z/H_T) — must be positive for real pressure.
base = 1 - (z_abs_m / H);
clamped = false;
if ~isfinite(base) || base <= 0
    % Altitude above ISA tropopause or non-physical: clamp to small positive value
    % so the model remains numerically valid. Flagged via clamped = true.
    base = 1e-6;
    clamped = true;
end

p_pa   = p0_pa * (base ^ beta);                     % Predicted pressure [Pa]
dp_dz  = -p0_pa * (beta / H) * (base ^ (beta - 1)); % dh/dz [Pa/m] (negative: pressure falls with altitude)
end

function gate = innovation_gate(innovation, S, enable_innovation_gate, innovation_gate_nsigma)
% innovation_gate
% Compute NIS and decide whether to accept or reject the measurement.
%
% NIS = nu^2 / S ~ chi^2(1) for a well-tuned consistent filter (mean = 1.0).
% Gate threshold is (n_sigma)^2; e.g. n_sigma=2 => threshold=4 (chi^2 95th pct = 3.84).
% When enable_innovation_gate is false, all finite measurements are accepted.
if ~isfinite(innovation) || ~isfinite(S) || S <= 0
    % Degenerate innovation or covariance — reject without computing NIS.
    gate = struct('accepted', false, 'nis', inf, 'threshold', innovation_gate_nsigma ^ 2);
    return;
end

nis = (innovation * innovation) / S;      % Normalized Innovation Squared
threshold = innovation_gate_nsigma ^ 2;   % Gate threshold in NIS units
accepted = ~enable_innovation_gate || (nis <= threshold);  % Always accept when gating off
gate = struct('accepted', accepted, 'nis', nis, 'threshold', threshold);
end

function txt = gate_reject_reason(model_clamped)
txt = 'innovation gate rejected';
if model_clamped
    txt = [txt, ' (pressure model clamped)'];
end
end

function txt = success_reason(model_clamped)
txt = 'ok';
if model_clamped
    txt = 'ok (pressure model clamped)';
end
end
