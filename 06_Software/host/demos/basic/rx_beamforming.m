% In this demo, we assume that sdr0 is open, and is fully
% calibrated. Look at the calibration demo to make sure this is done. In
% the minimum, the timing and phase offsets need to be calibrated.

% Transmit a wideband signal from a remote source. On the RX, capture
% samples, and apply the calibrations. Then, apply BF vectors for a set of
% AoA values. Plot them out.

nread = 1024;
nFFT = nread;
nskip = nread * 3;
ntimes = 10;
scMin = 50;
scMax = 50;


for iter = 1:100
    pause(0.1)
rxtd = sdr0.recv(nread, nskip, ntimes, 1);
rxtd = sdr0.applyCalRxArray(rxtd);

naoa = 101;
aoas = linspace(-1, 1, naoa);
pArray = zeros(1, naoa);

for iaoa = 1:naoa
    p = 0;
    aoa = aoas(iaoa);
    for itimes = 1:ntimes
        tdbf = zeros(nFFT, 1);
        for rxIndex=1:sdr0.nch
            td = rxtd(:,itimes,rxIndex);
            tdbf = tdbf + td * exp(1j*rxIndex*pi*sin(aoa)); % Apply BF Vec
        end % rxIndex
        fd = fftshift(fft(tdbf));
        p = p + sum(abs(fd( nFFT/2 + 1 + scMin : nFFT/2 + 1 + scMax)));
    end %itimes
    pArray(iaoa) = p;
end % iaoa

% Plot
pArray = pArray / max(pArray);
figure(3); clf;
plot(rad2deg(aoas), mag2db(pArray)); hold off;
xlabel('Angle of Arrival (Deg)');
ylabel('Power (dB)');
grid on; grid minor;
%ylim([-15 0])
end

% Clear workspace variables
clear aoa aoas fd iaoa naoa p pArray refTxIndex td tdbf txtdMod;
clear ans itimes m nFFT nread nskip ntimes rxIndex rxtd;
clear scIndex txfd txtd constellation scMax scMin;
