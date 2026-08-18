function ServoStreamerTabbedUI
% Two-tab UI:
% Tab 1: Convert sleeve/Simulink data to motor CSV
% Tab 2: Stream motor CSV to ESP32/Arduino

    state.filePath = "trajectory.csv";
    state.port = "COM8";
    state.baud = 115200;
    state.timeUnit = "seconds";
    state.sp = [];
    state.running = false;
    state.stopRequested = false;
    state.latestQueueFill = 0;
    state.doneReceived = false;
    state.endAckReceived = false;
    state.hrBpm = 72;

    state.imuPath = fullfile(pwd, "robot_arm_imu_log.csv");
    state.imuFID = [];
    state.imuRecording = false;

    TARGET_FILL = 18;
    LOW_WATER = 8;

    fig = uifigure('Name','Robot Arm UI','Position',[100 100 880 650]);

    % Make it look cool
    fig.Color = [0.88 0.92 0.98];

    accentPurple = [0.66 0.58 0.96];
    accentBlue   = [0.66 0.58 0.96]; %[0.52 0.78 1.00]
    accentPink   = [0.66 0.58 0.96]; %[0.96 0.72 0.90]

    panelDark    = [0.80 0.85 0.95];
    panelMid     = [0.90 0.93 0.99];

    textLight    = [0.18 0.20 0.30];

    tabs = uitabgroup(fig,'Position',[10 10 860 630]);

    convertTab = uitab(tabs,'Title','Convert Sleeve Data');
    streamTab  = uitab(tabs,'Title','Stream to Arm');
    
    convertTab.BackgroundColor = panelDark;
    streamTab.BackgroundColor  = panelDark;

    buildConvertTab();
    buildStreamTab();

    function buildConvertTab
        uilabel(convertTab,'Position',[20 550 130 22],'Text','Sleeve data file:');
        sleeveField = uieditfield(convertTab,'text','Position',[150 550 520 22],'Value',"sleeve_data.csv");

        uibutton(convertTab,'push','Position',[690 550 100 22],'Text','Browse...', ...
            'ButtonPushedFcn',@(~,~)browseSleeve());

        uilabel(convertTab,'Position',[20 510 130 22],'Text','Output motor CSV:');
        outField = uieditfield(convertTab,'text','Position',[150 510 520 22], ...
            'Value',fullfile(pwd,"converted_motor_trajectory.csv"));

        uibutton(convertTab,'push','Position',[690 510 100 22],'Text','Save As...', ...
            'ButtonPushedFcn',@(~,~)browseOutput());

        uilabel(convertTab,'Position',[20 470 130 22],'Text','Simulink model:');
        modelField = uieditfield(convertTab,'text','Position',[150 470 240 22],'Value',"SimulArmV3");

        uibutton(convertTab,'push','Position',[20 420 180 34],'Text','Convert Sleeve to Motors', ...
            'ButtonPushedFcn',@(~,~)safeRun(@convertSleeve));

        useBtn = uibutton(convertTab,'push','Position',[220 420 180 34],'Text','Use Output in Stream Tab', ...
            'ButtonPushedFcn',@(~,~)useConverted());

        convLog = uitextarea(convertTab,'Position',[20 20 810 380],'Editable','off');
        convLog.Value = "Conversion tab ready.";

        function browseSleeve
            [f,p] = uigetfile({'*.csv;*.xlsx;*.xls','Data Files';'*.*','All Files'}, ...
                'Select sleeve data file');
            if isequal(f,0), return; end
            sleeveField.Value = string(fullfile(p,f));
        end

        function browseOutput
            [f,p] = uiputfile({'*.csv','CSV Files'}, ...
                'Save motor trajectory CSV as', outField.Value);
            if isequal(f,0), return; end
            outField.Value = string(fullfile(p,f));
        end

        function useConverted
            state.filePath = string(outField.Value);
            fileField.Value = state.filePath;
            logMsg("Using converted file: " + state.filePath);
        end

        function convertSleeve
            inPath = string(sleeveField.Value);
            outPath = string(outField.Value);
            modelName = string(modelField.Value);

            if ~isfile(inPath)
                error("Sleeve data file not found.");
            end

            convLog.Value = [string(convLog.Value(:)); "Loading sleeve data..."];

            sleeveTbl = readtable(inPath);

            assignin('base','sleeveData',sleeveTbl);

            convLog.Value = [string(convLog.Value(:)); "Running Simulink model: " + modelName];

            simOut = sim(modelName);

            motorTbl = extractMotorTable(simOut);

            writetable(motorTbl, outPath);

            convLog.Value = [string(convLog.Value(:)); "Wrote motor CSV: " + outPath];
        end
    end

    function motorTbl = extractMotorTable(simOut)
        names = ["Tout","Bottom","Mid","Top","Elbow","Wrist"];

        if evalin('base','exist("motorTable","var")')
            motorTbl = evalin('base','motorTable');
            return;
        end

        if isprop(simOut,'motorTable')
            motorTbl = simOut.motorTable;
            return;
        end

        try
            logs = simOut.logsout;
            Tout = logs.get("Tout").Values.Data;
            Bottom = logs.get("Bottom").Values.Data;
            Mid = logs.get("Mid").Values.Data;
            Top = logs.get("Top").Values.Data;
            Elbow = logs.get("Elbow").Values.Data;
            Wrist = logs.get("Wrist").Values.Data;

            motorTbl = table(Tout, Bottom, Mid, Top, Elbow, Wrist);
            return;
        catch
        end

        error("Could not find motor output. Export a table named motorTable or logs named Tout, Bottom, Mid, Top, Elbow, Wrist.");
    end

    function buildStreamTab
        uilabel(streamTab,'Position',[20 575 80 22],'Text','CSV/XLSX:');
        fileField = uieditfield(streamTab,'text','Position',[100 575 520 22],'Value',state.filePath);

        uibutton(streamTab,'push','Position',[640 575 100 22],'Text','Browse...', ...
            'ButtonPushedFcn',@(~,~)safeRun(@onBrowseTrajectory));

        uilabel(streamTab,'Position',[20 535 50 22],'Text','Port:');
        portDrop = uidropdown(streamTab,'Position',[100 535 150 22], ...
            'Items',getPortsSafe(),'ValueChangedFcn',@onPortChange);

        uibutton(streamTab,'push','Position',[260 535 80 22],'Text','Refresh', ...
            'ButtonPushedFcn',@(~,~)safeRun(@onRefreshPorts));

       uilabel(streamTab,'Position',[360 535 45 22],'Text','Baud:');
        baudField = uidropdown(streamTab, ...
        'Position',[410 535 110 22], ...
        'Items',{'9600','57600','115200','230400','460800','921600','1000000'}, ...
        'Value','115200');

        uilabel(streamTab,'Position',[20 495 110 22],'Text','Timestamp unit:');
        unitDrop = uidropdown(streamTab,'Position',[140 495 120 22], ...
            'Items',{'seconds','ms'},'Value',state.timeUnit);

        uilabel(streamTab,'Position',[300 495 110 22],'Text','Heart Rate BPM:');
        hrField = uieditfield(streamTab,'numeric','Position',[420 495 80 22], ...
            'Value',state.hrBpm,'Limits',[1 240]);
        hrField.RoundFractionalValues = true;

        sendHrBtn = uibutton(streamTab,'push','Position',[520 495 100 22], ...
            'Text','Send HR','Enable','off', ...
            'ButtonPushedFcn',@(~,~)safeRun(@onSendHR));

        uilabel(streamTab,'Position',[20 455 90 22],'Text','IMU file:');
        imuFileField = uieditfield(streamTab,'text','Position',[100 455 520 22], ...
            'Value',state.imuPath);

        uibutton(streamTab,'push','Position',[640 455 100 22],'Text','Save As...', ...
            'ButtonPushedFcn',@(~,~)safeRun(@onBrowseIMUSave));

        connectBtn = uibutton(streamTab,'push','Position',[20 400 120 34], ...
            'Text','Connect','ButtonPushedFcn',@(~,~)safeRun(@onConnect));

        disconnectBtn = uibutton(streamTab,'push','Position',[150 400 120 34], ...
            'Text','Disconnect','Enable','off', ...
            'ButtonPushedFcn',@(~,~)safeRun(@onDisconnect));

        streamBtn = uibutton(streamTab,'push','Position',[280 400 140 34], ...
            'Text','Stream Live','Enable','off', ...
            'ButtonPushedFcn',@(~,~)safeRun(@onStreamLive));

        stopBtn = uibutton(streamTab,'push','Position',[430 400 90 34], ...
            'Text','Stop','Enable','off', ...
            'ButtonPushedFcn',@(~,~)safeRun(@onStop));

        zeroBtn = uibutton(streamTab,'push','Position',[530 400 80 34], ...
            'Text','Zero','Enable','off', ...
            'ButtonPushedFcn',@(~,~)safeRun(@onZero));

        imuStartBtn = uibutton(streamTab,'push','Position',[620 400 150 34], ...
            'Text','Get Motion Data','Enable','off', ...
            'ButtonPushedFcn',@(~,~)safeRun(@onStartIMU));

        imuStopBtn = uibutton(streamTab,'push','Position',[620 360 150 34], ...
            'Text','Stop Motion Data','Enable','off', ...
            'ButtonPushedFcn',@(~,~)safeRun(@onStopIMU));
        

        uilabel(streamTab,'Position',[20 360 100 22],'Text','Device log:');
        logBox = uitextarea(streamTab,'Position',[20 20 820 330],'Editable','off');
        logBox.Value = strings(0,1);

        logBox.BackgroundColor = panelMid;
        logBox.FontColor = textLight;
        logBox.FontName = 'Consolas';
        
        streamBtn.BackgroundColor = accentBlue;
        connectBtn.BackgroundColor = accentPurple;
        disconnectBtn.BackgroundColor = accentPurple;
        
        imuStartBtn.BackgroundColor = accentPink;
        imuStopBtn.BackgroundColor = accentPurple;
        
        stopBtn.BackgroundColor = accentPurple;
        zeroBtn.BackgroundColor = accentBlue;

        if ~isempty(portDrop.Items)
            state.port = string(portDrop.Items{1});
            portDrop.Value = portDrop.Items{1};
        end

        logMsg("Stream tab ready.");

        function onBrowseTrajectory
            [f,p] = uigetfile({'*.xlsx;*.xls;*.csv','Trajectory Files';'*.*','All Files'}, ...
                'Select trajectory file');
            if isequal(f,0), return; end
            state.filePath = string(fullfile(p,f));
            fileField.Value = state.filePath;
            logMsg("Selected trajectory file: " + state.filePath);
        end

        function onBrowseIMUSave
            [f,p] = uiputfile({'*.csv','CSV Files'}, ...
                'Save IMU data as', state.imuPath);
            if isequal(f,0), return; end
            state.imuPath = string(fullfile(p,f));
            imuFileField.Value = state.imuPath;
        end

        function onPortChange(src,~)
            state.port = string(src.Value);
        end

        function onRefreshPorts
            ports = getPortsSafe();
            portDrop.Items = ports;
            portDrop.Value = ports{1};
            state.port = string(ports{1});
            logMsg("Ports refreshed.");
        end

        function onConnect
            state.baud = str2double(baudField.Value);
            state.timeUnit = string(unitDrop.Value);
            state.hrBpm = round(hrField.Value);

            if ~isempty(state.sp)
                clearSerial();
            end

            if state.port == "<none>"
                error("No serial port selected.");
            end

            state.sp = serialport(state.port, state.baud);
            configureTerminator(state.sp, "LF");
            state.sp.Timeout = 0.2;

            pause(2);
            pumpSerial(0.5);

            logMsg("Connected to " + state.port);

            connectBtn.Enable = 'off';
            disconnectBtn.Enable = 'on';
            streamBtn.Enable = 'on';
            zeroBtn.Enable = 'on';
            sendHrBtn.Enable = 'on';
            imuStartBtn.Enable = 'on';
        end

        function onDisconnect
            if state.imuRecording
                stopIMULoggingLocal();
            end

            clearSerial();

            connectBtn.Enable = 'on';
            disconnectBtn.Enable = 'off';
            streamBtn.Enable = 'off';
            stopBtn.Enable = 'off';
            zeroBtn.Enable = 'off';
            sendHrBtn.Enable = 'off';
            imuStartBtn.Enable = 'off';
            imuStopBtn.Enable = 'off';

            logMsg("Disconnected.");
        end

        function onSendHR
            state.hrBpm = round(hrField.Value);
            writeline(state.sp, sprintf('HR %d', state.hrBpm));
            pumpSerial(0.2);
            logMsg("Sent HR " + state.hrBpm);
        end

        function onZero
            writeline(state.sp, "ZERO");
            pumpSerial(0.3);
            logMsg("Zero sent.");
        end

        function onStartIMU
            state.imuPath = string(imuFileField.Value);

            state.imuFID = fopen(state.imuPath,'w');
            fprintf(state.imuFID, "time_ms,roll_deg,pitch_deg,yaw_deg,gx_dps,gy_dps,gz_dps,ax_g,ay_g,az_g\n");

            writeline(state.sp, "IMU_START");

            state.imuRecording = true;
            imuStartBtn.Enable = 'off';
            imuStopBtn.Enable = 'on';

            logMsg("IMU recording started.");
        end

        function onStopIMU
            writeline(state.sp, "IMU_STOP");
            pumpSerial(0.2);
            stopIMULoggingLocal();
            logMsg("IMU recording stopped.");
        end

        function stopIMULoggingLocal
            try
                if ~isempty(state.imuFID) && state.imuFID > 0
                    fclose(state.imuFID);
                end
            catch
            end

            state.imuFID = [];
            state.imuRecording = false;

            imuStartBtn.Enable = 'on';
            imuStopBtn.Enable = 'off';
        end

        function onStop
            state.stopRequested = true;
            logMsg("Stop requested.");
        end

        function onStreamLive
            streamBtn.Enable = 'off';
            stopBtn.Enable = 'on';
            zeroBtn.Enable = 'off';
            sendHrBtn.Enable = 'off';

            state.running = true;
            state.stopRequested = false;
            state.doneReceived = false;
            state.endAckReceived = false;
            state.latestQueueFill = 0;

            try
                filePath = string(fileField.Value);

                if ~isfile(filePath)
                    error("Trajectory file not found.");
                end

                data = ReadCSVfile(filePath, state.timeUnit, 0);
                N = numel(data.t_ms_full);

                logMsg("Loaded " + N + " points.");

                flushInput();

                writeline(state.sp, sprintf('HR %d', round(hrField.Value)));
                pumpSerial(0.2);

                writeline(state.sp, "START");
                pumpSerial(0.25);

                nextIdx = 1;

                while nextIdx <= N && state.latestQueueFill < TARGET_FILL
                    sendPoint(nextIdx, data);
                    nextIdx = nextIdx + 1;
                    pumpSerial(0.01);
                end

                while true
                    if state.stopRequested
                        writeline(state.sp, "STOP");
                        pumpSerial(0.3);
                        break;
                    end

                    pumpSerial(0.02);

                    if nextIdx <= N
                        if state.latestQueueFill <= LOW_WATER
                            while nextIdx <= N && state.latestQueueFill < TARGET_FILL
                                sendPoint(nextIdx, data);
                                nextIdx = nextIdx + 1;
                                pumpSerial(0.005);
                            end
                        end
                    else
                        if ~state.endAckReceived
                            writeline(state.sp, "END");
                            pumpSerial(1.0);
                        end

                        if state.doneReceived
                            logMsg("Stream complete.");
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
            zeroBtn.Enable = 'on';
            sendHrBtn.Enable = 'on';
        end

        function sendPoint(k, data)
            line = sprintf('%u,%d,%d,%d,%d,%d', ...
                data.t_ms_full(k), ...
                data.bottom_tx(k), data.mid_tx(k), data.top_tx(k), ...
                data.elbow_tx(k), data.wrist_tx(k));

            writeline(state.sp, line);
        end

        function pumpSerial(durationSec)
            t0 = tic;

            while toc(t0) < durationSec
                while ~isempty(state.sp) && state.sp.NumBytesAvailable > 0
                    rx = strtrim(readline(state.sp));
                    handleDeviceLine(rx);
                end

                drawnow limitrate;
                pause(0.002);
            end
        end

        function handleDeviceLine(rx)
            s = string(rx);

            if startsWith(s, "IMU,")
                if state.imuRecording && ~isempty(state.imuFID) && state.imuFID > 0
                    fprintf(state.imuFID, "%s\n", extractAfter(s, "IMU,"));
                end
                return;
            end

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
                logMsg("DEVICE: " + s);
            end
        end

        function flushInput
            pause(0.05);
            while ~isempty(state.sp) && state.sp.NumBytesAvailable > 0
                rx = strtrim(readline(state.sp));
                handleDeviceLine(rx);
            end
        end

        function logMsg(msg)
            ts = datestr(now,'HH:MM:SS');
            v = string(logBox.Value(:));
            v = [v; "[" + string(ts) + "] " + string(msg)];

            if numel(v) > 300
                v = v(end-299:end);
            end

            logBox.Value = v;
            drawnow limitrate;
        end

        function clearSerial
            try
                if ~isempty(state.sp)
                    delete(state.sp);
                end
            catch
            end

            state.sp = [];
            state.running = false;
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

    function safeRun(fn)
        try
            fn();
        catch ME
            disp(getReport(ME,'extended'));
            uialert(fig, string(ME.message), "Callback Error");
        end
    end
end