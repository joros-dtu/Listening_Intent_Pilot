%% Experimental script with Vicon DataStream SDK
% PhD pilot recording
%
% Updated 11-11-2026 by Josephine Tanyous Rosenqvist
%   - one fixed soundscape (Cocktail party) in ALL recordings, incl. condition 2
%   - distractors only from 0, +-45, +-90, +-135, 180 deg, randomised + balanced
%   - ENTER = start recording + trigger word, BACKSPACE = redo
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% The xperiment is controlled from the Excel workbook
% 'experimentSetup.xlsx'.
%  The participant window only shows the target, trigger word and progress.
%
%  Conditions (one condition per block):
%    1 = Attention failure   : target + interferer facilitator talk live,
%                              + the soundscape
%    2 = Directed attention  : only the target facilitator talks,
%                              + the soundscape
%    3 = Automatic attention : target talks, distractors from the
%                              'Distractors' sheet (file, onset) + the soundscape
%
%  SOUNDSCAPE: ONE fixed file (soundscapeFile below, searched for in
%  BackgroundNoiseFolder) plays in EVERY recording of EVERY condition,
%  including condition 2. The 'Soundscapes' sheet and the Soundscape /
%  NoiseFile column of the Blocks sheet are no longer used.
%
%  DISTRACTORS are controlled from the 'Distractors' sheet
%  (Condition | Target | Recording | File | Loudspeaker | Onset_s; the extra
%  columns Talker / Angle_deg are for information only). File is relative to
%  DistractorFolder, e.g. mark\recording_....wav. Each file is played in
%  full (any length), cut only at the end of the recording.
%  Loudspeakers: only the 8 positions in distractorAngles below are allowed
%  (0, +-45, +-90, +-135, 180 deg = LS 24, 21, 3, 18, 6, 15, 9, 12).
%  Before the session the script checks that only these loudspeakers are
%  used, that each is used equally often, that no loudspeaker is used twice
%  in one recording and that no two distractors overlap in time.
%  The full playlist is written to the results file BEFORE the first
%  recording, and every sound that is played is logged with its file name,
%  loudspeaker, angle and clock time.
%
%  Distractors rows are keyed by Condition + Target, so they follow the
%  condition when you reorder the Blocks sheet. (An old-style Block column
%  still works if Condition/Target are missing.)
%
%  STORIES: 24 stories (= half of all recordings), always in the same order
%  regardless of condition: block b, recording r -> story mod((b-1)*8+r-1, 24)+1.
%  Physically, each facilitator has their own three coloured piles:
%    yellow pile = stories 1-8, pink pile = 9-16, blue pile = 17-24.
%  Blocks 1+4 = yellow, 2+5 = pink, 3+6 = blue. In condition 1 the interferer
%  reads the previous colour from their own piles (yellow -> blue), i.e. story n-8.
%
%  HEAD REFERENCE (once per session, before block 1):
%    The participant window shows "TRYK ENTER FOR REFERENCE". The participant
%    sits upright and looks straight ahead; pressing Enter averages the head
%    pose (TobiiGlasses segment) over refDuration_s. If the glasses are
%    occluded or the head moves too much, the screen says so -> press Enter
%    again. The reference is saved to headref_<...>.mat and into every
%    recording file as HeadReference (p0, q0, R0, ...). Use headRelative.m
%    afterwards to express head position/direction and gaze relative to it.
%
%  KEYS (participant window):
%    ENTER     = start a recording (cue screen) AND register the trigger
%                word (during a recording)
%    BACKSPACE = redo the previous recording (cue screen)
%    1-7       = questionnaire answers (unchanged)
%    Because ENTER is used both for the trigger word and for starting,
%    key presses are ignored for keyLockout_s after every screen change, so
%    a late trigger press can never start the next recording by accident.
%
%  Flow per recording:
%    cue screen -> participant presses ENTER (start recording)
%    -> Vicon streaming + audio playback start together
%    -> recording lasts RecordingDuration_s (Settings sheet)
%    -> Vicon data saved to its own .mat file
%       (GLOBAL head pose + eye tracker data, NaN where occluded)
%    -> end tone (same 1 kHz tone as the start tone) signals the end
%
%  REDO: on the cue screen, pressing BACKSPACE asks to redo the PREVIOUS recording
%    (red screen: "Tag seneste optagelse om - Er du sikker?").
%    ENTER = no (back to the cue screen), BACKSPACE = yes. The cue screen of the
%    previous recording is then shown, ENTER starts it, and its .mat file,
%    its row in Resultater and its rows in Lydlog are OVERWRITTEN.
%    Afterwards the experiment continues where it was.
%
%  GAZE CHECK: if more than gazeMissingMax (default half) of the frames of a
%    recording have no gaze data, a red screen asks "Advarsel: gaze data er
%    utilstrækkelig. Tag seneste optagelse om?" right after the recording.
%    ENTER = no (continue), BACKSPACE = yes (the same recording is redone and overwritten).
%
% To run a new participant, write the name in
%  Settings > ParticipantName (e.g. P05), SAVE the workbook, then press Run.
%
%% Files & hardware ---------------------------
setupFile    = 'experimentSetup.xlsx';
outputFolder = 'vicon_recordings';

% Quick-test override of the recording length in seconds.
% [] = use RecordingDuration_s from the Settings sheet (normal use).
durationOverride_s = [];

% Post-experiment questionnaire (SEVQuest, Danish, keys 1-7) after the
% last recording. Answers go to the sheet 'Spoergeskema' in the results file.
doQuestionnaire = true;

% Participant window (tablet)
cueMonitor    = 'rightmost';  % 'rightmost' / 'leftmost' screen in the Windows arrangement,
% or a MATLAB screen number (listed in the Command Window
% at start - NOT the same as the Windows display number)

cueFullscreen = true;   % false = small 480 x 700 window as before
cueTextSize   = 1.0;    % extra size factor for ALL text in the participant window
                        % (1.0 = new default; e.g. 1.2 = 20 % bigger, 0.9 = smaller)

% Vicon subject / segment (Tobii glasses)
SubjectName = System.String('P3');
SegmentName = System.String('TobiiGlassesP3');

% Gaze data check: after every recording, if more than this fraction of
% the frames has no gaze data (NaN or 0 in EyeTrackerGlobalGazeVector or
% EyeTrackerGlobalPosition), the participant window shows a red warning
% "Advarsel: gaze data er utilstrækkelig. Tag seneste optagelse om?"
% (ENTER = nej, BACKSPACE = ja -> the recording is redone and overwritten).
% 0.5 = more than half missing (e.g. > 1250 of 2500 frames in a 50 s recording).
gazeMissingMax = 0.5;     % [] or Inf = no gaze check

% Head reference
% Which direction of the TobiiGlassesP3 segment points out of the nose,
% in the segment's own coordinates (check in Nexus, e.g. [1 0 0] = +x, [0 -1 0] = -y).
headFwdLocal  = [1 0 0];
refDuration_s = 2;        % seconds the reference pose is averaged over

% Audio setup
fs              = 48000;
samplesPerFrame = 960;   % 50 fps to match Tobii 50 Hz;
noiseAmp        = 0.0895;   % gain for the soundscape (if any)
distractorAmp   = 0.20;   % gain for the distractor sounds

% Start / end tone: played on ALL loudspeakers (every channel in channelMapping,
% same level on each) when the begin-recording button is pressed, and again
% (identical tone, same level) when the recording is over.
playStartTone   = true;   % false = no start tone
playEndTone     = true;   % false = no end tone
startToneFreq   = 1000;   % Hz
startToneDur_s  = 1.0;    % seconds
startToneAmp    = 0.0005;   % gain PER loudspeaker (many speakers sum up -> keep low)
startToneRamp_s = 0.010;  % 10 ms raised-cosine fade in/out (avoids clicks)

% Soundscape: this ONE file is played in every recording of every
% condition (also condition 2). Searched for in Settings > BackgroundNoiseFolder
% (subfolders included).
soundscapeFile = 'Cocktail-Party_Large_Background_C-01_EM32_130dBFS_4OA.wav';

% Key lockout: after a screen change (cue screen, red redo / gaze screen),
% key presses are ignored for this many seconds. ENTER is both the trigger
% key and the start key, so this stops a late trigger press from starting
% the next recording (or answering the gaze warning) by accident.
keyLockout_s = 1.0;

% Output channels for the DISTRACTORS: the 24 loudspeakers at ear level.
% Loudspeaker k = ring position k = device channel 30 + k.
% (The previous 6-speaker setup used ring positions [2 4 6 22 20 18].)
distractorChannels = 30 + (1:24);
% Angle of loudspeaker 1..24 (degrees, 0 = straight ahead of the participant)
lsAngles = [-15 -30 -45 -60 -75 -90 -105 -120 -135 -150 -165 180 ...
            165 150 135 120 105 90 75 60 45 30 15 0];
% Allowed distractor angles. The loudspeakers themselves come from the
% Distractors sheet; the script refuses to start (ValidateDesign = 1) if a
% row uses another loudspeaker or the angles are not used equally often.
distractorAngles = [0 45 -45 90 -90 135 -135 180];
% Longest part of a distractor file that is played, in seconds
% (Inf = the whole file; it is always cut at the end of the recording).
distractorMax_s = Inf;

% Output channels for the SOUNDSCAPES:
% channel k of a soundscape file is played on soundscapeChannels(k)
% (36 channels). A mono soundscape file is played on all of them.
soundscapeChannels = [2:2:24 25:48];

% Microphones (recorded in sync with the Vicon data, one file per recording)
%   Mic11 = facilitator on the LEFT side of the setup  (Analog ch 11)
%   Mic12 = facilitator on the RIGHT side of the setup (Analog ch 12)
% Who sits left/right (A or B) comes from Settings > FacilitatorA_Side
% (looked up in the Counterbalancing sheet); micDescription is updated below.
% (Mic level -> dB SPL at the listening position: see mic_calibration_recording.m)
recordMics     = true;    % false = no microphone recording
micDeviceANA   = 'Analog (11+12) (RME UFX+ USB 3.0)';  % ch1 = Mic11, ch2 = Mic12
micBitDepth    = '16-bit integer';
micNames       = {'Mic11', 'Mic12'};   % micDescription / micFacilitator: set after the setup is read

%% ----------------------------------------------------------------
conditionNames = {'Attention failure', 'Directed attention', 'Automatic attention'};
% One sound-card stream that contains every channel used by either list.
% Where the two lists share a channel, soundscape and distractor are mixed.
channelMapping = unique([soundscapeChannels, distractorChannels]);
[~, out.ssCols]  = ismember(soundscapeChannels, channelMapping);   % column per soundscape channel
[~, out.disCols] = ismember(distractorChannels, channelMapping);   % column per loudspeaker
out.nOut = numel(channelMapping);
out.nLS  = numel(distractorChannels);
out.nSS  = numel(soundscapeChannels);
if numel(unique(soundscapeChannels)) ~= out.nSS || numel(unique(distractorChannels)) ~= out.nLS
    error('soundscapeChannels and distractorChannels must not contain the same channel twice.');
end

if numel(lsAngles) ~= numel(distractorChannels)
    error('lsAngles must have one angle per loudspeaker in distractorChannels.');
end
[okAng, distractorLS] = ismember(distractorAngles, lsAngles);   % loudspeaker number per angle
if ~all(okAng)
    error('distractorAngles %s not found in lsAngles.', mat2str(distractorAngles(~okAng)));
end
fprintf('[DEBUG] Distractor device channels (LS 1..%d): %s\n', numel(distractorChannels), mat2str(distractorChannels));
fprintf('Distraktor-hoejttalere: %s\n', strjoin(arrayfun(@(ls) sprintf('LS%d (%d°)', ls, lsAngles(ls)), ...
    distractorLS, 'UniformOutput', false), ', '));
fprintf('[DEBUG] Total device channels in stream: %d  (max=%d)\n', out.nOut, max(channelMapping));

% Folder of the real script file, even when run with Run Section / F9.
% Setup file, output folder, audio folders and the Vicon init script are
% all taken relative to this folder.
scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir) || contains(scriptDir, 'Editor_')
    try
        scriptDir = fileparts(matlab.desktop.editor.getActiveFilename);
    catch
        scriptDir = pwd;
    end
end
cd(scriptDir);
fprintf('Arbejdsmappe: %s\n', scriptDir);
% ---- Read and check the whole design BEFORE touching any hardware ----
cfg = loadSetup(setupFile, scriptDir);
% Seating (fixed for the whole session): which facilitator sits left/right,
% and which facilitator is on which mic (Mic11 = left, Mic12 = right)
FacilitatorA_Side = cfg.sideA;
FacilitatorB_Side = cfg.sideB;
if strcmp(cfg.sideA, 'left'); micFacilitator = {'A', 'B'}; else; micFacilitator = {'B', 'A'}; end
micDescription = {sprintf('Facilitator %s (venstre side)', micFacilitator{1}), ...
    sprintf('Facilitator %s (hoejre side)', micFacilitator{2})};
