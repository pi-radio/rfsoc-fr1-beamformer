%% CALIBRATIONS

% To perform calibration, first configure the hardware to operate
% at 3.25 GHz. The self-cal requires this frequency.

addpath('../../');
addpath('../../helper');

ip = "192.168.137.43";	% IP Address
isDebug = false;		% print debug messages

sdr0 = piradio.sdr.FullyDigital('ip', ip, 'isDebug', isDebug, ...
    'figNum', 100, 'name', 'lamarr-rev3.1-0001');

sdr0.fpga.configure('../../config/rfsoc_nyquist.cfg');
clear ip isDebug;


%% Calibrate of the RX array

% Pick a reference TX channel

nFFT = 1024;
nread = nFFT;
nskip = 1024*3;	% skip ADC data
ntimes = 50;	% num of batches to read

sdr0.recv(nFFT, nskip, ntimes, 1); % Dummy read

% Generate the TX waveform
scMin = -100;
scMax = 100;
niter =  1;
constellation = [1+1j 1-1j -1+1j -1-1j];

% expType = 1: Make initial measurements of the fractional timing offset
%
% expType = 2: Correct the fractional offsets and see if the residual
% errors are close to 0. Also measure the integer timing offsets. We do not
% expect integer timing offsets with ~2GHz sampling rate. So we just
% measure the integer timing offsets, make sure it's zero, but do not
% present code to correct it (this would be extremely simple to do). Also,
% measure the per-channel phase offset.
%
% expType = 3: Also correct the phase offsets, and make sure that the
% errors are now close to 0.

% How many unique fractional timing offsets are we going to search through?
nto = 101;
figure(3); clf;

pdpStore = zeros(sdr0.nch, 3, niter, ntimes, nFFT);

meanResidualTimingErrors = zeros(sdr0.nch, 1);
meanResidualPhaseErrors = zeros(sdr0.nch, 1);

