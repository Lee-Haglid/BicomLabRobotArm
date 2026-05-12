function ServoStreamUIV6
% ServoStreamUI - 5-joint live queue streamer
%
% Expected file columns:
%   Tout, Bottom, Mid, top, Elbow, Wrist

    state.filePath = "trajectory.csv";
    state.port = "";
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

    TARGET_FILL = 18;
    LOW_WATER = 8;

    fig = uifigure('Name','Arduino 5-Joint Live Streamer','Position',[100 100 720 490]);

    uilabel(fig,'Position',[20 435 80 22],'Text','CSV/XLSX:');
    fileField = uieditfield(fig,'text','Position',[100 435 470 22],'Value',state.filePath);
    uibutton(fig,'push','Position',[580 435 110 22],'Text','Browse...', ...
        'ButtonPushedFcn',@(~,~)safeRun(@onBrowse));

    uilabel(fig,'Position',[20 395 50 22],'Text','Port:');

    initialPorts = getPortsSafe();
    portDrop = uidropdown(fig,'Position',[100 395 150 22], ...
        'Items', initialPorts, ...
        'Value', initialPorts{1}, ...
        'ValueChangedFcn', @onPortChange);

    if ~strcmp(initialPorts{1}, "<none>")
        state.port = string(initialPorts{1});
    end

    uibutton(fig,'push','Position',[260 395 80 22],'Text','Refresh', ...
        'ButtonPushedFcn',@(~,~)safeRun(@onRefreshPorts));

    uilabel(fig,'Position',[360 395 45 22],'Text','Baud:');
    baudField = uieditfield(fig,'numeric','Position',[410 395 90 22], ...
        'Value',state.baud,'Limits',[1200 2000000]);
    baudField.RoundFractionalValues = true;
    baudField.ValueDisplayFormat = '%.0f';

    uilabel(fig,'Position',[20 355 110 22],'Text','Timestamp unit:');
    unitDrop = uidropdown(fig,'Position',[140 355 120 22], ...
        'Items',{'seconds','ms'},'Value',state.timeUnit);

    connectBtn = uibutton(fig,'push','Position',[20 305 120 34],'Text','Connect', ...
        'ButtonPushedFcn',@(~,~)safeRun(@onConnect));
    disconnectBtn = uibutton(fig,'push','Position',[150 305 120 34],'Text','Disconnect', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onDisconnect));
    streamBtn = uibutton(fig,'push','Position',[280 305 140 34],'Text','Stream Live', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onStreamLive));
    stopBtn = uibutton(fig,'push','Position',[430 305 90 34],'Text','Stop', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onStop));
    zeroBtn = uibutton(fig,'push','Position',[530 305 80 34],'Text','Zero', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onZero));

    uilabel(fig,'Position',[20 265 100 22],'Text','Arduino log:');
    logBox = uitextarea(fig,'Position',[20 20 670 245],'Editable','off');
    logBox.Value = strings(0,1);

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
        newPorts = getPortsSafe();

        oldValue = string(portDrop.Value);
        portDrop.Items = newPorts;

        if any(strcmp(newPorts, oldValue))
            portDrop.Value = char(oldValue);
        else
            portDrop.Value = newPorts{1};
        end

        if string(portDrop.Value) == "<none>"
            state.port = "";
        else
            state.port = string(portDrop.Value);
        end

        logMsg("Ports refreshed.");
    end

    function onConnect
        state.baud = baudField.Value;
        state.timeUnit = string(unitDrop.Value);

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
        state.running = true;
        state.stopRequested = false;
        state.doneReceived = false;
        state.endAckReceived = false;
        state.latestQueueFill = 0;

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
        else
            zeroBtn.Enable = 'off';
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

    function flushInput
        if isempty(state.sp), return; end
        pause(0.05);
        while state.sp.NumBytesAvailable > 0
            rx = strtrim(readline(state.sp));
            handleArduinoLine(rx);
        end
    end

    function ports = getPortsSafe
        try
            ports = cellstr(serialportlist("available"));
        catch
            ports = {};
        end

        if isempty(ports)
            ports = {'<none>'};
        end
    end

    function openRxLog
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

    function closeRxLog
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

    function clearSerial
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