fprintf('Siddeplacering: Facilitator A sidder %s, B sidder %s  (Mic11 = %s, Mic12 = %s)\n', ...
    sideDK(cfg.sideA), sideDK(cfg.sideB), micFacilitator{1}, micFacilitator{2});
if ~isempty(durationOverride_s)
    warning('TEST MODE: recording duration set to %.1f s in the script (Excel says %.1f s).', ...
        durationOverride_s, cfg.recordingDuration);
    cfg.recordingDuration = durationOverride_s;
end

cfg.lsAngles = lsAngles;
plan = planNoise(cfg, soundscapeFile); % same soundscape in every recording (also seeds rng)
cfg.distractorLS    = distractorLS;       % allowed loudspeakers (checked in validateSetup)
cfg.distractorMax_s = distractorMax_s;
validateSetup(cfg, plan, out, fs);     % errors out if anything is wrong
printDesign(cfg, plan, conditionNames);
participantName    = cfg.participantName;
recordingsPerBlock = cfg.recordingsPerBlock;
totalBlocks        = numel(cfg.blocks);
totalRecordings    = totalBlocks * recordingsPerBlock;
% Fixed length for every recording (rounded up to whole audio frames)
nFrames           = ceil(cfg.recordingDuration * fs / samplesPerFrame);
nSamp             = nFrames * samplesPerFrame;
recordingDuration = nSamp / fs;

if ~exist(outputFolder, 'dir'); mkdir(outputFolder); end
% Unique session ID (date + time) -> every run gets new file names,
% so earlier recordings are never overwritten
sessionID   = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
resultsFile = uniqueFilename(fullfile(outputFolder, ...
    sprintf('results_%s_%s.xlsx', participantName, sessionID)));
fprintf('Session: %s  |  Resultater gemmes i %s\n', sessionID, resultsFile);

% Keep a copy of the exact setup used for this session
copyfile(setupFile, uniqueFilename(fullfile(outputFolder, ...
    sprintf('setup_%s_%s.xlsx', participantName, sessionID))));

% Write session info + the planned playlist BEFORE starting
writecell({ ...
    'Deltager',              participantName; ...
    'SessionID',             sessionID; ...
    'RandomSeed',            plan.seed; ...
    'Soundscapemappe',       cfg.backgroundNoiseFolder; ...
    'Soundscape',            soundscapeFile; ...
    'DistraktorVinkler',     mat2str(distractorAngles); ...
    'DistraktorHoejttalere', mat2str(distractorLS); ...
    'Lydmappe',              cfg.distractorFolder; ...
    'Betingelser_blok1til6', mat2str([cfg.blocks.condition]); ...
    'Target_blok1til6',      strjoin({cfg.blocks.target}, ' '); ...
    'AndenHalvdel',          cfg.secondHalfOrder; ...
    'TargetMoenster',        cfg.targetPattern; ...
    'FacilitatorA_sidder',   cfg.sideA; ...
    'FacilitatorB_sidder',   cfg.sideB; ...
    'Mic11_venstre',         ['Facilitator ' micFacilitator{1}]; ...
    'Mic12_hoejre',          ['Facilitator ' micFacilitator{2}]; ...
    'Optagelseslaengde_sek', recordingDuration}, resultsFile, 'Sheet', 'Session');
writecell(playlistTable(cfg, plan), resultsFile, 'Sheet', 'Playliste');

% ---- Connect to Vicon once (loads SDK, connects, sets stream mode) ----
ViconDataStreamSDK_initialization

% ---- Audio device (opened once, reused for every recording) ----------
AP = audioDeviceWriter;
AP.Driver               = 'ASIO';
AP.Device               = 'ASIO MADIface USB';
AP.ChannelMappingSource = 'Property';
AP.ChannelMapping       = channelMapping;
AP.SampleRate           = fs;
AP.BitDepth             = '24-bit integer';