for expType = 1:3
    expType
    
    maxPos = zeros(sdr0.nch, niter, ntimes);
    maxVal = zeros(sdr0.nch, niter, ntimes);
    intPos = zeros(sdr0.nch, niter, ntimes);
    pk     = zeros(sdr0.nch, niter, ntimes);
        
    for iter = 1:niter
        fprintf('\n');
        txfd = zeros(nFFT, 1);
        txtd = zeros(nFFT, sdr0.nch);
        
        for scIndex = scMin:scMax
            if scIndex ~= 0
                txfd(nFFT/2 + 1 + scIndex, 1) = constellation(randi(4));
            end
        end

        txfd(:,1) = fftshift(txfd(:,1));
        txtd(:,1) = ifft(txfd(:,1));

        m = max(abs(txtd(:,1)));
       
        % Scale and send the signal
        txtd = txtd/m*30000;
        sdr0.send(txtd);
        
        % Receive the signal
        rxtd = sdr0.recv(nread,nskip,ntimes, 1);
        size(rxtd);
        
        for rxIndex=2:sdr0.nch % Ch 1 is used up for self-cal of the TX Array
            fprintf('\n');
            tos = linspace(-0.5, 0.5, nto);
            for ito = 1:nto
                to = tos(ito);
                fprintf('.');
                for itimes=1:ntimes
                    if (expType == 1)
                        rxtdShifted = fracDelay(rxtd(:,itimes,rxIndex), to, nFFT);
                    elseif (expType == 2)
                        rxtdShifted = fracDelay(rxtd(:,itimes,rxIndex), to + sdr0.calRxDelay(rxIndex), nFFT);
                    elseif (expType == 3)
                        rxtdShifted = fracDelay(rxtd(:,itimes,rxIndex), to + sdr0.calRxDelay(rxIndex), nFFT);
                        rxtdShifted = rxtdShifted * exp(1i*sdr0.calRxPhase(rxIndex));
                    end
                    rxfd = fft(rxtdShifted);
                    corrfd = rxfd .* conj(txfd);
                    corrtd = ifft(corrfd);
                    
                    [~, pos] = max(abs(corrtd));
                    val = corrtd(pos);
                    if abs(val) > abs(maxVal(rxIndex, iter, itimes))
                        % We have bound a "better" timing offset
                        maxVal(rxIndex, iter, itimes) = abs(val);
                        maxPos(rxIndex, iter, itimes) = tos(ito);
                        intPos(rxIndex, iter, itimes) = pos;
                        
                        % Measure the phase at the "best" to
                        pk(rxIndex, iter, itimes) = val;
                        pdpStore(rxIndex, expType, iter, itimes, :) = corrtd;
                        
                    end % if abs(val) > ...
                end % itimes
            end % ito
        end % rxIndex        
    end % iter
    
    % Calculate the fractional and integer timing offsets
    cols = 'mrgbcykm'; % Colors for the plots
    %maxPos(1,:,:) = maxPos(1,:,:) - maxPos(1,:,:); % For rxIndex=1, everything should be 0
    figure(3);
    for rxIndex=2:sdr0.nch
        
        % Fractional
        l = maxPos(rxIndex, :, :); % - maxPos(2,:,:); % Ch 2 is the reference RX
        l = reshape(l, 1, []);
        l = (wrapToPi(l*2*pi))/(2*pi);
        if (expType == 1)
            figure(3);
            subplot(7,1,1);
            plot(l, cols(rxIndex));
            title('Pre-Cal: Fractional Timing Offsets');
            xlabel('Iteration (Unsorted)');
            hold on;
            %ylim([-0.5 0.5]);
            c = sum(exp(1j*2*pi*l));
            c = angle(c);
            c = c /(2*pi);
            sdr0.calRxDelay(rxIndex) = (1)*c;
        elseif (expType == 2)
            figure(3);
            subplot(7,1,2);
            plot(l, cols(rxIndex));
            title('Post-Cal: Fractional Timing Offsets')
            xlabel('Iteration (Unsorted)');
            hold on;

            meanResidualTimingErrors(rxIndex) = mean(l);
            %ylim([-0.5 0.5]);
        end
        
        % Integer
        l = intPos(rxIndex, :, :) - intPos(2, :, :); % Ch 2 is the reference RX
        l = reshape(l, 1, []);
        l = sort(l);
        if (expType == 2)
            figure(3);
            subplot(7,8,16+rxIndex);
            plot(l, cols(rxIndex));
            title('Pre-Cal: Integer Timing Off.');
            hold on;
            ylim([-10 10]); grid on;
            medianIndex = length(l) / 2;
            sdr0.calRxDelay(rxIndex) = sdr0.calRxDelay(rxIndex) + l(medianIndex);
        elseif (expType == 3)
            figure(3);
            subplot(7,8,32+rxIndex);
            plot(l, cols(rxIndex));
            title('Post-Cal: Integer Timing Off.');
            hold on;
            ylim([-10 10]); grid on;
        end
        
        % Phase
        lRx = pk(rxIndex, :, :);
        lRx = reshape(lRx, 1, []);
        
        if (expType == 2)
            subplot(7,1,4);
            ph = wrapToPi(angle(lRx)); 
            plot(rad2deg(ph), cols(rxIndex)); hold on;
            %ylim([-pi pi]);
            title('Pre-Cal: LO Phase Offsets (Degree)');
            l = angle(sum(exp(1j*ph)));
            sdr0.calRxPhase(rxIndex) = (-1)*l;
        elseif (expType == 3)
            subplot(7,1,6);
            ph = wrapToPi(angle(lRx));
            plot(rad2deg(ph), cols(rxIndex)); hold on;
            %ylim([-pi pi]);
            title('Post-Cal: LO Phase Offsets (Degree)');

            % Print out the average phase error in degree
            meanResidualPhaseErrors(rxIndex) = mean(rad2deg(ph));
        end
        
    end % rxIndex
end % expType

% How good was the timing and phase calibration? Here are the
% residual errors printed out.
meanResidualTimingErrors
meanResidualPhaseErrors

% Let's flatten the ADCs for a given reference DAC

clearvars -except sdr0
clc;
nFFT = 1024;	% number of FFT points
txPower = 30000; % Do not exceed 30000
scMin = -100;
scMax = 100;
constellation = [1+1j 1-1j -1+1j -1-1j];

sdr0.calNFFT = nFFT;
sdr0.calSCMin = scMin;
sdr0.calSCMax = scMax;

txfd_single = zeros(nFFT, 1);

for scIndex = scMin:scMax
    if scIndex == 0
        continue;
    end
    txfd_single(nFFT/2 + 1 + scIndex) = constellation(randi(4));
end
txfd_single = fftshift(txfd_single); % In MATLAB order

txChId = 1; % This is the reference TX Channel to calibrate the RX Array

txtd = zeros(nFFT, sdr0.nch);       
txtd(:, txChId) = ifft(txfd_single);
txtd(:, txChId) = txPower*txtd(:, txChId)./max(abs(txtd(:, txChId)));
sdr0.send(txtd);
        
nskip = 1024*3;	% skip ADC data
nbatch = 500;	% num of batches
nFFT = 1024;

