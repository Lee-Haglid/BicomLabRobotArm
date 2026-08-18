function data = ReadCSVfile(filePath, timeUnit, offset)
% ReadCSVfile - read 5-joint trajectory file for Teensy SD playback
%
% Expected columns by name if present:
%   Tout, Bottom, Mid, Top, Elbow, Wrist
%
% Fallback:
%   first 6 numeric columns in that order
%
% This version keeps motor angles as decimals.
% Time is converted to integer milliseconds because the Teensy playback code
% uses uint32 millisecond timestamps.

    arguments
        filePath (1,1) string
        timeUnit (1,1) string {mustBeMember(timeUnit,["seconds","ms"])}
        offset (1,1) double = 0
    end

    if ~isfile(filePath)
        error("ReadCSVfile:FileNotFound", "File not found: %s", filePath);
    end

    [~,~,ext] = fileparts(filePath);
    ext = lower(ext);

    if ext == ".csv"
        T = readtable(filePath);
    else
        T = readtable(filePath, "FileType", "spreadsheet");
    end

    vars = string(T.Properties.VariableNames);
    varsLower = lower(strrep(strrep(vars," ",""),"_",""));

    idxTime   = find(varsLower == "tout", 1);
    idxBottom = find(varsLower == "bottom", 1);
    idxMid    = find(varsLower == "mid", 1);
    idxTop    = find(varsLower == "top", 1);
    idxElbow  = find(varsLower == "elbow", 1);
    idxWrist  = find(varsLower == "wrist", 1);

    if isempty(idxTime) || isempty(idxBottom) || isempty(idxMid) || isempty(idxTop) || isempty(idxElbow) || isempty(idxWrist)
        if width(T) < 6
            error("ReadCSVfile:BadFormat", ...
                "Need at least 6 columns: Tout, Bottom, Mid, Top, Elbow, Wrist.");
        end

        idxTime   = 1;
        idxBottom = 2;
        idxMid    = 3;
        idxTop    = 4;
        idxElbow  = 5;
        idxWrist  = 6;
    end

    t      = T{:,idxTime};
    bottom = T{:,idxBottom};
    mid    = T{:,idxMid};
    top    = T{:,idxTop};
    elbow  = T{:,idxElbow};
    wrist  = T{:,idxWrist};

    if ~isnumeric(t) || ~isnumeric(bottom) || ~isnumeric(mid) || ~isnumeric(top) || ~isnumeric(elbow) || ~isnumeric(wrist)
        error("ReadCSVfile:NonNumeric", "Trajectory columns must be numeric.");
    end

    if isempty(t)
        error("ReadCSVfile:Empty", "File contains no data rows.");
    end

    t = double(t);
    bottom = double(bottom);
    mid    = double(mid);
    top    = double(top);
    elbow  = double(elbow);
    wrist  = double(wrist);

    if timeUnit == "seconds"
        t_ms_full = uint32(round(1000 * (t - t(1))));
    else
        t_ms_full = uint32(round(t - t(1)));
    end

    if any(diff(double(t_ms_full)) < 0)
        error("ReadCSVfile:TimeOrder", "Timestamps must be monotonically increasing.");
    end

    bottom_tx = clampSigned90(bottom + offset);
    mid_tx    = clampSigned90(mid + offset);
    top_tx    = clampSigned90(top + offset);
    elbow_tx  = clampSigned90(elbow + offset);
    wrist_tx  = clampSigned90(wrist + offset);

    data = struct();
    data.t_ms_full = t_ms_full(:);

    data.bottom_raw = bottom(:);
    data.mid_raw    = mid(:);
    data.top_raw    = top(:);
    data.elbow_raw  = elbow(:);
    data.wrist_raw  = wrist(:);

    data.bottom_tx = bottom_tx(:);
    data.mid_tx    = mid_tx(:);
    data.top_tx    = top_tx(:);
    data.elbow_tx  = elbow_tx(:);
    data.wrist_tx  = wrist_tx(:);
end

function y = clampSigned90(x)
    y = min(max(double(x), -90), 90);
end