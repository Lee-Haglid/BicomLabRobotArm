%% Simulink Arm Angle Data Extract, Resample, Plot, and Export
%{
DESCRIPTION:
This script extracts arm angle data from Simulink output, unwraps angle
discontinuities, zeros each angle at the first sample, resamples onto a uniform
time vector, converts to degrees, plots the signals, and exports them to a CSV.

ASSUMPTIONS:
Simulink output is stored in:
   out.simout.Time
   out.simout.Data

Data columns:
   Column 1 - Bottom arm angle [rad]
   Column 2 - Middle arm angle [rad]
   Column 3 - Top arm angle [rad]
   Column 4 - Bicep angle [rad]
   Column 5 - Wrist angle [rad]
%}

%% User Inputs

dt_export = 0.02;                       % export time step [s]
output_filename = "simout_20ms.csv";    % output CSV file name

%% Extract Simulink Data

time_raw = out.simout.Time(:);
data_raw = out.simout.Data;

bottom_arm_raw = data_raw(:,1);         % bottom arm angle [rad]
middle_arm_raw = data_raw(:,2);         % middle arm angle [rad]
top_arm_raw    = data_raw(:,3);         % top arm angle [rad]
bicep_raw      = data_raw(:,4);         % bicep angle [rad]
wrist_raw      = data_raw(:,5);         % wrist angle [rad]

%% Unwrap Raw Angle Signals

bottom_arm_raw = unwrap(bottom_arm_raw);
middle_arm_raw = unwrap(middle_arm_raw);
top_arm_raw    = unwrap(top_arm_raw);
bicep_raw      = unwrap(bicep_raw);
wrist_raw      = unwrap(wrist_raw);

%% Zero Angles at First Sample

bottom_arm_raw = bottom_arm_raw - bottom_arm_raw(1);
middle_arm_raw = middle_arm_raw - middle_arm_raw(1);
top_arm_raw    = top_arm_raw    - top_arm_raw(1);
bicep_raw      = bicep_raw      - bicep_raw(1);
wrist_raw      = wrist_raw      - wrist_raw(1);

%% Create Uniform Time Vector

time_export = (time_raw(1):dt_export:time_raw(end)).';

%% Resample Signals

bottom_arm = interp1(time_raw, bottom_arm_raw, time_export, "linear");
middle_arm = interp1(time_raw, middle_arm_raw, time_export, "linear");
top_arm    = interp1(time_raw, top_arm_raw,    time_export, "linear");
bicep      = interp1(time_raw, bicep_raw,      time_export, "linear");
wrist      = interp1(time_raw, wrist_raw,      time_export, "linear");

%% Convert to Degrees

bottom_arm = rad2deg(bottom_arm);
middle_arm = rad2deg(middle_arm);
top_arm    = rad2deg(top_arm);
bicep      = rad2deg(bicep);
wrist      = rad2deg(wrist);

%% Plot Exported Signals

figure("Name","Resampled Simulink Angle Output","Color","w");

plot(time_export, bottom_arm, "LineWidth",1.5, "DisplayName","Bottom Arm");
hold on;
plot(time_export, middle_arm, "LineWidth",1.5, "DisplayName","Middle Arm");
plot(time_export, top_arm,    "LineWidth",1.5, "DisplayName","Top Arm");
plot(time_export, bicep,      "LineWidth",1.5, "DisplayName","Bicep");
plot(time_export, wrist,      "LineWidth",1.5, "DisplayName","Wrist");

grid on; box on;
xlabel("Time [s]");
ylabel("Angle [deg]");
title("Simulink Angle Output Resampled to 20 ms");
legend("Location","best");

%% Export CSV

time_export = time_export(:);
bottom_arm  = bottom_arm(:);
middle_arm  = middle_arm(:);
top_arm     = top_arm(:);
bicep       = bicep(:);
wrist       = wrist(:);

T = table(time_export, bottom_arm, middle_arm, top_arm, bicep, wrist, ...
    'VariableNames', {'Time_s','BottomArm_deg','MiddleArm_deg','TopArm_deg', ...
                      'Bicep_deg','Wrist_deg'});

writetable(T, output_filename);

fprintf("Exported %d samples to %s\n", height(T), output_filename);