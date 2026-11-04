%% recordReferenceCalibration.m
clear; clc;

%% ---- Settings -------------------------------------------------------
SAMPLE_RATE     = 48000;
CAL_DUR_S       = 10;
Lcal            = 94.03;
outputFile      = 'levelCalibrator.mat';
samplesPerFrame = 960;

% AN 5 = MADI channel 5 on the RME UFX+
% Check TotalMix to confirm which MADI channel AN 5 maps to
recChannel      = 5;        % <-- adjust if needed

%% ---- Audio device ---------------------------------------------------
APR = audioPlayerRecorder( ...
    'Device',                'ASIO MADIface USB', ...
    'SampleRate',            SAMPLE_RATE, ...
    'BitDepth',              '24-bit integer', ...
    'RecorderChannelMapping', recChannel, ...
    'PlayerChannelMapping',  1);           % dummy output channel

%% ---- Record ---------------------------------------------------------
input(sprintf(['Mount the calibrator on the microphone, switch it on.\n' ...
               'Press Enter to start recording (%.0f s) ...'], CAL_DUR_S), 's');

nFrames  = ceil(CAL_DUR_S * SAMPLE_RATE / samplesPerFrame);
silence  = zeros(samplesPerFrame, 1);     % play silence while recording
allData  = zeros(nFrames * samplesPerFrame, 1);

fprintf('Recording');
for f = 1:nFrames
    idx = (f-1)*samplesPerFrame + (1:samplesPerFrame);
    [allData(idx), ~, ~] = APR(silence);
    if mod(f, round(nFrames/10)) == 0; fprintf('.'); end
end
fprintf(' done.\n');
release(APR);

%% ---- Discard first second (device settling) -------------------------
data = allData(SAMPLE_RATE + 1 : end);

%% ---- RMS ------------------------------------------------------------
rmsVal          = rms(data);
levelCalibrator = [rmsVal, rmsVal];      % duplicated for [L R] compatibility
dBFS            = Lcal - 20*log10(rmsVal);

fprintf('\nCalibrator: %.2f dB SPL\n', Lcal);
fprintf('  RMS        = %.8f\n',   rmsVal);
fprintf('  0 dBFS     = %.2f dB SPL\n', dBFS);

%% ---- Save -----------------------------------------------------------
calDate = datetime('now');
save(outputFile, 'levelCalibrator', 'Lcal', 'calDate');

tsFile = sprintf('levelCalibrator_%s.mat', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
copyfile(outputFile, tsFile);

fprintf('\nSaved to %s (and %s).\n', outputFile, tsFile);
fprintf('Use   levelCalibrator = [%.8f  %.8f]   in your calibration script.\n', ...
    levelCalibrator);