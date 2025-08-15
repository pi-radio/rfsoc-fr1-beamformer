%% Simulation 1: Ideal beamforming for a single tone
%clear;
freq = 3.25e9;
c = physconst('LightSpeed');
lam = c/freq;
nch = 7;
pos = (0:nch-1)*0.5;
nangles = 1801;
ang = linspace(-90, 90, nangles);
niter = 1000;

% Direction of the desired Beam, in degrees
thetad = 25;
wd = steervec(pos, thetad);

% Direction of the desired NULL, in degrees
thetan = 0;
wn = steervec(pos, thetan);

rn = wn'*wd/(wn'*wn);

% Sidelobe canceler - remove the response at null direction
w = wd-wn*rn;
%w = wd;

af = zeros(1, nangles);
for iter = 1:niter

    % The ideal steering vector
    wsteer = w;

    % Calculate the per-channel amplitude error
    db_range = 0.1;
    a = db2mag(-db_range/2);
    b = db2mag(db_range/2);
    w_amp_errors = (b-a).*rand(nch, 1) + a;

    % Calculate the per-channel phase error
    angle_range = deg2rad(0.5);
    a = (-angle_range/2);
    b = (angle_range/2);
    w_angle_errors = (b-a).*rand(nch, 1) + a;
    rad2deg(w_angle_errors);

    wsteer = wsteer .* w_amp_errors;
    wsteer = wsteer .* exp(1j*w_angle_errors);

    wsteer = wsteer / norm(wsteer);

    b = arrayfactor(pos,ang, wsteer);
    for iangle=1:nangles
        af(1, iangle) = max(af(1, iangle), b(1, iangle));
    end    
    
end

af = af / max(abs(af));

figure(1);
h = plot(ang,mag2db(abs(af))); hold on;
set(h,'LineWidth',3)
%plot([thetan thetan],[-100 0],'r--','LineWidth',2); hold on;
%plot([thetad thetad],[-100 0],'b--','LineWidth',2); hold on;
xlabel('Angle (deg)')
ylabel('Array pattern (dB)')
ylim([-60 0])
title('Array Factor of Unsteered Uniform Linear Array')
grid on;
