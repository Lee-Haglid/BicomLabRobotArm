%% IMU Sleeve Processing for Simulink Angle Output
%{
DESCRIPTION:
This script parses bicep and wrist IMU data from a sleeve, calibrates the
accelerometer and gyroscope signals, calculates orientation with a complementary
filter, transforms the sensor frames using a simple arm calibration motion, and
outputs angles for Simulink. The arm initially ramps from neutral position
to start position.

The data must contain:
   1. A stationary period for accelerometer normalization and gyroscope
      bias correction
   2. An arm calibration motion consisting of:
         - arm straight down at the person's side
         - arm straight out from the person's body (angle doesnt matter, no wrist rotation)

FILTER:
Uses MATLAB's complementaryFilter without magnetometer input.
Accelerometer data corrects long-term gravity direction.
Gyroscope data captures short-term angular motion.

DATA FILE ASSUMPTIONS:
Each valid line contains synchronized bicep and wrist IMU data:
   t=...ms
   Bicep xyz(x,y,z) pqr(p,q,r)
   Wrist xyz(x,y,z) pqr(p,q,r)

Time is in milliseconds.
Gyroscope data is in degrees per second.
Accelerometer data is in g units.

USER INPUTS:
filename          - IMU log text file
cal_idx_range     - stationary sample range used for accel normalization
                    and gyro bias correction. Run data cuts from end of
                    this range.
armDownCal_idx    - sample index with arm straight down
armOutCal_idx     - sample index with arm straight out from body
yaw_offset        - shoulder joint yaw offset, degrees
pitch_offset      - shoulder joint pitch offset, degrees
zero_idx          - Where to cut imu data from for simulink start
signal_timeconst  - first-order filter time constant used in Simulink
accelGain         - complementary filter accelerometer gain
runAnimation      - true/false animation toggle

SIMULINK OUTPUTS:
time (s)
rot_x_bicep, rot_y_bicep, rot_z_bicep (rad)
rot_x_wrist, rot_y_wrist, rot_z_wrist (rad)
signal_timeconst

Calibration frame used for Simulink:
   +Z : down
   +X : right
   +Y : backward
%}

clear; clc; close all;

%% User Inputs

filename = "DATALOG.txt";

cal_idx_range = 25:44;   % stationary range for accel normalization and gyro bias correction
armDownCal_idx = 31;    % arm straight down calibration sample
armOutCal_idx  = 95;    % arm straight out calibration sample

accelGain = 0.3;         % complementary filter accel correction gain

% Simulink Inputs
shoulder_limit = 30;     % max shoulder joint angle limit from neutral [deg]
yaw_offset = 0;          % constant shoulder yaw offset [deg]. 
                         % 0 means bicep bends forward.

pitch_offset = 0;        % constant shoulder pitch roll offset [deg]. 
                         % 0 means arms straight down at angles of 0. 
                         % negative angle means pitch up

% where to cut imu data from for simulink
zero_idx = armDownCal_idx;

signal_timeconst = 0.01;  % Simulink first-order filter time constant [s]

% Visualization Options
runAnimation = false;    % enable/disable arrow bicep animation to check shoulder axis


%% Parse IMU Log File

g = 9.80665;             % gravity, m/s^2

raw = readlines(filename);
N = numel(raw);

time_ms = zeros(N,1);

bicep_accel = zeros(N,3);
bicep_pqr   = zeros(N,3);

wrist_accel = zeros(N,3);
wrist_pqr   = zeros(N,3);

numTok = "([-+0-9.eE]+|NaN)";

for i = 1:N
    line = raw(i);

    if strlength(line) < 10
        continue
    end

    tok = regexp(line, "t=(\d+)\s*ms", "tokens", "once");
    if ~isempty(tok)
        time_ms(i) = str2double(tok{1});
    end

    tok = regexp(line, "Bicep xyz\(" + numTok + "," + numTok + "," + numTok + "\)", ...
                 "tokens", "once");
    if ~isempty(tok)
        bicep_accel(i,:) = str2double(tok);
    end

    tok = regexp(line, "Bicep xyz\([^\)]*\)\s*pqr\(" + ...
                 numTok + "," + numTok + "," + numTok + "\)", ...
                 "tokens", "once");
    if ~isempty(tok)
        bicep_pqr(i,:) = str2double(tok);
    end

    tok = regexp(line, "Wrist xyz\(" + numTok + "," + numTok + "," + numTok + "\)", ...
                 "tokens", "once");
    if ~isempty(tok)
        wrist_accel(i,:) = str2double(tok);
    end

    tok = regexp(line, "Wrist xyz\([^\)]*\)\s*pqr\(" + ...
                 numTok + "," + numTok + "," + numTok + "\)", ...
                 "tokens", "once");
    if ~isempty(tok)
        wrist_pqr(i,:) = str2double(tok);
    end
