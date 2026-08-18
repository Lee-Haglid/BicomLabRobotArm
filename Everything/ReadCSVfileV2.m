function data = ReadCSVfile(csvFile, timeUnit, offset)
% ReadCSVfile - read trajectory CSV and convert to Arduino-ready data
%
% Inputs:
%   csvFile  - path to CSV file
%   timeUnit - "seconds" or "ms"
%   offset   - optional offset added on MATLAB side before transmission
%
% Output fields:
%   data.t_ms_full
%   data.a1_raw, data.a2_raw, data.a3_raw
%   data.a1_tx,  data.a2_tx,  data.a3_tx
%
% For your current Arduino code:
%   - send signed angles in roughly [-90, 90]
%   - Arduino adds +90 internally before servo write
% So usually keep offset = 0 here.

    arguments
        csvFile (1,1) string
        timeUnit (1,1) string {mustBeMember(timeUnit,["seconds","ms"])}
        offset (1,1) double = 0
    end

    if ~isfile(csvFile)
        error("ReadCSVfile:FileNotFound", "CSV file not found: %s", csvFile);
    end

    T = readtable(csvFile);

    if width(T) < 4
        error("ReadCSVfile:BadFormat", ...
            "CSV must have at least 4 columns: time, deg1, deg2, deg3.");
    end

    t  = T{:,1};
    a1 = T{:,2};
    a2 = T{:,3};
    a3 = T{:,4};

    if ~isnumeric(t) || ~isnumeric(a1) || ~isnumeric(a2) || ~isnumeric(a3)
        error("ReadCSVfile:NonNumeric", ...
            "The first four CSV columns must be numeric.");
    end

    if isempty(t)
        error("ReadCSVfile:Empty", "CSV file contains no data rows.");
    end

    % Convert timestamps to relative ms
    if timeUnit == "seconds"
        t_ms_full = uint32(round(1000 * (t - t(1))));
    else
        t_ms_full = uint32(round(t - t(1)));
    end

    if any(diff(double(t_ms_full)) < 0)
        error("ReadCSVfile:TimeOrder", ...
            "Timestamps must be monotonically increasing.");
    end

    % Values to transmit to Arduino
    a1_tx = clampSigned90(round(a1 + offset));
    a2_tx = clampSigned90(round(a2 + offset));
    a3_tx = clampSigned90(round(a3 + offset));

    data = struct();
    data.t_ms_full = t_ms_full(:);

    data.a1_raw = a1(:);
    data.a2_raw = a2(:);
    data.a3_raw = a3(:);

    data.a1_tx = a1_tx(:);
    data.a2_tx = a2_tx(:);
    data.a3_tx = a3_tx(:);
end

function y = clampSigned90(x)
    y = min(max(x,-90),90);
end