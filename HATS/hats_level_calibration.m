%% =========================================================
%  HATS LEVEL CALIBRATION  for experiment_script_pilot.m
%
%  Reads experimentSetup.xlsx and plays every soundscape and distractor the
%  experiment uses, EXACTLY as the experiment plays it:
%    - soundscape : channel 1 of the file, same signal on all soundscapeChannels,
%                   the first RecordingDuration_s seconds (looped if shorter)
%    - distractor : channel 1, max 2 s, on one loudspeaker at a time
%                   (all 6 loudspeakers are measured and energy-averaged)
%  The HATS ears are recorded, the level is computed in dB SPL, and a gain per
%  file is written to the 'Gains' sheet of experimentSetup.xlsx. The experiment
%  script reads that sheet and uses the gain for every file.
%  (A backup copy of the setup file is made before it is changed.
%   Close the workbook in Excel before running, or MATLAB cannot write to it.)
%
%  mode = 'calibrate' : measure with noiseAmp/distractorAmp, write the Gains sheet
%  mode = 'verify'    : measure with the gains in the Gains sheet, report deviation
%
%  Level = energy average over both ears (and over the 6 loudspeakers for
%  distractors), Leq over the played duration, unweighted (Z).
%% =========================================================

clear; clc;

%% << EDIT HERE >> ----------------------------------------------------
mode      = 'verify';               % 'calibrate' or 'verify'
setupFile = 'experimentSetup.xlsx';    % gains are read from / written to its 'Gains' sheet

% Target levels at the HATS ears (dB SPL)  <-- decide these
targetSoundscape_dB = 60;
targetDistractor_dB = 65;
tol_dB              = 1;               % verify: accepted deviation

% Calibrator
Lcal                = 94.02;           % calibrator level at the HATS ear (dB SPL)
calDur_s            = 10;
useSavedCalibration = true;            % true = use the RMS values in calibrationFile
calibrationFile     = 'levelCalibrator.mat';   % levelCalibrator = [RMS left, RMS right]
% Measured 2026-10-20 with the 94.02 dB calibrator on each ear:
%   levelCalibrator = [0.05272117 0.05424081]

% Measurement
soundscapeDur_s = [];                  % [] = RecordingDuration_s from Excel (what the experiment plays)
distractorMax_s = 2.0;                 % experiment plays max 2 s of each distractor
tail_s          = 0.5;                 % silence after each sound (system latency)

% --- MUST be identical to experiment_script_pilot.m ---------------
fs                 = 48000;
samplesPerFrame    = 960;
device             = 'ASIO MADIface USB';
noiseAmp           = 0.20;             % start gain soundscapes ('calibrate')
distractorAmp      = 0.20;             % start gain distractors ('calibrate')
distractorChannels = 30 + [2 4 6 22 20 18];
soundscapeChannels = [2:2:24 25:48];
% --- HATS input ---------------------------------------------------
hatsChannels       = [5 6];            % left, right
%% --------------------------------------------------------------------

scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir); scriptDir = pwd; end
cd(scriptDir);

channelMapping = unique([soundscapeChannels, distractorChannels]);
[~, ssCols]  = ismember(soundscapeChannels, channelMapping);
[~, disCols] = ismember(distractorChannels, channelMapping);
nOut = numel(channelMapping);
nLS  = numel(distractorChannels);

%% ---- Which files does the experiment use? ----
[stim, recDur] = listStimuli(setupFile, scriptDir);
if isempty(soundscapeDur_s); soundscapeDur_s = recDur; end
isSS  = strcmp({stim.Type}, 'Soundscape');
nStim = numel(stim);
fprintf('Experiment uses %d soundscape file(s) and %d distractor file(s).\n', ...
    sum(isSS), sum(~isSS));
missing = ~cellfun(@isfile, {stim.Path});
if any(missing)
    error('Files not found:\n  %s', strjoin({stim(missing).Path}, sprintf('\n  ')));
end

target = targetDistractor_dB * ones(nStim, 1);
target(isSS) = targetSoundscape_dB;

%% ---- Gains used for this measurement ----
amp = distractorAmp * ones(nStim, 1);
amp(isSS) = noiseAmp;
if strcmp(mode, 'verify')
    G = readGains(setupFile);
    for i = 1:nStim
        key = gainKey(stim(i).Type, stim(i).File);
        if ~isKey(G, key)
            error('%s "%s" is not in %s. Run mode = ''calibrate'' first.', ...
                stim(i).Type, stim(i).File, setupFile);
        end
        amp(i) = G(key);
    end