end

valid = time_ms > 0;

time_ms     = time_ms(valid);
bicep_accel = bicep_accel(valid,:);
bicep_pqr   = bicep_pqr(valid,:);
wrist_accel = wrist_accel(valid,:);
wrist_pqr   = wrist_pqr(valid,:);

time = (time_ms - time_ms(1)) / 1000;
sample = (1:length(time))';

%% Raw Sensor Data Plot for Calibration Range Selection

figure(1); clf;
set(gcf,"Name","Raw IMU Data for Calibration Selection","Color","w");
tiledlayout(2,2,"TileSpacing","compact","Padding","compact");

nexttile;
plot(sample, bicep_accel, "LineWidth",1.2);
grid on; box on;
title("Raw Bicep Acceleration");
xlabel("Sample Number");
ylabel("Acceleration [g]");
legend("X","Y","Z","Location","best");
addSampleMarkers(cal_idx_range, armDownCal_idx, armOutCal_idx);

nexttile;
plot(sample, bicep_pqr, "LineWidth",1.2);
grid on; box on;
title("Raw Bicep Gyroscope");
xlabel("Sample Number");
ylabel("Angular Rate [deg/s]");
legend("P","Q","R","Location","best");
addSampleMarkers(cal_idx_range, armDownCal_idx, armOutCal_idx);

nexttile;
plot(sample, wrist_accel, "LineWidth",1.2);
grid on; box on;
title("Raw Wrist Acceleration");
xlabel("Sample Number");
ylabel("Acceleration [g]");
legend("X","Y","Z","Location","best");
addSampleMarkers(cal_idx_range, armDownCal_idx, armOutCal_idx);

nexttile;
plot(sample, wrist_pqr, "LineWidth",1.2);
grid on; box on;
title("Raw Wrist Gyroscope");
xlabel("Sample Number");
ylabel("Angular Rate [deg/s]");
legend("P","Q","R","Location","best");
addSampleMarkers(cal_idx_range, armDownCal_idx, armOutCal_idx);

sgtitle("Raw IMU Data Before Calibration");

%% Basic Checks

nSamples = length(time);

if max(cal_idx_range) > nSamples || zero_idx > nSamples || ...
   armDownCal_idx > nSamples || armOutCal_idx > nSamples
    error("One or more calibration indices exceed the number of parsed samples.");
end

if min(cal_idx_range) < 1 || zero_idx < 1 || armDownCal_idx < 1 || armOutCal_idx < 1
    error("Calibration indices must be positive sample numbers.");
end

if armDownCal_idx == armOutCal_idx
    error("armDownCal_idx and armOutCal_idx must be different samples.");
end

dt = mean(diff(time));
Fs = 1 / dt;

%% Sensor Calibration

% Normalize acceleration using the selected stationary calibration range.
bicep_accel_norm = bicep_accel ./ norm(mean(bicep_accel(cal_idx_range,:),1));
wrist_accel_norm = wrist_accel ./ norm(mean(wrist_accel(cal_idx_range,:),1));

% Remove gyroscope bias using the selected stationary calibration range.
bicep_pqr_cal = bicep_pqr - mean(bicep_pqr(cal_idx_range,:),1);
wrist_pqr_cal = wrist_pqr - mean(wrist_pqr(cal_idx_range,:),1);

%% Plot Calibrated IMU Data Before Cut

figure(2); clf;
set(gcf,"Name","Calibrated IMU Data Before Cut","Color","w");
tiledlayout(2,2,"TileSpacing","compact","Padding","compact");

