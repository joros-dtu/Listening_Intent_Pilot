%% =========================================================
%  VISUALIZE + PLAY BACK ONE RECORDING
%  Load a .mat file saved by experiment_script_pilot and plot:
%    1. Head translation (x/y/z) over time
%    2. Head rotation (yaw/pitch/roll) over time
%    3. Gaze direction over time
%    4. Recorded microphone signal (the one being played back)
%    5. Audio timeline: soundscape + distractors + trigger responses
%  ...and play back the recorded mic audio with a moving playhead,
%  so you can hear whether each trigger response lines up with the word.
%
%  Distractors (condition 3) are labelled with the azimuth of the
%  loudspeaker they were played from (see lsAzimuth_deg below). The console
%  summary also prints the head yaw at distractor onset and the distractor
%  angle relative to the head.
%
%  By default the TARGET facilitator's mic is opened automatically: the
%  recording's Target ('A'/'B') is matched against micFacilitator (falling
%  back to micDescription / TargetSide for older recordings). You can still
%  switch channel with the drop-down; the target mic is labelled [TARGET].
%
%  Controls (buttons at the bottom, or keyboard):
%    Space          play / pause
%    Left / Right   jump -2 s / +2 s
%    Up / Down      previous / next trigger response (starts preRoll s before it)
%    f              toggle "follow" (scrolling window around the playhead)
%    Click a plot   jump to that time
%
%  Annotating trigger words (while listening):
%    m              mark a trigger word at the playhead
%    Delete/Backsp  delete the mark nearest the playhead (within 3 s)
%    t              cycle the nearest mark: auto -> HIT -> MISS -> auto
%    s              save the annotations into the .mat file
%  A word counts as HIT when a trigger response falls within hitWindow_s
%  after the mark, otherwise MISS (unless overridden with t). Responses not
%  matched to any word are counted as false alarms. Green = hit, red = miss.
%  Saving adds these variables to the recording (a one-time backup copy
%  <name>_orig.mat is written first):
%    TriggerWordTimes, TriggerWordHit, TriggerWordResponseRT,
%    TriggerWordLatency, TriggerFalseAlarmRTs, TriggerAnnotation
%% =========================================================
%% << EDIT HERE >> ------------------------------------------
matFile = '';   % leave empty to open a file picker, or paste a full path:
% matFile = 'vicon_recordings\recording_test_..._.mat';
% Head axes of the TobiiGlassesP3 segment, in the segment's own coordinates.
% From the pilot data: the gaze points along segment +z, and +y is up.
% (The pilot script used headFwdLocal = [1 0 0], which is the participant's
%  LEFT, so the saved HeadReference.R0 is rotated ~90 deg. It is rebuilt here
%  from HeadReference.q0, so old recordings are still usable.)
headFwdLocal = [0 0 1];
headUpLocal  = [0 1 0];
% Playback
playChannel  = 'target';  % 'target' = mic of the target facilitator (automatic),
% or a MicData column number to force a specific mic
preRoll_s    = 2;     % "prev/next response" starts this many seconds before the response
followWin_s  = 10;    % width of the scrolling window in follow mode
% Annotation
hitWindow_s  = [0 3]; % a response within [min max] s after the marked word = HIT
markOffset_s = 0;     % subtracted from the playhead when you press m (e.g. 0.2 to
% compensate for your own key-press delay)
% ---- Azimuth convention (used for ALL angles shown: yaw, gaze, distractors, target)
% 0 = straight ahead (head reference), NEGATIVE = LEFT, POSITIVE = RIGHT.
% Loudspeaker azimuths (deg), index = d.Sounds(s).Loudspeaker (channel = 30 + LS).
% Derived from AP.ChannelMapping = 30 + [6 4 2 22 20 18] -> [-90 -60 -30 30 60 90]:
% LS k = -15*k deg (LS 24 = front, LS 12 = behind).
lsAzimuth_deg = mod(-15 * (1:24) + 180, 360) - 180;
% Target talker azimuth, relative to the participant's head reference
targetAz_deg = struct('left', -22.5, 'right', +22.5);
%% ----------------------------------------------------------
if isempty(matFile)
    [f, p] = uigetfile('*.mat', 'Select a recording .mat file');
    if isequal(f, 0); disp('Cancelled.'); return; end
    matFile = fullfile(p, f);
end
d = load(matFile);
fprintf('Loaded: %s\n', matFile);
fprintf('  Condition %d (%s)  |  Target: %s  |  Trigger word: "%s"\n', ...
    d.Condition, d.ConditionName, d.Target, d.TriggerWord);