elseif ~strcmp(mode, 'calibrate')
    error('mode must be ''calibrate'' or ''verify''.');
end

%% ---- Estimated duration ----
estMin = (sum(isSS) * (soundscapeDur_s + tail_s) + ...
          sum(~isSS) * nLS * (distractorMax_s + tail_s + 0.5)) / 60;
fprintf('Estimated measurement time: %.0f min (+ calibration).\n', estMin);

%% ---- Audio devices ----
% One full-duplex object: plays and records in the same ASIO callback, so
% playback and recording stay in sync and do not underrun each other.
APR = audioPlayerRecorder('Device', device, 'SampleRate', fs, ...
    'BitDepth', '24-bit integer', ...
    'PlayerChannelMapping', channelMapping, ...
    'RecorderChannelMapping', hatsChannels);

try
    %% ---- 1. Calibrator, one ear at a time ----
    if useSavedCalibration
        if ~isfile(calibrationFile)
            error('Calibration file not found: %s', calibrationFile);
        end
        S = load(calibrationFile);
        if isfield(S, 'Lcal') && abs(S.Lcal - Lcal) > 0.01
            error('%s was measured with a %.2f dB calibrator, but Lcal = %.2f dB.', ...
                calibrationFile, S.Lcal, Lcal);
        end
        levelCalibrator = S.levelCalibrator(:).';          % [left right]
        assert(numel(levelCalibrator) == 2, 'levelCalibrator must be [RMS left, RMS right].');
        fprintf('Loaded calibration (%s, %.2f dB): RMS L %.5f, R %.5f\n', ...
            calibrationFile, Lcal, levelCalibrator);
        fprintf('  -> full scale (RMS = 1) corresponds to L %.1f / R %.1f dB SPL\n', ...
            Lcal - 20*log10(levelCalibrator));
    else
        levelCalibrator = zeros(1, 2);
        earName = {'LEFT', 'RIGHT'};
        for ear = 1:2
            input(sprintf('\nMount the calibrator on the %s ear, switch it on, press Enter...', ...
                earName{ear}), 's');
            rec = playRecord(APR, zeros(calDur_s*fs, nOut), samplesPerFrame);
            rec = rec(fs+1:end, :);                         % skip first second
            levelCalibrator(ear) = rms(rec(:, ear));
            fprintf('  %s: RMS %.5f (other ear %.1f dB lower)\n', earName{ear}, ...
                levelCalibrator(ear), 20*log10(levelCalibrator(ear) / rms(rec(:, 3-ear))));
        end
        calDate = datetime('now');
        save(calibrationFile, 'levelCalibrator', 'Lcal', 'calDate');
    end
    k2 = (10^(Lcal/20) ./ levelCalibrator).^2;             % 1x2: mean square -> (p/20uPa)^2

    input(sprintf('\nRemove the calibrator, HATS at the listening position, room quiet. Press Enter...'), 's');

    %% ---- Background noise ----
    % Measured once and subtracted (energy) from every measurement below.
    rec = playRecord(APR, zeros(10*fs, nOut), samplesPerFrame);
    msFloor = mean(rec.^2, 1);                           % 1x2 mean square per ear
    Lfloor  = 10*log10(k2 .* msFloor);
    fprintf('Background noise: L %.1f / R %.1f dB SPL (subtracted from all levels)\n', Lfloor);

    %% ---- 2. Measure every file ----
    Lear = nan(nStim, 2);          % dB SPL per ear
    Lls  = nan(nStim, nLS);        % distractors: dB SPL per loudspeaker (both ears)
    peak = nan(nStim, 1);          % peak of the file (channel 1, played part)

    for i = 1:nStim
        fprintf('\n[%d/%d] %s: %s  (gain %.4f)\n', i, nStim, stim(i).Type, stim(i).File, amp(i));
        if isSS(i)
            n = round(soundscapeDur_s * fs);
            y = readMono(stim(i).Path, fs, n);
            if numel(y) < n; y = repmat(y, ceil(n/numel(y)), 1); end   % loop, as experiment
            y = y(1:n);
            peak(i) = max(abs(y));
            sig = zeros(n, nOut);
            sig(:, ssCols) = amp(i) * repmat(y, 1, numel(ssCols));
            [ms, snr] = measure(APR, sig, n, tail_s, fs, samplesPerFrame, msFloor);
            Lear(i, :) = 10*log10(k2 .* ms);
        else
            y = readMono(stim(i).Path, fs, []);
            y = y(1:min(end, round(distractorMax_s * fs)));
            peak(i) = max(abs(y));
            n = numel(y);
            msLS = zeros(nLS, 2);
            snrLS = zeros(nLS, 2);
            for ls = 1:nLS
                sig = zeros(n, nOut);
                sig(:, disCols(ls)) = amp(i) * y;
                [msLS(ls, :), snrLS(ls, :)] = measure(APR, sig, n, tail_s, fs, samplesPerFrame, msFloor);
                pause(0.5);
            end
            snr = min(snrLS, [], 1);
            Lear(i, :) = 10*log10(k2 .* mean(msLS, 1));
            Lls(i, :)  = 10*log10(mean(k2 .* msLS, 2)).';
            fprintf('  per loudspeaker: %s dB\n', sprintf('%6.1f', Lls(i, :)));
        end
        fprintf('  L %.1f / R %.1f dB SPL  ->  %.1f dB (target %.1f)   [noise-corrected, S/N L %.1f / R %.1f dB]\n', ...
            Lear(i, :), energyMean(Lear(i, :)), target(i), snr);
        if any(snr < 3)
            warning(['Sound is less than 3 dB above the background noise - the level cannot ' ...
                'be measured reliably. Raise the gain or make the room quieter.']);
        end
    end
