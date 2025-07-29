%% CALIBRATIONS

% To perform calibration, first configure the hardware to operate
% at 3.25 GHz. The self-cal requires this frequency.

addpath('../../');
addpath('../../helper');

ip = "192.168.137.50";	% IP Address
isDebug = false;		% print debug messages

sdr0 = piradio.sdr.FullyDigital('ip', ip, 'isDebug', isDebug, ...
    'figNum', 100, 'name', 'lamarr-rev3.1-0001');

sdr0.fpga.configure('../../config/rfsoc_nyquist.cfg');
clear ip isDebug;


%% Calibrate of the RX array

% Pick a reference TX channel
txChId = 1;

nFFT = 1024;
nread = nFFT;
nskip = 1024*3;	% skip ADC data
ntimes = 100;	% num of batches to read


rxtd = sdr0.recv(nFFT, nskip, ntimes, 1);

% Generate the TX waveform
scMin = -400;
scMax = 400;
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
            subplot(6,1,1);
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
            subplot(6,1,2);
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
            subplot(6,8,16+rxIndex);
            plot(l, cols(rxIndex));
            title('Pre-Cal: Integer Timing Off.');
            hold on;
            ylim([-10 10]); grid on;
            medianIndex = length(l) / 2;
            sdr0.calRxDelay(rxIndex) = sdr0.calRxDelay(rxIndex) + l(medianIndex);
        elseif (expType == 3)
            figure(3);
            subplot(6,8,32+rxIndex);
            plot(l, cols(rxIndex));
            title('Post-Cal: Integer Timing Off.');
            hold on;
            ylim([-10 10]); grid on;
        end
        
        % Phase
        lRx = pk(rxIndex, :, :);
        lRx = reshape(lRx, 1, []);
        
        if (expType == 2)
            subplot(6,1,4);
            ph = wrapToPi(angle(lRx)); 
            plot(rad2deg(ph), cols(rxIndex)); hold on;
            %ylim([-pi pi]);
            title('Pre-Cal: LO Phase Offsets (Degree)');
            l = angle(sum(exp(1j*ph)));
            sdr0.calRxPhase(rxIndex) = (-1)*l;
        elseif (expType == 3)
            subplot(6,1,6);
            ph = wrapToPi(angle(lRx));
            plot(rad2deg(ph), cols(rxIndex)); hold on;
            %ylim([-pi pi]);
            title('Post-Cal: LO Phase Offsets (Degree)');

            % Print out the average phase error in degree
            meanResidualPhaseErrors(rxIndex) = mean(rad2deg(ph));
        end
        
    end % rxIndex
end % expType

meanResidualTimingErrors
meanResidualPhaseErrors

txtd = zeros(nFFT, sdr0.nch);
sdr0.send(txtd);
pause(1);
sdr0.recv(nread,nskip,ntimes, 1);

% Clear workspace variables
clear constellation expType iter maxPos maxVal nFFT niter rxtd scIndex;
clear scMin scMax txfd txIndex txtd m nread nskip nsamp ntimes;
clear ans corrfd corrtd diff iiter itimes ito nto pos rxfd rxtdShifted;
clear to tos val cols diffMatrix resTimingErrors toff vec medianIndex;
clear intPeakPos intpos c lRef lTx pk ar intPos l ph lRx rxIndex;
clear pdpStore txChId;


%% Calibrate of the TX array
% This script calibrates the TX-side timing and phase offsets. The TX under
% calibration is sdr0, and the reference RX is sdr0.

% Configure the RX number of samples, etc
nFFT = 1024;
nread = nFFT; % read ADC data for 256 cc (4 samples per cc)
nskip = nFFT*5;   % skip ADC data for this many cc
ntimes = 50;    % Number of batches to receive
% Generate the TX waveform
scMin = -400;
scMax = 400;
niter =  1;
constellation = [1+1j 1-1j -1+1j -1-1j];

% Ignore scaling factors for self-cal
sf = ones(sdr0.nch, 1);

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

sdr0.calTxDelay = zeros(sdr0.nch, 1);
sdr0.calTxPhase = zeros(sdr0.nch, 1);
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
            subplot(6,1,1);
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
            subplot(6,1,2);
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
            subplot(6,8,16+txIndex);
            plot(l, cols(txIndex)); grid on;
            title('Pre-Cal: Integer Timing Offsets');
            hold on;
            medianIndex = length(l)/2;
            sdr0.calTxDelay(txIndex) = sdr0.calTxDelay(txIndex) + l(medianIndex);
        elseif expType == 3
            figure(3);
            subplot(6,8,32+txIndex);
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
            subplot(6,1,4);
            ph = wrapToPi(angle(lTx)); % - angle(lRef));
            plot(rad2deg(ph), cols(txIndex)); hold on;
            %ylim([-180 180]);
            title('Pre-Cal: LO Phase Offsets (Degree)');
            l = angle(sum(exp(1j*ph)));
            sdr0.calTxPhase(txIndex) = (-1)*l;
        elseif (expType == 3)            
            subplot(6,1,6);
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
clear maxVal maxFrac pdpStore val m rxtdShifted;
clear refTxIndex refRxIndex sf txtdSingle val;



%% Stop transmitting and do a dummy read on both nodes
nFFT = 1024;
nread = nFFT;
nskip = nFFT * 3;
ntimes = 100;
txtd = zeros(nFFT, sdr0.nch);
sdr0.send(txtd);
sdr0.recv(nread,nskip,ntimes);

clear nFFT nskip ntimes nread txtd;

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