nexttile;
plot(sample, bicep_accel_norm, "LineWidth",1.3);
grid on; box on;
title("Bicep Acceleration");
xlabel("Sample Number");
ylabel("Acceleration [g]");
legend("X","Y","Z","Location","best");
addSampleMarkers(cal_idx_range, armDownCal_idx, armOutCal_idx);

nexttile;
plot(sample, bicep_pqr_cal, "LineWidth",1.3);
grid on; box on;
title("Bicep Gyroscope");
xlabel("Sample Number");
ylabel("Angular Rate [deg/s]");
legend("P","Q","R","Location","best");
addSampleMarkers(cal_idx_range, armDownCal_idx, armOutCal_idx);

nexttile;
plot(sample, wrist_accel_norm, "LineWidth",1.3);
grid on; box on;
title("Wrist Acceleration");
xlabel("Sample Number");
ylabel("Acceleration [g]");
legend("X","Y","Z","Location","best");
addSampleMarkers(cal_idx_range, armDownCal_idx, armOutCal_idx);

nexttile;
plot(sample, wrist_pqr_cal, "LineWidth",1.3);
grid on; box on;
title("Wrist Gyroscope");
xlabel("Sample Number");
ylabel("Angular Rate [deg/s]");
legend("P","Q","R","Location","best");
addSampleMarkers(cal_idx_range, armDownCal_idx, armOutCal_idx);

sgtitle("Normalized and Bias-Corrected IMU Data Before zero\_idx Cut");

%% Complementary Filter Orientation Estimate

FUSE_bicep = complementaryFilter( ...
    "OrientationFormat","Rotation matrix", ...
    "HasMagnetometer",false, ...
    "SampleRate",Fs, ...
    "AccelerometerGain",accelGain);

FUSE_wrist = complementaryFilter( ...
    "OrientationFormat","Rotation matrix", ...
    "HasMagnetometer",false, ...
    "SampleRate",Fs, ...
    "AccelerometerGain",accelGain);

DCM_bicep = FUSE_bicep(bicep_accel_norm * g, deg2rad(bicep_pqr_cal));
DCM_wrist = FUSE_wrist(wrist_accel_norm * g, deg2rad(wrist_pqr_cal));

%% Untransformed Euler Angles

% These angles are before the arm frame transformation.
rot_bicep_raw = rotm2eul(DCM_bicep, "XYZ");
rot_bicep_raw = unwrap(rot_bicep_raw);

rot_wrist_raw = rotm2eul(DCM_wrist, "XYZ");
rot_wrist_raw = unwrap(rot_wrist_raw);

%% Plot Untransformed Angles

figure(3); clf;
set(gcf,"Name","Untransformed Complementary Filter Angles","Color","w");
tiledlayout(2,1,"TileSpacing","compact","Padding","compact");

nexttile;
plot(sample, rad2deg(rot_bicep_raw(:,1)), "LineWidth",1.4, "DisplayName","X Rotation");
hold on;
plot(sample, rad2deg(rot_bicep_raw(:,2)), "LineWidth",1.4, "DisplayName","Y Rotation");
plot(sample, rad2deg(rot_bicep_raw(:,3)), "LineWidth",1.4, "DisplayName","Z Rotation");
xline(zero_idx, "--", "zero idx", "LabelVerticalAlignment","bottom", "HandleVisibility","off");
grid on; box on;
title("Bicep Untransformed Angles");
xlabel("Sample Number");
ylabel("Rotation [deg]");
legend("Location","best");

nexttile;
plot(sample, rad2deg(rot_wrist_raw(:,1)), "LineWidth",1.4, "DisplayName","X Rotation");
hold on;
plot(sample, rad2deg(rot_wrist_raw(:,2)), "LineWidth",1.4, "DisplayName","Y Rotation");
plot(sample, rad2deg(rot_wrist_raw(:,3)), "LineWidth",1.4, "DisplayName","Z Rotation");
xline(zero_idx, "--", "zero idx", "LabelVerticalAlignment","bottom", "HandleVisibility","off");
grid on; box on;
title("Wrist Untransformed Angles");
xlabel("Sample Number");
ylabel("Rotation [deg]");
legend("Location","best");

sgtitle("Angles Before Frame Transformation");

%% Frame Transformations