sdr0.calRxGains = zeros(sdr0.nch, nFFT);

for expType = 4:5

    expType
    rxtd = sdr0.recv(nFFT, nskip, nbatch, 1);

    for rxChId = 2:8

        fprintf('.');
        figure(3); subplot(7,8,48+rxChId);
    
        rxfd = zeros(nFFT, 1);
        for ibatch = 1:nbatch
            rxtd_tmp = squeeze(rxtd(:, ibatch, rxChId));
            rxfd = rxfd + fft(rxtd_tmp);
        end

        if (expType == 5)
            % Apply the Corrections
            rxfd = rxfd .* squeeze(sdr0.calRxGains(rxChId, :))';
        end

        txfd_single = fftshift(txfd_single); % Human
        rxfd = fftshift(rxfd); % Human

        h = zeros(nFFT, 1);
        for scIndex = scMin:scMax
            h(nFFT/2 + 1 + scIndex) = rxfd(nFFT/2 + 1 + scIndex) ./  txfd_single(nFFT/2 + 1 + scIndex);
        end

        txfd_single = fftshift(txfd_single); % MATLAB

        plot(mag2db(abs(h))); hold on;
        title('Gain Cal (Before Blue, After Red)');
        ylim([125 140]); grid on;
        
        if (expType == 4)
            for scIndex = scMin:scMax
                sdr0.calRxGains(rxChId, nFFT/2 + 1 + scIndex) = 1/abs(h(nFFT/2 + 1 + scIndex));
            end
            sdr0.calRxGains(rxChId, :) = fftshift(sdr0.calRxGains(rxChId, :));

            if (rxChId == 8)
                % Scale
                sdr0.calRxGains = sdr0.calRxGains .* max(abs(h));
            end
        end
    end % rxChId
end % expType


% Stop Transmitting and do a Dummy read
txtd = zeros(nFFT, sdr0.nch);
sdr0.send(txtd);
pause(0.1);
sdr0.recv(nFFT,nskip,nbatch, 1);

clearvars -except sdr0
fprintf('\nRX Array Calibration Done!\n');

%% Calibrate of the TX array
% This script calibrates the TX-side timing and phase offsets. The TX under
% calibration is sdr0, and the reference RX is sdr0.

% Configure the RX number of samples, etc
nFFT = 1024;
nread = nFFT; % read ADC data for 256 cc (4 samples per cc)
nskip = nFFT*5;   % skip ADC data for this many cc
ntimes = 50;    % Number of batches to receive
% Generate the TX waveform
scMin = -100;
scMax = 100;
niter =  1;
constellation = [1+1j 1-1j -1+1j -1-1j];

% expType = 1: Make initial measurements of the fractional timing offset
%
% expType = 2: Correct the fractional offsets and see if the residual
% errors are close to 0. Also measure the integer timing offsets. We do not
% expect integer timing offsets with ~1GHz sampling rate. Also,
% measure the per-channel phase offset.
%
% expType = 3: Also correct the phase offsets, and make sure that the
% errors are now close to 0.

% How many unique fractional timing offsets are we going to search through?
nto = 101; clc;
tos = linspace(-0.5, 0.5, nto);
figure(3); clf;
refRxIndex = 1;
refTxIndex = 2;

txfd = zeros(nFFT, 1);
txtd = zeros(nFFT, sdr0.nch);

for scIndex = scMin:scMax
    if (scIndex == 0)
        continue;
    end
    txfd(scIndex + nFFT/2 + 1) = constellation(randi(4)); % Human order
end
txfd = fftshift(txfd); % Machine order
txtdSingle = ifft(txfd);

m = max(abs(txtdSingle));
txtdSingle = txtdSingle ./m*30000;

maxFrac = zeros(sdr0.nch, niter, ntimes);
maxVal = zeros(sdr0.nch, niter, ntimes);
intPos = zeros(sdr0.nch, niter, ntimes);
pk     = zeros(sdr0.nch, niter, ntimes);
iter = 1;
cols = 'mrgbcykr'; % Colors for the plots

sdr0.calTxDelay = zeros(1, sdr0.nch);
sdr0.calTxPhase = zeros(1, sdr0.nch);
pdpStore = zeros(sdr0.nch, 3, niter, ntimes, nFFT);

meanResidualTimingErrors = zeros(sdr0.nch, 1);
meanResidualPhaseErrors = zeros(sdr0.nch, 1);