fprintf('  Duration: %.1f s  |  Vicon frames: %d\n', d.RecordingDuration, numel(d.FrameTime));
% Existing annotations (from an earlier session) are loaded so you can continue
ann = struct('times', zeros(1,0), 'override', zeros(1,0), 'h', gobjects(0), 'dirty', false);
if isfield(d, 'TriggerWordTimes') && ~isempty(d.TriggerWordTimes)
    ann.times    = d.TriggerWordTimes(:)';
    ann.override = nan(size(ann.times));
    if isfield(d, 'TriggerAnnotation') && isfield(d.TriggerAnnotation, 'Override') ...
            && numel(d.TriggerAnnotation.Override) == numel(ann.times)
        ann.override = d.TriggerAnnotation.Override(:)';
    end
    fprintf('  Loaded %d existing trigger-word annotations.\n', numel(ann.times));
end
if ~isfield(d, 'MicData') || isempty(d.MicData)
    error('This recording has no MicData, so there is nothing to play back.');
end
fs = double(d.fs);
if isfield(d, 'micNames'); micNames = cellstr(d.micNames); else
    micNames = arrayfun(@(k) sprintf('Mic %d', k), 1:size(d.MicData,2), 'UniformOutput', false); end
if isfield(d, 'micDescription'); micDesc = cellstr(d.micDescription); else; micDesc = micNames; end
% ---- Pick the target facilitator's mic ----
tgtCh = findTargetMic(d, size(d.MicData, 2));
if ischar(playChannel) || isstring(playChannel)        % 'target'
    if isempty(tgtCh)
        warning('Could not identify the target (%s) mic in this file - playing channel 1.', d.Target);
        playChannel = 1;
    else
        playChannel = tgtCh;
    end
end
playChannel = min(max(1, playChannel), size(d.MicData, 2));
if ~isempty(tgtCh)
    fprintf('  Target mic: channel %d (%s, %s)\n', tgtCh, micNames{tgtCh}, micDesc{tgtCh});
end
t = d.FrameTime(:);   % time axis from Vicon frames
%% ---- Figure layout ----------------------------------------
fig = figure('Name', sprintf('Recording — Cond %d — Target %s — "%s"', ...
    d.Condition, d.Target, d.TriggerWord), ...
    'NumberTitle', 'off', 'Color', 'w', 'Units', 'normalized', 'Position', [0.05 0.05 0.85 0.85]);
plotPanel = uipanel(fig, 'Units', 'normalized', 'Position', [0 0.11 1 0.89], ...
    'BorderType', 'none', 'BackgroundColor', 'w');
ctrlPanel = uipanel(fig, 'Units', 'normalized', 'Position', [0 0 1 0.11], ...
    'BorderType', 'none', 'BackgroundColor', [0.94 0.94 0.94]);
