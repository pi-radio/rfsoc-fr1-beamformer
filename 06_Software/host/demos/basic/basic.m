%% Add the folder containing +piradio to the MATLAB path.
addpath('../../');

% Parameters
ip = "192.168.137.50";	% IP Address
isDebug = false;		% print debug messages

% Create a Fully Digital SDR
sdr0 = piradio.sdr.FullyDigital('ip', ip, 'isDebug', isDebug, ...
    'figNum', 100, 'name', 'v3-revB-0001');

% Configure the RFSoC. Use the file corresponding to the desired frequency
sdr0.fpga.configure('../../config/rfsoc.cfg');

% A channel ID of 10 refers to "all channels".
% Otherwise channels are numbered 1 through 8.

txChId = 8;
rxChId = 8;



 %% Simple TX and RX test with a single channel

txChId = 2;

clc;
nFFT = 1024;	% number of FFT points
txPower = 10000; % Do not exceed 30000
scMin = -100;
scMax = 100;
constellation = [1+1j 1-1j -1+1j -1-1j];

txtd = zeros(nFFT, sdr0.nch);       
txfd = zeros(nFFT, sdr0.nch);

for scIndex = scMin:scMax
    if scIndex == 0
        continue;
    end
    txfd(nFFT/2 + 1 + scIndex, txChId) = constellation(randi(4));
end

txfd(:, txChId) = fftshift(txfd(:, txChId));
txtd(:, txChId) = ifft(txfd(:, txChId));
txtd(:, txChId) = txPower*txtd(:, txChId)./max(abs(txtd(:, txChId)));

        
% Send the data to the DACs
sdr0.send(txtd);

% Receive data
nskip = 1024*3;	% skip ADC data
nbatch = 100;	% num of batches

rxtd = sdr0.recv(nFFT, nskip, nbatch, 1);

%% Channel Sounder

rxtd = sdr0.recv(nFFT, nskip, nbatch);
rxtd = rxtd(:, 1, rxChId);
rxfd = fft(rxtd);
figure(1); clf;

for txChId = 8:8
    corr_fd = txfd(:, txChId) .* conj(rxfd);
    corr_td = ifft(corr_fd);
    
    p = mag2db(abs(corr_td));
    subplot(4,2,txChId)
    plot(p);
    %ylim([60 120]);
    grid on;
    [val, pos] = max(p)
end