for expType = 1:3
    fprintf('\n');
    maxFrac = zeros(sdr0.nch, niter, ntimes);
    maxVal = zeros(sdr0.nch, niter, ntimes);
    intPos = zeros(sdr0.nch, niter, ntimes);
    pk     = zeros(sdr0.nch, niter, ntimes);

    expType
    
    for txIndex = 2:sdr0.nch
        fprintf('\n');
        txtd = zeros(nFFT, sdr0.nch);
        txtd(:, txIndex) = txtdSingle;

        if ((expType == 1) || (expType == 2))
            txtd(:,txIndex) = fracDelay(txtdSingle, sdr0.calTxDelay(txIndex), nFFT);
        elseif (expType == 3)
            txtd(:,txIndex) = exp(1j*sdr0.calTxPhase(txIndex)) * fracDelay(txtdSingle, sdr0.calTxDelay(txIndex), nFFT);
        end

        sdr0.send(txtd);
        pause(0.1);
        rxtd = sdr0.recv(nFFT, nskip, ntimes, 1);

        for itimes = 1:ntimes
            fprintf('.');
            for ito = 1:nto
                to = tos(ito);
                rxtdShifted = fracDelay(rxtd(:,itimes,refRxIndex), to, nFFT);

                rxfd = fft(rxtdShifted);
                corrfd = zeros(nFFT, sdr0.nch);
                corrtd = zeros(nFFT, sdr0.nch);
                
                corrfd(:,txIndex) = conj(txfd) .* (rxfd);
                corrtd(:,txIndex) = ifft(corrfd(:,txIndex));
                
                [~, pos] = max(abs(corrtd(:,txIndex)));
                val = corrtd(pos, txIndex);
                if abs(val) >= abs(maxVal(txIndex, iter, itimes))
                    % We have bound a "better" timing offset
                    maxVal(txIndex, iter, itimes) = abs(val);
                    maxFrac(txIndex, iter, itimes) = tos(ito);
                    intPos(txIndex, iter, itimes) = pos;

                    pdpStore(txIndex, expType, iter, itimes, :) = corrtd(:,txIndex);
                    
                    % Save the complex max corr value, so that we can use
                    % its phase later.
                    pk(txIndex, iter, itimes) = val;

                end % if abs(val) > ...

            end % ito
        end % itimes

        % Fractional
        l = maxFrac(txIndex, :, :);
        l = reshape(l, 1, []);

        if expType == 1           
            figure(3);
            subplot(7,1,1);
            plot(l, cols(txIndex));
            title('Pre-Cal: Fractional Timing Offsets');
            xlabel('Iteration (Unsorted)');
            hold on;
            %ylim([-1 1]);
            c = sum(exp(1j*2*pi*l));
            c = angle(c);
            c = c /(2*pi);
            sdr0.calTxDelay(txIndex) = c;
        elseif expType == 2
            figure(3);
            subplot(7,1,2);
            plot(l, cols(txIndex)); grid on;
            title('Post-Cal: Fractional Timing Offsets')
            xlabel('Iteration (Unsorted)');
            hold on;
            %ylim([-1 1]);

            meanResidualTimingErrors(txIndex) = mean(l);
        end

        % Integer
        l = intPos(txIndex, :, :) - intPos(refTxIndex, :, :); % 2 is the reference TX index
        l = reshape(l, 1, []);
        l = sort(l);
        if (expType == 2)
            figure(3);
            subplot(7,8,16+txIndex);
            plot(l, cols(txIndex)); grid on;
            title('Pre-Cal: Integer Timing Offsets');
            hold on;
            medianIndex = length(l)/2;
            sdr0.calTxDelay(txIndex) = sdr0.calTxDelay(txIndex) + l(medianIndex);
        elseif expType == 3
            figure(3);
            subplot(7,8,32+txIndex);
            plot(l, cols(txIndex)); grid on;
            title('Post-Cal: Integer Timing Offsets');
            hold on;
        end

        % Phase
        %lRef = pk(2, :, :); % 2 is the reference TX index
        %lRef = reshape(lRef, 1, []);
        lTx = pk(txIndex, :, :);
        lTx = reshape(lTx, 1, []);
        
        if (expType == 2)
            subplot(7,1,4);
            ph = wrapToPi(angle(lTx)); % - angle(lRef));
            plot(rad2deg(ph), cols(txIndex)); hold on;
            %ylim([-180 180]);
            title('Pre-Cal: LO Phase Offsets (Degree)');
            l = angle(sum(exp(1j*ph)));
            sdr0.calTxPhase(txIndex) = (-1)*l;
        elseif (expType == 3)            
            subplot(7,1,6);
            ph = wrapToPi(angle(lTx)); % - angle(lRef));
            plot(rad2deg(ph), cols(txIndex)); hold on;
            %ylim([-180 180]);
            title('Post-Cal: LO Phase Offsets (Degree)');
            
            % Print the mean post-cal per-channel phase error
            meanResidualPhaseErrors(txIndex) = mean(rad2deg(ph)); 
        end
    
    end % txIndex