tl = tiledlayout(plotPanel, 5, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
%% ---- Express everything relative to the head reference ----
% Reference frame (upright): x = forward, y = left, z = up, origin = p0.
ref = d.HeadReference;
H0  = headFrame(quatToRot(ref.q0), headFwdLocal, headUpLocal);   % head axes at reference
fwd0 = H0(:,1); fwd0(3) = 0; fwd0 = fwd0 / norm(fwd0);
R0  = [fwd0, cross([0;0;1], fwd0), [0;0;1]];                       % upright reference
nF = size(d.GlobalTranslation, 1);
Trel = (d.GlobalTranslation - ref.p0(:)') * R0;      % [forward left up]
ypr = nan(nF, 3);
for k = 1:nF
    q = d.GlobalRotationQuaternion(k, :);
    if any(isnan(q)); continue; end
    M = H0' * headFrame(quatToRot(q), headFwdLocal, headUpLocal);
    ypr(k,1) = -atan2d(M(2,1), M(1,1));                % yaw,   + = turn right
    ypr(k,2) = asind(max(-1, min(1, M(3,1))));         % pitch, + = nose up
    ypr(k,3) = atan2d(M(3,2), M(3,3));                 % roll,  + = right ear down
end
G = d.EyeTrackerGlobalGazeVector;
G(all(G == 0, 2), :) = NaN;                            % (0,0,0) = lost tracking
G = G ./ vecnorm(G, 2, 2);
Grel  = G * R0;
gazeAz = -atan2d(Grel(:,2), Grel(:,1));               % + = right
gazeEl = asind(Grel(:,3));
% ---- Target talker side -> azimuth ----
tgtSide = '';
if isfield(d, 'TargetSide') && ~isempty(d.TargetSide)
    tgtSide = lower(strtrim(char(d.TargetSide)));
elseif isfield(d, 'Target') && isfield(d, ['Facilitator' upper(char(d.Target)) '_Side'])
    tgtSide = lower(strtrim(char(d.(['Facilitator' upper(char(d.Target)) '_Side']))));
end
if isfield(targetAz_deg, tgtSide)
    tgtAz = targetAz_deg.(tgtSide);
    fprintf('  Target %s sits %s -> azimuth %+.1f°\n', d.Target, tgtSide, tgtAz);
else
    tgtAz = NaN;
    warning('Could not find the target side in this file - no target line drawn.');
end
%% ---- 1. Head translation ----------------------------------
ax1 = nexttile(tl);
plot(ax1, t, Trel(:,1), 'r', t, Trel(:,2), 'g', t, Trel(:,3), 'b', 'LineWidth', 1.2);
legend(ax1, 'Forward','Left','Up', 'Location','best', 'AutoUpdate','off');
ylabel(ax1, 'mm'); title(ax1, 'Head Translation (relative to reference)'); grid(ax1, 'on');
addEventLines(ax1, d);
%% ---- 2. Head rotation -------------------------------------
ax2 = nexttile(tl);
plot(ax2, t, ypr(:,1), 'r', t, ypr(:,2), 'g', t, ypr(:,3), 'b', 'LineWidth', 1.2);
legend(ax2, 'Yaw (+right)','Pitch (+up)','Roll (+right ear down)', 'Location','best', 'AutoUpdate','off');
addTargetLine(ax2, tgtAz, d.Target, tgtSide);
ylabel(ax2, 'Angle (°)'); title(ax2, 'Head Rotation (relative to reference)'); grid(ax2, 'on');
addEventLines(ax2, d);
%% ---- 3. Gaze direction (azimuth / elevation) ---------------
ax3 = nexttile(tl);
plot(ax3, t, gazeAz, 'k', t, gazeEl, 'm', 'LineWidth', 1.2);
% ylim(ax3, [--45 45]); yticks(ax3, -180:45:180);
ylabel(ax3, 'Angle (°)');
legend(ax3, 'Azimuth (+right)', 'Elevation (+up)', 'Location', 'best', 'AutoUpdate', 'off');
addTargetLine(ax3, tgtAz, d.Target, tgtSide);
title(ax3, 'Gaze Direction (relative to reference forward)'); grid(ax3, 'on');
addEventLines(ax3, d);
%% ---- 4. Recorded microphone signal ------------------------
axMic = nexttile(tl);
hMic = plot(axMic, nan, nan, 'Color', [0.3 0.3 0.3]);
ylim(axMic, [-1 1]); ylabel(axMic, 'norm.'); grid(axMic, 'on');
addEventLines(axMic, d);
%% ---- 5. Audio event timeline ------------------------------
ax4 = nexttile(tl);
hold(ax4, 'on');
yPos    = 1;
colors  = struct('Soundscape', [0.2 0.6 1], 'Distraktor', [1 0.4 0.2]);
names   = struct('Soundscape', 'Soundscape', 'Distraktor', 'Distractor');
for s = 1:numel(d.Sounds)
    snd = d.Sounds(s);
    if isfield(colors, snd.Type); col = colors.(snd.Type); else; col = [0.5 0.5 0.5]; end
    if strcmp(snd.Type, 'Distraktor')
        text(ax4, snd.Onset_s + snd.Duration_s, yPos, [' ' lsAngleStr(snd.Loudspeaker, lsAzimuth_deg)], ...
            'FontWeight', 'bold', 'FontSize', 9, 'Color', col*0.7, 'HitTest', 'off', ...
            'Clipping', 'on', 'Interpreter', 'none');
    end
    rectangle(ax4, 'Position', [snd.Onset_s, yPos-0.4, snd.Duration_s, 0.8], ...
        'FaceColor', col, 'EdgeColor', col*0.7, 'LineWidth', 1);
    yPos = yPos + 1;
end
% legend entries (dummy patches; rectangles can't go in a legend)
for ty = fieldnames(colors)'
    if any(strcmp({d.Sounds.Type}, ty{1}))
        c = colors.(ty{1});
        patch(ax4, nan, nan, c, 'EdgeColor', c*0.7, 'DisplayName', names.(ty{1}));
    end
end
if ~isempty(d.TriggerRTs)
    for rt = d.TriggerRTs(:)'
        xline(ax4, rt, '--k', 'LineWidth', 1.5, 'HandleVisibility', 'off');
    end
    plot(ax4, nan, nan, '--k', 'LineWidth', 1.5, 'DisplayName', ...
        sprintf('Trigger response (n=%d)', numel(d.TriggerRTs)));
end
legend(ax4, 'Location', 'best', 'AutoUpdate', 'off');
yticks(ax4, []);
ylim(ax4, [0 yPos]);
title(ax4, 'Audio Events + Trigger Responses (distractor azimuth: - = left, + = right)'); grid(ax4, 'on');
xlabel(ax4, 'Time (s)');
%% ---- Link x-axes ------------------------------------------
allAx = [ax1 ax2 ax3 axMic ax4];
linkaxes(allAx, 'x');
xlim(ax1, [0 d.RecordingDuration]);
%% ---- Playheads --------------------------------------------
hHead = gobjects(1, numel(allAx));
for k = 1:numel(allAx)
    hHead(k) = xline(allAx(k), 0, '-', 'Color', [0 0.45 0.9], 'LineWidth', 2, ...
        'HandleVisibility', 'off', 'HitTest', 'off');
end
%% ---- Controls ---------------------------------------------
row1 = 0.53; row2 = 0.05; rh = 0.42;   % two rows: playback / annotation
bg = [0.94 0.94 0.94];
btn = @(str, x, y, w, cb) uicontrol(ctrlPanel, 'Style', 'pushbutton', 'String', str, ...
    'Units', 'normalized', 'Position', [x y w rh], 'FontSize', 10, 'Callback', cb);
hPlay = btn('Play',          0.005, row1, 0.06, @(src,~) uiCall(src, fig, @togglePlay));
btn('|<< 0 s',               0.07,  row1, 0.06, @(src,~) uiCall(src, fig, @(f) seekTo(f, 0)));
btn('<< 2 s',                0.135, row1, 0.05, @(src,~) uiCall(src, fig, @(f) seekRel(f, -2)));
btn('2 s >>',                0.19,  row1, 0.05, @(src,~) uiCall(src, fig, @(f) seekRel(f, 2)));
btn('Prev response',         0.25,  row1, 0.08, @(src,~) uiCall(src, fig, @(f) jumpResponse(f, -1)));
btn('Next response',         0.335, row1, 0.08, @(src,~) uiCall(src, fig, @(f) jumpResponse(f, +1)));
hFollow = uicontrol(ctrlPanel, 'Style', 'checkbox', 'String', sprintf('Follow (%g s)', followWin_s), ...
    'Units', 'normalized', 'Position', [0.425 row1 0.08 rh], 'FontSize', 10, ...
    'BackgroundColor', bg, 'Callback', @(src,~) uiCall(src, fig, @(f) applyFollow(f)));
chanStr = arrayfun(@(k) sprintf('%d: %s – %s', k, micNames{k}, micDesc{k}), ...
    1:size(d.MicData,2), 'UniformOutput', false);
if ~isempty(tgtCh); chanStr{tgtCh} = [chanStr{tgtCh} '  [TARGET]']; end
hChan = uicontrol(ctrlPanel, 'Style', 'popupmenu', 'String', chanStr, 'Value', playChannel, ...
    'Units', 'normalized', 'Position', [0.51 row1 0.2 rh], 'FontSize', 10, ...
    'Callback', @(src,~) uiCall(src, fig, @(f) setChannel(f, src.Value)));
hTime = uicontrol(ctrlPanel, 'Style', 'text', 'String', '', 'HorizontalAlignment', 'left', ...
    'Units', 'normalized', 'Position', [0.72 row1 0.275 rh*0.85], 'FontSize', 11, ...
    'FontName', 'Consolas', 'BackgroundColor', bg);
% annotation row
btn('Mark word (M)',         0.005, row2, 0.09, @(src,~) uiCall(src, fig, @addMark));
btn('Delete nearest (Del)',  0.10,  row2, 0.10, @(src,~) uiCall(src, fig, @deleteMark));
btn('Toggle hit/miss (T)',   0.205, row2, 0.10, @(src,~) uiCall(src, fig, @toggleOverride));
btn('Save to .mat (S)',      0.31,  row2, 0.09, @(src,~) uiCall(src, fig, @saveAnn));
hAnn = uicontrol(ctrlPanel, 'Style', 'text', 'String', '', 'HorizontalAlignment', 'left', ...
    'Units', 'normalized', 'Position', [0.41 row2 0.585 rh*0.85], 'FontSize', 11, ...
    'FontName', 'Consolas', 'BackgroundColor', bg);
%% ---- Playback state ---------------------------------------
pb = struct();
pb.d = d; pb.fs = fs; pb.dur = size(d.MicData, 1) / fs;
pb.ax = allAx; pb.axMic = axMic; pb.hMic = hMic; pb.hHead = hHead;
pb.hPlay = hPlay; pb.hFollow = hFollow; pb.hChan = hChan; pb.hTime = hTime;
pb.micNames = micNames; pb.micDesc = micDesc; pb.tgtCh = tgtCh;
pb.preRoll = preRoll_s; pb.followWin = followWin_s;
pb.rts = sort(d.TriggerRTs(:))';
pb.player = [];
pb.matFile = matFile; pb.ax4 = ax4; pb.hAnn = hAnn;
pb.hitWin = hitWindow_s; pb.markOffset = markOffset_s;
setappdata(fig, 'pb', pb);
setappdata(fig, 'tNow', 0);
setappdata(fig, 'ann', ann);
setChannel(fig, playChannel);   % builds the audioplayer + mic plot
setPlayhead(fig, 0);
redrawAnn(fig);
set(fig, 'WindowButtonDownFcn', @(f,~) clickSeek(f), ...
    'WindowKeyPressFcn',   @(f,e) keyPress(f, e), ...
    'CloseRequestFcn',     @(f,~) closeFig(f));
%% ---- Console summary --------------------------------------
fprintf('\nAudio events (azimuth: - = left, + = right, 0 = reference forward):\n');
for s = 1:numel(d.Sounds)
    snd = d.Sounds(s);
    extra = '';
    if strcmp(snd.Type, 'Distraktor')
        az = lsAz(snd.Loudspeaker, lsAzimuth_deg);
        [~, kf] = min(abs(t - snd.Onset_s));
        hy = ypr(kf, 1);                                   % head yaw at onset
        extra = sprintf('  azimuth %+.0f°  (head yaw %+.0f° -> %+.0f° re. head)', ...
            az, hy, mod(az - hy + 180, 360) - 180);
    end
    fprintf('  [%.1f – %.1f s]  %s  "%s"  LS %d%s\n', ...
        snd.Onset_s, snd.Onset_s + snd.Duration_s, snd.Type, snd.File, snd.Loudspeaker, extra);
end
if ~isempty(d.TriggerRTs)
    fprintf('\nTrigger responses (s): %s\n', ...
        strjoin(arrayfun(@(x) sprintf('%.3f', x), d.TriggerRTs, 'UniformOutput', false), ', '));
else
    fprintf('\nNo trigger responses recorded.\n');
end
fprintf('\nPlayback: Space = play/pause, Left/Right = -/+2 s, Up/Down = prev/next response, f = follow, click = seek.\n');
fprintf('Annotate: m = mark word, Del = delete nearest, t = toggle hit/miss, s = save.\n');
%% =========================================================
%  PLAYBACK FUNCTIONS
%% =========================================================
function ch = findTargetMic(d, nCh)
% Index of the MicData column recording the target facilitator ([] if unknown).
% 1) micFacilitator ('A'/'B') == Target
% 2) micDescription contains "Facilitator <Target>"
% 3) micDescription contains the target side (left/venstre, right/hoejre)
    ch = [];
    if ~isfield(d, 'Target'); return; end
    tgt = upper(strtrim(char(d.Target)));
    if isfield(d, 'micFacilitator')
        mf = upper(strtrim(cellstr(d.micFacilitator)));
        ch = find(strcmp(mf, tgt), 1);
    end
    if isempty(ch) && isfield(d, 'micDescription')
        desc = lower(cellstr(d.micDescription));
        ch = find(contains(desc, lower(['facilitator ' tgt])), 1);
        if isempty(ch) && isfield(d, 'TargetSide')
            side = lower(strtrim(char(d.TargetSide)));
            keys = {side};
            if strcmp(side, 'left');  keys{end+1} = 'venstre'; end
            if strcmp(side, 'right'); keys{end+1} = 'hoejre';  end
            ch = find(contains(desc, keys), 1);
        end
    end
    if ~isempty(ch) && ch > nCh; ch = []; end
