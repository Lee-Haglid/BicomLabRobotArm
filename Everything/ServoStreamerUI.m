function ServoStreamerUI
% ServoStreamUI - 5-joint live queue streamer + HR send
%
% Expected file columns:
%   Tout, Bottom, Mid, top, Elbow, Wrist
%
% Protocol:
%   MATLAB -> HR <bpm>
%   MATLAB -> START
%   MATLAB -> t_ms,bottom,mid,top,elbow,wrist
%   MATLAB -> END
%   MATLAB -> STOP
%   MATLAB -> ZERO

    state.filePath = "trajectory.csv";
    state.port = "COM5";
    state.baud = 115200;
    state.timeUnit = "seconds";
    state.sp = [];
    state.running = false;
    state.stopRequested = false;
    state.latestQueueFill = 0;
    state.doneReceived = false;
    state.endAckReceived = false;
    state.rxLogFID = [];
    state.rxLogPath = "";
    state.hrBpm = 72;

    TARGET_FILL = 18;
    LOW_WATER = 8;

    fig = uifigure('Name','Arduino 5-Joint Live Streamer','Position',[100 100 760 530]);

    uilabel(fig,'Position',[20 475 80 22],'Text','CSV/XLSX:');
    fileField = uieditfield(fig,'text','Position',[100 475 470 22],'Value',state.filePath);
    uibutton(fig,'push','Position',[580 475 110 22],'Text','Browse...', ...
        'ButtonPushedFcn',@(~,~)safeRun(@onBrowse));

    uilabel(fig,'Position',[20 435 50 22],'Text','Port:');
    portDrop = uidropdown(fig,'Position',[100 435 150 22], ...
        'Items',getPortsSafe(),'ValueChangedFcn',@onPortChange);
    uibutton(fig,'push','Position',[260 435 80 22],'Text','Refresh', ...
        'ButtonPushedFcn',@(~,~)safeRun(@onRefreshPorts));

    uilabel(fig,'Position',[360 435 45 22],'Text','Baud:');
    baudField = uieditfield(fig,'numeric','Position',[410 435 90 22], ...
        'Value',state.baud,'Limits',[1200 2000000]);
    baudField.RoundFractionalValues = true;
    baudField.ValueDisplayFormat = '%.0f';

    uilabel(fig,'Position',[20 395 110 22],'Text','Timestamp unit:');
    unitDrop = uidropdown(fig,'Position',[140 395 120 22], ...
        'Items',{'seconds','ms'},'Value',state.timeUnit);

    % NEW: HR controls
    uilabel(fig,'Position',[300 395 110 22],'Text','Heart Rate BPM:');
    hrField = uieditfield(fig,'numeric','Position',[420 395 80 22], ...
        'Value',state.hrBpm,'Limits',[1 240]);
    hrField.RoundFractionalValues = true;
    hrField.ValueDisplayFormat = '%.0f';

    sendHrBtn = uibutton(fig,'push','Position',[520 395 100 22],'Text','Send HR', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onSendHR));

    connectBtn = uibutton(fig,'push','Position',[20 345 120 34],'Text','Connect', ...
        'ButtonPushedFcn',@(~,~)safeRun(@onConnect));
    disconnectBtn = uibutton(fig,'push','Position',[150 345 120 34],'Text','Disconnect', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onDisconnect));
    streamBtn = uibutton(fig,'push','Position',[280 345 140 34],'Text','Stream Live', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onStreamLive));
    stopBtn = uibutton(fig,'push','Position',[430 345 90 34],'Text','Stop', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onStop));
    zeroBtn = uibutton(fig,'push','Position',[530 345 80 34],'Text','Zero', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onZero));

    uilabel(fig,'Position',[20 305 100 22],'Text','Arduino log:');
    logBox = uitextarea(fig,'Position',[20 20 710 285],'Editable','off');
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
        [f,p] = uigetfile({'*.xlsx;*.xls;*.csv','Trajectory Files (*.xlsx,*.xls,*.csv)';'*.*','All Files'}, ...
            'Select trajectory file');
        if isequal(f,0), return; end
        state.filePath = string(fullfile(p,f));
        fileField.Value = state.filePath;
        logMsg("Selected file: " + state.filePath);
    end

    function onPortChange(src,~)
        val = string(src.Value);
        if val == "<none>"
            state.port = "";
        else
            state.port = val;
        end
    end

    function onRefreshPorts
        ports = getPortsSafe();
        portDrop.Items = ports;
        if ~isempty(ports) && strlength(ports{1}) > 0
            portDrop.Value = ports{1};
            if string(ports{1}) == "<none>"
                state.port = "";
            else
                state.port = string(ports{1});
            end
        end
        logMsg("Ports refreshed.");
    end

    function onConnect
        state.baud = baudField.Value;
        state.timeUnit = string(unitDrop.Value);
        state.hrBpm = round(hrField.Value);

        try
            if ~isempty(state.sp), clearSerial(); end
            if strlength(state.port) == 0 || state.port == "<none>"
                error("No serial port selected.");
            end

            state.sp = serialport(state.port, state.baud);
            configureTerminator(state.sp, "LF");
            state.sp.Timeout = 0.2;
            pause(2);

            openRxLog();
            pumpSerial(0.5);

            logMsg("Connected to " + state.port + " @ " + state.baud + " baud.");
            connectBtn.Enable = 'off';
            disconnectBtn.Enable = 'on';
            streamBtn.Enable = 'on';
            stopBtn.Enable = 'off';
            zeroBtn.Enable = 'on';
            sendHrBtn.Enable = 'on';

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
        sendHrBtn.Enable = 'off';
    end

    function onSendHR
        if isempty(state.sp)
            logMsg("ERROR: Not connected.");
            return;
        end
        if state.running
            logMsg("HR update blocked while streaming.");
            return;
        end

        state.hrBpm = round(hrField.Value);
        writeline(state.sp, sprintf('HR %d', state.hrBpm));
        waitForCondition(@() false, 0.2);
        logMsg("Sent HR " + state.hrBpm + " BPM.");
    end

    function onZero
        if isempty(state.sp)
            logMsg("ERROR: Not connected.");
            return;
        end
        if state.running
            logMsg("Zero blocked: currently running.");
            return;
        end

        writeline(state.sp, "ZERO");
        waitForCondition(@() false, 0.3);
        logMsg("Zero command sent.");
    end

    function onStop
        state.stopRequested = true;
        logMsg("Stop requested.");
    end

    function onStreamLive
        if isempty(state.sp)
            logMsg("ERROR: Not connected.");
            return;
        end

        streamBtn.Enable = 'off';
        stopBtn.Enable = 'on';
        zeroBtn.Enable = 'off';
        sendHrBtn.Enable = 'off';
        state.running = true;
        state.stopRequested = false;
        state.doneReceived = false;
        state.endAckReceived = false;
        state.latestQueueFill = 0;
        state.hrBpm = round(hrField.Value);

        try
            filePath = string(fileField.Value);
            if strlength(filePath) == 0 || ~isfile(filePath)
                error("Trajectory file not found.");
            end

            data = ReadCSVfile(filePath, state.timeUnit, 0);
            N = numel(data.t_ms_full);

            [outPath, base, ~] = fileparts(filePath);
            sentLogPath = fullfile(outPath, base + "_SENT_TO_ARDUINO.csv");
            sentTbl = table(double(data.t_ms_full(:)), ...
                            data.bottom_raw(:), data.mid_raw(:), data.top_raw(:), data.elbow_raw(:), data.wrist_raw(:), ...
                            data.bottom_tx(:), data.mid_tx(:), data.top_tx(:), data.elbow_tx(:), data.wrist_tx(:), ...
                'VariableNames', {'t_ms_full','bottom_raw','mid_raw','top_raw','elbow_raw','wrist_raw', ...
                                  'bottom_tx','mid_tx','top_tx','elbow_tx','wrist_tx'});
            writetable(sentTbl, sentLogPath);

            logMsg("Loaded " + N + " points.");
            logMsg("Wrote send-log: " + sentLogPath);

            flushInput();

            % NEW: send HR first
            writeline(state.sp, sprintf('HR %d', state.hrBpm));
            waitForCondition(@() false, 0.2);
            logMsg("Sent startup HR " + state.hrBpm + " BPM.");

            writeline(state.sp, "START");
            waitForCondition(@() false, 0.25);

            nextIdx = 1;

            while nextIdx <= N && state.latestQueueFill < TARGET_FILL
                sendPoint(nextIdx, data);
                nextIdx = nextIdx + 1;
                waitForCondition(@() false, 0.02);
            end

            while true
                if state.stopRequested
                    writeline(state.sp, "STOP");
                    waitForCondition(@() false, 0.3);
                    logMsg("Stopped.");
                    break;
                end

                pumpSerial(0.02);

                if nextIdx <= N
                    if state.latestQueueFill <= LOW_WATER
                        while nextIdx <= N && state.latestQueueFill < TARGET_FILL
                            sendPoint(nextIdx, data);
                            nextIdx = nextIdx + 1;
                            waitForCondition(@() false, 0.01);
                            if state.stopRequested
                                break;
                            end
                        end
                    end
                else
                    if ~state.endAckReceived
                        writeline(state.sp, "END");
                        logMsg("END sent.");
                        waitForCondition(@() state.endAckReceived, 1.0);
                    end

                    if state.doneReceived
                        logMsg("Live stream complete.");
                        break;
                    end
                end

                drawnow limitrate;
            end

        catch ME
            logMsg("STREAM ERROR: " + string(ME.message));
        end

        state.running = false;
        state.stopRequested = false;
        streamBtn.Enable = 'on';
        stopBtn.Enable = 'off';
        if ~isempty(state.sp)
            zeroBtn.Enable = 'on';
            sendHrBtn.Enable = 'on';
        else
            zeroBtn.Enable = 'off';
            sendHrBtn.Enable = 'off';
        end
    end

    function sendPoint(k, data)
        line = sprintf('%u,%d,%d,%d,%d,%d', ...
            data.t_ms_full(k), ...
            data.bottom_tx(k), data.mid_tx(k), data.top_tx(k), data.elbow_tx(k), data.wrist_tx(k));
        writeline(state.sp, line);
    end

    function tf = waitForCondition(condFcn, durationSec)
        t0 = tic;
        tf = false;
        while toc(t0) < durationSec
            pumpSerial(0.01);
            if condFcn()
                tf = true;
                return;
            end
            pause(0.002);
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
            pause(0.002);
        end
    end

    function handleArduinoLine(rx)
        try
            if ~isempty(state.rxLogFID) && state.rxLogFID > 0
                fprintf(state.rxLogFID, "[%s] %s\n", datestr(now,'HH:MM:SS.FFF'), string(rx));
            end
        catch
        end

        s = string(rx);

        if startsWith(s, "ACK ")
            parts = split(s);
            if numel(parts) >= 2
                n = str2double(parts(2));
                if ~isnan(n)
                    state.latestQueueFill = n;
                end
            end
        elseif s == "DONE"
            state.doneReceived = true;
        elseif s == "END-ACK"
            state.endAckReceived = true;
        end

        if strlength(s) > 0
            logMsg("ARDUINO: " + s);
        end
    end

    function flushInput()
        if isempty(state.sp), return; end
        pause(0.05);
        while state.sp.NumBytesAvailable > 0
            rx = strtrim(readline(state.sp));
            handleArduinoLine(rx);
        end
    end

    function ports = getPortsSafe()
        try
            ports = cellstr(serialportlist("available"));
        catch
            ports = {};
        end
        if isempty(ports)
            ports = {'<none>'};
        end
    end

    function openRxLog()
        try
            filePath = string(fileField.Value);
            if strlength(filePath) == 0
                filePath = "session";
            end
            [outPath, base, ~] = fileparts(filePath);
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