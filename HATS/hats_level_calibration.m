%% =========================================================
%  HATS LEVEL CALIBRATION  for experiment_script_pilot.m
%
%  Reads experimentSetup.xlsx and plays every soundscape and distractor the
%  experiment uses, EXACTLY as the experiment plays it:
%    - soundscape : the ONE fixed soundscapeFile (same as the experiment),
%                   channel 1 on all soundscapeChannels, the first
%                   RecordingDuration_s seconds (looped if shorter)
%    - distractor : every file in the Distractors sheet (condition 3 rows),
%                   channel 1, the WHOLE file, on one loudspeaker at a time.
%                   measureAllLS = true : measured on all 8 distractor
%                   loudspeakers (0, +-45, +-90, +-135, 180 deg) and
%                   energy-averaged -> one gain per file, independent of
%                   where it is placed in the Distractors sheet.
%                   measureAllLS = false: only on the loudspeaker(s) the file
%                   is assigned to in the Distractors sheet (much faster).
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
distractorMax_s = Inf;                 % experiment plays the whole distractor file (Inf)
tail_s          = 0.5;                 % silence after each sound (system latency)
measureAllLS    = true;                % true = every distractor on all 8 loudspeakers (~30 min)
                                       % false = only on its loudspeaker(s) from the Distractors sheet (~5 min)
onlyNewFiles    = false;               % 'calibrate' only: true = measure only files that are not
                                       % yet in the Gains sheet (keeps the existing gains)

% --- MUST be identical to experiment_script_pilot.m ---------------
fs                 = 48000;
samplesPerFrame    = 960;
device             = 'ASIO MADIface USB';
noiseAmp           = 0.20;             % start gain soundscapes ('calibrate')
distractorAmp      = 0.20;             % start gain distractors ('calibrate')
soundscapeFile     = 'Cocktail-Party_Large_Background_C-01_EM32_130dBFS_4OA.wav';
distractorChannels = 30 + (1:24);      % loudspeaker k = device channel 30 + k
lsAngles = [-15 -30 -45 -60 -75 -90 -105 -120 -135 -150 -165 180 ...
            165 150 135 120 105 90 75 60 45 30 15 0];   % angle of loudspeaker 1..24
distractorAngles   = [0 45 -45 90 -90 135 -135 180];    % loudspeakers used for distractors
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
[okAng, measLS] = ismember(distractorAngles, lsAngles);   % loudspeaker numbers to measure on
if ~all(okAng); error('distractorAngles not found in lsAngles.'); end
nLS  = numel(measLS);          % columns of Lls = these loudspeakers
fprintf('Distractor loudspeakers: %s\n', strjoin(arrayfun(@(l) sprintf('LS%d (%d deg)', ...
    l, lsAngles(l)), measLS, 'UniformOutput', false), ', '));

%% ---- Which files does the experiment use? ----
[stim, recDur] = listStimuli(setupFile, scriptDir, soundscapeFile);
if onlyNewFiles && strcmp(mode, 'calibrate')
    Gold = readGains(setupFile);
    isNew = ~cellfun(@(t, f) isKey(Gold, gainKey(t, f)), {stim.Type}, {stim.File});
    fprintf('onlyNewFiles: %d of %d files are not in the Gains sheet yet - only these are measured.\n', ...
        sum(isNew), numel(stim));
    stim = stim(isNew);
    if isempty(stim); fprintf('Nothing to measure.\n'); return; end
end
for i = 1:numel(stim)
    bad = setdiff(stim(i).LS, measLS);
    if ~isempty(bad)
        warning('%s is assigned to loudspeaker(s) %s in the Distractors sheet, which are not in distractorAngles.', ...
            stim(i).File, mat2str(bad));
    end
end
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
disDur = arrayfun(@(s) min(fileDuration(s.Path), distractorMax_s), stim(~isSS));
if measureAllLS
    nPlay = nLS * ones(size(disDur));
else
    nPlay = arrayfun(@(s) numel(s.LS), stim(~isSS));