end
function uiCall(src, fig, fn)
% Run a button callback, then take keyboard focus off the control so
% Space/arrow keys go to the figure (and don't re-press the button).
    fn(fig);
    if isvalid(src)
        set(src, 'Enable', 'off'); drawnow; set(src, 'Enable', 'on');
    end
end
function setChannel(fig, ch)
    pb = getappdata(fig, 'pb');
    wasPlaying = ~isempty(pb.player) && isvalid(pb.player) && isplaying(pb.player);
    if ~isempty(pb.player) && isvalid(pb.player); stop(pb.player); delete(pb.player); end
    x = double(pb.d.MicData(:, ch));
    x = x - mean(x);
    pk = max(abs(x));
    if pk > 0; x = 0.9 * x / pk; end              % normalise: raw levels are very low
    fprintf('Playing channel %d (%s, %s), gain %+.1f dB\n', ch, pb.micNames{ch}, ...
        pb.micDesc{ch}, 20*log10(0.9/max(pk, eps)));
    % min/max envelope for the plot (5 ms blocks)
    blk = round(0.005 * pb.fs);
    n   = floor(numel(x) / blk);
    X   = reshape(x(1:n*blk), blk, n);
    tt  = ((0:n-1) + 0.5) * blk / pb.fs;
    set(pb.hMic, 'XData', reshape([tt; tt], 1, []), ...
        'YData', reshape([min(X,[],1); max(X,[],1)], 1, []));
    if isequal(ch, pb.tgtCh); tag = 'TARGET, playing'; else; tag = 'playing'; end
    title(pb.axMic, sprintf('Mic %d: %s — %s (%s)', ch, pb.micNames{ch}, pb.micDesc{ch}, tag));
    p = audioplayer(x, pb.fs);
    p.TimerPeriod = 0.03;
    p.TimerFcn = @(~,~) onTimer(fig);
    p.StartFcn = @(~,~) set(pb.hPlay, 'String', 'Pause');
    p.StopFcn  = @(~,~) onStop(fig);
    pb.player = p;
    setappdata(fig, 'pb', pb);
    if wasPlaying; startAt(fig, getappdata(fig, 'tNow')); end
end
function onTimer(fig)
    if ~isvalid(fig); return; end
    pb = getappdata(fig, 'pb');
    if isplaying(pb.player)
        setPlayhead(fig, (pb.player.CurrentSample - 1) / pb.fs);
    end
end
function onStop(fig)
    if ~isvalid(fig); return; end
    pb = getappdata(fig, 'pb');
    set(pb.hPlay, 'String', 'Play');
end
function startAt(fig, tStart)
    pb = getappdata(fig, 'pb');
    s0 = max(1, min(pb.player.TotalSamples, round(tStart * pb.fs) + 1));
    setPlayhead(fig, (s0 - 1) / pb.fs);
    play(pb.player, s0);
end
function togglePlay(fig)
    pb = getappdata(fig, 'pb');
    if isplaying(pb.player)
        pause(pb.player);
    else
        tNow = getappdata(fig, 'tNow');
        if tNow >= pb.dur - 0.05; tNow = 0; end   % at the end -> restart
        startAt(fig, tNow);
    end
end
function seekTo(fig, tNew)
    pb = getappdata(fig, 'pb');
    tNew = max(0, min(pb.dur, tNew));
    if isplaying(pb.player)
        stop(pb.player);
        startAt(fig, tNew);
    else
        setPlayhead(fig, tNew);
    end
end
function seekRel(fig, dt)
    seekTo(fig, getappdata(fig, 'tNow') + dt);
end
function jumpResponse(fig, direction)
% Jump to preRoll seconds before the previous/next trigger response.
    pb = getappdata(fig, 'pb');
    if isempty(pb.rts); return; end
    starts = max(0, pb.rts - pb.preRoll);
    tNow = getappdata(fig, 'tNow');
    if direction > 0
        k = find(starts > tNow + 0.1, 1, 'first');
    else
        k = find(starts < tNow - 0.5, 1, 'last');   % 0.5 s grace so repeated presses step back
    end
    if isempty(k); return; end
    seekTo(fig, starts(k));
end
function setPlayhead(fig, tNow)
    pb = getappdata(fig, 'pb');
    setappdata(fig, 'tNow', tNow);
    set(pb.hHead, 'Value', tNow);
    % follow mode: scrolling window around the playhead
    if pb.hFollow.Value
        w  = min(pb.followWin, pb.dur);
        x0 = max(0, min(pb.dur - w, tNow - 0.3 * w));
        xlim(pb.ax(1), [x0 x0 + w]);
    end
    % readout: nearest response before / after the playhead
    msg = sprintf('t = %6.2f s', tNow);
    if ~isempty(pb.rts)
        kPrev = find(pb.rts <= tNow, 1, 'last');
        kNext = find(pb.rts >  tNow, 1, 'first');
        if ~isempty(kPrev)
            msg = sprintf('%s | resp #%d @ %.2f s (%.1f s ago)', msg, kPrev, pb.rts(kPrev), tNow - pb.rts(kPrev));
        end
        if ~isempty(kNext)
            msg = sprintf('%s | next @ %.2f s', msg, pb.rts(kNext));
        end
    end
    set(pb.hTime, 'String', msg);
    drawnow limitrate;
end
function clickSeek(fig)
    obj = fig.CurrentObject;
    if isempty(obj); return; end
    ax = ancestor(obj, 'axes');
    if isempty(ax); return; end
    pb = getappdata(fig, 'pb');
    if ~any(ax == pb.ax); return; end
    cp = get(ax, 'CurrentPoint');
    seekTo(fig, cp(1, 1));
end
function keyPress(fig, e)
    pb = getappdata(fig, 'pb');
    switch e.Key
        case 'space';      togglePlay(fig);
        case 'leftarrow';  seekRel(fig, -2);
        case 'rightarrow'; seekRel(fig,  2);
        case 'uparrow';    jumpResponse(fig, -1);
        case 'downarrow';  jumpResponse(fig, +1);
        case 'f'
            pb.hFollow.Value = ~pb.hFollow.Value;
            applyFollow(fig);
        case 'm';                     addMark(fig);
        case {'delete', 'backspace'}; deleteMark(fig);
        case 't';                     toggleOverride(fig);
        case 's';                     saveAnn(fig);
    end
end
function applyFollow(fig)
    pb = getappdata(fig, 'pb');
    if ~pb.hFollow.Value; xlim(pb.ax(1), [0 pb.dur]); end   % back to full view
    setPlayhead(fig, getappdata(fig, 'tNow'));
end
function closeFig(fig)
% Always closes the window, whatever goes wrong (only an explicit "Cancel"
% keeps it open). If saving fails, the annotations are copied to the base
% workspace as "unsavedTriggerAnnotation" so nothing is lost.
    try
        pb = getappdata(fig, 'pb');
        if ~isempty(pb) && ~isempty(pb.player) && isvalid(pb.player)
            stop(pb.player);
        end
        ann = getappdata(fig, 'ann');
        if ~isempty(ann) && ann.dirty
            a = questdlg('Save trigger-word annotations to the .mat file before closing?', ...
                'Unsaved annotations', 'Save', 'Discard', 'Cancel', 'Save');
            if strcmp(a, 'Cancel'); return; end
            if ~strcmp(a, 'Discard')          % 'Save', or dialog closed with X
                try
                    saveAnn(fig);
                catch err
                    assignin('base', 'unsavedTriggerAnnotation', ...
                        struct('times', ann.times, 'override', ann.override, 'file', pb.matFile));
                    warning('Could not save annotations (%s).\nThey are in the workspace variable "unsavedTriggerAnnotation".', err.message);
                end
            end
        end
    catch err
        warning('Error while closing: %s', err.message);
    end
    try
        pb = getappdata(fig, 'pb');
        if ~isempty(pb) && ~isempty(pb.player) && isvalid(pb.player); delete(pb.player); end
    catch
    end
    delete(fig);
end
%% =========================================================
%  ANNOTATION FUNCTIONS
%% =========================================================
function addMark(fig)
    pb  = getappdata(fig, 'pb');
    ann = getappdata(fig, 'ann');
    tm  = max(0, getappdata(fig, 'tNow') - pb.markOffset);
    [ann.times, idx] = sort([ann.times, tm]);
    ov = [ann.override, NaN];
    ann.override = ov(idx);
    ann.dirty = true;
    setappdata(fig, 'ann', ann);
    fprintf('Marked trigger word at %.2f s\n', tm);
    redrawAnn(fig);
end
function deleteMark(fig)
    ann = getappdata(fig, 'ann');
    k = nearestMark(fig, ann);
    if isempty(k); return; end
    fprintf('Deleted mark at %.2f s\n', ann.times(k));
    ann.times(k) = []; ann.override(k) = [];
    ann.dirty = true;
    setappdata(fig, 'ann', ann);
    redrawAnn(fig);
end
function toggleOverride(fig)
% auto -> HIT -> MISS -> auto
    ann = getappdata(fig, 'ann');
    k = nearestMark(fig, ann);
    if isempty(k); return; end
    o = ann.override(k);
    if isnan(o); o = 1; elseif o == 1; o = 0; else; o = NaN; end
    ann.override(k) = o;
    ann.dirty = true;
    setappdata(fig, 'ann', ann);
    lbl = {'auto', 'HIT', 'MISS'};
    fprintf('Mark at %.2f s set to %s\n', ann.times(k), lbl{1 + ~isnan(o) + (o == 0)});
    redrawAnn(fig);
end
function k = nearestMark(fig, ann)
    k = [];
    if isempty(ann.times); return; end
    [dt, k] = min(abs(ann.times - getappdata(fig, 'tNow')));
    if dt > 3
        fprintf('No mark within 3 s of the playhead.\n'); k = [];
    end
end
function [hit, rtMatch, faRT] = classifyWords(times, override, rts, win)
% Each word is matched to the first unused response within win after it.
    n = numel(times);
    hit = false(1, n); rtMatch = nan(1, n);
    used = false(size(rts));
    for k = 1:n
        c = find(~used & rts >= times(k) + win(1) & rts <= times(k) + win(2), 1, 'first');
        if ~isempty(c)
            used(c) = true; rtMatch(k) = rts(c); hit(k) = true;
        end
    end
    hit(override == 1) = true;      % manual overrides
    hit(override == 0) = false;
    faRT = rts(~used);
end
function redrawAnn(fig)
    pb  = getappdata(fig, 'pb');
    ann = getappdata(fig, 'ann');
    delete(ann.h(isgraphics(ann.h)));
    h = gobjects(0);
    [hit, ~, faRT] = classifyWords(ann.times, ann.override, pb.rts, pb.hitWin);
    yl = ylim(pb.ax4);
    for k = 1:numel(ann.times)
        if hit(k); col = [0 0.6 0]; lbl = 'HIT'; else; col = [0.85 0 0]; lbl = 'MISS'; end
        if ~isnan(ann.override(k)); lbl = [lbl '*']; end   % * = manual override
        for ax = pb.ax
            h(end+1) = xline(ax, ann.times(k), '-', 'Color', col, 'LineWidth', 2, ...
                'HandleVisibility', 'off', 'HitTest', 'off'); %#ok<AGROW>
        end
        h(end+1) = text(pb.ax4, ann.times(k), yl(2) - 0.12*diff(yl), sprintf(' %d %s', k, lbl), ...
            'Color', col, 'FontWeight', 'bold', 'HitTest', 'off', 'Clipping', 'on'); %#ok<AGROW>
    end
    for rt = faRT
        h(end+1) = text(pb.ax4, rt, yl(1) + 0.12*diff(yl), ' FA', 'Color', [0.4 0.4 0.4], ...
            'FontWeight', 'bold', 'HitTest', 'off', 'Clipping', 'on'); %#ok<AGROW>
    end
    ann.h = h;
    setappdata(fig, 'ann', ann);
    msg = sprintf('Words: %d | Hits: %d | Misses: %d | False alarms: %d', ...
        numel(ann.times), sum(hit), sum(~hit), numel(faRT));
    if ann.dirty; msg = [msg '   (unsaved)']; end
    set(pb.hAnn, 'String', msg);
end
function saveAnn(fig)
    pb  = getappdata(fig, 'pb');
    ann = getappdata(fig, 'ann');
    [hit, rtMatch, faRT] = classifyWords(ann.times, ann.override, pb.rts, pb.hitWin);
    TriggerWordTimes      = ann.times(:);          % s, marked word onsets
    TriggerWordHit        = hit(:);                % true = response given
    TriggerWordResponseRT = rtMatch(:);            % s, matched response (NaN = none)
    TriggerWordLatency    = rtMatch(:) - ann.times(:);   % s, response - word
    TriggerFalseAlarmRTs  = faRT(:);               % s, responses without a word
    user = getenv('USERNAME'); if isempty(user); user = getenv('USER'); end
    TriggerAnnotation = struct( ...
        'HitWindow_s', pb.hitWin, 'MarkOffset_s', pb.markOffset, ...
        'Override', ann.override(:), ...           % NaN = auto, 1 = forced HIT, 0 = forced MISS
        'nWords', numel(hit), 'nHits', sum(hit), 'nMisses', sum(~hit), ...
        'nFalseAlarms', numel(faRT), 'MicChannel', pb.hChan.Value, ...
        'TargetMicChannel', pb.tgtCh, ...
        'Annotator', user, 'Date', char(datetime('now')));
    % one-time backup of the untouched recording
    [p, n, e] = fileparts(pb.matFile);
    bk = fullfile(p, [n '_orig' e]);
    if ~exist(bk, 'file'); copyfile(pb.matFile, bk); fprintf('Backup written: %s\n', bk); end
    save(pb.matFile, 'TriggerWordTimes', 'TriggerWordHit', 'TriggerWordResponseRT', ...
        'TriggerWordLatency', 'TriggerFalseAlarmRTs', 'TriggerAnnotation', '-append');
    ann.dirty = false;
    setappdata(fig, 'ann', ann);
    redrawAnn(fig);
    fprintf('Saved %d words (%d hits, %d misses, %d false alarms) to %s\n', ...
        numel(hit), sum(hit), sum(~hit), numel(faRT), pb.matFile);
end
%% =========================================================
%  PLOT / GEOMETRY HELPERS
%% =========================================================
function addEventLines(ax, d)
% Thin vertical lines for distractor onsets, trigger responses and
% (optionally) known trigger-word onsets.
    for s = 1:numel(d.Sounds)
        if strcmp(d.Sounds(s).Type, 'Distraktor')
            xline(ax, d.Sounds(s).Onset_s, ':', 'Color', [1 0.4 0.2], 'LineWidth', 1, 'HandleVisibility', 'off');
        end
    end
    for rt = d.TriggerRTs(:)'
        xline(ax, rt, '--k', 'LineWidth', 1, 'HandleVisibility', 'off');
    end
end
function addTargetLine(ax, az, tgt, side)
% Horizontal line at the target talker's azimuth (yaw / gaze-azimuth plots).
    if isnan(az); return; end
    yline(ax, az, '-.', sprintf('Target %s (%s, %+.1f°)', tgt, side, az), ...
        'Color', [0 0.5 0], 'LineWidth', 1.5, 'HandleVisibility', 'off', 'HitTest', 'off', ...
        'LabelHorizontalAlignment', 'left', 'FontWeight', 'bold');
end
function az = lsAz(ls, lsAzimuth_deg)
% Azimuth (deg) of loudspeaker number ls; NaN if unknown.
    if ls >= 1 && ls <= numel(lsAzimuth_deg); az = lsAzimuth_deg(ls); else; az = NaN; end
end
function s = lsAngleStr(ls, lsAzimuth_deg)
    az = lsAz(ls, lsAzimuth_deg);
    if isnan(az); s = 'az ?'; else; s = sprintf('%+.0f°', az); end
end
function H = headFrame(R, fwdLocal, upLocal)
% Columns = head forward, left, up in lab coordinates (orthonormal).
    f = R * fwdLocal(:);  f = f / norm(f);
    u = R * upLocal(:);   u = u - (u' * f) * f;  u = u / norm(u);
    H = [f, cross(u, f), u];
end
function R = quatToRot(q)
% q = [x y z w] (Vicon SDK order) -> 3x3 rotation matrix (segment -> lab)
    q = q / norm(q);
    x = q(1); y = q(2); z = q(3); w = q(4);
    R = [1-2*(y^2+z^2)  2*(x*y-z*w)    2*(x*z+y*w);
         2*(x*y+z*w)    1-2*(x^2+z^2)  2*(y*z-x*w);
         2*(x*z-y*w)    2*(y*z+x*w)    1-2*(x^2+y^2)];
end