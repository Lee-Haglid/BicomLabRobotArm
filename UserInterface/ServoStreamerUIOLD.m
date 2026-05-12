function ServoStreamerUI
% ServoStreamerUI - UI to stream CSV trajectory to Arduino over serial
% CSV format: time, deg1, deg2, deg3
%
% Protocol (HANDSHAKE, CHUNKED STORE-THEN-PLAY):
%   For each chunk (<= MAX_SAMPLES):
%     PC -> "CLEAR"          (Arduino replies "CLEARED", "RDY")
%     PC -> lines "t_ms,a1,a2,a3" (Arduino replies "RDY" each line)
%     PC -> "END"            (Arduino replies "LOADED n", "OK", "RDY")
%     PC -> "PLAY"           (Arduino plays; ends with "DONE", then "RDY")
%     PC waits for "DONE" before next chunk
%
% Logs:
%  - <csv>_SENT_TO_ARDUINO.csv : exactly what MATLAB sent (after mapping/clamp)
%  - <csv>_ARDUINO_RX_LOG.txt  : every line received from Arduino (timestamped)

    % ------------ Defaults ------------
    state.csvFile = "trajectory.csv";
    state.port    = "COM5";
    state.baud    = 115200;
    state.timeUnit = "seconds"; % "seconds" or "ms"
    state.sp = [];
    state.stopRequested = false;

    MAX_SAMPLES = 180; % must match Arduino MAX_SAMPLES

    % Angle mapping (IMPORTANT if your CSV has negatives)
    % If your CSV angles are centered around 0, use OFFSET=90 so -90..+90 maps to 0..180
    OFFSET = 90;

    % ------------ UI Figure ------------
    fig = uifigure('Name','Arduino Servo CSV Streamer','Position',[100 100 620 420]);

    % File selection
    uilabel(fig,'Position',[20 375 70 22],'Text','CSV File:');
    fileField = uieditfield(fig,'text','Position',[90 375 380 22],'Value',state.csvFile);
    uibutton(fig,'push','Position',[480 375 120 22],'Text','Browse...', ...
        'ButtonPushedFcn',@(~,~)safeRun(@()onBrowse()));

    % Serial settings
    uilabel(fig,'Position',[20 335 70 22],'Text','Port:');
    portDrop = uidropdown(fig,'Position',[90 335 160 22],'Items',getPorts(),'ValueChangedFcn',@onPortChange);

    uibutton(fig,'push','Position',[260 335 80 22],'Text','Refresh', ...
        'ButtonPushedFcn',@(~,~)safeRun(@()onRefreshPorts()));

    uilabel(fig,'Position',[360 335 50 22],'Text','Baud:');
    baudField = uieditfield(fig,'numeric','Position',[410 335 90 22],'Value',state.baud,'Limits',[1200 2000000]);
    baudField.RoundFractionalValues = true;
    baudField.ValueDisplayFormat = '%.0f';

    % Time unit
    uilabel(fig,'Position',[20 295 120 22],'Text','Timestamp unit:');
    unitDrop = uidropdown(fig,'Position',[140 295 120 22],'Items',{'seconds','ms'},'Value',state.timeUnit);

    % Buttons
    connectBtn = uibutton(fig,'push','Position',[20 245 120 34],'Text','Connect', ...
        'ButtonPushedFcn',@(~,~)safeRun(@()onConnect()));

    disconnectBtn = uibutton(fig,'push','Position',[150 245 120 34],'Text','Disconnect',...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@()onDisconnect()));

    streamBtn = uibutton(fig,'push','Position',[280 245 120 34],'Text','Load + Play (All)', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@()onStreamAll()));

    stopBtn = uibutton(fig,'push','Position',[410 245 120 34],'Text','Stop', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@()onStop()));

    % Log / status
    uilabel(fig,'Position',[20 205 80 22],'Text','Log:');
    logBox = uitextarea(fig,'Position',[20 20 580 185],'Editable','off');
    logBox.Value = strings(0,1);

    % Log files
    state.rxLogFID = [];
    state.rxLogPath = "";

    % Try to set initial port if present
    if ~isempty(portDrop.Items)
        if any(strcmp(portDrop.Items, state.port))
            portDrop.Value = state.port;
        else
            state.port = string(portDrop.Value);
        end
    end

    logMsg("UI ready.");

    % ------------ Callbacks ------------
    function onBrowse(~,~)
        [f,p] = uigetfile({'*.csv','CSV Files (*.csv)';'*.*','All Files'}, 'Select trajectory CSV');
        if isequal(f,0), return; end
        state.csvFile = string(fullfile(p,f));
        fileField.Value = state.csvFile;
        logMsg("Selected file: " + state.csvFile);
    end

    function onPortChange(src,~)
        state.port = string(src.Value);
    end

    function onRefreshPorts(~,~)
        ports = getPorts();
        if isempty(ports), ports = {''}; end
        portDrop.Items = ports;
        if ~isempty(ports) && strlength(ports{1})>0
            portDrop.Value = ports{1};
            state.port = string(ports{1});
        end
        logMsg("Ports refreshed.");
    end

    function onConnect(~,~)
        if ~isvalid(fig), return; end

        state.baud = baudField.Value;
        state.timeUnit = string(unitDrop.Value);

        try
            if ~isempty(state.sp), clearSerial(); end
            if strlength(state.port)==0, error("No serial port selected."); end

            state.sp = serialport(state.port, state.baud);
            configureTerminator(state.sp, "LF");
            state.sp.Timeout = 15; % a little longer since playback waits happen
            pause(2); % Arduino auto-reset

            % Flush any startup text
            while state.sp.NumBytesAvailable > 0
                rx = readline(state.sp);
                logArduinoLine(rx);
            end

            openRxLog(); % start RX log file

            logMsg("Connected to " + state.port + " @ " + state.baud + " baud.");
            connectBtn.Enable = 'off';
            disconnectBtn.Enable = 'on';
            streamBtn.Enable = 'on';
            stopBtn.Enable = 'off';

        catch ME
            logMsg("CONNECT ERROR: " + string(ME.message));
            clearSerial();
        end
    end

    function onDisconnect(~,~)
        clearSerial();
        logMsg("Disconnected.");
        connectBtn.Enable = 'on';
        disconnectBtn.Enable = 'off';
        streamBtn.Enable = 'off';
        stopBtn.Enable = 'off';
    end

    function onStop(~,~)
        state.stopRequested = true;
        logMsg("Stop requested (will stop after current chunk).");
    end

    function onStreamAll(~,~)
        if isempty(state.sp)
            logMsg("ERROR: Not connected.");
            return;
        end

        streamBtn.Enable = 'off';
        stopBtn.Enable = 'on';
        state.stopRequested = false;

        try
            csvPath = string(fileField.Value);
            if strlength(csvPath)==0 || ~isfile(csvPath)
                error("CSV file not found.");
            end

            logMsg("Reading CSV...");
            T = readtable(csvPath);

            if width(T) < 4
                error("CSV must have at least 4 columns: time, deg1, deg2, deg3.");
            end

            t  = T{:,1};
            a1 = T{:,2};
            a2 = T{:,3};
            a3 = T{:,4};

            % Convert timestamps -> ms relative to whole file
            if state.timeUnit == "seconds"
                t_ms_full = uint32(round(1000 * (t - t(1))));
            else
                t_ms_full = uint32(round(t - t(1)));
            end

            if any(diff(double(t_ms_full)) < 0)
                error("Timestamps must be monotonically increasing.");
            end

            % Map raw angles -> servo degrees (and clamp)
            a1_servo_full = clamp180(round(a1 + OFFSET));
            a2_servo_full = clamp180(round(a2 + OFFSET));
            a3_servo_full = clamp180(round(a3 + OFFSET));

            % Write the full "what MATLAB will send" log (before chunking)
            [outPath,base,~] = fileparts(csvPath);
            sentLogPath = fullfile(outPath, base + "_SENT_TO_ARDUINO.csv");
            sentTbl = table(double(t_ms_full(:)), a1(:), a2(:), a3(:), ...
                            a1_servo_full(:), a2_servo_full(:), a3_servo_full(:), ...
                'VariableNames', {'t_ms_full','a1_raw','a2_raw','a3_raw','a1_servo','a2_servo','a3_servo'});
            writetable(sentTbl, sentLogPath);
            logMsg("Wrote send-log: " + sentLogPath);

            % Flush any pending incoming lines so handshake is clean
            flushInput();

            % ---- Chunk loop ----
            N = numel(t_ms_full);
            nChunks = ceil(N / MAX_SAMPLES);
            logMsg("Total points: " + N + " -> " + nChunks + " chunks of up to " + MAX_SAMPLES + ".");

            for c = 1:nChunks
                if state.stopRequested
                    logMsg("Stopped before chunk " + c + ".");
                    break;
                end

                i1 = (c-1)*MAX_SAMPLES + 1;
                i2 = min(c*MAX_SAMPLES, N);

                t_chunk = t_ms_full(i1:i2);
                a1_chunk = a1_servo_full(i1:i2);
                a2_chunk = a2_servo_full(i1:i2);
                a3_chunk = a3_servo_full(i1:i2);

                % Re-zero chunk time to start at 0 for Arduino playback
                t0 = double(t_chunk(1));
                t_chunk = uint32(double(t_chunk) - t0);

                logMsg("Chunk " + c + "/" + nChunks + ": points " + i1 + "-" + i2 + " (" + numel(t_chunk) + " pts)");

                % CLEAR
                logMsg("Sending CLEAR...");
                writeline(state.sp, "CLEAR");
                waitForToken("RDY"); % Arduino prints CLEARED then RDY

                % Stream lines with handshake
                logMsg("Streaming " + numel(t_chunk) + " rows...");
                for k = 1:numel(t_chunk)
                    if state.stopRequested
                        logMsg("Stop requested during chunk " + c + " at row " + k + ".");
                        break;
                    end

                    line = sprintf("%lu,%d,%d,%d", t_chunk(k), a1_chunk(k), a2_chunk(k), a3_chunk(k));
                    writeline(state.sp, line);

                    waitForToken("RDY"); % must get RDY back per line
                    drawnow limitrate;
                end

                if state.stopRequested
                    break;
                end

                % END load
                logMsg("Sending END...");
                writeline(state.sp, "END");
                waitForToken("RDY"); % consumes LOADED/OK and returns at RDY

                % PLAY and WAIT DONE
                logMsg("Sending PLAY...");
                writeline(state.sp, "PLAY");
                logMsg("Waiting for DONE (chunk " + c + ")...");
                waitForToken("DONE"); % ignore RDY spam during playback
                logMsg("Chunk " + c + " DONE.");

                % After DONE, Arduino should send RDY too; drain a bit so next chunk starts clean
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

        streamBtn.Enable = 'on';
        stopBtn.Enable = 'off';
        state.stopRequested = false;
    end

    % ------------ Helpers ------------
    function ports = getPorts()
        try
            ports = cellstr(serialportlist("available"));
        catch
            ports = {};
        end
    end

    function y = clamp180(x)
        y = min(max(x,0),180);
    end

    function flushInput()
        while state.sp.NumBytesAvailable > 0
            rx = readline(state.sp);
            logArduinoLine(rx);
        end
    end

    function waitForToken(token)
        % Read lines until we see 'token'. Log everything Arduino says.
        while true
            rx = strtrim(readline(state.sp)); % blocks until LF or timeout
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
            if strlength(csvPath)==0, return; end
            [outPath,base,~] = fileparts(csvPath);
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
        % Log raw Arduino line to file + (optionally) UI
        try
            if ~isempty(state.rxLogFID) && state.rxLogFID > 0
                fprintf(state.rxLogFID, "[%s] %s\n", datestr(now,'HH:MM:SS.FFF'), string(rx));
            end
        catch
        end
        % Don't spam the UI with every RDY during playback—only show non-RDY
        if ~strcmp(strtrim(string(rx)), "RDY") && strlength(strtrim(string(rx)))>0
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
    end
end