end % expType

meanResidualTimingErrors
meanResidualPhaseErrors

txtd = zeros(nFFT, sdr0.nch);
sdr0.send(txtd);
pause(1);
sdr0.recv(nread,nskip,ntimes, 1);

% Clear workspace variables
clear constellation expType iter nFFT niter rxtd scIndex;
clear scMin scMax txfd txIndex txtd nread nskip nsamp ntimes;
clear ans corrfd corrtd diff iiter itimes ito nto pos rxfd ;
clear to tos cols diffMatrix resTimingErrors toff vec ;
clear intPeakPos intpos c lRef lTx pk ar intPos l ph medianIndex;
clear maxVal maxFrac val m rxtdShifted;
clear refTxIndex refRxIndex sf txtdSingle val;
%clear pdpStore

% Flatten the per-channel TX Gain Curves
nFFT = 1024;
nskip = 1024*3;	% skip ADC data
nbatch = 4000;	% num of batches
scMin = -100;
scMax = 100;
constellation = [1+1j 1-1j -1+1j -1-1j];
txPower = 10000;
sdr0.calNFFT = nFFT;
sdr0.calSCMin = scMin;
sdr0.calSCMax = scMax;

txfd_original = zeros(nFFT, 1);

for scIndex = scMin:scMax
    if scIndex == 0
        continue;
    end
    txfd_original(nFFT/2 + 1 + scIndex) = constellation(randi(4));
end

txfd_original = fftshift(txfd_original); % We are now in MATLAB order
txtd_single_original = ifft(txfd_original); % Used only for scaling

h_accum = zeros(sdr0.nch, nFFT);
figure(3);

sdr0.calTxGains = zeros(sdr0.nch, nFFT);

for expType = 4:5
    expType
    for txChId = 2:8
        fprintf('.');
        if (expType == 4)
            txfd = txfd_original;
        elseif (expType == 5)
            % Apply the TX Cal
            txfd = txfd_original .* squeeze(sdr0.calTxGains(txChId, :))';
        end

        txtd_single = ifft(txfd);
        txtd_single = txPower*txtd_single./max(abs(txtd_single_original));
        txtd = zeros(nFFT, sdr0.nch);
        txtd(:, txChId) = txtd_single;
        sdr0.send(txtd);
        pause(0.1);

        rxtd = sdr0.recv(nFFT, nskip, nbatch, 1);
        rxfd = zeros(nFFT, 1);

        figure(3); subplot(7,8,48+txChId);
    
        for ibatch = 1:nbatch
            rxtd_tmp = squeeze(rxtd(:, ibatch, 1));
            rxfd = rxfd + fft(rxtd_tmp);
        end
    
        h = rxfd ./ txfd_original;
        h = fftshift(h); % MATLAB to Human
        plot(mag2db(abs(h(nFFT/2 + 1 + scMin : nFFT/2 + 1 + scMax)))); hold on;
        title('TX Gain Curve (Before: Blue; After: Red)');
        ylim([130 150]);
        grid on;

        if (expType == 4)
            m = 0;
            for scIndex = scMin:scMax
                if scIndex == 0
                    continue;
                end
                % h is still in Human order
                m = max(m, abs(h(nFFT/2 + 1 + scIndex)));
                sdr0.calTxGains(txChId, nFFT/2 + 1 + scIndex) = 1/abs(h(nFFT/2 + 1 + scIndex));
            end
    
            sdr0.calTxGains(txChId, :) = fftshift(sdr0.calTxGains(txChId, :));

            if (txChId == 8)
                % Do the scaling here
                sdr0.calTxGains = sdr0.calTxGains * m;
            end
        end % expType == 1

    end % txChId
    
end % expType

txtd = txtd*0;
sdr0.send(txtd);
sdr0.recv(nFFT, nskip, nbatch, 1);

fprintf('\nTX Array Calibration Done!\n');

clearvars -except sdr0

%% Debug by looking at pdpStore
figure(1); clf; clc;
for txIndex = 8:8
    a = pdpStore(txIndex, 1, 1, 1, :);
    b = reshape(a, [1024 1]);
    c = mag2db(abs(b));
    subplot(2, 4, txIndex)
    plot(c); grid on; grid minor;
    [val, pos] = max(c);
    pos
end



