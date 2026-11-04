%% Microphone calibration recording
% Records 30 s of speech from
%   1) Mic11 (Analog ch 11, facilitator X, LEFT)  + AN5 (MADI ch 1, reference)
%   2) Mic12 (Analog ch 12, other facilitator, RIGHT) + AN5 (MADI ch 1, reference)
% Same devices / settings as experiment_script_pilot.m.
% Everything is saved to ONE .mat file in 'vicon_recordings':
%   mic_calibration_<yyyyMMdd_HHmmss>.mat
%
% Created 03-11-2026
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
clear; clc;

%% Settings ---------------------------------------------------------------
outputFolder    = 'vicon_recordings';
recDuration_s   = 30;        % seconds per recording
fs              = 48000;
samplesPerFrame = 960;

micDeviceMADI = 'MADI (1-8) (RME UFX+ USB 3.0)';      % ch1 = AN5
micDeviceANA  = 'Analog (11+12) (RME UFX+ USB 3.0)';  % ch1 = Mic11, ch2 = Mic12
micBitDepth   = '16-bit integer';

% Recording plan: name, label, Analog channel used (1 = Mic11, 2 = Mic12)
plan = struct( ...
    'Name',       {'Mic11_AN5', 'Mic12_AN5'}, ...
    'Mic',        {'Mic11', 'Mic12'}, ...
    'Desc',       {'Facilitator X (venstre side)', 'Anden facilitator (hoejre side)'}, ...
    'AnalogChan', {1, 2});

%% Prepare -----------------------------------------------------------------
if ~exist(outputFolder, 'dir'); mkdir(outputFolder); end
sessionID = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
outFile   = uniqueFilename(fullfile(outputFolder, ...
    sprintf('mic_calibration_%s.mat', sessionID)));

nFrames = ceil(recDuration_s * fs / samplesPerFrame);
nSamp   = nFrames * samplesPerFrame;
RecordingDuration = nSamp / fs;

readerMADI = audioDeviceReader('Device', micDeviceMADI, 'SampleRate', fs, ...
    'NumChannels', 2, 'BitDepth', micBitDepth, 'SamplesPerFrame', samplesPerFrame);
readerANA  = audioDeviceReader('Device', micDeviceANA,  'SampleRate', fs, ...
    'NumChannels', 2, 'BitDepth', micBitDepth, 'SamplesPerFrame', samplesPerFrame);
cleanupObj = onCleanup(@() releaseReaders(readerMADI, readerANA));

fprintf('Mic calibration  |  Session %s\n', sessionID);
fprintf('Data will be saved to %s\n\n', outFile);

%% Record ----------------------------------------------------------------
Calibration = struct([]);
for k = 1:numel(plan)
    p = plan(k);
    fprintf('--- Recording %d/%d: %s + AN5 (%.0f s) ---\n', k, numel(plan), p.Mic, RecordingDuration);
    fprintf('Speaker at %s (%s). Press ENTER to start...\n', p.Mic, p.Desc);
    input('', 's');

    MicData    = zeros(nSamp, 2, 'single');   % [AN5, Mic11/Mic12]
    MicOverrun = zeros(nFrames, 2);           % dropped samples [MADI ANA] per frame

    setup(readerMADI);
    setup(readerANA);
    StartClock = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
    fprintf('RECORDING... speak now\n');
    lastSec = -1;
    for seg = 1:nFrames
        [fM, oM] = readerMADI();   % ch1 = AN5
        [fA, oA] = readerANA();    % ch1 = Mic11, ch2 = Mic12
        idx = (seg-1)*samplesPerFrame+1 : seg*samplesPerFrame;
        MicData(idx, :)    = single([fM(:,1), fA(:,p.AnalogChan)]);
        MicOverrun(seg, :) = [oM, oA];
        sec = floor(seg * samplesPerFrame / fs);
        if sec ~= lastSec && mod(sec, 5) == 0
            fprintf('  %2d / %.0f s\n', sec, RecordingDuration);
            lastSec = sec;
        end
    end
    release(readerMADI);
    release(readerANA);

    % Quick level check
    peak_dBFS = 20*log10(max(abs(MicData), [], 1) + eps);
    rms_dBFS  = 20*log10(sqrt(mean(MicData.^2, 1)) + eps);
    fprintf('  Done. Peak [AN5 %s]: %.1f / %.1f dBFS  |  RMS: %.1f / %.1f dBFS\n', ...
        p.Mic, peak_dBFS, rms_dBFS);
    if any(peak_dBFS > -0.5); warning('Possible clipping in recording %s.', p.Name); end
    if any(MicOverrun(:)); warning('%d dropped samples in recording %s.', sum(MicOverrun(:)), p.Name); end

    Calibration(k).Name        = p.Name;
    Calibration(k).MicNames    = {'AN5', p.Mic};
    Calibration(k).MicDesc     = {'Referencemikrofon foran deltager', p.Desc};
    Calibration(k).MicData     = MicData;        % col 1 = AN5, col 2 = Mic11/Mic12
    Calibration(k).MicOverrun  = MicOverrun;
    Calibration(k).StartClock  = StartClock;
    Calibration(k).Peak_dBFS   = peak_dBFS;
    Calibration(k).RMS_dBFS    = rms_dBFS;

    % Save after every recording so nothing is lost if the second one fails
    save(outFile, 'Calibration', 'sessionID', 'fs', 'samplesPerFrame', ...
        'RecordingDuration', 'micDeviceMADI', 'micDeviceANA', 'micBitDepth');
    fprintf('  Saved to %s\n\n', outFile);
end

fprintf('Calibration finished. All data in %s\n', outFile);

%% Local functions -----------------------------------------------------------
function f = uniqueFilename(f)
% Append _2, _3, ... if the file already exists (never overwrite)
[d, n, e] = fileparts(f);
k = 2;
while exist(f, 'file')
    f = fullfile(d, sprintf('%s_%d%s', n, k, e));
    k = k + 1;
end
end

function releaseReaders(varargin)
for i = 1:numel(varargin)
    try release(varargin{i}); catch; end
end
end
