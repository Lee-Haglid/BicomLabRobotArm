function ServoStreamerUI
% ServoStreamUI - 5-joint chunked store-then-play streamer
%
% Expected file columns:
%   Tout, Bottom, Mid, top, Elbow, Wrist
%
% Protocol per chunk:
%   MATLAB -> CLEAR
%   MATLAB -> t_ms,bottom,mid,top,elbow,wrist
%   MATLAB -> END
%   MATLAB -> PLAY
%
% Arduino replies:
%   RDY after each accepted line
%   LOADED n / OK / RDY after END
%   PLAYING
%   rpyew: ...
%   DONE / RDY after playback complete

    % ------------ Defaults ------------
    state.filePath = "trajectory.csv";
    state.port = "COM5";
    state.baud = 115200;
    state.timeUnit = "seconds";
    state.sp = [];
    state.stopRequested = false;
    state.running = false;
    state.rxLogFID = [];
    state.rxLogPath = "";

    MAX_SAMPLES = 120;   % must match Arduino MAX_SAMPLES

    % ------------ UI ------------
    fig = uifigure('Name','Arduino 5-Joint Chunked Streamer','Position',[100 100 700 470]);

    uilabel(fig,'Position',[20 420 80 22],'Text','CSV/XLSX:');
    fileField = uieditfield(fig,'text','Position',[100 420 450 22],'Value',state.filePath);

    uibutton(fig,'push','Position',[560 420 110 22],'Text','Browse...', ...
        'ButtonPushedFcn',@(~,~)safeRun(@onBrowse));

    uilabel(fig,'Position',[20 380 50 22],'Text','Port:');
    portDrop = uidropdown(fig,'Position',[100 380 150 22], ...
        'Items',getPorts(),'ValueChangedFcn',@onPortChange);

    uibutton(fig,'push','Position',[260 380 80 22],'Text','Refresh', ...
        'ButtonPushedFcn',@(~,~)safeRun(@onRefreshPorts));

    uilabel(fig,'Position',[360 380 45 22],'Text','Baud:');
    baudField = uieditfield(fig,'numeric','Position',[410 380 90 22], ...
        'Value',state.baud,'Limits',[1200 2000000]);
    baudField.RoundFractionalValues = true;
    baudField.ValueDisplayFormat = '%.0f';

    uilabel(fig,'Position',[20 340 110 22],'Text','Timestamp unit:');
    unitDrop = uidropdown(fig,'Position',[140 340 120 22], ...
        'Items',{'seconds','ms'},'Value',state.timeUnit);

    connectBtn = uibutton(fig,'push','Position',[20 290 120 34],'Text','Connect', ...
        'ButtonPushedFcn',@(~,~)safeRun(@onConnect));

    disconnectBtn = uibutton(fig,'push','Position',[150 290 120 34],'Text','Disconnect', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onDisconnect));

    streamBtn = uibutton(fig,'push','Position',[280 290 140 34],'Text','Load + Play', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onStreamAll));

    stopBtn = uibutton(fig,'push','Position',[430 290 90 34],'Text','Stop', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onStop));

    zeroBtn = uibutton(fig,'push','Position',[530 290 80 34],'Text','Zero', ...
        'Enable','off','ButtonPushedFcn',@(~,~)safeRun(@onZero));

    uilabel(fig,'Position',[20 250 100 22],'Text','Arduino log:');
    logBox = uitextarea(fig,'Position',[20 20 650 230],'Editable','off');
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
        [f,p] = uigetfile({'*.xlsx;*.xls;*.csv','Trajectory Files (*.xlsx,*.xls,*.csv)';'*.*','All Files'}, ...
            'Select trajectory file');
        if isequal(f,0)
            return;
        end
        state.filePath = string(fullfile(p,f));
        fileField.Value = state.filePath;
        logMsg("Selected file: " + state.filePath);
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
            state.sp.Timeout = 0.3;
            pause(2);

            openRxLog();
            flushInput();

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
            logMsg("Zero blocked: currently running.");
            return;
        end

        writeline(state.sp, "ZERO");
        waitForToken("RDY");
        logMsg("Zero command sent.");
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
            filePath = string(fileField.Value);
            if strlength(filePath) == 0 || ~isfile(filePath)
                error("Trajectory file not found.");
            end

            logMsg("Reading trajectory...");
            data = ReadCSVfile(filePath, state.timeUnit, 0);

            N = numel(data.t_ms_full);
            nChunks = ceil(N / MAX_SAMPLES);

            [outPath, base, ~] = fileparts(filePath);
            sentLogPath = fullfile(outPath, base + "_SENT_TO_ARDUINO.csv");
            sentTbl = table(double(data.t_ms_full(:)), ...
                            data.bottom_raw(:), data.mid_raw(:), data.top_raw(:), data.elbow_raw(:), data.wrist_raw(:), ...
                            data.bottom_tx(:), data.mid_tx(:), data.top_tx(:), data.elbow_tx(:), data.wrist_tx(:), ...
                'VariableNames', {'t_ms_full','bottom_raw','mid_raw','top_raw','elbow_raw','wrist_raw', ...
                                  'bottom_tx','mid_tx','top_tx','elbow_tx','wrist_tx'});
            writetable(sentTbl, sentLogPath);

            logMsg("Loaded " + N + " points -> " + nChunks + " chunks.");
            logMsg("Wrote send-log: " + sentLogPath);

            flushInput();

            for c = 1:nChunks
                if state.stopRequested
                    sendStopAndDrain();
                    logMsg("Stopped before chunk " + c + ".");
                    break;
                end

                i1 = (c-1)*MAX_SAMPLES + 1;
                i2 = min(c*MAX_SAMPLES, N);

                t_chunk      = data.t_ms_full(i1:i2);
                bottom_chunk = data.bottom_tx(i1:i2);
                mid_chunk    = data.mid_tx(i1:i2);
                top_chunk    = data.top_tx(i1:i2);
                elbow_chunk  = data.elbow_tx(i1:i2);
                wrist_chunk  = data.wrist_tx(i1:i2);

                t0 = double(t_chunk(1));
                t_chunk = uint32(double(t_chunk) - t0);

                logMsg("Chunk " + c + "/" + nChunks + " points " + i1 + "-" + i2 + ".");

                writeline(state.sp, "CLEAR");
                waitForToken("RDY");

                for k = 1:numel(t_chunk)
                    if state.stopRequested
                        sendStopAndDrain();
                        logMsg("Stopped during chunk " + c + ".");
                        break;
                    end

                    line = sprintf('%u,%d,%d,%d,%d,%d', ...
                        t_chunk(k), bottom_chunk(k), mid_chunk(k), top_chunk(k), elbow_chunk(k), wrist_chunk(k));
                    writeline(state.sp, line);
                    waitForToken("RDY");
                    drawnow limitrate;
                end

                if state.stopRequested
                    break;
                end

                writeline(state.sp, "END");
                waitForToken("RDY");

                writeline(state.sp, "PLAY");
                waitForToken("DONE");

                logMsg("Chunk " + c + " complete.");
                flushInput();
            end

            if ~state.stopRequested
                logMsg("All chunks complete.");
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

    % ------------ Helpers ------------
    function sendStopAndDrain
        if isempty(state.sp)
            return;
        end
        writeline(state.sp, "STOP");
        waitForToken("RDY");
    end

    function ports = getPorts()
        try
            ports = cellstr(serialportlist("available"));
        catch
            ports = {};
        end
    end

    function flushInput()
        if isempty(state.sp)
            return;
        end
        pause(0.05);
        while state.sp.NumBytesAvailable > 0
            rx = strtrim(readline(state.sp));
            logArduinoLine(rx);
        end
    end

    function waitForToken(token)
        while true
            if state.stopRequested && state.running && ~strcmp(token,"RDY")
                % let stop be handled by outer loop, not here
                drawnow limitrate;
            end

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

    function logArduinoLine(rx)
        try
            if ~isempty(state.rxLogFID) && state.rxLogFID > 0
                fprintf(state.rxLogFID, "[%s] %s\n", datestr(now,'HH:MM:SS.FFF'), string(rx));
            end
        catch
        end

        if strlength(string(rx)) > 0
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