%% Demo Rotation Signal Generator

clear; clc; close all;

%% Settings

dt = 0.01;           % time step [s]
freq = .1;          % circle sine frequency [Hz]

amp_deg = 10;        % pitch/roll/yaw/circle amplitude [deg]

circle_time = 20;    % duration of circular bicep motion [s]
ramp_in_time = 1.0;  % time to rise into full circle [s]
ramp_out_time = 1.0; % time to return to zero [s]

pause_time = 0;    % pause between segments [s]

wrist_y_test_angle_deg = 45;  % wrist bend angle [deg]
wrist_z_test_angle_deg = 20;  % wrist twist angle [deg]

move_time = 2;     % time to move to angle [s]
hold_time = 0.1;     % time to hold angle [s]
return_time = move_time;   % time to return to zero [s]

% Simulink Inputs
shoulder_limit = 45;     % max shoulder joint angle limit from neutral [deg]
yaw_offset = 0;          % constant shoulder yaw offset [deg]

pitch_offset = -45;      % negative angle means pitch up
signal_timeconst = 0.01;  % Simulink first-order filter time constant [s]

%% Segment Times

plus_minus_time = 2*move_time + 2*hold_time + return_time;
out_back_time   = move_time + hold_time + return_time;

T = 0;

T_pitch_start = T;
T_pitch_end = T_pitch_start + plus_minus_time;
T = T_pitch_end + pause_time;

T_roll_start = T;
T_roll_end = T_roll_start + plus_minus_time;
T = T_roll_end + pause_time;

T_yaw_start = T;
T_yaw_end = T_yaw_start + plus_minus_time;
T = T_yaw_end + pause_time;

T_circle_start = T;
T_circle_end = T_circle_start + circle_time;
T = T_circle_end + pause_time;

T_wrist_y_start = T;
T_wrist_y_end = T_wrist_y_start + out_back_time;
T = T_wrist_y_end + pause_time;

T_wrist_z_start = T;
T_wrist_z_end = T_wrist_z_start + plus_minus_time;
T = T_wrist_z_end + pause_time;

T_pitch_wrist_start = T;
T_pitch_wrist_end = T_pitch_wrist_start + out_back_time;

T_end = T_pitch_wrist_end;

%% Time

time = (0:dt:T_end)';

%% Initialize Signals

rot_x_bicep = zeros(size(time));
rot_y_bicep = zeros(size(time));
rot_z_bicep = zeros(size(time));

rot_x_wrist = zeros(size(time));
rot_y_wrist = zeros(size(time));
rot_z_wrist = zeros(size(time));

%% 1. Pitch Positive, Negative, Back

idx = time >= T_pitch_start & time <= T_pitch_end;
t_seg = time(idx) - T_pitch_start;

profile = smoothPlusMinusBack(t_seg, move_time, hold_time, return_time);

rot_x_bicep(idx) = deg2rad(amp_deg) * profile;

%% 2. Roll Positive, Negative, Back

idx = time >= T_roll_start & time <= T_roll_end;
t_seg = time(idx) - T_roll_start;

profile = smoothPlusMinusBack(t_seg, move_time, hold_time, return_time);

rot_y_bicep(idx) = deg2rad(amp_deg) * profile;

%% 3. Yaw Positive, Negative, Back

idx = time >= T_yaw_start & time <= T_yaw_end;
t_seg = time(idx) - T_yaw_start;

profile = smoothPlusMinusBack(t_seg, move_time, hold_time, return_time);

rot_z_bicep(idx) = deg2rad(amp_deg) * profile;

%% 4. Circular Bicep Rotation Segment

idx_circle = time >= T_circle_start & time <= T_circle_end;
t_circle = time(idx_circle) - T_circle_start;

amp = deg2rad(amp_deg);
omega = 2*pi*freq;

% Ramp in
ramp_in = min(t_circle / ramp_in_time, 1);
ramp_in = 0.5 - 0.5*cos(pi*ramp_in);

% Ramp out
time_to_circle_end = circle_time - t_circle;
ramp_out = min(time_to_circle_end / ramp_out_time, 1);
ramp_out = 0.5 - 0.5*cos(pi*ramp_out);

% Combined envelope
ramp = ramp_in .* ramp_out;

rot_x_bicep(idx_circle) = ramp .* amp .* sin(omega*t_circle);
rot_y_bicep(idx_circle) = ramp .* amp .* sin(omega*t_circle + deg2rad(90));
rot_z_bicep(idx_circle) = 0;

%% 5. Wrist Y Bend Out and Back

idx = time >= T_wrist_y_start & time <= T_wrist_y_end;
t_seg = time(idx) - T_wrist_y_start;

profile = smoothOutBack(t_seg, move_time, hold_time, return_time);

rot_y_wrist(idx) = deg2rad(wrist_y_test_angle_deg) * profile;

%% 6. Wrist Z Positive, Negative, Back

idx = time >= T_wrist_z_start & time <= T_wrist_z_end;
t_seg = time(idx) - T_wrist_z_start;

profile = smoothPlusMinusBack(t_seg, move_time, hold_time, return_time);

rot_z_wrist(idx) = deg2rad(wrist_z_test_angle_deg) * profile;

%% 7. Pitch, Wrist Y, and Wrist Z Movement Together, Then Back

idx = time >= T_pitch_wrist_start & time <= T_pitch_wrist_end;
t_seg = time(idx) - T_pitch_wrist_start;

profile = smoothOutBack(t_seg, move_time, hold_time, return_time);

% Pitch motion
rot_x_bicep(idx) = deg2rad(amp_deg) * profile;

% Wrist Y bend at same time
rot_y_wrist(idx) = deg2rad(wrist_y_test_angle_deg) * profile;