end
estMin = (sum(isSS) * (soundscapeDur_s + tail_s) + ...
          sum(nPlay(:) .* (disDur(:) + tail_s + 0.6))) / 60;
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
            y = y(1:min(end, round(min(distractorMax_s, 1e6) * fs)));   % whole file (as experiment)
            peak(i) = max(abs(y));
            n = numel(y);
            if measureAllLS
                useLS = measLS;
            else
                useLS = intersect(measLS, stim(i).LS, 'stable');
                if isempty(useLS); useLS = measLS; end   % not assigned -> measure on all
            end
            msLS  = nan(nLS, 2);
            snrLS = nan(nLS, 2);
            for j = find(ismember(measLS, useLS))
                sig = zeros(n, nOut);
                sig(:, disCols(measLS(j))) = amp(i) * y;
                [msLS(j, :), snrLS(j, :)] = measure(APR, sig, n, tail_s, fs, samplesPerFrame, msFloor);
                pause(0.5);
            end
            done = ~isnan(msLS(:, 1));
            snr = min(snrLS(done, :), [], 1);
            Lear(i, :) = 10*log10(k2 .* mean(msLS(done, :), 1));
            Lls(i, :)  = 10*log10(mean(k2 .* msLS, 2)).';
            fprintf('  per loudspeaker (%s): %s dB\n', ...
                strjoin(arrayfun(@(l) sprintf('%d', lsAngles(l)), measLS(done), 'UniformOutput', false), ' / '), ...
                sprintf('%6.1f', Lls(i, done)));
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
    % Keep the old Gains rows of files that were NOT measured now
    % (e.g. onlyNewFiles = true); measured files get their new row.
    if ismember('Gains', sheetnames(setupFile))
        Told = readtable(setupFile, 'Sheet', 'Gains', 'TextType', 'char');
        if ~isempty(Told) && all(ismember(T.Properties.VariableNames, Told.Properties.VariableNames))
            newKeys = cellfun(@gainKey, T.Type, T.File, 'UniformOutput', false);
            oldKeys = cellfun(@gainKey, Told.Type, Told.File, 'UniformOutput', false);
            Told = Told(~ismember(oldKeys, newKeys), T.Properties.VariableNames);
            if isdatetime(Told.CalibrationDate)
                Told.CalibrationDate = cellstr(char(Told.CalibrationDate, 'yyyy-MM-dd HH:mm'));
            elseif isstring(Told.CalibrationDate)
                Told.CalibrationDate = cellstr(Told.CalibrationDate);
            end
            T = [Told; T];
        end
    end
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
    'distractorChannels', 'soundscapeChannels', 'soundscapeDur_s', 'distractorMax_s', ...
    'measLS', 'lsAngles', 'measureAllLS');


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

function d = fileDuration(p)
    info = audioinfo(p);
    d = info.Duration;
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

function [stim, recDur] = listStimuli(file, baseDir, soundscapeFile)
% Unique soundscape / distractor files that the experiment will play:
%   - the one fixed soundscapeFile (played in every recording)
%   - every file in the Distractors sheet that belongs to condition 3
%     (Condition column; an old-style Block column is also understood).
% stim(i).LS = loudspeaker(s) the file is assigned to in the Distractors sheet.
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

    stim = struct('Type', {}, 'File', {}, 'Path', {}, 'LS', {});
    seen = {};
    [stim, seen] = addStim(stim, seen, 'Soundscape', soundscapeFile, noiseDir);

    if ismember('Distractors', sheetnames(file))
        D = readSheet(file, 'Distractors');
        n = numel(D.File);
        isCond3 = false(n, 1);
        if isfield(D, 'Condition')
            for i = 1:n; isCond3(i) = toNum(D.Condition{i}) == 3; end
        elseif isfield(D, 'Block')               % old style: Block -> condition via Blocks sheet
            B = readSheet(file, 'Blocks');
            cond = containers.Map('KeyType', 'double', 'ValueType', 'double');
            for i = 1:numel(B.Block); cond(toNum(B.Block{i})) = toNum(B.Condition{i}); end
            for i = 1:n
                b = toNum(D.Block{i});
                isCond3(i) = isKey(cond, b) && cond(b) == 3;
            end
        else
            error('Distractors sheet needs a Condition (or Block) column.');
        end
        for i = find(isCond3)'
            f = toText(D.File{i});
            if isempty(f); continue; end
            ls = NaN;
            if isfield(D, 'Loudspeaker'); ls = toNum(D.Loudspeaker{i}); end
            [stim, seen] = addStim(stim, seen, 'Distractor', f, disDir, ls);
        end
    end
end

function [stim, seen] = addStim(stim, seen, type, f, folder, ls)
% Adds a file once; if it is listed again, only its loudspeaker is added.
    if nargin < 6; ls = NaN; end
    key = gainKey(type, f);
    k = find(strcmp(seen, key), 1);
    if ~isempty(k)
        if ~isnan(ls); stim(k).LS = unique([stim(k).LS, ls]); end
        return;
    end
    seen{end+1} = key;
    lsList = ls(~isnan(ls));
    stim(end+1) = struct('Type', type, 'File', f, 'Path', findInFolder(f, folder), 'LS', lsList);
end

function T = readSheet(file, sheet)
    C = readcell(file, 'Sheet', sheet);
    C(cellfun(@(v) isa(v, 'missing'), C)) = {''};
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