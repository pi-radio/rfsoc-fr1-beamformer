clear; clc;
N = 10;
% Frequencies are in normalized units
FreqVect = 0:0.01:1;
A1 = 100*ones(1, 30);
A3 = 200*ones(1, 30);
A2 = linspace(100, 200, 41);
AmpVect = [A1 A2 A3];
d15 = designfilt("arbmagfir",...
    FilterOrder=N, ...
    Amplitudes=AmpVect, ...
    Frequencies=FreqVect,...
    DesignMethod="freqsamp");

fvtool(d15);