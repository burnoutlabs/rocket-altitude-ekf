function [x_upd, P_upd, info] = ekf_update_baro( ...
    x_pred, P_pred, z_baro, ...
    r_baro_var, min_variance_floor, ...
    enforce_covariance_symmetry, ...
    enable_innovation_gate, innovation_gate_nsigma)
% ekf_update_baro
% Linear barometric altitude update: y = z + v,  v ~ N(0, r_baro_var).
%
% This is the baseline linear KF measurement step — provided for A/B comparison
% against ekf_update_baro_pressure. It treats baro altitude directly as the
% measurement, using a fixed H = [1 0 0] and constant R = r_baro_var [m^2].
%
% Limitation: real barometers measure pressure, not altitude. Applying a fixed
% linear model ignores the nonlinear ISA pressure-altitude relationship and the
% altitude-dependent sensitivity of the sensor. Use ekf_update_baro_pressure for
% the physically correct EKF update.

% H = [1, 0, 0]: altitude is the only state that directly couples to this measurement.
H = [1, 0, 0];

% --- Guard: skip update on invalid sensor input ---
if ~isfinite(z_baro)
    x_upd = x_pred;
    P_upd = P_pred;
    info = struct('used', false, ...
        'innovation', nan, ...
        'innovation_raw', nan, ...
        'innovation_m_equiv', nan, ...
        'S', nan, 'K', [nan; nan; nan], ...
        'nis', nan, 'gated_out', false, ...
        'measurement_unit', 'm', ...
        'reason', 'nonfinite measurement');
    return;
end

% --- Innovation: residual between measured altitude and predicted altitude ---
% nu = y - H*x^- = z_baro - z_hat
innovation = z_baro - H * x_pred;
% Innovation covariance S = H*P^-*H' + R (scalar here since H is 1x3)
S = H * P_pred * H' + r_baro_var;

% --- Innovation gate (NIS test) ---
gate = innovation_gate(innovation, S, enable_innovation_gate, innovation_gate_nsigma);
if ~gate.accepted
    x_upd = x_pred;
    P_upd = P_pred;
    info = struct('used', false, ...
        'innovation', innovation, ...
        'innovation_raw', innovation, ...
        'innovation_m_equiv', innovation, ...
        'S', S, 'K', [nan; nan; nan], ...
        'nis', gate.nis, 'gated_out', true, ...
        'measurement_unit', 'm', ...
        'reason', 'innovation gate rejected');
    return;
end

% --- Kalman gain: K = P^- * H' / S ---
K = (P_pred * H') / S;
% --- State update: x^+ = x^- + K * nu ---
x_upd = x_pred + K * innovation;

% --- Joseph-form covariance update ---
% Same rationale as ekf_update_baro_pressure: preserves symmetry and
% positive-definiteness under finite-precision arithmetic.
I = eye(3);
KH = K * H;
P_upd = (I - KH) * P_pred * (I - KH)' + K * r_baro_var * K';

if enforce_covariance_symmetry
    P_upd = 0.5 * (P_upd + P_upd');
end
for i = 1:3
    if ~isfinite(P_upd(i, i)) || P_upd(i, i) < min_variance_floor
        P_upd(i, i) = min_variance_floor;
    end
end

info = struct('used', true, ...
    'innovation', innovation, ...
    'innovation_raw', innovation, ...
    'innovation_m_equiv', innovation, ...
    'S', S, 'K', K, ...
    'nis', gate.nis, 'gated_out', false, ...
    'measurement_unit', 'm', ...
    'reason', 'ok');
end

function gate = innovation_gate(innovation, S, enable_innovation_gate, innovation_gate_nsigma)
% innovation_gate: compute NIS and accept/reject the measurement.
% Identical logic to the version in ekf_update_baro_pressure.
if ~isfinite(innovation) || ~isfinite(S) || S <= 0
    gate = struct('accepted', false, 'nis', inf, 'threshold', innovation_gate_nsigma ^ 2);
    return;
end

nis = (innovation * innovation) / S;      % NIS = nu^2 / S ~ chi^2(1) when filter is consistent
threshold = innovation_gate_nsigma ^ 2;
accepted = ~enable_innovation_gate || (nis <= threshold);
gate = struct('accepted', accepted, 'nis', nis, 'threshold', threshold);
end