% Start / end tone (built once): 1 kHz sine, identical on every output
% channel, padded with zeros to whole audio frames. The same signal is used
% for the start tone and the end tone.
nToneSamp = round(startToneDur_s * fs);
tTone     = (0:nToneSamp-1)' / fs;
tone      = startToneAmp * sin(2*pi*startToneFreq*tTone);
nRamp     = round(startToneRamp_s * fs);
ramp      = 0.5 * (1 - cos(pi * (0:nRamp-1)' / nRamp));
tone(1:nRamp)         = tone(1:nRamp) .* ramp;
tone(end-nRamp+1:end) = tone(end-nRamp+1:end) .* flipud(ramp);
nToneFrames = ceil(nToneSamp / samplesPerFrame);
tone(nToneFrames * samplesPerFrame, 1) = 0;            % zero-pad to whole frames
toneSig   = repmat(tone, 1, out.nOut);                  % same signal on all loudspeakers

% ---- Microphone readers (opened once, started/stopped per recording) ----
% SamplesPerFrame = samplesPerFrame, so exactly one mic frame is read per
% loop iteration -> mic samples line up 1:1 with the playback frames and
% with FrameTime / the Vicon frames.
micReaders = {};
if recordMics
    readerANA  = audioDeviceReader('Device', micDeviceANA,  'SampleRate', fs, ...
        'NumChannels', 2, 'BitDepth', micBitDepth, 'SamplesPerFrame', samplesPerFrame);
    micReaders = {readerANA};
end

% Results (one row per recording) and sound log (one row per sound played).
% Rows are indexed by the overall recording number, so a redo simply
% replaces the row(s) of that recording.
headers  = {'Blok', 'Optagelse', 'Betingelse', 'BetingelseNavn', 'Target', ...
    'Interferer', 'TargetSide', 'InterfererSide', 'Historie', 'InterfererHistorie', 'Triggerord', 'AntalSvar', 'Reaktionstider_sek', ...
    'Starttid', 'Soundscape', 'Distraktorer', 'Varighed_sek', 'ViconFil', 'MikrofonFil', 'AntalOmtagninger', 'GazeManglende_pct'};
results  = cell(totalRecordings, numel(headers));
recDone  = false(totalRecordings, 1);     % recording has been made at least once
redoCount = zeros(totalRecordings, 1);     % how often each recording was redone
viconFiles = cell(totalRecordings, 1);     % file name per recording (reused on redo -> overwrite)
soundLog    = {};
soundLogRec = zeros(0, 1);                 % overall recording number of every soundLog row
logHdr   = {'Blok', 'Optagelse', 'Betingelse', 'Type', 'Fil', 'Hoejttaler', 'Vinkel_grader', ...
    'Start_sek', 'Slut_sek', 'Starttid', 'Sluttid'};

% Build the cue window
fig = buildCueWindow(cueMonitor, cueFullscreen, cueTextSize);
try
    % ---- Head reference (Enter in the participant window) ----------
    HeadReference = runReferenceCalibration(fig, MyClient, SubjectName, SegmentName, ...
        refDuration_s, headFwdLocal);
    save(uniqueFilename(fullfile(outputFolder, ...
        sprintf('headref_%s_%s.mat', participantName, sessionID))), 'HeadReference');
    nextRec    = 1;   % next NEW recording
    redoRec    = 0;   % recording to redo (0 = none)
    shownBlock = 0;   % last block whose instructions were printed
    while nextRec <= totalRecordings || redoRec > 0   % redoRec: the last recording can also be redone
        isRedo = redoRec > 0;
        if isRedo; thisRec = redoRec; else; thisRec = nextRec; end
        blockIdx = ceil(thisRec / recordingsPerBlock);
        recIdx   = thisRec - (blockIdx - 1) * recordingsPerBlock;
        blk      = cfg.blocks(blockIdx);
        % Facilitator instructions (command window) for a new block, or
        % again when a redo goes back into the previous block
        if blockIdx ~= shownBlock || isRedo
            hasSoundscape = any(~cellfun(@isempty, plan.noise(blockIdx, :)));
            printBlockInstructions(cfg, blk, blockIdx, totalBlocks, conditionNames, hasSoundscape);
            [s1, i1] = storyFor(cfg, blockIdx, 1);
            fprintf('  Target: %s (historie %d-%d)', pileName(cfg, s1), s1, s1 + recordingsPerBlock - 1);
            if ~isnan(i1)
                fprintf('  |  Interferer: %s (historie %d-%d)', pileName(cfg, i1), i1, i1 + recordingsPerBlock - 1);
            end
            fprintf('\n');
            shownBlock = blockIdx;
        end
        if isRedo
            fprintf('\n>>>>> OMTAGNING af blok %d / optagelse %d - den gamle optagelse overskrives <<<<<\n', ...
                blockIdx, recIdx);
        end
        progressAtStart = 100 * (thisRec - 1) / totalRecordings;
        triggerWord     = cfg.triggerWords{blockIdx, recIdx};
        NoiseFile       = plan.noise{blockIdx, recIdx};   % '' = silence (default)
        [Story, InterfererStory] = storyFor(cfg, blockIdx, recIdx);
        % Build the full playback signal BEFORE the participant starts,
        % so the recording begins instantly when ENTER is pressed.
        [sigPlay, Sounds] = buildSignal(cfg, plan, blockIdx, recIdx, ...
            fs, nSamp, out, noiseAmp, distractorAmp);
        % Show cue screen for this recording (participant sees target only)
        showBlock(fig, blockIdx, totalBlocks, targetLabel(cfg, blk.target), ...
            progressAtStart, recIdx, recordingsPerBlock, triggerWord, isRedo);
        % Wait for ENTER (start recording) or BACKSPACE (redo the previous
        % recording). BACKSPACE only works on the cue screen of a NEW
        % recording, when a previous recording exists.
        canRedo = ~isRedo && thisRec > 1 && recDone(thisRec - 1);
        if strcmp(waitForStartOrRedo(fig, canRedo, keyLockout_s), 'redo')
            if confirmRedo(fig, [], [], [], keyLockout_s)
                redoRec = thisRec - 1;
                fprintf('  Omtagning bekræftet (BACKSPACE + BACKSPACE).\n');
            else
                fprintf('  Omtagning annulleret.\n');
            end
            continue;   % show the cue screen again (for the redo, or the same one)
        end
        % Start the mic streams fresh for this recording (they were
        % stopped after the previous one, so no stale buffered audio).
        MicData        = zeros(nSamp, 2, 'single');            % [Mic11 Mic12]
        MicOverrun     = zeros(nFrames, 1);                    % dropped samples per frame
        MicToneData    = zeros(nToneFrames * samplesPerFrame * playStartTone, 2, 'single');
        MicEndToneData = zeros(nToneFrames * samplesPerFrame * playEndTone,   2, 'single');
        if recordMics
            setup(readerANA);
        end
        % Start tone on all loudspeakers -> signals that a new recording
        % begins. Played BEFORE the recording clock starts, so FrameTime,
        % sound onsets and trigger RTs are unaffected. The mics already
        % record during the tone (saved as MicToneData, useful to check
        % the playback -> mic latency).
        if playStartTone
            MicToneData = playTone(AP, toneSig, nToneFrames, samplesPerFrame, ...
                recordMics, micReaders, MicToneData);
        end
        % Clear trigger state before recording starts
        setappdata(fig, 'triggerPressed', false);
        setappdata(fig, 'triggerRTs', []);
        fprintf('Blok %d/%d  |  Optagelse %d/%d  |  Betingelse %d  |  Target %s  |  Triggerord: %s  (%.2f s)\n', ...
            blockIdx, totalBlocks, recIdx, recordingsPerBlock, blk.condition, ...
            blk.target, triggerWord, recordingDuration);
        fprintf('  %s læser historie %d (%s)', blk.target, Story, pileName(cfg, Story));
        if ~isnan(InterfererStory)
            fprintf('  |  %s (interferer) læser historie %d (%s)', ...
                interfererOf(blk), InterfererStory, pileName(cfg, InterfererStory));
        end
        fprintf('\n');
        fprintf('  Soundscape: %s\n', soundscapeLabel(NoiseFile));
        nDis = sum(strcmp({Sounds.Type}, 'Distraktor'));
        if nDis > 0; fprintf('  %d distraktorer\n', nDis); end
        % Fresh Vicon storage for this recording (NaN = occluded / no data)
        GlobalTranslation          = nan(nFrames, 3);   % mm, lab coordinates
        GlobalRotationQuaternion   = nan(nFrames, 4);   % [x y z w] (Vicon SDK order)
        EyeTrackerGlobalPosition   = nan(nFrames, 3);   % mm, lab coordinates
        EyeTrackerGlobalGazeVector = nan(nFrames, 3);   % unit vector, lab coordinates
        FrameTime                  = zeros(nFrames, 1); % s since recording start
        ViconFrameNumber           = zeros(nFrames, 1);
        setRecordingState(fig, true);
        RecordingStartClock = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
        recStart = tic;
        setappdata(fig, 'recStartTime', recStart);
        setappdata(fig, 'isRecording', true);
        % ---- VICON STREAMING + AUDIO PLAYBACK ----------------------
        % Runs for exactly nFrames audio frames (soundscape in every
        % condition, distractors on top in condition 3).
        for seg = 1:nFrames
            data = sigPlay((seg-1)*samplesPerFrame+1 : seg*samplesPerFrame, :);
            while MyClient.GetFrame().Result ~= ViconDataStreamSDK.DotNET.Result.Success
            end
            FrameTime(seg)        = toc(recStart);
            ViconFrameNumber(seg) = double(MyClient.GetFrameNumber().FrameNumber);
            % Global segment translation + rotation (skip if occluded)
            Out_T = MyClient.GetSegmentGlobalTranslation(SubjectName, SegmentName);
            Out_Q = MyClient.GetSegmentGlobalRotationQuaternion(SubjectName, SegmentName);
            if ~Out_T.Occluded && ~Out_Q.Occluded
                GlobalTranslation(seg, :)        = [Out_T.Translation(1) Out_T.Translation(2) Out_T.Translation(3)];
                GlobalRotationQuaternion(seg, :) = [Out_Q.Rotation(1) Out_Q.Rotation(2) ...
                    Out_Q.Rotation(3) Out_Q.Rotation(4)];
            end
            % Eye tracker (first one only -> exactly one row per frame)
            if MyClient.GetEyeTrackerCount().EyeTrackerCount > 0
                Out_P = MyClient.GetEyeTrackerGlobalPosition(uint32(0));
                Out_G = MyClient.GetEyeTrackerGlobalGazeVector(uint32(0));
                if ~Out_G.Occluded
                    EyeTrackerGlobalPosition(seg, :)   = [Out_P.Position(1) Out_P.Position(2) Out_P.Position(3)];
                    EyeTrackerGlobalGazeVector(seg, :) = [Out_G.GazeVector(1) Out_G.GazeVector(2) Out_G.GazeVector(3)];
                end
            end
            % Play this audio frame (blocks -> paces the loop in real time)
            AP(data);
            % Read the matching mic frame (samplesPerFrame samples each)
            if recordMics
                [fA, oA] = readerANA();    % ch1 = Mic11, ch2 = Mic12
                MicData((seg-1)*samplesPerFrame+1 : seg*samplesPerFrame, :) = ...
                    single(fA(:, 1:2));
                MicOverrun(seg) = oA;
            end
            % Update progress bar; drawnow limitrate also lets the ENTER
            % (trigger) key-press callback fire without slowing the loop down
            overallPct = progressAtStart + (seg / nFrames) * (100 / totalRecordings);
            updateProgress(fig, overallPct);
        end
        % ------------------------------------------------------------
        setappdata(fig, 'isRecording', false);   % ENTER presses no longer count as triggers
        % End tone on all loudspeakers (same tone + level as the start tone)
        % -> signals that the recording is over. Played AFTER the last
        % recorded frame, so the recording itself is unaffected. The mics
        % still run during the tone (saved as MicEndToneData).
        if playEndTone
            MicEndToneData = playTone(AP, toneSig, nToneFrames, samplesPerFrame, ...
                recordMics, micReaders, MicEndToneData);
        end
        setRecordingState(fig, false);
        if recordMics
            release(readerANA);    % stop stream until the next recording
        end
        % ---- Save Vicon data for this recording --------------------
        TriggerRTs        = getappdata(fig, 'triggerRTs');
        Condition         = blk.condition;
        ConditionName     = conditionNames{blk.condition};
        Target            = blk.target;
        Interferer        = interfererOf(blk);
        TargetSide        = facilitatorSide(cfg, Target);       % 'left' / 'right'
        InterfererSide    = facilitatorSide(cfg, Interferer);   % '' if no interferer
        TriggerWord       = triggerWord;
        RecordingDuration = recordingDuration;
        Distractors       = Sounds(strcmp({Sounds.Type}, 'Distraktor'));
        if isRedo
            redoCount(thisRec) = redoCount(thisRec) + 1;
        end
        RedoCount = redoCount(thisRec);
        % Gaze data check: a frame is missing if the gaze vector or the eye
        % tracker position is NaN or all zeros in that frame.
        gazeMissing = any(isnan(EyeTrackerGlobalGazeVector), 2) | any(isnan(EyeTrackerGlobalPosition), 2) | ...
            all(EyeTrackerGlobalGazeVector == 0, 2) | all(EyeTrackerGlobalPosition == 0, 2);
        GazeMissingFrames   = sum(gazeMissing);
        GazeMissingFraction = GazeMissingFrames / nFrames;
        gazeInsufficient = ~isempty(gazeMissingMax) && GazeMissingFraction > gazeMissingMax;
        % recording_<deltager>_<session>_<nr>_blok<b>_opt<r>_cond<c>_target<T>.mat
        % A redo reuses the file name of the first take -> the file is overwritten.
        if isempty(viconFiles{thisRec})
            viconFiles{thisRec} = uniqueFilename(fullfile(outputFolder, ...
                sprintf('recording_%s_%s_%03d_blok%d_opt%d_cond%d_target%s.mat', ...
                participantName, sessionID, thisRec, blockIdx, recIdx, Condition, Target)));
        end
        viconFile = viconFiles{thisRec};
        % Sounds = every sound played (Type, File, Loudspeaker, Onset_s, Duration_s),
        % times in seconds relative to RecordingStartClock / FrameTime = 0
        save(viconFile, 'GlobalRotationQuaternion', 'GlobalTranslation', ...
            'EyeTrackerGlobalPosition', 'EyeTrackerGlobalGazeVector', 'HeadReference', ...
            'FrameTime', 'ViconFrameNumber', 'TriggerRTs', ...
            'Condition', 'ConditionName', 'Target', 'Interferer', ...
            'TargetSide', 'InterfererSide', 'FacilitatorA_Side', 'FacilitatorB_Side', ...
            'lsAngles', 'distractorAngles', ...
            'micFacilitator', 'participantName', ...
            'NoiseFile', 'Distractors', 'Sounds', 'RecordingStartClock', ...
            'TriggerWord', 'Story', 'InterfererStory', 'RecordingDuration', 'RedoCount', ...
            'GazeMissingFrames', 'GazeMissingFraction', ...
            'fs', 'samplesPerFrame', 'channelMapping', ...
            'soundscapeChannels', 'distractorChannels', ...
            'MicData', 'MicToneData', 'MicEndToneData', 'MicOverrun', 'micNames', 'micDescription');
        if isRedo
            fprintf('  Vicon-data OVERSKREVET: %s', viconFile);
        else
            fprintf('  Vicon-data gemt: %s', viconFile);
        end
        fprintf(' (%d frames, %.0f%% hoved tracket, %.0f%% blik tracket)\n', ...
            nFrames, 100 * mean(~isnan(GlobalTranslation(:, 1))), ...
            100 * mean(~isnan(EyeTrackerGlobalGazeVector(:, 1))));
        % Log trigger responses
        rts = TriggerRTs;
        if ~isempty(rts)
            rtStr = strjoin(arrayfun(@(t) sprintf('%.3f', t), rts, 'UniformOutput', false), ', ');
            fprintf('  Triggerord "%s" — %d svar registreret (sek): %s\n', ...
                triggerWord, numel(rts), rtStr);
        else
            rtStr = '';
            fprintf('  Intet svar på triggerord "%s".\n', triggerWord);
        end
        startStr = char(RecordingStartClock);
        results(thisRec, :) = { ...
            blockIdx, recIdx, Condition, ConditionName, Target, Interferer, ...
            TargetSide, InterfererSide, Story, storyCell(InterfererStory), ...
            triggerWord, numel(rts), rtStr, startStr, soundscapeLabel(NoiseFile), ...
            distractorString(Distractors), recordingDuration, viconFile, viconFile, RedoCount, round(100 * GazeMissingFraction, 1) };
        recDone(thisRec) = true;
        % One log row per sound: which file, which loudspeaker, when.
        % On a redo the old rows of this recording are replaced.
        keep        = soundLogRec ~= thisRec;
        soundLog    = soundLog(keep, :);
        soundLogRec = soundLogRec(keep);
        for s = 1:numel(Sounds)
            t0 = RecordingStartClock + seconds(Sounds(s).Onset_s);
            t1 = t0 + seconds(Sounds(s).Duration_s);
            ang = Sounds(s).Angle_deg;  if isnan(ang); ang = ''; end
            soundLog(end+1, :) = { ...
                blockIdx, recIdx, Condition, Sounds(s).Type, Sounds(s).File, ...
                Sounds(s).Loudspeaker, ang, Sounds(s).Onset_s, ...
                Sounds(s).Onset_s + Sounds(s).Duration_s, char(t0), char(t1)}; %#ok<SAGROW>
            soundLogRec(end+1, 1) = thisRec; %#ok<SAGROW>
        end
        [soundLogRec, ord] = sort(soundLogRec);   % keep the log in recording order
        soundLog = soundLog(ord, :);
        % Save after every recording (safe if the experiment crashes)
        writecell([headers; results(recDone, :)], resultsFile, 'Sheet', 'Resultater');
        if ~isempty(soundLog)
            writecell([logHdr; soundLog], resultsFile, 'Sheet', 'Lydlog');
        end
        if isRedo
            fprintf('  Omtagning af blok %d / optagelse %d færdig - fortsætter med næste optagelse.\n', ...
                blockIdx, recIdx);
            redoRec = 0;
        else
            fprintf('  Optagelse %d færdig.\n', recIdx);
            if recIdx == recordingsPerBlock
                fprintf('Blok %d færdig.\n', blockIdx);
            end
            nextRec = nextRec + 1;
        end
        % ---- Gaze data check -> offer to redo THIS recording --------
        if gazeInsufficient
            fprintf(2, '  ADVARSEL: gaze data mangler i %d af %d frames (%.0f%%).\n', ...
                GazeMissingFrames, nFrames, 100 * GazeMissingFraction);
            if confirmRedo(fig, 'Advarsel: gaze data er utilstrækkelig.', ...
                    'Tag seneste optagelse om?', 30, keyLockout_s)
                redoRec = thisRec;
                fprintf('  Omtagning bekræftet (gaze-advarsel).\n');
            else
                fprintf('  Ingen omtagning - fortsætter.\n');
            end
        end
    end
catch ME
    % Always release hardware, even on error / closed window
    shutdownHardware(MyClient, AP, TransmitMulticast);
    rethrow(ME);
end
shutdownHardware(MyClient, AP, TransmitMulticast);
fprintf('Resultater gemt i %s\n', resultsFile);
% ---- Post-experiment questionnaire (SEVQuest) -------------------------
% Hardware is already released. Every answer is written to the sheet
% 'Spoergeskema' in resultsFile as soon as it is given.
if doQuestionnaire && isvalid(fig)
    fprintf('\n===== SPØRGESKEMA (SEVQuest) =====\n');
    try
        runQuestionnaire(fig, resultsFile, keyLockout_s);
        fprintf('Spørgeskema gemt på arket "Spoergeskema" i %s\n', resultsFile);
    catch ME
        warning('Spørgeskema afbrudt: %s (svar indtil da er gemt).', ME.message);
    end
end
% Finished
if isvalid(fig)
    updateProgress(fig, 100);
    setLabel(fig, 'instruction', 'Eksperiment slut!');
    setLabel(fig, 'condition',   'Mange tak :)');
    setLabel(fig, 'triggerHeader', '');
    setLabel(fig, 'triggerWord', '');
    setLabel(fig, 'triggerStatus', '');
    set(findobj(fig, 'Tag', 'proceedBtn'), 'String', 'Tak for din deltagelse', ...
        'BackgroundColor', [0.20 0.78 0.35], 'ForegroundColor', [1 1 1]);
    drawnow;
    pause(3);
end
if isvalid(fig); delete(fig); end
disp('Eksperiment slut.');


%%  INTERNAL FUNCTIONS  
%% ---------------- Excel setup: reading ----------------------------
function cfg = loadSetup(file, baseDir)
% Reads Settings / Blocks / Recordings / Distractors / Soundscapes from the workbook.
if ~isfile(file)
    error('Setup file not found: %s', file);
end
sheets = sheetnames(file);
% --- Settings (Parameter | Value) ---
S   = readcell(file, 'Sheet', 'Settings');
settings = containers.Map();
for i = 2:size(S, 1)
    key = toText(S{i, 1});
    if ~isempty(key); settings(key) = S{i, 2}; end
end
cfg.participantName    = toText(getSetting(settings, 'ParticipantName', 'test'));
cfg.recordingDuration  = toNum(getSetting(settings, 'RecordingDuration_s', 50));
cfg.recordingsPerBlock = toNum(getSetting(settings, 'RecordingsPerBlock', 8));
cfg.blocksPerCondition = toNum(getSetting(settings, 'BlocksPerCondition', 2));
cfg.validateDesign     = toNum(getSetting(settings, 'ValidateDesign', 1)) ~= 0;
cfg.distractorFolder      = toText(getSetting(settings, 'DistractorFolder', ...
    getSetting(settings, 'AudioFolder', fullfile('..', 'HOA SSR database'))));
cfg.backgroundNoiseFolder = toText(getSetting(settings, 'BackgroundNoiseFolder', ...
    getSetting(settings, 'SoundscapeFolder', ...
    getSetting(settings, 'NoiseFolder', cfg.distractorFolder))));
cfg.noisePattern          = toText(getSetting(settings, 'SoundscapePattern', ...
    getSetting(settings, 'NoisePattern', '*.wav')));
cfg.randomSeed         = toNum(getSetting(settings, 'RandomSeed', NaN));
cfg.labelA             = toText(getSetting(settings, 'TargetLabel_A', 'A'));
cfg.labelB             = toText(getSetting(settings, 'TargetLabel_B', 'B'));
cfg.facilitatorASide   = toText(getSetting(settings, 'FacilitatorA_Side', ''));
cfg.secondHalfOrder    = toText(getSetting(settings, 'SecondHalfOrder', ''));
cfg.targetPattern      = toText(getSetting(settings, 'TargetPattern', ''));
if contains(upper(cfg.facilitatorASide), 'NOT FOUND')
    error(['Participant "%s" (Settings > ParticipantName) is not in the Counterbalancing sheet. ' ...
        'Add a row for this participant or fix the name, save the workbook and run again.'], cfg.participantName);
end
if isempty(cfg.participantName); cfg.participantName = 'test'; end
% Seating: Counterbalancing > 'Facilitator A sits' must be left or right
switch lower(cfg.facilitatorASide)
    case {'left', 'l', 'venstre', 'v'};  cfg.sideA = 'left';  cfg.sideB = 'right';
    case {'right', 'r', 'hoejre', 'højre', 'h'}; cfg.sideA = 'right'; cfg.sideB = 'left';
    otherwise
        error(['Settings > FacilitatorA_Side is "%s" for participant "%s" - must be left or right. ' ...
            'Fix "Facilitator A sits" in the Counterbalancing sheet, save the workbook and run again.'], ...
            cfg.facilitatorASide, cfg.participantName);
end
if ~(cfg.recordingDuration > 0)
    error('Settings: RecordingDuration_s must be a positive number.');
end
if ~(cfg.recordingsPerBlock >= 1) || mod(cfg.recordingsPerBlock, 1) ~= 0
    error('Settings: RecordingsPerBlock must be a whole number >= 1.');
end
cfg.distractorFolder      = resolvePath(cfg.distractorFolder, baseDir);
cfg.backgroundNoiseFolder = resolvePath(cfg.backgroundNoiseFolder, baseDir);
% --- Blocks ---
B = readSheet(file, 'Blocks', {'Block', 'Condition', 'Target'});
n = B.nRows;
if n == 0; error('Blocks sheet is empty.'); end
blocks = repmat(struct('number', NaN, 'condition', NaN, 'target', '', 'noiseFile', ''), 1, n);
for i = 1:n
    blocks(i).number    = toNum(B.Block{i});
    blocks(i).condition = toNum(B.Condition{i});
    blocks(i).target    = upper(toText(B.Target{i}));
    if isfield(B, 'Soundscape')
        blocks(i).noiseFile = toText(B.Soundscape{i});
    elseif isfield(B, 'NoiseFile')                  % old column name
        blocks(i).noiseFile = toText(B.NoiseFile{i});
    end
    if isSilence(blocks(i).noiseFile); blocks(i).noiseFile = ''; end
    if strcmpi(blocks(i).noiseFile, 'random'); blocks(i).noiseFile = 'RANDOM'; end
end
[~, order] = sort([blocks.number]);
blocks = blocks(order);
if ~isequal([blocks.number], 1:n)
    error('Blocks sheet: Block numbers must be 1..%d, each used once (found: %s).', ...
        n, mat2str([blocks.number]));
end
cfg.blocks = blocks;
% --- Recordings (trigger words) ---
R  = readSheet(file, 'Recordings', {'Block', 'Recording', 'TriggerWord'});
tw = cell(n, cfg.recordingsPerBlock);
for i = 1:R.nRows
    b = toNum(R.Block{i});  r = toNum(R.Recording{i});
    if ~ismember(b, 1:n) || ~ismember(r, 1:cfg.recordingsPerBlock)
        error('Recordings sheet, row %d: Block %g / Recording %g is out of range (blocks 1..%d, recordings 1..%d).', ...
            i + 1, b, r, n, cfg.recordingsPerBlock);
    end
    if ~isempty(tw{b, r})
        error('Recordings sheet: Block %d / Recording %d is listed twice.', b, r);
    end
    tw{b, r} = toText(R.TriggerWord{i});
end
[mb, mr] = find(cellfun(@isempty, tw));
if ~isempty(mb)
    error('Recordings sheet: no trigger word for %s.', strjoin(arrayfun( ...
        @(b, r) sprintf('Block %d/Rec %d', b, r), mb, mr, 'UniformOutput', false), ', '));
end
cfg.triggerWords = tw;
% --- Distractors (optional sheet), files relative to DistractorFolder ---
%     Rows are keyed by Condition + Target (or an old-style Block column).
D = struct('Block', zeros(0, 1), 'Condition', zeros(0, 1), 'Target', {cell(0, 1)}, ...
    'Recording', zeros(0, 1), 'File', {cell(0, 1)}, 'Path', {cell(0, 1)}, ...
    'Loudspeaker', zeros(0, 1), 'Onset_s', zeros(0, 1));
if ismember('Distractors', sheets)
    Draw = readSheet(file, 'Distractors', {'Recording', 'File', 'Loudspeaker', 'Onset_s'});
    [kB, kC, kT] = rowKeys(Draw, 'Distractors');
    for i = 1:Draw.nRows
        D.Block(end+1, 1)       = kB(i);
        D.Condition(end+1, 1)   = kC(i);
        D.Target{end+1, 1}      = kT{i};
        D.Recording(end+1, 1)   = toNum(Draw.Recording{i});
        D.File{end+1, 1}        = toText(Draw.File{i});
        D.Path{end+1, 1}        = findInFolder(D.File{end}, cfg.distractorFolder);
        D.Loudspeaker(end+1, 1) = toNum(Draw.Loudspeaker{i});
        D.Onset_s(end+1, 1)     = toNum(Draw.Onset_s{i});
    end
end
cfg.distractors = mapToBlocks(D, blocks, 'Distractors');
% --- Soundscapes sheet: no longer used (one fixed soundscape, see
%     soundscapeFile at the top of the script). ---
if ismember('Soundscapes', sheets)
    fprintf('Bemaerk: arket "Soundscapes" ignoreres - samme soundscape i alle optagelser.\n');
end
% --- Stories: half of all recordings, in coloured piles of RecordingsPerBlock ---
cfg.nStories = n * cfg.recordingsPerBlock / 2;
if mod(cfg.nStories, 1) ~= 0
    error('Blocks x RecordingsPerBlock must be even (each story is read twice).');
end
end
function [kB, kC, kT] = rowKeys(T, sheet)
% Per-row key of a Distractors/Soundscapes sheet: Condition + Target
% (preferred) or Block (old style). Unused parts are NaN / ''.
n  = T.nRows;
kB = nan(n, 1);  kC = nan(n, 1);  kT = repmat({''}, n, 1);
if isfield(T, 'Condition') && isfield(T, 'Target')
    for i = 1:n
        kC(i) = toNum(T.Condition{i});
        kT{i} = upper(toText(T.Target{i}));
        if isnan(kC(i)) || ~ismember(kT{i}, {'A', 'B'})
            error('%s sheet, row %d: Condition must be a number and Target A or B.', sheet, i + 1);
        end
    end
elseif isfield(T, 'Block')
    for i = 1:n; kB(i) = toNum(T.Block{i}); end
else
    error('Sheet "%s" needs the columns Condition + Target (or Block).', sheet);
end
end
function T = mapToBlocks(T, blocks, sheet)
% Replaces Condition + Target by the block number(s) that currently have that
% condition and target in the Blocks sheet. Rows with no matching block are
% dropped with a warning. Old-style rows (Block given) are kept as they are.
src = zeros(0, 1);  newB = zeros(0, 1);
conds = [blocks.condition];  targs = {blocks.target};
for k = 1:numel(T.Block)
    if isnan(T.Condition(k))
        src(end+1, 1) = k;  newB(end+1, 1) = T.Block(k); %#ok<AGROW>
        continue;
    end
    idx = find(conds == T.Condition(k) & strcmp(targs, T.Target{k}));
    if isempty(idx)
        warning('%s row %d: no block has condition %g with target %s - row ignored.', ...
            sheet, k + 1, T.Condition(k), T.Target{k});
    end
    for j = idx
        src(end+1, 1) = k;  newB(end+1, 1) = blocks(j).number; %#ok<AGROW>
    end
end
f = fieldnames(T);
for i = 1:numel(f)
    T.(f{i}) = T.(f{i})(src);
end
T.Block = newB;
end
function tf = isSilence(s)
tf = any(strcmpi(s, {'silence', 'stilhed', 'none'}));
end
function p = resolvePath(p, baseDir)
% Relative path -> relative to baseDir. Absolute paths are kept.
if isempty(p); return; end
isAbs = startsWith(p, {'/', '\'}) || ~isempty(regexp(p, '^[A-Za-z]:', 'once'));
if ~isAbs; p = fullfile(baseDir, p); end
end
function p = findInFolder(filename, baseDir)
% Like resolvePath, but also searches subfolders of baseDir when the file
% is not found directly in baseDir. Returns the full path of the first
% match found (alphabetical order), or baseDir\filename if nothing found
% (so the validator can report a clear "file not found" error).
if isempty(filename)
    p = '';
    return;
end
% Absolute path or already contains a subfolder separator -> keep as-is
isAbs = startsWith(filename, {'/', '\'}) || ~isempty(regexp(filename, '^[A-Za-z]:', 'once'));
if isAbs
    p = filename;
    return;
end
% Try direct join first (fastest, covers the common case)
direct = fullfile(baseDir, filename);
if isfile(direct)
    p = direct;
    return;
end
% Search recursively through all subfolders
[~, name, ext] = fileparts(filename);
L = dir(fullfile(baseDir, '**', [name ext]));
L = L(~[L.isdir]);
if ~isempty(L)
    paths = sort(fullfile({L.folder}, {L.name}));
    p = paths{1};   % first alphabetical match
else
    p = direct;     % not found - return direct path so validator reports it
end
end
function T = readSheet(file, sheet, required)
% Reads a sheet with a header row into a struct of cell columns (by header
% name, so column order does not matter). Fully empty rows are dropped.
C = readcell(file, 'Sheet', sheet);
if isempty(C)
    hdr = {}; body = {};
else
    hdr  = cellfun(@toText, C(1, :), 'UniformOutput', false);
    body = C(2:end, :);
    if ~isempty(body)
        body = body(~all(cellfun(@(v) isempty(toText(v)), body), 2), :);
    end
end
T = struct('nRows', size(body, 1));
for j = 1:numel(hdr)
    if ~isempty(hdr{j})
        T.(matlab.lang.makeValidName(hdr{j})) = body(:, j);
    end
end
for k = 1:numel(required)
    if ~isfield(T, required{k})
        error('Sheet "%s" is missing the column "%s".', sheet, required{k});
    end
end
end
function v = getSetting(map, key, default)
if isKey(map, key) && ~isempty(toText(map(key)))
    v = map(key);
else
    v = default;
end
end
function s = toText(v)
% Any Excel cell value -> trimmed char ('' for empty/missing).
if iscell(v)
    if isempty(v); s = ''; return; end
    v = v{1};
end
if isempty(v) || isa(v, 'missing'); s = ''; return; end
if isstring(v)
    if ismissing(v); s = ''; return; end
    v = char(v);
end
if isnumeric(v) || islogical(v)
    if isnan(double(v)); s = ''; else; s = num2str(v); end
else
    s = strtrim(char(v));
end
end
function x = toNum(v)
% Any Excel cell value -> double (NaN for empty/missing). Accepts '2,5'.
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

%% Soundscape plan 
function plan = planNoise(cfg, soundscapeFile)
% The SAME soundscape file is played in every recording of every condition
% (1, 2 and 3). Also seeds the random generator for this session (the
% seed is logged and used for the distractor loudspeaker assignment).
nB  = numel(cfg.blocks);
rpb = cfg.recordingsPerBlock;
% Random seed: from Settings, or a new one each session (always logged)
if isnan(cfg.randomSeed)
    rng('shuffle');
    st = rng;
    plan.seed = double(st.Seed);
else
    plan.seed = cfg.randomSeed;
end
rng(plan.seed);
if isempty(soundscapeFile)
    error('soundscapeFile is empty - set it at the top of the script.');
end
p = findInFolder(soundscapeFile, cfg.backgroundNoiseFolder);
plan.noise     = repmat({soundscapeFile}, nB, rpb);   % name shown in logs
plan.noisePath = repmat({p}, nB, rpb);                % full path used for playback
plan.poolSize  = 1;
end
function C = playlistTable(cfg, plan)
% Planned playlist, one row per recording (written before the session).
C = {'Blok', 'Optagelse', 'Betingelse', 'Target', 'Historie', 'Interferer', ...
    'InterfererHistorie', 'Triggerord', 'Soundscape', 'Distraktorer'};
D = cfg.distractors;
for b = 1:numel(cfg.blocks)
    blk = cfg.blocks(b);
    for r = 1:cfg.recordingsPerBlock
        dStr = '';
        if blk.condition == 3
            k = find(D.Block == blk.number & D.Recording == r);
            dStr = strjoin(arrayfun(@(i) sprintf('%s@LS%d(%ddeg)@%.2fs', D.File{i}, ...
                D.Loudspeaker(i), cfg.lsAngles(D.Loudspeaker(i)), D.Onset_s(i)), ...
                k(:)', 'UniformOutput', false), '; ');
        end
        [st, ist] = storyFor(cfg, b, r);
        C(end+1, :) = {b, r, blk.condition, blk.target, st, interfererOf(blk), ...
            storyCell(ist), cfg.triggerWords{b, r}, ...
            soundscapeLabel(plan.noise{b, r}), dStr}; %#ok<AGROW>
    end
end
end

%% Excel setup: checking
function validateSetup(cfg, plan, out, fs)
% Checks the whole design and every audio file that will be played.
% Hard problems -> error. Design balance -> error (or warning if
% ValidateDesign = 0). Minor issues -> warning.
nCh = out.nLS;   % number of distractor loudspeakers
errs = {}; design = {}; warns = {};
nBlocks = numel(cfg.blocks);
rpb     = cfg.recordingsPerBlock;
conds   = [cfg.blocks.condition];
targs   = {cfg.blocks.target};
% --- conditions / targets ---
for b = 1:nBlocks
    if ~ismember(conds(b), 1:3)
        errs{end+1} = sprintf('Block %d: Condition must be 1, 2 or 3 (found "%g").', b, conds(b)); %#ok<AGROW>
    end
    if ~ismember(targs{b}, {'A', 'B'})
        errs{end+1} = sprintf('Block %d: Target must be A or B (found "%s").', b, targs{b}); %#ok<AGROW>
    end
end
% --- balance: each condition N times, A and B equally often within it ---
for c = 1:3
    inC = conds == c;
    nA  = sum(inC & strcmp(targs, 'A'));
    nB  = sum(inC & strcmp(targs, 'B'));
    if sum(inC) ~= cfg.blocksPerCondition
        design{end+1} = sprintf('Condition %d is used in %d block(s), expected %d.', ...
            c, sum(inC), cfg.blocksPerCondition); %#ok<AGROW>
    end
    if nA ~= nB
        design{end+1} = sprintf('Condition %d: A is target %d time(s), B %d time(s) - must be equal.', ...
            c, nA, nB); %#ok<AGROW>
    end
end
% Map from Excel block number -> loop index (blocks are sorted by number)
blockNumbers = [cfg.blocks.number];
% --- distractor rows ---
D = cfg.distractors;
useRow = false(numel(D.Block), 1);
for k = 1:numel(D.Block)
    row    = k + 1;          % Excel row number
    bNum   = D.Block(k);     % block number as written in Excel
    r      = D.Recording(k);
    bIdx   = find(blockNumbers == bNum, 1);   % loop index for this block
    if isempty(bIdx) || ~ismember(r, 1:rpb)
        errs{end+1} = sprintf('Distractors row %d: Block %g / Recording %g out of range.', row, bNum, r); %#ok<AGROW>
        continue;
    end
    if conds(bIdx) ~= 3
        warns{end+1} = sprintf('Distractors row %d: block %d is condition %d - row ignored.', row, bNum, conds(bIdx)); %#ok<AGROW>
        continue;
    end
    if ~ismember(D.Loudspeaker(k), 1:nCh)
        errs{end+1} = sprintf('Distractors row %d: Loudspeaker must be 1..%d (found %g).', row, nCh, D.Loudspeaker(k)); %#ok<AGROW>
    elseif ~ismember(D.Loudspeaker(k), cfg.distractorLS)
        design{end+1} = sprintf('Distractors row %d: Loudspeaker %d (%d deg) is not one of the allowed distractor loudspeakers %s.', ...
            row, D.Loudspeaker(k), cfg.lsAngles(D.Loudspeaker(k)), mat2str(cfg.distractorLS)); %#ok<AGROW>
    end
    if isnan(D.Onset_s(k)) || D.Onset_s(k) < 0 || D.Onset_s(k) >= cfg.recordingDuration
        errs{end+1} = sprintf('Distractors row %d: Onset_s %g is outside 0..%g s.', row, D.Onset_s(k), cfg.recordingDuration); %#ok<AGROW>
    end
    if isempty(D.File{k})
        errs{end+1} = sprintf('Distractors row %d: File is empty.', row); %#ok<AGROW>
    end
    useRow(k) = true;
end
for bIdx = find(conds == 3)
    bNum = blockNumbers(bIdx);
    for r = 1:rpb
        inRec = find(useRow & D.Block == bNum & D.Recording == r);
        if isempty(inRec)
            warns{end+1} = sprintf('Block %d / Recording %d (condition 3) has no distractors.', bNum, r); %#ok<AGROW>
        elseif numel(unique(D.Loudspeaker(inRec))) < numel(inRec)
            warns{end+1} = sprintf('Block %d / Recording %d: the same loudspeaker is used more than once.', bNum, r); %#ok<AGROW>
        end
    end
end
% --- balance: every allowed loudspeaker used equally often ---
usedLS = D.Loudspeaker(useRow);
if ~isempty(usedLS)
    nPer = arrayfun(@(x) sum(usedLS == x), cfg.distractorLS);
    if numel(unique(nPer)) > 1
        design{end+1} = sprintf(['Distractor loudspeakers are not used equally often: %s ' ...
            '(LS: times used).'], strjoin(arrayfun(@(x, n) sprintf('LS%d(%d deg): %d', x, ...
            cfg.lsAngles(x), n), cfg.distractorLS, nPer, 'UniformOutput', false), ', ')); %#ok<AGROW>
    end
end
% --- soundscape files that will be played (header check only, fast) ---
noisePaths = unique(plan.noisePath(~cellfun(@isempty, plan.noisePath)));
for i = 1:numel(noisePaths)
    f = noisePaths{i};
    if ~isfile(f)
        errs{end+1} = sprintf('Soundscape file not found: %s', f); %#ok<AGROW>
        continue;
    end
    info = audioinfo(f);
    if info.SampleRate ~= fs
        errs{end+1} = sprintf('%s has fs = %d Hz, expected %d Hz.', f, info.SampleRate, fs); %#ok<AGROW>
    end
    % Channel 1 is always used and spread across all soundscape outputs,
    % so any number of channels in the file is accepted.
    if info.Duration < cfg.recordingDuration
        warns{end+1} = sprintf('%s is only %.1f s - it will be looped to fill %.1f s.', ...
            f, info.Duration, cfg.recordingDuration); %#ok<AGROW>
    end
end
% --- distractor files ---
D.Dur_s = zeros(numel(D.Block), 1);   % played duration per row (0 = not played / not found)
for k = find(useRow)'
    f = D.Path{k};
    if isempty(f); continue; end
    if ~isfile(f)
        errs{end+1} = sprintf('Distractors row %d: file not found: %s', k + 1, f); %#ok<AGROW>
        continue;
    end
    info = audioinfo(f);
    if info.SampleRate ~= fs
        warns{end+1} = sprintf('Distractors row %d: %s has fs = %d Hz (expected %d Hz) - will be resampled automatically.', ...
            k + 1, D.File{k}, info.SampleRate, fs); %#ok<AGROW>
    end
    D.Dur_s(k, 1) = min(info.Duration, cfg.distractorMax_s);
    endT = D.Onset_s(k) + D.Dur_s(k);
    if endT > cfg.recordingDuration
        warns{end+1} = sprintf('Distractors row %d: %s ends at %.1f s, will be cut at %.1f s.', ...
            k + 1, D.File{k}, endT, cfg.recordingDuration); %#ok<AGROW>
    end
end
% --- overlap: two distractors playing at the same time in one recording ---
for bIdx = find(conds == 3)
    for r = 1:rpb
        k = find(useRow & D.Block == blockNumbers(bIdx) & D.Recording == r & D.Dur_s > 0);
        [t0, o] = sort(D.Onset_s(k));  k = k(o);
        t1 = t0 + D.Dur_s(k);
        for j = 2:numel(k)
            if t0(j) < t1(j - 1)
                warns{end+1} = sprintf('Block %d / Recording %d: %s (%.1f s) starts before %s has finished (%.1f s).', ...
                    blockNumbers(bIdx), r, D.File{k(j)}, t0(j), D.File{k(j - 1)}, t1(j - 1)); %#ok<AGROW>
            end
        end
    end
end
% --- report ---
for i = 1:numel(warns); warning('Setup: %s', warns{i}); end
if ~isempty(design)
    if cfg.validateDesign
        errs = [errs, design];
    else
        for i = 1:numel(design)
            warning('Setup (ValidateDesign = 0, continuing anyway): %s', design{i});
        end
    end
end
if ~isempty(errs)
    error('Setup file has %d problem(s):\n  - %s', numel(errs), strjoin(errs, sprintf('\n  - ')));
end
end
function printDesign(cfg, plan, conditionNames)
fprintf('\n===== DESIGN (%s) =====\n', cfg.participantName);
fprintf('Optagelseslængde: %.1f s  |  %d optagelser pr. blok\n', ...
    cfg.recordingDuration, cfg.recordingsPerBlock);
fprintf('Facilitator A sidder: %s  |  Facilitator B sidder: %s  |  anden halvdel: %s  |  target: %s\n', ...
    sideDK(cfg.sideA), sideDK(cfg.sideB), cfg.secondHalfOrder, cfg.targetPattern);
fprintf('Soundscape i ALLE optagelser: %s  (seed %d)\n', plan.noise{1, 1}, plan.seed);
for b = 1:numel(cfg.blocks)
    blk = cfg.blocks(b);
    nD  = sum(cfg.distractors.Block == b);
    nS  = sum(~cellfun(@isempty, plan.noise(b, :)));
    fprintf('  Blok %d: Betingelse %d (%s), Target %s', ...
        b, blk.condition, conditionNames{blk.condition}, blk.target);
    if nS > 0
        fprintf(', soundscape i %d/%d optagelser', nS, cfg.recordingsPerBlock);
    else
        fprintf(', stilhed');
    end
    if blk.condition == 3; fprintf(', %d distraktorer i alt', nD); end
    fprintf('\n');
end
% Distractors per loudspeaker (condition 3 blocks only)
D3 = ismember(cfg.distractors.Block, find([cfg.blocks.condition] == 3));
if any(D3)
    fprintf('Distraktorer pr. hoejttaler (fra arket Distractors):\n');
    for x = cfg.distractorLS(:)'
        fprintf('  LS%-2d (%4d°): %d\n', x, cfg.lsAngles(x), sum(cfg.distractors.Loudspeaker(D3) == x));
    end
end
fprintf('Hele playlisten står på arket "Playliste" i resultatfilen.\n');
fprintf('=========================\n\n');
end
function printBlockInstructions(cfg, blk, blockIdx, totalBlocks, conditionNames, hasSoundscape)
% Instructions for the experimenter / facilitators (command window only).
other = interfererOf(blk);
if hasSoundscape; bg = 'soundscape'; else; bg = 'stilhed'; end
if isempty(other); other = setdiff({'A', 'B'}, {blk.target}); other = other{1}; end
tgt = sprintf('%s (%s)', blk.target, sideDK(facilitatorSide(cfg, blk.target)));
oth = sprintf('%s (%s)', other, sideDK(facilitatorSide(cfg, other)));
fprintf('\n============ BLOK %d/%d — Betingelse %d: %s ============\n', ...
    blockIdx, totalBlocks, blk.condition, conditionNames{blk.condition});
switch blk.condition
    case 1
        fprintf('  %s fortæller (TARGET)  |  %s fortæller (INTERFERER)  |  %s\n', tgt, oth, bg);
    case 2
        fprintf('  %s fortæller (TARGET)  |  %s er tavs  |  %s\n', tgt, oth, bg);
    case 3
        fprintf('  %s fortæller (TARGET)  |  %s er tavs  |  %s + distraktorer\n', tgt, oth, bg);
end
fprintf('==========================================================\n');
end

%% Audio
function [sig, Sounds] = buildSignal(cfg, plan, b, r, fs, nSamp, out, noiseAmp, distractorAmp)
% Builds the playback matrix (nSamp x numel(channelMapping)) for one recording:
%   cond 1, 2, 3 : the soundscape file for the whole recording
%   cond 3       : + distractors on top
% Soundscape channel k -> column out.ssCols(k)  (= soundscapeChannels(k))
% Loudspeaker ls       -> column out.disCols(ls) (= distractorChannels(ls))
% Sounds lists everything that is played (Loudspeaker 0 = soundscape channels,
% Angle_deg = NaN for the soundscape).
sig    = zeros(nSamp, out.nOut);
Sounds = struct('Type', {}, 'File', {}, 'Loudspeaker', {}, 'Angle_deg', {}, ...
    'Onset_s', {}, 'Duration_s', {});
blk    = cfg.blocks(b);
nf = plan.noisePath{b, r};
if ~isempty(nf)
    info = audioinfo(nf);
    y = audioread(nf, [1 min(nSamp, info.TotalSamples)]);   % read only what is needed
    if size(y, 1) < nSamp                                    % loop if shorter
        y = repmat(y, ceil(nSamp / size(y, 1)), 1);
    end
    y = y(1:nSamp, :);
    % Use channel 1 of the file only, spread across all soundscape output
    % channels — matches the reference playback script behaviour.
    y1 = repmat(y(:, 1), 1, out.nSS);
    sig(:, out.ssCols) = sig(:, out.ssCols) + noiseAmp * y1;
    Sounds(end+1) = struct('Type', 'Soundscape', 'File', plan.noise{b, r}, ...
        'Loudspeaker', 0, 'Angle_deg', NaN, 'Onset_s', 0, 'Duration_s', nSamp / fs);
end
if blk.condition == 3
    D = cfg.distractors;
    blockNum = blk.number;   % actual block number from Excel, not loop index
    distRows = find(D.Block == blockNum & D.Recording == r)';
    fprintf('[DEBUG] Block %d (number %d) / Rec %d: found %d distractor row(s).\n', b, blockNum, r, numel(distRows));
    for k = distRows
        info = audioinfo(D.Path{k});
        y  = audioread(D.Path{k});
        y  = y(:, 1);
        if info.SampleRate ~= fs
            y = resample(y, fs, info.SampleRate);
        end
        ls  = D.Loudspeaker(k);
        col = out.disCols(ls);
        i0       = round(D.Onset_s(k) * fs) + 1;
        maxSamps = round(min(cfg.distractorMax_s, 1e6) * fs);   % whole file unless distractorMax_s is set
        i1       = min(i0 + min(numel(y), maxSamps) - 1, nSamp);
        sig(i0:i1, col) = sig(i0:i1, col) + distractorAmp * y(1:i1 - i0 + 1);
        fprintf('[DEBUG] Distractor: file="%s"  LS=%d (%d°)  device_ch=%d  onset=%.1fs  peak=%.4f\n', ...
            D.File{k}, ls, cfg.lsAngles(ls), out.disCols(ls), D.Onset_s(k), max(abs(distractorAmp * y)));
        Sounds(end+1) = struct('Type', 'Distraktor', 'File', D.File{k}, ...
            'Loudspeaker', ls, 'Angle_deg', cfg.lsAngles(ls), 'Onset_s', D.Onset_s(k), ...
            'Duration_s', (i1 - i0 + 1) / fs); %#ok<AGROW>
    end
    fprintf('[DEBUG] disCols (sig matrix column per LS 1..%d): %s\n', out.nLS, mat2str(out.disCols));
end
if max(abs(sig(:))) >= 1
    warning('Blok %d / Optagelse %d: signal clips (peak %.2f) - lower noiseAmp/distractorAmp.', ...
        b, r, max(abs(sig(:))));
end
end
function [story, intStory] = storyFor(cfg, b, r)
% Story read by the target in block b / recording r: fixed by position,
% independent of condition. Interferer (condition 1 only) reads the story
% one pile (= RecordingsPerBlock stories) back, wrapping around. NaN = none.
rpb      = cfg.recordingsPerBlock;
story    = mod((b - 1) * rpb + r - 1, cfg.nStories) + 1;
intStory = NaN;
if cfg.blocks(b).condition == 1
    intStory = mod(story - rpb - 1, cfg.nStories) + 1;
end
end
function s = pileName(cfg, story)
% Colour of the physical pile a story is in
% (stories 1-8 yellow, 9-16 pink, 17-24 blue; each facilitator has their own).
p = floor((story - 1) / cfg.recordingsPerBlock) + 1;
colours = {'yellow', 'pink', 'blue'};
if p <= numel(colours); s = [colours{p} ' pile']; else; s = sprintf('pile %d', p); end
end
function c = storyCell(x)
% NaN -> '' so the Excel results show an empty cell
if isnan(x); c = ''; else; c = x; end
end
function s = soundscapeLabel(f)
if isempty(f); s = 'stilhed'; else; s = f; end
end
function s = interfererOf(blk)
% Only condition 1 has an interferer: the facilitator who is not the target.
if blk.condition == 1
    if strcmp(blk.target, 'A'); s = 'B'; else; s = 'A'; end
else
    s = '';
end
end
function s = facilitatorSide(cfg, who)
% 'left' / 'right' for facilitator 'A' or 'B'; '' for no facilitator
switch who
    case 'A'; s = cfg.sideA;
    case 'B'; s = cfg.sideB;
    otherwise; s = '';
end
end
function s = sideDK(side)
% Danish label for the command window
switch side
    case 'left';  s = 'venstre';
    case 'right'; s = 'højre';
    otherwise;    s = '';
end
end
function lbl = targetLabel(cfg, target)
if strcmp(target, 'A'); lbl = cfg.labelA; else; lbl = cfg.labelB; end
end
function s = distractorString(d)
if isempty(d); s = ''; return; end
s = strjoin(arrayfun(@(x) sprintf('%s@LS%d(%ddeg)@%.2fs', x.File, x.Loudspeaker, x.Angle_deg, x.Onset_s), ...
    d, 'UniformOutput', false), '; ');
end

%% Head reference 
function ref = runReferenceCalibration(fig, MyClient, Subj, Seg, dur_s, fwdLocal)
% Shows the reference screen, waits for Enter, measures. Repeats on failure.
msg = '';
while true
    showReferenceScreen(fig, msg);
    waitForEnter(fig);
    setReferenceMeasuring(fig, dur_s);
    ref = captureHeadReference(MyClient, Subj, Seg, dur_s, fwdLocal);
    if ref.ok; break; end
    msg = ref.failReason;
    fprintf('Reference mislykkedes: %s\n', msg);
end
setLabel(fig, 'triggerStatus', '✓  Referenceposition gemt');
set(findobj(fig, 'Tag', 'proceedBtn'), 'String', 'Reference gemt', ...
    'BackgroundColor', [0.20 0.78 0.35], 'ForegroundColor', [1 1 1]);
drawnow;
pause(1.5);
end
function showReferenceScreen(fig, failMsg)
setLabel(fig, 'blockLabel',    'Referenceposition');
setLabel(fig, 'instruction',   'Sid ret op og kig ligeud');
setLabel(fig, 'condition',     '');
setLabel(fig, 'triggerHeader', '');
setLabel(fig, 'triggerWord',   '');
setLabel(fig, 'triggerStatus', failMsg);
set(findobj(fig, 'Tag', 'triggerStatus'), 'ForegroundColor', [0.80 0.10 0.10]);
set(findobj(fig, 'Tag', 'proceedBtn'), 'String', 'TRYK  ENTER  FOR REFERENCE', ...
    'BackgroundColor', [0.10 0.45 0.85], 'ForegroundColor', [1 1 1]);
updateProgress(fig, 0);
figure(fig);
drawnow;
end
function setReferenceMeasuring(fig, dur_s)
setLabel(fig, 'triggerStatus', '');
set(findobj(fig, 'Tag', 'triggerStatus'), 'ForegroundColor', [0.08 0.58 0.08]);
set(findobj(fig, 'Tag', 'proceedBtn'), ...
    'String', sprintf('Måler (%g s) – hold hovedet stille', dur_s), ...
    'BackgroundColor', [0.85 0.15 0.15], 'ForegroundColor', [1 1 1]);
drawnow;
end
function waitForEnter(fig, lockout_s)
% Blocks until Enter (or numpad Enter) is pressed in the cue window.
% Presses within lockout_s seconds after the call are ignored.
if nargin < 2 || isempty(lockout_s); lockout_s = 0; end
figure(fig);
drawnow;
t0 = tic;
while isvalid(fig)
    if waitforbuttonpress() == 1                     % 1 = key press
        if toc(t0) < lockout_s; continue; end
        if isEnterKey(get(fig, 'CurrentKey'), get(fig, 'CurrentCharacter'))
            return;
        end
    end
end
end
function tf = isEnterKey(key, ch)
% Enter / Return on the main keyboard or the numpad
tf = any(strcmpi(key, {'return', 'enter'})) || any(ismember(double(ch), [13 3]));
end
function tf = isBackspaceKey(key, ch)
tf = strcmpi(key, 'backspace') || any(double(ch) == 8);
end
function ref = captureHeadReference(MyClient, Subj, Seg, dur_s, fwdLocal)
% Averages the global head pose over dur_s. ref.ok = false if it failed.
maxStd_mm = 10;      % more head movement than this -> measure again
P = []; Q = [];
t = tic;
while toc(t) < dur_s
    while MyClient.GetFrame().Result ~= ViconDataStreamSDK.DotNET.Result.Success; end
    T = MyClient.GetSegmentGlobalTranslation(Subj, Seg);
    R = MyClient.GetSegmentGlobalRotationQuaternion(Subj, Seg);
    if ~T.Occluded && ~R.Occluded
        P(end+1, :) = [T.Translation(1) T.Translation(2) T.Translation(3)];        %#ok<AGROW>
        Q(end+1, :) = [R.Rotation(1) R.Rotation(2) R.Rotation(3) R.Rotation(4)];   %#ok<AGROW> [x y z w]
    end
end
ref.nFrames    = size(P, 1);
ref.fwdLocal   = fwdLocal(:);
ref.ok         = false;
ref.failReason = '';
if ref.nFrames < 10
    ref.failReason = sprintf('Brillerne kunne ikke ses (%d frames) – tryk ENTER igen', ref.nFrames);
    return;
end
ref.posStd = std(P, 0, 1);
if max(ref.posStd) > maxStd_mm
    ref.failReason = sprintf('Hovedet bevægede sig (%.0f mm) – tryk ENTER igen', max(ref.posStd));
    return;
end
% Average quaternion (same hemisphere first: q and -q are the same rotation)
Q  = Q .* sign(Q * Q(1, :)');
q0 = mean(Q, 1);  q0 = q0 / norm(q0);
Rfull = quatToRot(q0);
% Upright reference: lab vertical + the head's horizontal facing direction
fwd  = Rfull * fwdLocal(:);  fwd(3) = 0;  fwd = fwd / norm(fwd);
up   = [0; 0; 1];
left = cross(up, fwd);
ref.p0        = mean(P, 1)';          % mm, lab coordinates
ref.q0        = q0;                   % [x y z w]
ref.R0        = [fwd left up];        % columns = new x (forward), y (left), z (up) in lab coords
ref.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
ref.ok        = true;
fprintf('Reference gemt (%d frames, std %.1f/%.1f/%.1f mm).\n', ref.nFrames, ref.posStd);
end
function R = quatToRot(q)
% q = [x y z w] (Vicon SDK order) -> 3x3 rotation matrix (segment -> lab)
x = q(1); y = q(2); z = q(3); w = q(4);
R = [1-2*(y^2+z^2)  2*(x*y-z*w)    2*(x*z+y*w);
    2*(x*y+z*w)    1-2*(x^2+z^2)  2*(y*z-x*w);
    2*(x*z-y*w)    2*(y*z+x*w)    1-2*(x^2+y^2)];
end
%% Files / hardware
function f = uniqueFilename(f)
% Safety net: if the file already exists, append _v2, _v3, ... so nothing
% is ever overwritten.
[p, n, e] = fileparts(f);
k = 2;
while exist(f, 'file')
    f = fullfile(p, sprintf('%s_v%d%s', n, k, e));
    k = k + 1;
end
end
function micBuf = playTone(AP, toneSig, nToneFrames, samplesPerFrame, recordMics, micReaders, micBuf)
% Plays the start/end tone (all loudspeakers) frame by frame and, if the
% mics are running, records them into micBuf ([Mic11 Mic12]).
for k = 1:nToneFrames
    idx = (k-1)*samplesPerFrame+1 : k*samplesPerFrame;
    AP(toneSig(idx, :));
    if recordMics
        fA = micReaders{1}();   % Analog: ch1 = Mic11, ch2 = Mic12
        micBuf(idx, :) = single(fA(:, 1:2));
    end
end
end
function shutdownHardware(MyClient, AP, TransmitMulticast)
try
    if TransmitMulticast; MyClient.StopTransmittingMulticast(); end
    MyClient.Disconnect();
catch
end
try release(AP); catch; end
disp('Vicon afbrudt og lydkort frigivet.');
end

%% Participant window 
function fig = buildCueWindow(monitor, fullscreen, textSize)
% The layout below is designed in pixels for a 480 x 700 window. At the end
% everything is converted to relative units and the window is moved to
% screen 'monitor' and (optionally) made full screen; fonts are scaled to
% the screen size and multiplied by textSize (cueTextSize in the settings).
% Font sizes are larger than in the first pilot version (readability on the
% tablet); the boxes are made taller so the bigger text still fits.
if nargin < 1 || isempty(monitor);    monitor    = 1;    end
if nargin < 2 || isempty(fullscreen); fullscreen = true; end
if nargin < 3 || isempty(textSize);   textSize   = 1;    end
fig = figure( ...
    'Name',        'Cue Screen', ...
    'NumberTitle', 'off', ...
    'MenuBar',     'none', ...
    'ToolBar',     'none', ...
    'Color',       [1 1 1], ...
    'Position',    [200 80 480 700], ...
    'Resize',      'on', ...
    'WindowStyle', 'normal', ...
    'KeyPressFcn', @onKeyPress);
% Initialise appdata used by the key-press callback
setappdata(fig, 'triggerPressed', false);
setappdata(fig, 'triggerRTs',     []);     % array of all reaction times
setappdata(fig, 'isRecording',    false);
setappdata(fig, 'recStartTime',   uint64(0));
% --- Block badge panel + label ---
uipanel(fig, ...
    'Units',           'pixels', ...
    'Position',        [15 618 450 72], ...
    'BorderType',      'line', ...
    'HighlightColor',  [0 0 0], ...
    'BackgroundColor', [1 1 1], ...
    'Tag',             'blockPanel');
uicontrol(fig, ...
    'Style',               'text', ...
    'Units',               'pixels', ...
    'Position',            [18 621 444 66], ...
    'String',              'Blok 1 af 6  |  Optagelse 1 af 8', ...
    'FontSize',            21, ...
    'FontWeight',          'bold', ...
    'HorizontalAlignment', 'center', ...
    'BackgroundColor',     [1 1 1], ...
    'ForegroundColor',     [0.1 0.1 0.1], ...
    'Tag',                 'blockLabel');
% --- Instruction label ---
uicontrol(fig, ...
    'Style',               'text', ...
    'Units',               'pixels', ...
    'Position',            [15 512 450 98], ...
    'String',              'Ret opmærksomheden mod', ...
    'FontSize',            30, ...
    'HorizontalAlignment', 'center', ...
    'BackgroundColor',     [1 1 1], ...
    'ForegroundColor',     [0.15 0.15 0.15], ...
    'Tag',                 'instruction');
% --- Target label (tag kept as 'condition') ---
uicontrol(fig, ...
    'Style',               'text', ...
    'Units',               'pixels', ...
    'Position',            [15 405 450 105], ...
    'String',              '', ...
    'FontSize',            54, ...
    'FontWeight',          'bold', ...
    'HorizontalAlignment', 'center', ...
    'BackgroundColor',     [1 1 1], ...
    'ForegroundColor',     [0.05 0.05 0.05], ...
    'Tag',                 'condition');
% --- Trigger word header (hidden during the head reference) ---
uicontrol(fig, ...
    'Style',               'text', ...
    'Units',               'pixels', ...
    'Position',            [15 357 450 44], ...
    'String',              'Tryk  ENTER  når du hører:', ...
    'FontSize',            22, ...
    'HorizontalAlignment', 'center', ...
    'BackgroundColor',     [1 1 1], ...
    'ForegroundColor',     [0.30 0.30 0.30], ...
    'Tag',                 'triggerHeader');
% --- Trigger word display (blue box) ---
uicontrol(fig, ...
    'Style',               'text', ...
    'Units',               'pixels', ...
    'Position',            [50 282 380 70], ...
    'String',              '', ...
    'FontSize',            38, ...
    'FontWeight',          'bold', ...
    'HorizontalAlignment', 'center', ...
    'BackgroundColor',     [0.91 0.95 1.00], ...
    'ForegroundColor',     [0.05 0.30 0.70], ...
    'Tag',                 'triggerWord');
% --- Trigger response indicator ---
uicontrol(fig, ...
    'Style',               'text', ...
    'Units',               'pixels', ...
    'Position',            [15 218 450 60], ...
    'String',              '', ...
    'FontSize',            19, ...
    'FontWeight',          'bold', ...
    'HorizontalAlignment', 'center', ...
    'BackgroundColor',     [1 1 1], ...
    'ForegroundColor',     [0.08 0.58 0.08], ...
    'Tag',                 'triggerStatus');
% --- Progress percentage label ---
uicontrol(fig, ...
    'Style',               'text', ...
    'Units',               'pixels', ...
    'Position',            [20 184 300 30], ...
    'String',              '0% færdiggjort', ...
    'FontSize',            16, ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor',     [1 1 1], ...
    'ForegroundColor',     [0.30 0.30 0.30], ...
    'Tag',                 'pctLabel');
% --- Progress bar (axes + green patch) ---
ax = axes(fig, ...
    'Units',    'pixels', ...
    'Position', [20 150 440 30], ...
    'XLim',     [0 1], ...
    'YLim',     [0 1], ...
    'XTick',    [], ...
    'YTick',    [], ...
    'Box',      'on', ...
    'Color',    [0.91 0.91 0.91], ...
    'LineWidth', 1.2, ...
    'XColor',   [0.7 0.7 0.7], ...
    'YColor',   [0.7 0.7 0.7], ...
    'Tag',      'progressAxes');
patch(ax, [0 0 0 0], [0 0 1 1], [0.20 0.78 0.35], ...
    'EdgeColor', 'none', 'Tag', 'progressPatch');
% --- Status / proceed button ---
uicontrol(fig, ...
    'Style',           'text', ...
    'Units',           'pixels', ...
    'Position',        [15 22 450 112], ...
    'String',          'TRYK  ENTER  FOR AT STARTE', ...
    'FontSize',        28, ...
    'FontWeight',      'bold', ...
    'BackgroundColor', [0.20 0.78 0.35], ...
    'ForegroundColor', [1 1 1], ...
    'Tag',             'proceedBtn');
placeOnScreen(fig, monitor, fullscreen, textSize);
end
function placeOnScreen(fig, monitor, fullscreen, textSize)
% Moves the cue window to the chosen screen and scales the whole layout.
if nargin < 4 || isempty(textSize); textSize = 1; end
mons = get(0, 'MonitorPositions');            % one row per screen [x y w h]
fprintf('Skærme fundet af MATLAB (nr: x, y, bredde, højde):\n');
for i = 1:size(mons, 1)
    fprintf('  %d: %s\n', i, mat2str(mons(i, :)));
end
if ischar(monitor) || isstring(monitor)
    switch lower(char(monitor))
        case 'rightmost'; [~, monitor] = max(mons(:, 1));
        case 'leftmost';  [~, monitor] = min(mons(:, 1));
        otherwise; error('cueMonitor must be a number, ''rightmost'' or ''leftmost''.');
    end
end
fprintf('Deltagervindue åbnes på skærm %d.\n', monitor);
if monitor > size(mons, 1)
    warning('Skærm %d findes ikke (%d skærm(e) fundet) - bruger skærm %d.', ...
        monitor, size(mons, 1), size(mons, 1));
    monitor = size(mons, 1);
end
m = mons(monitor, :);
if fullscreen
    % Fonts follow the screen size. min() keeps the text inside its boxes
    % on a portrait screen too (the layout is designed 480 wide x 700 high).
    scale = min(m(4) / 700, m(3) / 480);
else
    scale = 1;
end
scale = scale * textSize;
setappdata(fig, 'fontScale', scale);
% All elements -> relative units so they stretch with the window
kids = allchild(fig);
for i = 1:numel(kids)
    if isprop(kids(i), 'Units'); set(kids(i), 'Units', 'normalized'); end
    if isprop(kids(i), 'FontSize')
        set(kids(i), 'FontSize', get(kids(i), 'FontSize') * scale);
    end
end
% Window centred on the chosen screen, then full screen there
set(fig, 'Units', 'pixels', 'Position', [m(1) + (m(3) - 480) / 2, ...
    m(2) + (m(4) - 700) / 2, 480, 700]);
if fullscreen
    set(fig, 'WindowState', 'fullscreen');
end
drawnow;
end
function p = px2norm(p)
% Pixel position in the 480 x 700 design -> relative position
p = p ./ [480 700 480 700];
end
function onKeyPress(fig, evt)
% Fires on every key press. Appends a new reaction time for each ENTER during recording.
if isEnterKey(evt.Key, evt.Character)
    if isappdata(fig, 'isRecording') && getappdata(fig, 'isRecording')
        t0  = getappdata(fig, 'recStartTime');
        rt  = toc(t0);
        rts = getappdata(fig, 'triggerRTs');
        rts(end+1) = rt;
        setappdata(fig, 'triggerRTs',     rts);
        setappdata(fig, 'triggerPressed', true);
        setLabel(fig, 'triggerStatus', sprintf('✓  %d svar registreret', numel(rts)));
    end
end
end
function action = waitForStartOrRedo(fig, canRedo, lockout_s)
% Blocks until ENTER (start recording -> 'start') or BACKSPACE (redo
% previous recording -> 'redo') is pressed. BACKSPACE is only accepted
% when canRedo is true; otherwise a short note is shown and the function
% keeps waiting. Presses within lockout_s seconds are ignored (so a late
% trigger press from the previous recording cannot start this one).
if nargin < 3 || isempty(lockout_s); lockout_s = 0; end
figure(fig);
drawnow;                           % flush key presses queued during the recording
t0 = tic;
while true
    if waitforbuttonpress() == 1   % 1 = key press (0 = mouse click)
        if toc(t0) < lockout_s; continue; end
        key = get(fig, 'CurrentKey');
        ch  = get(fig, 'CurrentCharacter');
        if isEnterKey(key, ch)
            action = 'start';
            return;
        elseif isBackspaceKey(key, ch)
            action = 'redo';
            if canRedo; return; end
            setLabel(fig, 'triggerStatus', 'Ingen tidligere optagelse at tage om');
            set(findobj(fig, 'Tag', 'triggerStatus'), 'ForegroundColor', [0.80 0.10 0.10]);
            drawnow;
        end
    end
end
end
function yes = confirmRedo(fig, line1, line2, line2Size, lockout_s)
% Red safety screen, by default "Tag seneste optagelse om - Er du sikker?".
% line1 / line2 / line2Size (font size of line2) give other texts, e.g. the
% gaze data warning. ENTER = no, BACKSPACE = yes. Every other key is ignored,
% and so is any key within lockout_s seconds. The normal look of the
% window is restored afterwards (the caller redraws the cue screen).
if nargin < 5 || isempty(lockout_s); lockout_s = 0; end
red   = [0.80 0.08 0.08];
white = [1 1 1];
props = {'BackgroundColor', 'ForegroundColor', 'String', 'FontSize', 'Visible'};
h     = findobj(fig, 'Type', 'uicontrol');      % all text fields
hp    = findobj(fig, 'Type', 'uipanel');        % block badge frame
old   = get(h, props);
oldP  = get(hp, {'BackgroundColor', 'HighlightColor'});
oldFigColor = get(fig, 'Color');
fsc   = getappdata(fig, 'fontScale');  if isempty(fsc); fsc = 1; end
if nargin < 2 || isempty(line1);     line1     = 'Tag seneste optagelse om'; end
if nargin < 3 || isempty(line2);     line2     = 'Er du sikker?';            end
if nargin < 4 || isempty(line2Size); line2Size = 40;                         end
set(fig, 'Color', red);
set(h,  'BackgroundColor', red, 'ForegroundColor', white);
set(hp, 'BackgroundColor', red, 'HighlightColor', white);
setLabel(fig, 'instruction',   line1);
setLabel(fig, 'condition',     line2);
set(findobj(fig, 'Tag', 'condition'), 'FontSize', line2Size * fsc);
setLabel(fig, 'triggerHeader', '');
set(findobj(fig, 'Tag', 'triggerWord'), 'Visible', 'off');
setLabel(fig, 'triggerStatus', '');
set(findobj(fig, 'Tag', 'proceedBtn'), 'String', 'ENTER = NEJ      BACKSPACE = JA', ...
    'BackgroundColor', [0.55 0.02 0.02], 'ForegroundColor', white);
figure(fig);
drawnow;
yes = false;
t0  = tic;
while true
    if waitforbuttonpress() == 1
        if toc(t0) < lockout_s; continue; end
        key = get(fig, 'CurrentKey');
        ch  = get(fig, 'CurrentCharacter');
        if isEnterKey(key, ch);     yes = false; break; end
        if isBackspaceKey(key, ch); yes = true;  break; end
    end
end
% Restore the normal colours / fonts
set(h,  props, old);
set(hp, {'BackgroundColor', 'HighlightColor'}, oldP);
set(fig, 'Color', oldFigColor);
drawnow;
end
function showBlock(fig, blockIdx, totalBlocks, targetText, pct, recIdx, recsPerBlock, triggerWord, isRedo)
% Participant view: block/recording counter, target, trigger word.
% The condition itself is never shown. isRedo = true -> marked as a redo.
if nargin < 9; isRedo = false; end
setLabel(fig, 'blockLabel', sprintf('Blok %d af %d  |  Optagelse %d af %d', ...
    blockIdx, totalBlocks, recIdx, recsPerBlock));
setLabel(fig, 'instruction',   'Ret opmærksomheden mod');
setLabel(fig, 'condition',     targetText);
setLabel(fig, 'triggerHeader', 'Tryk  ENTER  når du hører:');
setLabel(fig, 'triggerWord',   triggerWord);
setLabel(fig, 'triggerStatus', '');   % clear previous response indicator
set(findobj(fig, 'Tag', 'triggerStatus'), 'ForegroundColor', [0.08 0.58 0.08]);
if isRedo
    setLabel(fig, 'triggerStatus', 'Omtagning af seneste optagelse');
    set(findobj(fig, 'Tag', 'triggerStatus'), 'ForegroundColor', [0.80 0.10 0.10]);
end
updateProgress(fig, pct);
setRecordingState(fig, false);
figure(fig);
drawnow;
end
function updateProgress(fig, pct)
pct = max(0, min(100, pct));
p = findobj(fig, 'Tag', 'progressPatch');
if ~isempty(p)
    set(p, 'XData', [0, pct/100, pct/100, 0]);
end
lbl = findobj(fig, 'Tag', 'pctLabel');
if ~isempty(lbl)
    set(lbl, 'String', sprintf('%.0f%% færdiggjort', pct));
end
drawnow limitrate;   % max ~20 Hz redraw, also processes key callbacks
end
function setLabel(fig, tag, str)
h = findobj(fig, 'Tag', tag);
if ~isempty(h); set(h, 'String', str); end
end
function setRecordingState(fig, isRecording)
btn = findobj(fig, 'Tag', 'proceedBtn');
if isempty(btn); return; end
if isRecording
    set(btn, ...
        'String',          'Optagelse i gang...', ...
        'BackgroundColor', [0.85 0.15 0.15], ...
        'ForegroundColor', [1 1 1]);
else
    set(btn, ...
        'String',          'TRYK  ENTER  FOR AT STARTE', ...
        'BackgroundColor', [0.20 0.78 0.35], ...
        'ForegroundColor', [1 1 1]);
end
drawnow;
end

%% Post-experiment questionnaire (SEVQuest) 
function Q = sevQuestions()
% SEVQuest - Subjective Ecological Validity Questionnaire, items SEVQ01-10
% (7-point scale). Ermert, Dewi, Smeds & Fels (2026), doi:10.5281/zenodo.21062865,
% CC BY-SA 4.0. Danish translation. The open-text items (Hvorfor?, SEVQ11-13)
% are not included. Columns: Code | Category | Question text.
Q = { ...
    'SEVQ01', 'Individ', ...
    'Hvor fortrolig er du i dit daglige liv med den situation, der blev præsenteret i forsøget?'; ...
    'SEVQ02', 'Omgivelser', ...
    'Hvor lig var situationen i forsøget sammenlignelige situationer i det virkelige liv?'; ...
    'SEVQ03', 'Stimuluskilder', ...
    'Hvor lig var de lyde, du hørte i forsøget, lyde fra sammenlignelige situationer, du har oplevet i det virkelige liv?'; ...
    'SEVQ04', 'Stimuluskilder', ...
    'Hvor lig var det, du så i forsøget, synsindtryk fra sammenlignelige situationer i det virkelige liv?'; ...
    'SEVQ05', 'Opgave', ...
    'Hvor sammenlignelig var opgaven i forsøget med de udfordringer og opgaver, du møder i hverdagen?'; ...
    'SEVQ06', 'Deltagelseskontekst', ...
    'Hvor godt tilpas følte du dig under forsøget?'; ...
    'SEVQ07', 'Deltagelseskontekst', ...
    'I hvilken grad mener du, at din præstation i dette forsøg afspejler dine evner i virkelige situationer?'; ...
    'SEVQ08', 'Deltagelseskontekst', ...
    'Hvor naturligt synes du selv, at du opførte dig under forsøget?'; ...
    'SEVQ09', 'Deltagelseskontekst', ...
    'Hvor meget anstrengte du dig for at løse opgaven?'; ...
    'SEVQ10', 'Generelt', ...
    'I hvilken grad mener du, at resultaterne af dette forsøg kan overføres til virkelige situationer?'};
end
function answers = runQuestionnaire(fig, resultsFile, lockout_s)
% Shows the SEVQuest questions one by one in the cue window. The participant
% types 1-7 to answer (number row or numpad); Backspace goes back one question.
% Every answer is written immediately to the sheet 'Spoergeskema'.
% lockout_s: Enter presses right after the last recording are ignored.
if nargin < 3; lockout_s = 0; end
Q       = sevQuestions();
nQ      = size(Q, 1);
answers = nan(nQ, 1);
rts     = nan(nQ, 1);
stamps  = repmat({''}, nQ, 1);
saved   = questionnaireLayout(fig);                   % switch layout
restore = onCleanup(@() questionnaireLayout(fig, saved)); %#ok<NASGU>
writeQuestionnaire(resultsFile, Q, answers, rts, stamps);   % empty sheet first
% Intro screen
setLabel(fig, 'blockLabel',    'Spørgeskema');
setLabel(fig, 'instruction',   sprintf(['Til sidst vil vi gerne bede dig besvare %d korte ' ...
    'spørgsmål om forsøget.\n\nSvar ved at taste et tal fra 1 til 7.'], nQ));
setLabel(fig, 'triggerStatus', '');
set(findobj(fig, 'Tag', 'proceedBtn'), 'String', 'TRYK  ENTER  FOR AT STARTE', ...
    'BackgroundColor', [0.10 0.45 0.85], 'ForegroundColor', [1 1 1]);
updateProgress(fig, 0);
waitForEnter(fig, lockout_s);
k = 1;
while k <= nQ
    showQuestion(fig, k, nQ, Q{k, 3}, answers(k));
    t0 = tic;
    [key, ch] = waitForKey(fig);
    if isempty(key) && isempty(ch)
        warning('Spørgeskemavinduet blev lukket ved spørgsmål %d.', k);
        break;
    end
    if isscalar(ch) && ch >= '1' && ch <= '7'
        answers(k) = double(ch) - double('0');
        rts(k)     = toc(t0);
        stamps{k}  = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
        writeQuestionnaire(resultsFile, Q, answers, rts, stamps);
        fprintf('  %s: %d  (%.1f s)\n', Q{k, 1}, answers(k), rts(k));
        set(findobj(fig, 'Tag', 'proceedBtn'), 'String', sprintf('✓  Dit svar: %d', answers(k)), ...
            'BackgroundColor', [0.10 0.55 0.25]);
        drawnow;
        pause(0.6);                       % short visual confirmation
        k = k + 1;
    elseif strcmp(key, 'backspace') && k > 1
        k = k - 1;
    end
end
if isvalid(fig); updateProgress(fig, 100); end
end
function showQuestion(fig, k, nQ, text, prevAnswer)
setLabel(fig, 'blockLabel',    sprintf('Spørgsmål %d af %d', k, nQ));
setLabel(fig, 'instruction',   text);
parts = {};
if ~isnan(prevAnswer)
    parts{end+1} = sprintf('Nuværende svar: %d', prevAnswer);
end
if k > 1
    parts{end+1} = 'Backspace = forrige spørgsmål';
end
setLabel(fig, 'triggerStatus', strjoin(parts, '   |   '));
set(findobj(fig, 'Tag', 'proceedBtn'), 'String', 'TAST ET TAL FRA 1 TIL 7', ...
    'BackgroundColor', [0.20 0.78 0.35], 'ForegroundColor', [1 1 1]);
updateProgress(fig, 100 * (k - 1) / nQ);
figure(fig);
drawnow;
end
function saved = questionnaireLayout(fig, saved)
% questionnaireLayout(fig)        -> switches the cue window to the
%                                    questionnaire layout, returns old values
% questionnaireLayout(fig, saved) -> restores the old layout
tags  = {'instruction', 'condition', 'triggerHeader', 'triggerWord', 'triggerStatus'};
props = {'Position', 'FontSize', 'FontWeight', 'ForegroundColor', 'Visible', 'String'};
if nargin == 2
    if ~isvalid(fig); return; end
    for i = 1:numel(tags)
        h = findobj(fig, 'Tag', tags{i});
        if ~isempty(h); set(h, props, saved.(tags{i})); end
    end
    return;
end
saved = struct();
for i = 1:numel(tags)
    saved.(tags{i}) = get(findobj(fig, 'Tag', tags{i}), props);
end
fs = getappdata(fig, 'fontScale');
if isempty(fs); fs = 1; end
set(findobj(fig, 'Tag', 'instruction'), 'Position', px2norm([15 375 450 238]), ...
    'FontSize', 24 * fs, 'FontWeight', 'normal', 'String', '');
set(findobj(fig, 'Tag', 'condition'), 'Position', px2norm([15 310 450 60]), ...
    'FontSize', 32 * fs, 'FontWeight', 'bold', 'ForegroundColor', [0.05 0.05 0.05], ...
    'String', '1    2    3    4    5    6    7');
set(findobj(fig, 'Tag', 'triggerHeader'), 'Position', px2norm([15 258 450 48]), ...
    'FontSize', 17 * fs, 'String', '1 = slet ikke          7 = i meget høj grad');
set(findobj(fig, 'Tag', 'triggerWord'), 'Visible', 'off', 'String', '');
set(findobj(fig, 'Tag', 'triggerStatus'), 'Position', px2norm([15 214 450 40]), ...
    'FontSize', 15 * fs, 'FontWeight', 'normal', 'ForegroundColor', [0.40 0.40 0.40], ...
    'String', '');
drawnow;
end
function [key, ch] = waitForKey(fig)
% Blocks until a key is pressed in the cue window. Empty outputs = window closed.
key = '';  ch = '';
if ~isvalid(fig); return; end
figure(fig);
drawnow;
while isvalid(fig)
    try
        r = waitforbuttonpress();
    catch
        return;                     % window was closed
    end
    if r == 1                       % 1 = key press (0 = mouse click)
        key = get(fig, 'CurrentKey');
        ch  = get(fig, 'CurrentCharacter');
        return;
    end
end
end
function writeQuestionnaire(resultsFile, Q, answers, rts, stamps)
% One row per question; empty cells = not answered (yet).
C = {'Nr', 'Kode', 'Kategori', 'Spoergsmaal', 'Svar_1til7', 'Svartid_sek', 'Tidspunkt'};
for k = 1:size(Q, 1)
    a = answers(k);  r = rts(k);
    if isnan(a); a = ''; end
    if isnan(r); r = ''; end
    C(end+1, :) = {k, Q{k, 1}, Q{k, 2}, Q{k, 3}, a, r, stamps{k}}; %#ok<AGROW>
end
writecell(C, resultsFile, 'Sheet', 'Spoergeskema');
end