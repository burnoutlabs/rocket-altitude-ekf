function altitude_m = altitude_from_pressure_pa(pressure_pa, varargin)
% altitude_from_pressure_pa
% Convert pressure (Pa) to altitude (m) using ISA troposphere relation.
%
% Name-Value options:
%   'p0_pa' - sea-level reference pressure (default: 101325 Pa)
%
% Formula:
%   h = (T0/L) * (1 - (p/p0)^(R*L/g0))
% with constants for ISA troposphere.

options = struct('p0_pa', 101325);
options = apply_name_value(options, varargin{:});

pressure_pa = double(pressure_pa);
altitude_m = nan(size(pressure_pa));

valid = isfinite(pressure_pa) & isfinite(options.p0_pa) & (pressure_pa > 0) & (options.p0_pa > 0);
if ~any(valid)
    return;
end

% ISA constants
T0 = 288.15;      % K
L  = 0.0065;      % K/m
g0 = 9.80665;     % m/s^2
R  = 287.05287;   % J/(kg*K)
exp_term = R * L / g0;  % approx 0.190263

ratio = pressure_pa(valid) ./ options.p0_pa;
altitude_m(valid) = (T0 / L) .* (1 - ratio .^ exp_term);
end

