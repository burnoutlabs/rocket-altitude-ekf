function [headers, header_line] = read_csv_header(file_path)
% read_csv_header
% Read first CSV header line and return trimmed tokens.

fid = fopen(file_path, 'r');
if fid == -1
    error('Unable to open file: %s', file_path);
end
cleanup = onCleanup(@() fclose(fid));

header_line = fgetl(fid);
if ~ischar(header_line)
    error('File does not contain a readable header line: %s', file_path);
end

parts = strsplit(header_line, ',');
headers = strtrim(parts);
end
