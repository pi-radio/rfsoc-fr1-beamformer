%% 0. In this demo, sdr1 is the device under test (DUT). The reference
%  receiver (i.e., helper) can be one of three things:

%   p1) sdr2, under our control
%   p2) reference antenna in the chamber, under control of the operator
%   p3) FieldFox, under our control. The FieldFox TX port and and RX port
%       should be connected to an isolated power combiner (port_1 and
%       port_2). The common port of the power combiner (port_C) should be
%       connected to a whip antenna. This way, a common antenna is used for
%       the FieldFox transmitting and receiving. Configure the FieldFox in
%       SA mode. Set the center frequency to 3250 MHz, and the span to
%       100 MHz. 

% This block of code makes sure that neither sdr is transmitting.
clearvars -except sdr1 sdr2;
nFFT = 1024;
scMin = -50; scMax = 50;

txtd = zeros(nFFT, sdr1.nch);
sdr1.send(txtd);
sdr2.send(txtd);
pause(0.2);
sdr1.recv(nFFT, nFFT*3, 10, 1);
sdr2.recv(nFFT, nFFT*3, 10, 1);

txfd = zeros(nFFT, 1);
constellation = [1+1j 1-1j -1+1j -1-1j];

% Generate a reference TX waveform
for scIndex = scMin:scMax
    txfd(nFFT/2 + 1 + scIndex) = constellation(randi(4));
end
txfd = fftshift(txfd);
txtd_single = ifft(txfd);
m = max(abs(txtd_single));
txtd_single = txtd_single / m * 20000;
clearvars -except sdr1 sdr2 txtd_single nFFT scMin scMax;

%% 1. sdr1 needs to detect the AoA from the "helper". Make the helper transmit.

%   p1) Run this block of code. This will make the "helper" sdr2 transmit
%       a known signal, so that sdr1 can detect it. 
%   p2) Tell the operator to transmit a CW tone at 3250.96 MHz from the
%       reference antenna. Do not run this block of code.
%   p3) Configure the FieldFox to transmit a tone at 3250.96 MHz, with
%       maximum power. Turn on the transmitter. Do not run this block of
%       code.

txtd = zeros(nFFT, sdr2.nch);
for txChId = 2:8
    txtd(:, txChId) = txtd_single; % Beamform straight ahead
end
txtd = sdr2.applyCalTxArray(txtd);
sdr2.send(txtd);
clearvars -except sdr1 sdr2 scMin scMax nFFT txtd_single;

%% 2. Now, let the DUT (sdr1) detect the AoA of the signal from "helper"
%  Always run this code, irrespective of (p1, p2, p3)

clc;
nread = 1024;
nFFT = nread;
nskip = nread * 3;
ntimes = 100;

rxtd = sdr1.recv(nread, nskip, ntimes, 1);
rxtd = sdr1.applyCalRxArray(rxtd);

naoa = 301;
aoas = linspace(-1, 1, naoa);
pArray = zeros(1, naoa);

for iaoa = 1:naoa
    p = 0;
    aoa = aoas(iaoa);
    for itimes = 1:ntimes
        tdbf = zeros(nFFT, 1);
        for rxIndex=1:sdr1.nch
            td = rxtd(:,itimes,rxIndex);
            tdbf = tdbf + td * exp(1j*rxIndex*pi*sin(aoa)); % Apply BF Vec
        end % rxIndex
        fd = fftshift(fft(tdbf));
        p = p + sum(abs(fd( nFFT/2 + 1 + scMin : nFFT/2 + 1 + scMax)));
    end %itimes
    pArray(iaoa) = p;
end % iaoa

% Plot
figure(3);  clf;
plot(rad2deg(aoas), mag2db(pArray), 'LineWidth', 5); hold on;
xlabel('Angle of Arrival (Deg)');
ylabel('Power (dB)');
set(gca, 'FontSize', 30);
grid on; grid minor;
[a, b] = max(pArray);
detected_aoa = rad2deg(aoas(b));
sprintf("Detected the AoA at %2.2f degrees", detected_aoa)
detected_aoa = detected_aoa * (-1);