% Wrist Z twist at same time
rot_z_wrist(idx) = deg2rad(wrist_z_test_angle_deg) * profile;

%% Plot Signals

figure(1); clf;
set(gcf,"Name","Demo Rotation Outputs","Color","w");

tiledlayout(2,1,"TileSpacing","compact","Padding","compact");

nexttile;
plot(time, rad2deg(rot_x_bicep), "LineWidth",1.5, "DisplayName","Pitch / X Bicep");
hold on;
plot(time, rad2deg(rot_y_bicep), "LineWidth",1.5, "DisplayName","Roll / Y Bicep");
plot(time, rad2deg(rot_z_bicep), "LineWidth",1.5, "DisplayName","Yaw / Z Bicep");
grid on; box on;
title("Bicep Rotation Demo Signal");
xlabel("Time [s]");
ylabel("Rotation [deg]");
legend("Location","best");

nexttile;
plot(time, rad2deg(rot_x_wrist), "LineWidth",1.5, "DisplayName","Wrist X");
hold on;
plot(time, rad2deg(rot_y_wrist), "LineWidth",1.5, "DisplayName","Wrist Y Bend");
plot(time, rad2deg(rot_z_wrist), "LineWidth",1.5, "DisplayName","Wrist Z Twist");
grid on; box on;
title("Wrist Rotation Demo Signal");
xlabel("Time [s]");
ylabel("Rotation [deg]");
legend("Location","best");

sgtitle("Simulink Demo Inputs");

%% Optional X-Y Circle Check

figure(2); clf;
set(gcf,"Name","Bicep X-Y Rotation Path","Color","w");

idx_circle_plot = time >= T_circle_start & time <= T_circle_end;

plot(rad2deg(rot_x_bicep(idx_circle_plot)), ...
     rad2deg(rot_y_bicep(idx_circle_plot)), ...
     "LineWidth",1.5);

grid on; box on; axis equal;
title("Bicep X-Y Rotation Path During Circle Segment");
xlabel("X Rotation [deg]");
ylabel("Y Rotation [deg]");

%% Optional Wrist Profile Plot

figure(3); clf;
set(gcf,"Name","Wrist Y Bend and Z Twist Profiles","Color","w");

plot(time, rad2deg(rot_y_wrist), "LineWidth",1.5, "DisplayName","Wrist Y Bend");
hold on;
plot(time, rad2deg(rot_z_wrist), "LineWidth",1.5, "DisplayName","Wrist Z Twist");
grid on; box on;
title("Wrist Y Bend and Z Twist Test");
xlabel("Time [s]");
ylabel("Wrist Rotation [deg]");
legend("Location","best");

%% Optional Segment Markers Plot

figure(4); clf;
set(gcf,"Name","Demo Segment Timeline","Color","w");

plot(time, rad2deg(rot_x_bicep), "LineWidth",1.5, "DisplayName","X Bicep");
hold on;
plot(time, rad2deg(rot_y_bicep), "LineWidth",1.5, "DisplayName","Y Bicep");
plot(time, rad2deg(rot_z_bicep), "LineWidth",1.5, "DisplayName","Z Bicep");
plot(time, rad2deg(rot_y_wrist), "LineWidth",1.5, "DisplayName","Y Wrist");
plot(time, rad2deg(rot_z_wrist), "LineWidth",1.5, "DisplayName","Z Wrist");

xline(T_pitch_start, "--", "Pitch", "HandleVisibility","off");
xline(T_roll_start, "--", "Roll", "HandleVisibility","off");
xline(T_yaw_start, "--", "Yaw", "HandleVisibility","off");
xline(T_circle_start, "--", "Circle", "HandleVisibility","off");
xline(T_wrist_y_start, "--", "Wrist Y", "HandleVisibility","off");
xline(T_wrist_z_start, "--", "Wrist Z", "HandleVisibility","off");
xline(T_pitch_wrist_start, "--", "Pitch+Wrist", "HandleVisibility","off");

grid on; box on;
title("Full Demo Timeline");
xlabel("Time [s]");
ylabel("Rotation [deg]");
legend("Location","best");

%% Helper Functions

function s = smoothOutBack(t, move_time, hold_time, return_time)

    s = zeros(size(t));

    % Move from 0 to +1
    idx_move = t >= 0 & t < move_time;
    tau = t(idx_move) / move_time;
    s(idx_move) = 0.5 - 0.5*cos(pi*tau);

    % Hold at +1
    idx_hold = t >= move_time & t < move_time + hold_time;
    s(idx_hold) = 1;

    % Return from +1 to 0
    idx_return = t >= move_time + hold_time & t <= move_time + hold_time + return_time;
    tau = (t(idx_return) - move_time - hold_time) / return_time;
    s(idx_return) = 0.5 + 0.5*cos(pi*tau);

end

function s = smoothPlusMinusBack(t, move_time, hold_time, return_time)

    s = zeros(size(t));

    t1 = move_time;
    t2 = t1 + hold_time;
    t3 = t2 + move_time;
    t4 = t3 + hold_time;
    t5 = t4 + return_time;

    % Move from 0 to +1
    idx = t >= 0 & t < t1;
    tau = t(idx) / move_time;
    s(idx) = 0.5 - 0.5*cos(pi*tau);

    % Hold at +1
    idx = t >= t1 & t < t2;
    s(idx) = 1;

    % Move directly from +1 to -1
    idx = t >= t2 & t < t3;
    tau = (t(idx) - t2) / move_time;
    s(idx) = cos(pi*tau);

    % Hold at -1
    idx = t >= t3 & t < t4;
    s(idx) = -1;

    % Move from -1 to 0
    idx = t >= t4 & t <= t5;
    tau = (t(idx) - t4) / return_time;
    s(idx) = -0.5 - 0.5*cos(pi*tau);

end