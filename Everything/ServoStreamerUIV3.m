function ServoStreamerUI
% ServoStreamUI - live buffered serial streamer for Arduino servo playback
% CSV format: time, deg1, deg2, deg3
%
% Live streaming protocol:
%   Arduino startup / reset:
%       READY
%       BUF n
%
%   MATLAB -> Arduino:
%       START
%       t_ms,a1,a2,a3
%       ...
%       END
%
%   Arduino -> MATLAB:
%       READY
%       BUF n         current buffered point count
%       PLAYING       once first point starts executing
%       rpy: a b c    actual commanded servo positions
%       DONE          after END received and buffer fully drained
%
% Notes:
%   - MATLAB sends signed angles in [-90, 90]
%   - Arduino adds +90 offset internally before servo write
%   - Zero button only works when not running

    % ------------ Defaults ------------
    state.csvFile = "trajectory.csv";
    state.port = "COM5";
    state.baud = 115200;
    state.timeUnit = "seconds";
    state.sp = [];
    state.stopRequested = false;
    state.running = false;
    state.rxLogFID = [];
    state.rxLogPath = "";
    state.latestBufCount = inf;
    state.endSeen = false;

    % streaming thresholds
    TARGET_FILL = 18;   % try to keep this many points buffered
    LOW_WATER   = 8;    % refill when below this

    fig = uifigure('Name','Arduino Servo Live Streamer','Position',[100 100 640 440]);

    uilabel(fig,'Position',[20 395 70 22],'Text','CSV File:');
    fileField = uieditfield(fig,'text','Position',[90 395 390 22],'Value',state.csvFile);
    uibutton(fig,'push','Position',[490 395 120 22],'Text','Browse...', ...
        'ButtonPushedFcn',@(~,~)safeRun(@onBrowse));

    uilabel(fig,'Position',[20 355 70 22],'Text','Port:');
    portDrop = uidropdown(fig,'Position',[90 355 160 22], ...
        'Items',getPorts(),'ValueChangedFcn',@onPortChange);

    uibutton(fig,'push','Position',[260 355 80 22],'Text','Refresh', ...
        'ButtonPushedFcn',@(~,~)safeRun(@onRefreshPorts));

    uilabel(fig,'Position',[360 355 50 22],'Text','Baud:');
    baudField = uieditfield(fig,'numeric','Position',[410 355 90 22], ...
        'Value',state.baud,'Limits',[1200 2000000]);
    baudField.RoundFractionalValues = true;
    baudField.ValueDisplayFormat = '%.0f';

    uilabel(fig,'Position',[20 315 120 22],'Text','Timestamp unit:');
    unitDrop = uidropdown(fig,'Position',[140 315 120 22], ...
        'Items',{'seconds','ms'},'Value',state.timeUnit);

    connectBtn = uibutton(fig,'push','Position',[20 265 120 34],'Text','Connect', ...
        'ButtonPushedFcn',@(~,~)safeRun(@onConnect));

    disconnectBtn = uibutton(fig,'push','Position',[150 265 120 34],'Text','Disconnect', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onDisconnect));

    streamBtn = uibutton(fig,'push','Position',[280 265 140 34],'Text','Stream Live', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onStreamLive));

    stopBtn = uibutton(fig,'push','Position',[430 265 90 34],'Text','Stop', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onStop));

    zeroBtn = uibutton(fig,'push','Position',[530 265 80 34],'Text','Zero', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onZero));

    uilabel(fig,'Position',[20 225 100 22],'Text','Arduino log:');
    logBox = uitextarea(fig,'Position',[20 20 590 205],'Editable','off');
    logBox.Value = strings(0,1);

    if ~isempty(portDrop.Items)
        if any(strcmp(portDrop.Items, state.port))
            portDrop.Value = state.port;
        else
            state.port = string(portDrop.Value);
        end
    end

    logMsg("UI ready.");

    function onBrowse
        [f,p] = uigetfile({'*.csv','CSV Files (*.csv)';'*.*','All Files'}, 'Select trajectory CSV');
        if isequal(f,0)
            return;
        end
        state.csvFile = string(fullfile(p,f));
        fileField.Value = state.csvFile;
        logMsg("Selected file: " + state.csvFile);
    end

    function onPortChange(src,~)
        state.port = string(src.Value);
    end

    function onRefreshPorts
        ports = getPorts();
        if isempty(ports)
            ports = {''};
        end
        portDrop.Items = ports;
        if ~isempty(ports) && strlength(ports{1}) > 0
            portDrop.Value = ports{1};
            state.port = string(ports{1});
        end
        logMsg("Ports refreshed.");
    end

    function onConnect
        state.baud = baudField.Value;
        state.timeUnit = string(unitDrop.Value);

        try
            if ~isempty(state.sp)
                clearSerial();
            end
            if strlength(state.port) == 0
                error("No serial port selected.");
            end

            state.sp = serialport(state.port, state.baud);
            configureTerminator(state.sp, "LF");
            state.sp.Timeout = 0.1;
            pause(2);

            openRxLog();
            pumpSerial(0.5);

            logMsg("Connected to " + state.port + " @ " + state.baud + " baud.");
            connectBtn.Enable = 'off';
            disconnectBtn.Enable = 'on';
            streamBtn.Enable = 'on';
            stopBtn.Enable = 'off';
            zeroBtn.Enable = 'on';

        catch ME
            logMsg("CONNECT ERROR: " + string(ME.message));
            clearSerial();
        end
    end

    function onDisconnect
        clearSerial();
        logMsg("Disconnected.");
        connectBtn.Enable = 'on';
        disconnectBtn.Enable = 'off';
        streamBtn.Enable = 'off';
        stopBtn.Enable = 'off';
        zeroBtn.Enable = 'off';
    end

    function onStop
        state.stopRequested = true;
        logMsg("Stop requested.");
    end

    function onZero
        if isempty(state.sp)
            logMsg("ERROR: Not connected.");
            return;
        end
        if state.running
            logMsg("Zero blocked: stream is running.");
            return;
        end

        writeline(state.sp, "ZERO");
        pause(0.1);
        pumpSerial(0.5);
        logMsg("Zero command sent.");
    end

    function onStreamLive
        if isempty(state.sp)
            logMsg("ERROR: Not connected.");
            return;
        end

        streamBtn.Enable = 'off';
        stopBtn.Enable = 'on';
        zeroBtn.Enable = 'off';
        state.stopRequested = false;
        state.running = true;
        state.endSeen = false;
        state.latestBufCount = 0;

        try
            csvPath = string(fileField.Value);
            if strlength(csvPath) == 0 || ~isfile(csvPath)
                error("CSV file not found.");
            end

            data = ReadCSVfile(csvPath, state.timeUnit, 0);
            N = numel(data.t_ms_full);
            logMsg("Loaded " + N + " CSV points.");

            [outPath, base, ~] = fileparts(csvPath);
            sentLogPath = fullfile(outPath, base + "_SENT_TO_ARDUINO.csv");
            sentTbl = table(double(data.t_ms_full(:)), ...
                            data.a1_raw(:), data.a2_raw(:), data.a3_raw(:), ...
                            data.a1_tx(:), data.a2_tx(:), data.a3_tx(:), ...
                'VariableNames', {'t_ms_full','a1_raw','a2_raw','a3_raw','a1_tx','a2_tx','a3_tx'});
            writetable(sentTbl, sentLogPath);
            logMsg("Wrote send-log: " + sentLogPath);

            % clear stale input and start new run
            pumpSerial(0.2);
            writeline(state.sp, "START");
            pause(0.05);
            pumpSerial(0.3);

            nextIdx = 1;

            % initial fill
            while nextIdx <= N && state.latestBufCount < TARGET_FILL
                sendPoint(nextIdx, data);
                nextIdx = nextIdx + 1;
                pumpSerial(0.02);
            end

            % continuous streaming loop
            while ~state.stopRequested
                pumpSerial(0.02);

                if nextIdx <= N
                    if state.latestBufCount <= LOW_WATER
                        while nextIdx <= N && state.latestBufCount < TARGET_FILL
                            sendPoint(nextIdx, data);
                            nextIdx = nextIdx + 1;
                            pumpSerial(0.01);
                        end
                    end
                else
                    % all points sent, send END once and wait for DONE
                    if ~state.endSeen
                        writeline(state.sp, "END");
                        state.endSeen = true;
                        logMsg("END sent. Waiting for Arduino to drain buffer...");
                    end

                    if sawDoneRecently()
                        break;
                    end
                end

                drawnow limitrate;
            end

            if state.stopRequested
                writeline(state.sp, "STOP");
                pumpSerial(0.3);
                logMsg("Stopped.");
            else
                logMsg("Live stream complete.");
            end

        catch ME
            logMsg("STREAM ERROR: " + string(ME.message));
        end

        state.running = false;
        streamBtn.Enable = 'on';
        stopBtn.Enable = 'off';
        state.stopRequested = false;
        if ~isempty(state.sp)
            zeroBtn.Enable = 'on';
        else
            zeroBtn.Enable = 'off';
        end
    end

    function tf = sawDoneRecently
        persistent doneFlag
        if isempty(doneFlag)
            doneFlag = false;
        end
        tf = doneFlag;
        if tf
            doneFlag = false;
        end

        function setDoneFlag
            doneFlag = true;
        end
    end

    function sendPoint(k, data)
        line = sprintf('%u,%d,%d,%d', data.t_ms_full(k), data.a1_tx(k), data.a2_tx(k), data.a3_tx(k));
        writeline(state.sp, line);
    end

    function ports = getPorts()
        try
            ports = cellstr(serialportlist("available"));
        catch
            ports = {};
        end
    end

    function pumpSerial(durationSec)
        t0 = tic;
        while toc(t0) < durationSec
            while ~isempty(state.sp) && state.sp.NumBytesAvailable > 0
                rx = strtrim(readline(state.sp));
                handleArduinoLine(rx);
            end
            drawnow limitrate;
            pause(0.005);
        end
    end

    function handleArduinoLine(rx)
        try
            if ~isempty(state.rxLogFID) && state.rxLogFID > 0
                fprintf(state.rxLogFID, "[%s] %s\n", datestr(now,'HH:MM:SS.FFF'), string(rx));
            end
        catch
        end

        if startsWith(string(rx), "BUF ")
            parts = split(string(rx));
            if numel(parts) >= 2
                n = str2double(parts(2));
                if ~isnan(n)
                    state.latestBufCount = n;
                end
            end
        elseif strcmp(string(rx), "DONE")
            state.endSeen = true;
            % lightweight completion latch
            persistent doneStamp
            doneStamp = now;
        end

        if strlength(string(rx)) > 0
            logMsg("ARDUINO: " + string(rx));
        end
    end

    function openRxLog()
        try
            csvPath = string(fileField.Value);
            if strlength(csvPath) == 0
                csvPath = "session";
            end
            [outPath, base, ~] = fileparts(csvPath);
            if strlength(outPath) == 0
                outPath = pwd;
            end
            state.rxLogPath = fullfile(outPath, base + "_ARDUINO_RX_LOG.txt");
            state.rxLogFID = fopen(state.rxLogPath, 'a');
            if state.rxLogFID > 0
                fprintf(state.rxLogFID, "===== NEW SESSION %s =====\n", datestr(now,'yyyy-mm-dd HH:MM:SS'));
            end
        catch
        end
    end

    function closeRxLog()
        try
            if ~isempty(state.rxLogFID) && state.rxLogFID > 0
                fprintf(state.rxLogFID, "===== END SESSION %s =====\n\n", datestr(now,'yyyy-mm-dd HH:MM:SS'));
                fclose(state.rxLogFID);
            end
        catch
        end
        state.rxLogFID = [];
    end

    function safeRun(fn)
        try
            fn();
        catch ME
            try
                logMsg("UI ERROR: " + string(ME.message));
            catch
            end
            disp(getReport(ME,'extended'));
            uialert(fig, string(ME.message), "Callback Error");
        end
    end

    function logMsg(msg)
        ts = datestr(now,'HH:MM:SS');
        newLine = "[" + string(ts) + "] " + string(msg);
        v = string(logBox.Value(:));
        v = [v; newLine];
        if numel(v) > 300
            v = v(end-299:end);
        end
        logBox.Value = v;
        drawnow limitrate;
    end

    function clearSerial()
        try
            closeRxLog();
            if ~isempty(state.sp)
                delete(state.sp);
            end
        catch
        end
        state.sp = [];
        state.running = false;
    end
end