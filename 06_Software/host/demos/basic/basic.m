%% Add the folder containing +piradio to the MATLAB path.
clear;
addpath('../../');

% ip = "192.168.137.43";	% IP Address
% isDebug = false;		% print debug messages
% sdr1 = piradio.sdr.FullyDigital('ip', ip, 'isDebug', isDebug, 'figNum', 100, 'name', 'navy-001', 'fc', 3.56988e9);
% sdr1.fpga.configure('../../config/rfsoc_n48.cfg');

ip = "192.168.137.44";	% IP Address
isDebug = false;		% print debug messages
sdr2 = piradio.sdr.FullyDigital('ip', ip, 'isDebug', isDebug, 'figNum', 200, 'name', 'navy-002', 'fc', 3.56988e9);
sdr2.fpga.configure('../../config/rfsoc_n48.cfg');


%% Simple TX and RX test with a single channel

 % txChId = 1 refers to the TX channel that's used to self-cal the RX array
 % txChId = 2..8 refer to the regular TX channels
 % rxChId = 1 refers to the RX channel that's used to self-cal the TX array
 % rxChId = 2..8 refer to the regular RX channels

sdr2.set_mode('gnb');
txChId = 1;

clc;
nFFT = 1024;	% number of FFT points
txPower = 0000; % Do not exceed 30000
scMin = 1;
scMax = 1;
constellation = [1+1j 1-1j -1+1j -1-1j];

txtd = zeros(nFFT, sdr2.nch);       
txfd = zeros(nFFT, sdr2.nch);

for scIndex = scMin:scMax
    txfd(nFFT/2 + 1 + scIndex, txChId) = constellation(randi(4));
end

txfd(:, txChId) = fftshift(txfd(:, txChId));
txtd(:, txChId) = ifft(txfd(:, txChId));
txtd(:, txChId) = txPower*txtd(:, txChId)./max(abs(txtd(:, txChId)));

        
% Send the data to the DACs
sdr2.send(txtd);

%% Receive data
nskip = 1024*3;	% skip ADC data
nbatch = 10;	% num of batches
for i=1:1
    rxtd = sdr1.recv(nFFT, nskip, nbatch, 1);
end
