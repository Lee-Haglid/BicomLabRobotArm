%User settings
csvFile = "simout_20ms.csv";   % your CSV file
port    = "COM7";             % change to your Arduino COM port
baud    = 115200;

%Read CSV
T = readtable(csvFile);

% Expect columns: time, deg1, deg2, deg3
t  = T{:,1};
a1 = T{:,2};
a2 = T{:,3};
a3 = T{:,4};

% Convert timestamps to milliseconds (relative)
% If your CSV timestamps are already ms, remove the *1000
t_ms = uint32(round(1000 * (t - t(1))));

% Sanity check
if any(diff(double(t_ms)) < 0)
    error("Timestamps must be monotonically increasing.");
end

%Set up the serial port
sp = serialport(port, baud);
configureTerminator(sp, "LF");
pause(2);   % allow Arduino auto-reset

% Flush any startup text
while sp.NumBytesAvailable > 0
    readline(sp);
end

% send the data over
disp("Sending trajectory...");

writeline(sp, "START");

for k = 1:numel(t_ms)
    line = sprintf("%lu,%d,%d,%d", ...
        t_ms(k), round(a1(k)), round(a2(k)), round(a3(k)));

    writeline(sp, line);

    % Optional throttle (uncomment if USB ever overruns)
    % pause(0.001);
end

writeline(sp, "END");

disp("Done streaming.");


