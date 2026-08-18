function ServoStreamerTabbedUI_TeensySD
% Two-tab UI:
% Tab 1: Convert sleeve/Simulink data to motor CSV
% Tab 2: Upload CSV to Teensy SD and control playback

    state.filePath = "trajectory.csv";
    state.port = "COM8";
    state.baud = 115200;
    state.timeUnit = "seconds";
    state.sp = [];
    state.hrBpm = 72;

    state.imuPath = fullfile(pwd, "robot_arm_imu_log.csv");
    state.imuFID = [];
    state.imuRecording = false;

    fig = uifigure('Name','Robot Arm UI','Position',[100 100 880 650]);

    fig.Color = [0.88 0.92 0.98];

    accentPurple = [0.66 0.58 0.96];
    accentBlue   = [0.66 0.58 0.96];
    accentPink   = [0.66 0.58 0.96];

    panelDark    = [0.80 0.85 0.95];
    panelMid     = [0.90 0.93 0.99];

    textLight    = [0.18 0.20 0.30];

    tabs = uitabgroup(fig,'Position',[10 10 860 630]);

    convertTab = uitab(tabs,'Title','Convert Sleeve Data');
    streamTab  = uitab(tabs,'Title','Teensy SD Playback');

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

        uibutton(convertTab,'push','Position',[220 420 180 34],'Text','Use Output in Playback Tab', ...
            'ButtonPushedFcn',@(~,~)useConverted());

        convLog = uitextarea(convertTab,'Position',[20 20 810 380],'Editable','off');
        convLog.Value = "Conversion tab ready.";
        convLog.BackgroundColor = panelMid;
        convLog.FontColor = textLight;
        convLog.FontName = 'Consolas';

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

        uploadBtn = uibutton(streamTab,'push','Position',[280 400 120 34], ...
            'Text','Upload CSV','Enable','off', ...
            'ButtonPushedFcn',@(~,~)safeRun(@onUploadFile));

        startBtn = uibutton(streamTab,'push','Position',[410 400 100 34], ...
            'Text','Start','Enable','off', ...
            'ButtonPushedFcn',@(~,~)safeRun(@onStartPlayback));

        stopBtn = uibutton(streamTab,'push','Position',[520 400 90 34], ...
            'Text','Stop','Enable','off', ...
            'ButtonPushedFcn',@(~,~)safeRun(@onStopPlayback));

        zeroBtn = uibutton(streamTab,'push','Position',[620 400 80 34], ...
            'Text','Zero','Enable','off', ...
            'ButtonPushedFcn',@(~,~)safeRun(@onZero));

        imuStartBtn = uibutton(streamTab,'push','Position',[710 400 130 34], ...
            'Text','Get Motion Data','Enable','off', ...
            'ButtonPushedFcn',@(~,~)safeRun(@onStartIMU));

        imuStopBtn = uibutton(streamTab,'push','Position',[710 360 130 34], ...
            'Text','Stop Motion Data','Enable','off', ...
            'ButtonPushedFcn',@(~,~)safeRun(@onStopIMU));

        uilabel(streamTab,'Position',[20 360 100 22],'Text','Device log:');
        logBox = uitextarea(streamTab,'Position',[20 20 820 330],'Editable','off');
        logBox.Value = strings(0,1);

        logBox.BackgroundColor = panelMid;
        logBox.FontColor = textLight;
        logBox.FontName = 'Consolas';

        uploadBtn.BackgroundColor = accentBlue;
        startBtn.BackgroundColor = accentBlue;
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

        logMsg("Teensy SD playback tab ready.");

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

            logMsg("Connected to " + state.port + " @ " + baudField.Value + " baud");

            connectBtn.Enable = 'off';
            disconnectBtn.Enable = 'on';
            uploadBtn.Enable = 'on';
            startBtn.Enable = 'on';
            stopBtn.Enable = 'on';
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
            uploadBtn.Enable = 'off';
            startBtn.Enable = 'off';
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

        function onUploadFile
            filePath = string(fileField.Value);

            if ~isfile(filePath)
                error("Trajectory file not found.");
            end

            uploadBtn.Enable = 'off';
            startBtn.Enable = 'off';

            try
                uploadTrajectoryFile(filePath);
                startBtn.Enable = 'on';
            catch ME
                uploadBtn.Enable = 'on';
                startBtn.Enable = 'on';
                rethrow(ME);
            end

            uploadBtn.Enable = 'on';
        end

        function uploadTrajectoryFile(filePath)
            logMsg("Reading trajectory file...");

            data = ReadCSVfile(filePath, state.timeUnit, 0);
            N = numel(data.t_ms_full);

            if N < 2
                error("Trajectory file has too few points.");
            end

            logMsg("Uploading " + N + " points to Teensy SD...");

            flushInput();

            writeline(state.sp, "UPLOAD_BEGIN,traj.csv");
            waitForLine("UPLOAD-READY", 5);

            writeline(state.sp, "time_ms,bottom,mid,top,elbow,wrist");
            pumpSerial(0.01);

            for k = 1:N
                line = sprintf('%u,%.6f,%.6f,%.6f,%.6f,%.6f', ...
    data.t_ms_full(k), ...
    data.bottom_tx(k), data.mid_tx(k), data.top_tx(k), ...
    data.elbow_tx(k), data.wrist_tx(k))

                writeline(state.sp, line);

                if mod(k,20) == 0
                    pumpSerial(0.02);
                end

                if mod(k,100) == 0
                    logMsg("Uploaded " + k + " / " + N + " points");
                end
            end

            writeline(state.sp, "UPLOAD_END");
            waitForLine("UPLOAD-DONE", 10);

            logMsg("Upload complete. File saved as traj.csv on Teensy SD.");
        end

        function onStartPlayback
            state.hrBpm = round(hrField.Value);

            writeline(state.sp, sprintf('HR %d', state.hrBpm));
            pumpSerial(0.2);

            writeline(state.sp, "START");
            pumpSerial(0.3);

            logMsg("Started Teensy SD playback.");
        end

        function onStopPlayback
            writeline(state.sp, "STOP");
            pumpSerial(0.3);
            logMsg("Stop sent.");
        end

        function onStartIMU
            state.imuPath = string(imuFileField.Value);

            state.imuFID = fopen(state.imuPath,'w');
            fprintf(state.imuFID, "time_ms,roll_deg,pitch_deg,yaw_deg,gx_dps,gy_dps,gz_dps,ax_g,ay_g,az_g\n");

            writeline(state.sp, "IMU_START");

            state.imuRecording = true;
            imuStartBtn.Enable = 'off';
            imuStopBtn.Enable = 'on';

            logMsg("IMU recording started: " + state.imuPath);
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

        function waitForLine(target, timeoutSec)
            t0 = tic;

            while toc(t0) < timeoutSec
                if ~isempty(state.sp) && state.sp.NumBytesAvailable > 0
                    rx = strtrim(readline(state.sp));
                    handleDeviceLine(rx);

                    if string(rx) == string(target)
                        return;
                    end
                end

                drawnow limitrate;
                pause(0.005);
            end

            error("Timed out waiting for " + target);
        end

        function handleDeviceLine(rx)
            s = string(rx);

            if startsWith(s, "IMU,")
                if state.imuRecording && ~isempty(state.imuFID) && state.imuFID > 0
                    fprintf(state.imuFID, "%s\n", extractAfter(s, "IMU,"));
                end
                return;
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
