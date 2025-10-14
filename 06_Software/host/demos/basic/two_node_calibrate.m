clc;
addpath('../../');
addpath('../../helper');
isDebug = false;		% print debug messages

sdr1 = piradio.sdr.FullyDigital('ip', "192.168.137.43", ...
    'isDebug', isDebug, 'figNum', 100, 'name', 'sdr1');
%sdr2 = piradio.sdr.FullyDigital('ip', "192.168.137.44", ...
%    'isDebug', isDebug, 'figNum', 200, 'name', 'sdr2');

sdr1.fpga.configure('../../config/rfsoc_nyquist.cfg');
%sdr2.fpga.configure('../../config/rfsoc_nyquist.cfg');

clear isDebug;

% This is a simple test to make sure that all ADCs are working.
% Simply look at Fig. 100 and 200, and make sure that some noise
% is present in the RX frequency-domain graphs.

sdr1.recv(1024, 2048, 10, 1);
%sdr2.recv(1024, 2048, 10, 1);

%% Calibrate both radios
sdr1.calRxArray();
sdr1.calTxArray();
%
sdr2.calRxArray();
sdr2.calTxArray();