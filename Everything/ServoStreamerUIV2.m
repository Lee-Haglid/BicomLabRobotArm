function ServoStreamerUI
% ServoStreamUI - UI to stream CSV trajectory to Arduino over serial
% CSV format: time, deg1, deg2, deg3
%
% Protocol:
%   For each chunk (<= MAX_SAMPLES):
%     PC -> "CLEAR"          Arduino replies "CLEARED", "RDY"
%     PC -> lines "t_ms,a1,a2,a3" Arduino replies "RDY" each line
%     PC -> "END"            Arduino replies "LOADED n", "OK", "RDY"
%     PC -> "PLAY"           Arduino plays; ends with "DONE", then "RDY"
%
% Notes:
%   - MATLAB does not print every sent coordinate
%   - Arduino should print "rpy: a b c" during playback
%   - Zero button only works when not running

    % ------------ Defaults ------------
    state.csvFile = "trajectory.csv";
    state.port = "COM5";
    state.baud = 115200;
    state.timeUnit = "seconds";   % "seconds" or "ms"
    state.sp = [];
    state.stopRequested = false;
    state.running = false;
    state.rxLogFID = [];
    state.rxLogPath = "";

    MAX_SAMPLES = 180;
    OFFSET = 0;   % keep 0 if Arduino adds +90 itself

    % ------------ UI Figure ------------
    fig = uifigure('Name','Arduino Servo CSV Streamer','Position',[100 100 620 420]);

    uilabel(fig,'Position',[20 375 70 22],'Text','CSV File:');
    fileField = uieditfield(fig,'text','Position',[90 375 380 22],'Value',state.csvFile);
    uibutton(fig,'push','Position',[480 375 120 22],'Text','Browse...', ...
        'ButtonPushedFcn',@(~,~)safeRun(@onBrowse));

    uilabel(fig,'Position',[20 335 70 22],'Text','Port:');
    portDrop = uidropdown(fig,'Position',[90 335 160 22], ...
        'Items',getPorts(),'ValueChangedFcn',@onPortChange);

    uibutton(fig,'push','Position',[260 335 80 22],'Text','Refresh', ...
        'ButtonPushedFcn',@(~,~)safeRun(@onRefreshPorts));

    uilabel(fig,'Position',[360 335 50 22],'Text','Baud:');
    baudField = uieditfield(fig,'numeric','Position',[410 335 90 22], ...
        'Value',state.baud,'Limits',[1200 2000000]);
    baudField.RoundFractionalValues = true;
    baudField.ValueDisplayFormat = '%.0f';

    uilabel(fig,'Position',[20 295 120 22],'Text','Timestamp unit:');
    unitDrop = uidropdown(fig,'Position',[140 295 120 22], ...
        'Items',{'seconds','ms'},'Value',state.timeUnit);

    connectBtn = uibutton(fig,'push','Position',[20 245 120 34],'Text','Connect', ...
        'ButtonPushedFcn',@(~,~)safeRun(@onConnect));

    disconnectBtn = uibutton(fig,'push','Position',[150 245 120 34],'Text','Disconnect', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onDisconnect));

    streamBtn = uibutton(fig,'push','Position',[280 245 120 34],'Text','Load + Play (All)', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onStreamAll));

    stopBtn = uibutton(fig,'push','Position',[410 245 120 34],'Text','Stop', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onStop));

    zeroBtn = uibutton(fig,'push','Position',[540 245 60 34],'Text','Zero', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onZero));

    uilabel(fig,'Position',[20 205 80 22],'Text','Log:');
    logBox = uitextarea(fig,'Position',[20 20 580 185],'Editable','off');
    logBox.Value = strings(0,1);

    if ~isempty(portDrop.Items)
        if any(strcmp(portDrop.Items, state.port))
            portDrop.Value = state.port;
        else
            state.port = string(portDrop.Value);
        end
    end

    logMsg("UI ready.");

    % ------------ Callbacks ------------
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
        if ~isvalid(fig)
            return;
        end

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
            state.sp.Timeout = 15;
            pause(2);

            while state.sp.NumBytesAvailable > 0
                rx = readline(state.sp);
                logArduinoLine(rx);
            end

            openRxLog();

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
        logMsg("Stop requested (will stop after current chunk).");
    end

    function onZero
        if isempty(state.sp)
            logMsg("ERROR: Not connected.");
            return;
        end

        if state.running
            logMsg("Zero blocked: trajectory is currently running.");
            return;
        end

        % Standalone centered command in the same signed-angle format as the CSV
        line = sprintf('%u,%d,%d,%d', 0, 0, 0, 0);
        writeline(state.sp, "CLEAR");
        waitForToken("RDY");
        writeline(state.sp, line);
        waitForToken("RDY");
        writeline(state.sp, "END");
        waitForToken("RDY");
        writeline(state.sp, "PLAY");
        waitForToken("DONE");

        logMsg("Zero command executed.");
        pause(0.05);
        flushInput();
    end

    function onStreamAll
        if isempty(state.sp)
            logMsg("ERROR: Not connected.");
            return;
        end

        streamBtn.Enable = 'off';
        stopBtn.Enable = 'on';
        zeroBtn.Enable = 'off';
        state.stopRequested = false;
        state.running = true;

        try
            csvPath = string(fileField.Value);
            if strlength(csvPath) == 0 || ~isfile(csvPath)
                error("CSV file not found.");
            end

            logMsg("Reading CSV...");
            data = ReadCSVfile(csvPath, state.timeUnit, OFFSET);

            [outPath, base, ~] = fileparts(csvPath);
            sentLogPath = fullfile(outPath, base + "_SENT_TO_ARDUINO.csv");
            sentTbl = table(double(data.t_ms_full(:)), ...
                            data.a1_raw(:), data.a2_raw(:), data.a3_raw(:), ...
                            data.a1_tx(:), data.a2_tx(:), data.a3_tx(:), ...
                'VariableNames', {'t_ms_full','a1_raw','a2_raw','a3_raw','a1_tx','a2_tx','a3_tx'});
            writetable(sentTbl, sentLogPath);
            logMsg("Wrote send-log: " + sentLogPath);

            flushInput();

            N = numel(data.t_ms_full);
            nChunks = ceil(N / MAX_SAMPLES);
            logMsg("Total points: " + N + " -> " + nChunks + " chunks of up to " + MAX_SAMPLES + ".");

            for c = 1:nChunks
                if state.stopRequested
                    logMsg("Stopped before chunk " + c + ".");
                    break;
                end

                i1 = (c-1)*MAX_SAMPLES + 1;
                i2 = min(c*MAX_SAMPLES, N);

                t_chunk  = data.t_ms_full(i1:i2);
                a1_chunk = data.a1_tx(i1:i2);
                a2_chunk = data.a2_tx(i1:i2);
                a3_chunk = data.a3_tx(i1:i2);

                t0 = double(t_chunk(1));
                t_chunk = uint32(double(t_chunk) - t0);

                logMsg("Chunk " + c + "/" + nChunks + ": points " + i1 + "-" + i2 + " (" + numel(t_chunk) + " pts)");

                logMsg("Sending CLEAR...");
                writeline(state.sp, "CLEAR");
                waitForToken("RDY");

                logMsg("Streaming " + numel(t_chunk) + " rows...");
                for k = 1:numel(t_chunk)
                    if state.stopRequested
                        logMsg("Stop requested during chunk " + c + " at row " + k + ".");
                        break;
                    end

                    line = sprintf('%u,%d,%d,%d', t_chunk(k), a1_chunk(k), a2_chunk(k), a3_chunk(k));
                    writeline(state.sp, line);

                    waitForToken("RDY");
                    drawnow limitrate;
                end

                if state.stopRequested
                    break;
                end

                logMsg("Sending END...");
                writeline(state.sp, "END");
                waitForToken("RDY");

                logMsg("Sending PLAY...");
                writeline(state.sp, "PLAY");
                logMsg("Waiting for DONE (chunk " + c + ")...");
                waitForToken("DONE");
                logMsg("Chunk " + c + " DONE.");

                pause(0.05);
                flushInput();
            end

            if ~state.stopRequested
                logMsg("All chunks complete.");
            else
                logMsg("Stopped.");
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

    % ------------ Helpers ------------
    function ports = getPorts()
        try
            ports = cellstr(serialportlist("available"));
        catch
            ports = {};
        end
    end

    function flushInput()
        while state.sp.NumBytesAvailable > 0
            rx = readline(state.sp);
            logArduinoLine(rx);
        end
    end

    function waitForToken(token)
        while true
            rx = strtrim(readline(state.sp));
            logArduinoLine(rx);

            if strcmp(rx, token)
                return;
            end
            drawnow limitrate;
        end
    end

    function openRxLog()
        try
            csvPath = string(fileField.Value);
            if strlength(csvPath) == 0
                return;
            end
            [outPath, base, ~] = fileparts(csvPath);
            state.rxLogPath = fullfile(outPath, base + "_ARDUINO_RX_LOG.txt");
            state.rxLogFID = fopen(state.rxLogPath, 'a');
            if state.rxLogFID > 0
                fprintf(state.rxLogFID, "===== NEW SESSION %s =====\n", datestr(now,'yyyy-mm-dd HH:MM:SS'));
                logMsg("Arduino RX log: " + state.rxLogPath);
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

    function logArduinoLine(rx)
        try
            if ~isempty(state.rxLogFID) && state.rxLogFID > 0
                fprintf(state.rxLogFID, "[%s] %s\n", datestr(now,'HH:MM:SS.FFF'), string(rx));
            end
        catch
        end

        if ~strcmp(strtrim(string(rx)), "RDY") && strlength(strtrim(string(rx))) > 0
            logMsg("ARDUINO: " + string(rx));
        end
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
        if numel(v) > 250
            v = v(end-249:end);
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