catch ME
    release(APR);
    rethrow(ME);
end
release(APR);

%% ---- 3. Results ----
Level = arrayfun(@(i) energyMean(Lear(i, :)), (1:nStim)');
Type  = {stim.Type}';
File  = {stim.File}';
Dev   = Level - target;

if strcmp(mode, 'calibrate')
    Gain = amp .* 10.^((target - Level) / 20);
    clip = Gain .* peak >= 1;
    if any(clip)
        warning('These files would clip with the new gain (lower the target):\n  %s', ...
            strjoin(File(clip), sprintf('\n  ')));
    end
    calDateStr = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'));
    CalibrationDate = repmat({calDateStr}, nStim, 1);
    T = table(Type, File, Gain, Level, target, amp, Lear(:, 1), Lear(:, 2), Gain .* peak, ...
        CalibrationDate, 'VariableNames', {'Type', 'File', 'Gain', 'Level_dB', 'Target_dB', ...
        'GainMeasured', 'Level_L_dB', 'Level_R_dB', 'PeakAfterGain', 'CalibrationDate'});

    % Backup of the setup file, then replace the Gains sheet (all files the
    % experiment uses are measured, so nothing needed is lost) + CalibrationInfo
    backup = sprintf('%s_backup_%s.xlsx', erase(setupFile, '.xlsx'), ...
        char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
    copyfile(setupFile, backup);
    writetable(T, setupFile, 'Sheet', 'Gains', 'WriteMode', 'overwritesheet');
    writecell({'Parameter', 'Value'; 'Date', calDateStr; 'Calibrator_dB', Lcal; ...
        'CalibratorRMS_L', levelCalibrator(1); 'CalibratorRMS_R', levelCalibrator(2); ...
        'BackgroundNoise_L_dB', Lfloor(1); 'BackgroundNoise_R_dB', Lfloor(2); ...
        'TargetSoundscape_dB', targetSoundscape_dB; 'TargetDistractor_dB', targetDistractor_dB; ...
        'SoundscapeDuration_s', soundscapeDur_s; 'DistractorMax_s', distractorMax_s}, ...
        setupFile, 'Sheet', 'CalibrationInfo', 'WriteMode', 'overwritesheet');
    fprintf('\nGains written to the ''Gains'' sheet of %s (backup: %s).\n', setupFile, backup);
    fprintf('Now run with mode = ''verify''.\n');
    disp(T(:, {'Type', 'File', 'Level_dB', 'Target_dB', 'Gain'}));
else
    ok = abs(Dev) <= tol_dB;
    T = table(Type, File, amp, Lear(:, 1), Lear(:, 2), Level, target, Dev, ok, ...
        'VariableNames', {'Type', 'File', 'Gain', 'Level_L_dB', 'Level_R_dB', ...
        'Level_dB', 'Target_dB', 'Deviation_dB', 'WithinTolerance'});
    verifyFile = sprintf('levelVerification_%s.xlsx', ...
        char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
    writetable(T, verifyFile, 'Sheet', 'Verification');
    disp(T(:, {'Type', 'File', 'Level_dB', 'Target_dB', 'Deviation_dB'}));
    if all(ok)
        fprintf('\nAll %d files within +/- %.1f dB. Saved in %s\n', nStim, tol_dB, verifyFile);
    else
        warning('%d file(s) outside +/- %.1f dB - run ''calibrate'' again.', sum(~ok), tol_dB);
    end
end

save(sprintf('levelCalibration_%s_%s.mat', mode, ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))), ...
    'T', 'Lear', 'Lls', 'Lfloor', 'levelCalibrator', 'Lcal', 'stim', 'amp', ...
    'distractorChannels', 'soundscapeChannels', 'soundscapeDur_s', 'distractorMax_s');


%% ================================================================
%  LOCAL FUNCTIONS
%% ================================================================
function [ms, snr] = measure(APR, sig, n, tail_s, fs, spf, msFloor)
% Plays sig (+ silent tail) and returns the mean square per ear over n samples,
% with the background-noise energy subtracted, plus the signal-to-noise ratio (dB).
    if max(abs(sig(:))) >= 1
        error('Output clips (peak %.2f). Lower the gain.', max(abs(sig(:))));
    end
    sig = [sig; zeros(round(tail_s*fs), size(sig, 2))];
    rec = playRecord(APR, sig, spf);
    if max(abs(rec(:))) > 0.99; warning('HATS input close to clipping.'); end
    % Energy of the sound = recorded energy - noise energy over the whole recording
    % (the tail/latency contain noise only, so they are corrected for as well)
    eSig = sum(rec.^2, 1) - msFloor * size(rec, 1);
    ms   = max(eSig, eps) / n;                       % mean square over the sound's length
    snr  = 10*log10(max(ms, eps) ./ msFloor);
end

function rec = playRecord(APR, sig, spf)
% Plays sig frame by frame and records the HATS ears at the same time.
    nFrames = ceil(size(sig, 1) / spf);
    sig(end+1:nFrames*spf, :) = 0;
    rec = zeros(nFrames*spf, numel(APR.RecorderChannelMapping));

    % Lead-in: a few silent frames first. Underruns from the pause before this
    % call (e.g. while a large file was loaded) are reported here and ignored,
    % so only dropouts during the actual sound are counted below.
    for f = 1:5
        APR(zeros(spf, size(sig, 2)));
    end

    nUnder = 0; nOver = 0;
    for f = 1:nFrames
        idx = (f-1)*spf + (1:spf);
        [rec(idx, :), u, o] = APR(sig(idx, :));
        nUnder = nUnder + u;
        nOver  = nOver + o;
    end
    if nUnder > 0 || nOver > 0
        warning('Dropouts: %d underrun / %d overrun samples.', nUnder, nOver);
    end
end

function L = energyMean(Ldb)
    L = 10*log10(mean(10.^(Ldb(:)/10)));
end

function y = readMono(p, fs, n)
% Channel 1 of the file (as the experiment), resampled to fs if needed.
    info = audioinfo(p);
    if isempty(n) || info.SampleRate ~= fs
        y = audioread(p);
    else
        y = audioread(p, [1 min(n, info.TotalSamples)]);
    end
    y = y(:, 1);
    if info.SampleRate ~= fs
        y = resample(y, fs, info.SampleRate);
    end
end

function key = gainKey(type, file)
% Same key as experiment_script_pilot.m: type + file name without folder, lower case.
    type = lower(type);
    if startsWith(type, 'distra'); type = 'distractor'; end
    [~, nm, ext] = fileparts(file);
    key = [type '|' lower([nm ext])];
end

function G = readGains(setupFile)
    if ~ismember('Gains', sheetnames(setupFile))
        error('%s has no ''Gains'' sheet. Run mode = ''calibrate'' first.', setupFile);
    end
    T = readtable(setupFile, 'Sheet', 'Gains', 'TextType', 'char');
    G = containers.Map();
    for i = 1:height(T)
        G(gainKey(T.Type{i}, T.File{i})) = T.Gain(i);
    end
end

function [stim, recDur] = listStimuli(file, baseDir)
% Unique soundscape / distractor files that the experiment will play.
    S = readcell(file, 'Sheet', 'Settings');
    prm = containers.Map();
    for i = 2:size(S, 1)
        if ischar(S{i, 1}) || isstring(S{i, 1}); prm(char(S{i, 1})) = S{i, 2}; end
    end
    recDur   = toNum(getSetting(prm, 'RecordingDuration_s', 50));
    % Mirror the fallback alias logic in loadSetup (experiment script)
    defaultDisDir = fullfile(baseDir, '..', 'HOA SSR database');
    disDir   = resolvePath(toText(getSetting(prm, 'DistractorFolder', ...
                   getSetting(prm, 'AudioFolder', defaultDisDir))), baseDir);
    noiseDir = resolvePath(toText(getSetting(prm, 'BackgroundNoiseFolder', ...
                   getSetting(prm, 'SoundscapeFolder', ...
                   getSetting(prm, 'NoiseFolder', disDir)))), baseDir);

    B = readSheet(file, 'Blocks');
    cond = containers.Map('KeyType', 'double', 'ValueType', 'double');
    for i = 1:numel(B.Block); cond(toNum(B.Block{i})) = toNum(B.Condition{i}); end
    if isfield(B, 'Soundscape') || isfield(B, 'NoiseFile')
        warning(['Blocks sheet has a Soundscape/NoiseFile column - only the Soundscapes ' ...
            'sheet is used here. Check that no block uses RANDOM or a fixed file.']);
    end

    stim = struct('Type', {}, 'File', {}, 'Path', {});
    seen = {};

    sheets = sheetnames(file);
    if ismember('Soundscapes', sheets)
        SC = readSheet(file, 'Soundscapes');
        for i = 1:numel(SC.Block)
            b = toNum(SC.Block{i}); f = toText(SC.File{i});
            if isempty(f) || any(strcmpi(f, {'silence', 'stilhed', 'none'})); continue; end
            if ~isKey(cond, b) || ~ismember(cond(b), [1 3]); continue; end
            [stim, seen] = addStim(stim, seen, 'Soundscape', f, noiseDir);
        end
    end
    if ismember('Distractors', sheets)
        D = readSheet(file, 'Distractors');
        for i = 1:numel(D.Block)
            b = toNum(D.Block{i}); f = toText(D.File{i});
            if isempty(f) || ~isKey(cond, b) || cond(b) ~= 3; continue; end
            [stim, seen] = addStim(stim, seen, 'Distractor', f, disDir);
        end
    end
end

function [stim, seen] = addStim(stim, seen, type, f, folder)
    key = gainKey(type, f);
    if ismember(key, seen); return; end
    seen{end+1} = key;
    stim(end+1) = struct('Type', type, 'File', f, 'Path', findInFolder(f, folder));
end

function T = readSheet(file, sheet)
    C = readcell(file, 'Sheet', sheet);
    hdr = cellfun(@toText, C(1, :), 'UniformOutput', false);
    body = C(2:end, :);
    body = body(~all(cellfun(@(v) isempty(toText(v)), body), 2), :);
    T = struct();
    for j = 1:numel(hdr)
        if ~isempty(hdr{j}); T.(matlab.lang.makeValidName(hdr{j})) = body(:, j); end
    end
end

function p = resolvePath(p, baseDir)
    isAbs = startsWith(p, {'/', '\'}) || ~isempty(regexp(p, '^[A-Za-z]:', 'once'));
    if ~isAbs; p = fullfile(baseDir, p); end
end

function p = findInFolder(filename, baseDir)
% Same search as the experiment: direct, then subfolders (first alphabetical).
    isAbs = startsWith(filename, {'/', '\'}) || ~isempty(regexp(filename, '^[A-Za-z]:', 'once'));
    if isAbs; p = filename; return; end
    p = fullfile(baseDir, filename);
    if isfile(p); return; end
    [~, nm, ext] = fileparts(filename);
    L = dir(fullfile(baseDir, '**', [nm ext]));
    L = L(~[L.isdir]);
    if ~isempty(L)
        paths = sort(fullfile({L.folder}, {L.name}));
        p = paths{1};
    end
end

function s = toText(v)
    if isempty(v) || isa(v, 'missing'); s = ''; return; end
    if isnumeric(v) || islogical(v)
        if isnan(double(v)); s = ''; else; s = num2str(v); end
    else
        s = strtrim(char(v));
    end
end

function v = getSetting(map, key, default)
% Mirror of getSetting in experiment_script_pilot.m: value for key, or default if missing / empty.
    if isKey(map, key) && ~isempty(toText(map(key)))
        v = map(key);
    else
        v = default;
    end
end

function x = toNum(v)
    if iscell(v)
        if isempty(v); x = NaN; return; end
        v = v{1};
    end
    if isempty(v) || isa(v, 'missing')
        x = NaN;
    elseif isnumeric(v) || islogical(v)
        x = double(v);
    else
        x = str2double(strrep(toText(v), ',', '.'));
    end
end