% Clear workspace variables
clearvars -except sdr1 sdr2 scMin scMax nFFT detected_aoa txtd_single;

%% 3. Now, make the "helper" stop transmitting.

%   p1) Run this block of code. This will make the "helper" sdr2 stop
%       transmitting.
%   p2) Tell the operator to stop transmitting. Do not run this block of
%       code.
%   p3) Configure the FieldFox to stop transmitting (i.e., turn the source
%       OFF). Do not run this block of code.

txtd = zeros(nFFT, sdr2.nch);
sdr2.send(txtd);
clearvars -except sdr1 sdr2 scMin scMax nFFT detected_aoa txtd_single;

%% 4. Now, make sdr1 Beamform/Nullform toward the "helper"
%  (p1, p2, p3): Always run this code.

% Mode 1: Beamform at AoA, Nullform 20 degrees away
% Mode 2: Beamform at AoA, no control of NULL
% Mode 3: Beamform at AoA + 20, Nullform at AoA
% Mode 4: Beamform at AoA + 20, no control of NULL

mode = 3;   % Set the mode

freq = 3.25e9;
c = physconst('LightSpeed');
lam = c/freq;
nch = 7;
pos = (0:nch-1)*0.5;

if (mode == 1)      % Mode 1: Beamform at AoA, Nullform 20 degrees away
    thetad = detected_aoa;
    thetan = detected_aoa + 20;
    wd = steervec(pos, thetad);
    wn = steervec(pos, thetan);
    rn = wn'*wd/(wn'*wn);
    w = wd-wn*rn;
elseif (mode == 2)  % Mode 2: Beamform at AoA, no control of NULL
    thetad = detected_aoa;
    wd = steervec(pos, thetad);
    w = wd;
elseif (mode == 3)  % Mode 3: Beamform at AoA + 20, Nullform at AoA
    thetad = detected_aoa + 20;
    thetan = detected_aoa;
    wd = steervec(pos, thetad);
    wn = steervec(pos, thetan);
    rn = wn'*wd/(wn'*wn);
    w = wd-wn*rn;
elseif (mode == 4)  % Mode 4: Beamform at AoA + 20, no control of NULL
    thetad = detected_aoa + 20;
    wd = steervec(pos, thetad);
    w = wd;
else
    fprintf("Invalid Mode %d", mode);
    assert(0);
end

w = [0; w];

txtdMod = txtd_single * w';
txtdMod = sdr1.applyCalTxArray(txtdMod);
sdr1.send(txtdMod);
clearvars -except sdr1 sdr2 scMin scMax nFFT detected_aoa txtd_single mode;

%% 5. Now, let the helper measure the received power.

%   p1) Run this block of code. The helper (sdr2) will measure received
%       power.
%   p2) Tell the operator to measure the incoming power at the reference
%       antenna. Do not run this block of code.
%   p3) Measure the input power into the FieldFox. Do not run this block of
%       code.

nread = nFFT;
nskip = nread * 3;
ntimes = 100;

rxtd = sdr2.recv(nread, nskip, ntimes, 1);
rxtd = sdr2.applyCalRxArray(rxtd);

rxtd_accum = zeros(nFFT, 1); % Look at boresight
for rxChId = 2:sdr2.nch
    for itimes = 1:ntimes
        rxtd_accum = rxtd_accum + rxtd(:, itimes, rxChId);
    end
end
rxfd = fftshift(fft(rxtd_accum));
a = 0;
for scIndex = scMin:scMax
    if scIndex == 0
        continue;
    end
    a = a + abs(rxfd(nFFT/2 + 1 + scIndex));
end
a = mag2db(abs(a));
fprintf("Mode %d: Measured power is %2.2f dB\n", mode, a);

% Clear workspace variables
clearvars -except sdr1 sdr2 nFFT scMin scMax detected_aoa txtd_single mode;

%% 6. Finally, Make the whole experiment quiet. We are done.

txtd = zeros(nFFT, sdr1.nch);
sdr1.send(txtd);
sdr2.send(txtd);
pause(0.2);
sdr1.recv(nFFT, nFFT*3, 10, 1);
sdr2.recv(nFFT, nFFT*3, 10, 1);

clearvars -except sdr1 sdr2