% First calibration pose: arm straight down.
g_down_bicep = bicep_accel_norm(armDownCal_idx,:)';
g_down_wrist = wrist_accel_norm(armDownCal_idx,:)';

% Second calibration pose: arm straight out from the body.
g_out_bicep = bicep_accel_norm(armOutCal_idx,:)';
g_out_wrist = wrist_accel_norm(armOutCal_idx,:)';

C_bicep = computeGravityCalibration(g_down_bicep, g_out_bicep);
C_wrist = computeGravityCalibration(g_down_wrist, g_out_wrist);

DCM_bicep_cal = pagemtimes(C_bicep, DCM_bicep);
DCM_wrist_cal = pagemtimes(C_wrist, DCM_wrist);

%% Transformed Euler Angles

rot_bicep = rotm2eul(DCM_bicep_cal, "XYZ");
rot_bicep = unwrap(rot_bicep);

rot_wrist = rotm2eul(DCM_wrist_cal, "XYZ");
rot_wrist = unwrap(rot_wrist);

% Zero angles at zero_idx before cutting data.
rot_bicep = rot_bicep - rot_bicep(zero_idx,:);
rot_wrist = rot_wrist - rot_wrist(zero_idx,:);

% Optional bicep roll offset.
rot_bicep(:,1) = rot_bicep(:,1) + deg2rad(yaw_offset);

%% Cut Data From zero_idx

idx_keep = zero_idx:length(time);

time = time(idx_keep);
time = time - time(1);

bicep_accel_norm = bicep_accel_norm(idx_keep,:);
bicep_pqr_cal    = bicep_pqr_cal(idx_keep,:);
wrist_accel_norm = wrist_accel_norm(idx_keep,:);
wrist_pqr_cal    = wrist_pqr_cal(idx_keep,:);

rot_bicep = rot_bicep(idx_keep,:);
rot_wrist = rot_wrist(idx_keep,:);

%% Simulink-Ready Outputs

rot_x_bicep =   rot_bicep(:,1);
rot_y_bicep = - rot_bicep(:,2);
rot_z_bicep =   rot_bicep(:,3);

rot_x_wrist =   (rot_wrist(:,1) - rot_bicep(:,1));
rot_y_wrist =  - (rot_wrist(:,2) - rot_bicep(:,2));
rot_z_wrist =   (rot_wrist(:,3) - rot_bicep(:,3));

%% Initial Bicep X Ramp Segment for Simulink

ramp_time = 3.0;   % seconds for x bicep to ramp from pitch_offset to 0

dt = mean(diff(time));
time_ramp = (0:dt:ramp_time-dt)';

n_ramp = length(time_ramp);

% Ramp x bicep from pitch_offset to 0
rot_x_bicep_ramp = linspace(deg2rad(-45-pitch_offset), 0, n_ramp)';

% Shift original motion to start after ramp
time_motion = time + ramp_time;

% New combined time vector
time = [time_ramp; time_motion];

% Add ramp before x bicep, keep all others zero
rot_x_bicep = [rot_x_bicep_ramp; rot_x_bicep];
rot_y_bicep = [zeros(n_ramp,1); rot_y_bicep];
rot_z_bicep = [zeros(n_ramp,1); rot_z_bicep];

rot_x_wrist = [zeros(n_ramp,1); rot_x_wrist];
rot_y_wrist = [zeros(n_ramp,1); rot_y_wrist];
rot_z_wrist = [zeros(n_ramp,1); rot_z_wrist];

%% Plot Rotation Outputs

figure(4); clf;
set(gcf,"Name","Simulink Rotation Outputs","Color","w");
tiledlayout(2,1,"TileSpacing","compact","Padding","compact");

nexttile;
plot(time, rad2deg(rot_x_bicep), "LineWidth",1.4, "DisplayName","X Rotation");
hold on;
plot(time, rad2deg(rot_y_bicep), "LineWidth",1.4, "DisplayName","Y Rotation");
plot(time, rad2deg(rot_z_bicep), "LineWidth",1.4, "DisplayName","Z Rotation");
grid on; box on;
title("Bicep Rotation");
xlabel("Time [s]");
ylabel("Rotation [deg]");
legend("Location","best");

