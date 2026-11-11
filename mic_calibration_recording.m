%% Microphone calibration recording (HATS reference)
% Calibrates the facilitator mics against the HATS at the listening position.
% Records 30 s of speech from
%   1) Mic11 (Analog ch 11, facilitator X, LEFT)   + HATS ears (L/R)
%   2) Mic12 (Analog ch 12, other facilitator, RIGHT) + HATS ears (L/R)
%
% The HATS is calibrated in dB SPL with the same calibrator data as
% hats_level_calibration.m (levelCalibrator.mat = RMS of the 94.02 dB
% calibrator on each ear). For every mic the script computes
%   MicToSPL_dB = L_HATS (dB SPL, energy mean of both ears) - L_mic (dBFS RMS)
% i.e.  speech level at the listening position [dB SPL] ~ 20*log10(rms(mic)) + MicToSPL_dB
% (valid for the talker/mic geometry used during calibration).
% Background noise is measured once and subtracted (energy) from all levels.
%
% Mic devices / settings are the same as experiment_script_pilot.m.
% HATS input is the same as hats_level_calibration.m (ASIO MADIface USB, ch 5/6).
% Everything is saved to ONE .mat file in 'vicon_recordings':
%   mic_calibration_<yyyyMMdd_HHmmss>.mat
%
% Created 03-11-2026, HATS version 05-11-2026
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
clear; clc;

%% Settings ---------------------------------------------------------------
outputFolder    = 'vicon_recordings';
recDuration_s   = 30;        % seconds per recording
noiseDuration_s = 10;        % background noise measurement (0 = skip)
fs              = 48000;
samplesPerFrame = 960;

% Facilitator mics (as in experiment_script_pilot.m)
micDeviceANA  = 'Analog (11+12) (RME UFX+ USB 3.0)';  % ch1 = Mic11, ch2 = Mic12
micBitDepth   = '16-bit integer';

% HATS (as in hats_level_calibration.m)
hatsDevice    = 'ASIO MADIface USB';
hatsChannels  = [5 6];       % left, right
hatsBitDepth  = '24-bit integer';

% HATS calibrator
Lcal                = 94.02;                  % calibrator level at the HATS ear (dB SPL)
calDur_s            = 10;
useSavedCalibration = true;                   % true = use the RMS values in calibrationFile
calibrationFile     = 'levelCalibrator.mat';  % levelCalibrator = [RMS left, RMS right]

% Recording plan: name, label, Analog channel used (1 = Mic11, 2 = Mic12)
plan = struct( ...
    'Name',       {'Mic11_HATS', 'Mic12_HATS'}, ...
    'Mic',        {'Mic11', 'Mic12'}, ...
    'Desc',       {'Facilitator X (venstre side)', 'Anden facilitator (hoejre side)'}, ...
    'AnalogChan', {1, 2});

%% Prepare -----------------------------------------------------------------
scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir); scriptDir = pwd; end

if ~exist(outputFolder, 'dir'); mkdir(outputFolder); end
sessionID = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
outFile   = uniqueFilename(fullfile(outputFolder, ...
    sprintf('mic_calibration_%s.mat', sessionID)));

nFrames = ceil(recDuration_s * fs / samplesPerFrame);
nSamp   = nFrames * samplesPerFrame;
RecordingDuration = nSamp / fs;

readerHATS = audioDeviceReader('Driver', 'ASIO', 'Device', hatsDevice, ...
    'SampleRate', fs, 'BitDepth', hatsBitDepth, 'SamplesPerFrame', samplesPerFrame, ...
    'ChannelMappingSource', 'Property', 'ChannelMapping', hatsChannels);
readerANA  = audioDeviceReader('Device', micDeviceANA, 'SampleRate', fs, ...
    'NumChannels', 2, 'BitDepth', micBitDepth, 'SamplesPerFrame', samplesPerFrame);
cleanupObj = onCleanup(@() releaseReaders(readerHATS, readerANA));

fprintf('Mic calibration (HATS reference)  |  Session %s\n', sessionID);
fprintf('Data will be saved to %s\n\n', outFile);

