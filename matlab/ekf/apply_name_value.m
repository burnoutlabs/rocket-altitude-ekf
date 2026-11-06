function out = apply_name_value(defaults, varargin)
% apply_name_value
% Simple name-value parser used across EKF module functions.

out = defaults;
if mod(numel(varargin), 2) ~= 0
    error('Name-value arguments must be provided in pairs.');
end

for i = 1:2:numel(varargin)
    name = varargin{i};
    value = varargin{i + 1};

    if ~ischar(name) && ~isstring(name)
        error('Option names must be char or string.');
    end

    key = char(name);
    if ~isfield(out, key)
        error('Unknown option: %s', key);
    end

    out.(key) = value;
end
end