nexttile;
plot(time, rad2deg(rot_x_wrist), "LineWidth",1.4, "DisplayName","X Rotation");
hold on;
plot(time, rad2deg(rot_y_wrist), "LineWidth",1.4, "DisplayName","Y Rotation");
plot(time, rad2deg(rot_z_wrist), "LineWidth",1.4, "DisplayName","Z Rotation");
grid on; box on;
title("Wrist Rotation Relative to Bicep");
xlabel("Time [s]");
ylabel("Rotation [deg]");
legend("Location","best");

sgtitle("Final Angle Outputs for Simulink");

%% Optional Animation

if runAnimation
    animate_vector(rot_bicep, time);
end

%% Local Functions

function C = computeGravityCalibration(g_down, g_out)
% computeGravityCalibration
%
% Builds a calibration rotation matrix from two measured gravity vectors.
%
% Inputs:
%   g_down - measured gravity vector when arm is straight down
%   g_out  - measured gravity vector when arm is straight out from body
%
% Output:
%   C      - 3x3 orthonormal calibration matrix

    x_meas = -cross(g_down, g_out);
    x_meas = x_meas / norm(x_meas);

    z_meas = g_down;
    z_meas = z_meas / norm(z_meas);

    y_meas = cross(x_meas, z_meas);
    y_meas = y_meas / norm(y_meas);

    B = [x_meas, y_meas, -z_meas];

    C_unrefined = eye(3) / B;

    [U,~,V] = svd(C_unrefined);
    C = U * V';

    if det(C) < 0
        U(:,3) = -U(:,3);
        C = U * V';
    end
end


function addSampleMarkers(cal_idx_range, armDownCal_idx, armOutCal_idx)
% addSampleMarkers
%
% Adds stationary calibration region shading and arm calibration pose lines.

    ax = gca;
    yl = ylim(ax);

    x1 = cal_idx_range(1);
    x2 = cal_idx_range(end);

    hold on;

    % More visible green stationary calibration region
    p = patch([x1 x2 x2 x1], [yl(1) yl(1) yl(2) yl(2)], ...
        [0.20 0.85 0.30], ...
        "FaceAlpha",0.30, ...
        "EdgeColor",[0.10 0.55 0.15], ...
        "LineWidth",1.0, ...
        "DisplayName","Stationary Calibration Region");

    uistack(p,"bottom");

    xline(armDownCal_idx, "--", "Arm Down", ...
        "LabelVerticalAlignment","bottom", ...
        "HandleVisibility","off");

    xline(armOutCal_idx, "--", "Arm Out", ...
        "LabelVerticalAlignment","bottom", ...
        "HandleVisibility","off");

    ylim(yl);
end

function animate_vector(rot, time)
% animate_vector
%
% Animates a unit vector using XYZ Euler angles.
%
% Inputs:
%   rot  - Nx3 Euler angles in radians
%   time - Nx1 time vector in seconds

    DCM_anim = eul2rotm(rot, "XYZ");

    vec = [0; 0; 1];
    vec_new = pagemtimes(DCM_anim, vec);

    nSteps = length(time);

    figure("Name","Bicep Orientation Animation","Color","w");
    grid on; axis equal; box on; hold on;
    xlabel("X");
    ylabel("Y");
    zlabel("Z");
    view(135,30);

    limit = 1.2;
    xlim([-limit limit]);
    ylim([-limit limit]);
    zlim([-limit limit]);

    hArrow = quiver3(0,0,0, ...
        vec_new(1,1), vec_new(2,1), vec_new(3,1), ...
        0, "LineWidth",3, "MaxHeadSize",0.5);

    hTrace = plot3(vec_new(1,1), vec_new(2,1), vec_new(3,1), ...
        ":", "LineWidth",1.5);

    hTitle = title(sprintf("Time: %.2f s", time(1)));

    for i = 1:nSteps
        set(hArrow, ...
            "UData",vec_new(1,i), ...
            "VData",vec_new(2,i), ...
            "WData",vec_new(3,i));

        set(hTrace, ...
            "XData",vec_new(1,1:i), ...
            "YData",vec_new(2,1:i), ...
            "ZData",vec_new(3,1:i));

        set(hTitle, "String", sprintf("Time: %.2f s", time(i)));

        drawnow limitrate;
        pause(0.01);
    end
end