%% HATS calibration (dB SPL) ---------------------------------------------
if useSavedCalibration
    calPath = calibrationFile;
    if ~isfile(calPath); calPath = fullfile(scriptDir, calibrationFile); end
    if ~isfile(calPath)
        error('Calibration file not found: %s (set useSavedCalibration = false to measure).', ...
            calibrationFile);
    end
    S = load(calPath);
    if isfield(S, 'Lcal') && abs(S.Lcal - Lcal) > 0.01
        error('%s was measured with a %.2f dB calibrator, but Lcal = %.2f dB.', ...
            calPath, S.Lcal, Lcal);
    end
    levelCalibrator = S.levelCalibrator(:).';          % [left right]
    assert(numel(levelCalibrator) == 2, 'levelCalibrator must be [RMS left, RMS right].');
    fprintf('Loaded HATS calibration (%s, %.2f dB): RMS L %.5f, R %.5f\n', ...
        calPath, Lcal, levelCalibrator);
else
    levelCalibrator = zeros(1, 2);
    earName = {'LEFT', 'RIGHT'};
    for ear = 1:2
        input(sprintf('Mount the calibrator on the %s ear, switch it on, press Enter...', ...
            earName{ear}), 's');
        rec = recordFrames(readerHATS, [], ceil(calDur_s * fs / samplesPerFrame), 1);
        rec = rec(fs+1:end, :);                          % skip first second
        levelCalibrator(ear) = rms(rec(:, ear));
        fprintf('  %s: RMS %.5f (other ear %.1f dB lower)\n', earName{ear}, ...
            levelCalibrator(ear), 20*log10(levelCalibrator(ear) / rms(rec(:, 3-ear))));
    end
    calDate = datetime('now');
    save(calibrationFile, 'levelCalibrator', 'Lcal', 'calDate');
    fprintf('HATS calibration saved to %s\n', calibrationFile);
end
fprintf('  -> full scale (RMS = 1) corresponds to L %.1f / R %.1f dB SPL\n\n', ...
    Lcal - 20*log10(levelCalibrator));
k2 = (10^(Lcal/20) ./ levelCalibrator).^2;             % 1x2: mean square -> (p/20uPa)^2

%% Background noise ---------------------------------------------------------
% HATS at the listening position, mics in place, nobody talking.
% msFloor = mean square per channel [HATS L, HATS R, Mic11, Mic12]
msFloor = zeros(1, 4);
if noiseDuration_s > 0
    input('HATS at the listening position, room quiet, nobody talking. Press Enter...', 's');
    fprintf('Measuring background noise (%.0f s)...\n', noiseDuration_s);
    nNoise = ceil(noiseDuration_s * fs / samplesPerFrame);
    [recH, recM] = recordFrames(readerHATS, readerANA, nNoise, 0);
    msFloor = mean([recH, recM].^2, 1);
    fprintf('  HATS: L %.1f / R %.1f dB SPL  |  Mic11 %.1f / Mic12 %.1f dBFS\n\n', ...
        10*log10(k2 .* msFloor(1:2)), 10*log10(msFloor(3:4) + eps));
end
LfloorHATS_dB = 10*log10(k2 .* msFloor(1:2) + eps);
LfloorMic_dBFS = 10*log10(msFloor(3:4) + eps);

