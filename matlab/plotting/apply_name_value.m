function out = apply_name_value(defaults, varargin)
% apply_name_value  Apply name-value pairs to a defaults struct.
%
% Usage:
%   opts = apply_name_value(struct('a', 1, 'b', 2), 'a', 10)
%
% Errors on unknown keys or an odd number of arguments.

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