%% Record ----------------------------------------------------------------
Calibration = struct([]);
for k = 1:numel(plan)
    p = plan(k);
    fprintf('--- Recording %d/%d: %s + HATS (%.0f s) ---\n', k, numel(plan), p.Mic, RecordingDuration);
    fprintf('Speaker at %s (%s), HATS at the listening position. Press ENTER to start...\n', ...
        p.Mic, p.Desc);
    input('', 's');

    StartClock = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
    fprintf('RECORDING... speak now\n');
    [recH, recM, MicOverrun] = recordFrames(readerHATS, readerANA, nFrames, 5);
    MicData = single([recH, recM(:, p.AnalogChan)]);   % [HATS L, HATS R, Mic11/Mic12]

    % Quick level check (clipping)
    peak_dBFS = 20*log10(max(abs(MicData), [], 1) + eps);
    rms_dBFS  = 20*log10(sqrt(mean(double(MicData).^2, 1)) + eps);
    if any(peak_dBFS > -0.5); warning('Possible clipping in recording %s.', p.Name); end
    if any(MicOverrun(:)); warning('%d dropped samples in recording %s.', sum(MicOverrun(:)), p.Name); end

    % Noise-corrected levels
    msFl  = msFloor([1 2 2 + p.AnalogChan]);
    ms    = mean(double(MicData).^2, 1);
    msCor = max(ms - msFl, eps);
    snr   = 10*log10(msCor ./ max(msFl, eps));
    LHATS_ear = 10*log10(k2 .* msCor(1:2));            % dB SPL per ear
    LHATS     = 10*log10(mean(k2 .* msCor(1:2)));      % energy mean of both ears
    Lmic_dBFS = 10*log10(msCor(3));
    MicToSPL_dB = LHATS - Lmic_dBFS;

    fprintf('  Done. HATS: L %.1f / R %.1f dB SPL -> %.1f dB SPL  |  %s: %.1f dBFS\n', ...
        LHATS_ear, LHATS, p.Mic, Lmic_dBFS);
    fprintf('  Peak [HATS L / R / %s]: %.1f / %.1f / %.1f dBFS\n', p.Mic, peak_dBFS);
    fprintf('  S/N [HATS L / R / %s]: %.1f / %.1f / %.1f dB\n', p.Mic, snr);
    fprintf('  ==> %s: dB SPL at listening position = dBFS + %.1f dB\n', p.Mic, MicToSPL_dB);
    if noiseDuration_s > 0 && any(snr < 10)
        warning('S/N below 10 dB in recording %s - level estimate may be unreliable.', p.Name);
    end

    Calibration(k).Name          = p.Name;
    Calibration(k).MicNames      = {'HATS_L', 'HATS_R', p.Mic};
    Calibration(k).MicDesc       = {'HATS venstre oere (lytteposition)', ...
                                    'HATS hoejre oere (lytteposition)', p.Desc};
    Calibration(k).MicData       = MicData;      % col 1/2 = HATS L/R, col 3 = Mic11/Mic12
    Calibration(k).MicOverrun    = MicOverrun;   % dropped samples [HATS ANA] per frame
    Calibration(k).StartClock    = StartClock;
    Calibration(k).Peak_dBFS     = peak_dBFS;
    Calibration(k).RMS_dBFS      = rms_dBFS;     % not noise-corrected
    Calibration(k).SNR_dB        = snr;
    Calibration(k).LHATS_ear_dB  = LHATS_ear;    % noise-corrected, dB SPL [L R]
    Calibration(k).LHATS_dB      = LHATS;        % energy mean of both ears, dB SPL
    Calibration(k).Lmic_dBFS     = Lmic_dBFS;    % noise-corrected, dBFS RMS
    Calibration(k).MicToSPL_dB   = MicToSPL_dB;  % dB SPL (HATS) = mic dBFS + MicToSPL_dB

    % Save after every recording so nothing is lost if the second one fails
    save(outFile, 'Calibration', 'sessionID', 'fs', 'samplesPerFrame', ...
        'RecordingDuration', 'micDeviceANA', 'micBitDepth', ...
        'hatsDevice', 'hatsChannels', 'hatsBitDepth', ...
        'Lcal', 'levelCalibrator', 'msFloor', 'LfloorHATS_dB', 'LfloorMic_dBFS');
    fprintf('  Saved to %s\n\n', outFile);
end

fprintf('Calibration finished. All data in %s\n', outFile);
for k = 1:numel(Calibration)
    fprintf('  %-6s: dB SPL = dBFS + %.1f dB  (HATS %.1f dB SPL)\n', ...
        Calibration(k).MicNames{3}, Calibration(k).MicToSPL_dB, Calibration(k).LHATS_dB);
end

%% Local functions -----------------------------------------------------------
function [recH, recM, overrun] = recordFrames(readerH, readerM, nFrames, progressEvery_s)
% Records nFrames frames from the HATS reader and (optionally) the mic reader.
% Both streams are started fresh and released afterwards.
% progressEvery_s = 0 -> no progress output.
spf = readerH.SamplesPerFrame;
fs  = readerH.SampleRate;
hasMic = ~isempty(readerM);
recH = zeros(nFrames*spf, numel(readerH.ChannelMapping));
recM = zeros(nFrames*spf, 2 * hasMic);
overrun = zeros(nFrames, 2);
setup(readerH);
if hasMic; setup(readerM); end
lastSec = -1;
for seg = 1:nFrames
    idx = (seg-1)*spf+1 : seg*spf;
    [recH(idx, :), overrun(seg, 1)] = readerH();
    if hasMic
        [fA, overrun(seg, 2)] = readerM();
        recM(idx, :) = fA(:, 1:2);
    end
    sec = floor(seg * spf / fs);
    if progressEvery_s > 0 && sec ~= lastSec && mod(sec, progressEvery_s) == 0
        fprintf('  %2d / %.0f s\n', sec, nFrames * spf / fs);
        lastSec = sec;
    end
end
release(readerH);
if hasMic; release(readerM); end
end

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
