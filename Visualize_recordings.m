%% =========================================================
%  VISUALIZE ONE RECORDING
%  Load a .mat file saved by experiment_script_pilot and plot:
%    1. Head translation (x/y/z) over time
%    2. Head rotation (quaternion x/y/z/w) over time
%    3. Gaze vector over time
%    4. Audio timeline: soundscape + distractors + trigger responses
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

t = d.FrameTime(:);   % time axis from Vicon frames

%% ---- Figure layout ----------------------------------------
fig = figure('Name', sprintf('Recording — %s — Cond %d — Target %s — "%s"', ...
    d.TriggerWord, d.Condition, d.Target, d.TriggerWord), ...
    'NumberTitle', 'off', 'Color', 'w');

nRows = 4;
tiledlayout(fig, nRows, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

%% ---- Express everything relative to the head reference ----
% Reference frame (upright): x = forward, y = left, z = up, origin = p0.
ref = d.HeadReference;
H0  = headFrame(quatToRot(ref.q0), headFwdLocal, headUpLocal);   % head axes at reference
fwd0 = H0(:,1); fwd0(3) = 0; fwd0 = fwd0 / norm(fwd0);
R0  = [fwd0, cross([0;0;1], fwd0), [0;0;1]];                       % upright reference

nF = size(d.GlobalTranslation, 1);

% Translation: mm in the reference frame, 0 = reference position
Trel = (d.GlobalTranslation - ref.p0(:)') * R0;      % [forward left up]

% Rotation: yaw/pitch/roll of the head relative to the reference HEAD POSE
% (all three = 0 when the head is exactly as during the reference)
ypr = nan(nF, 3);
for k = 1:nF
    q = d.GlobalRotationQuaternion(k, :);
    if any(isnan(q)); continue; end
    M = H0' * headFrame(quatToRot(q), headFwdLocal, headUpLocal);  % head in ref-head coords
    ypr(k,1) = atan2d(M(2,1), M(1,1));                 % yaw,   + = turn left
    ypr(k,2) = asind(max(-1, min(1, M(3,1))));         % pitch, + = nose up
    ypr(k,3) = atan2d(M(3,2), M(3,3));                % roll,  + = right ear down
end

% Gaze: direction in the upright reference frame
G = d.EyeTrackerGlobalGazeVector;
G(all(G == 0, 2), :) = NaN;                            % (0,0,0) = lost tracking
G = G ./ vecnorm(G, 2, 2);
Grel  = G * R0;
gazeAz = atan2d(Grel(:,2), Grel(:,1));                 % 0 = reference forward, + = left
gazeEl = asind(Grel(:,3));                             % 0 = horizontal, + = up

%% ---- 1. Head translation ----------------------------------
ax1 = nexttile;
plot(t, Trel(:,1), 'r', t, Trel(:,2), 'g', t, Trel(:,3), 'b', 'LineWidth', 1.2);
legend('Forward','Left','Up', 'Location','best', 'AutoUpdate','off');
ylabel('mm'); title('Head Translation (relative to reference)'); grid on; xlim([0 d.RecordingDuration]);
addEventLines(ax1, d);

%% ---- 2. Head rotation -------------------------------------
ax2 = nexttile;
plot(t, ypr(:,1), 'r', t, ypr(:,2), 'g', t, ypr(:,3), 'b', 'LineWidth', 1.2);
legend('Yaw (+left)','Pitch (+up)','Roll (+right ear down)', 'Location','best', 'AutoUpdate','off');
ylabel('Angle (°)'); title('Head Rotation (relative to reference)'); grid on; xlim([0 d.RecordingDuration]);
addEventLines(ax2, d);

%% ---- 3. Gaze direction (azimuth / elevation) ---------------
ax3 = nexttile;
plot(t, gazeAz, 'k', t, gazeEl, 'm', 'LineWidth', 1.2);
ylim([-180 180]); yticks(-180:45:180);
ylabel('Angle (°)');
legend('Azimuth (+left)', 'Elevation (+up)', 'Location', 'best', 'AutoUpdate', 'off');
title('Gaze Direction (relative to reference forward)'); grid on; xlim([0 d.RecordingDuration]);
addEventLines(ax3, d);

%% ---- 4. Audio event timeline ------------------------------
ax4 = nexttile;
hold(ax4, 'on');

yPos    = 1;   % y position per sound type
yLabels = {};
yTicks  = [];
colors  = struct('Soundscape', [0.2 0.6 1], 'Distraktor', [1 0.4 0.2]);

for s = 1:numel(d.Sounds)
    snd = d.Sounds(s);
    col = colors.(snd.Type);
    yTicks(end+1)  = yPos; %#ok<AGROW>
    yLabels{end+1} = sprintf('%s\n%s\n(LS %d)', snd.Type, snd.File, snd.Loudspeaker); %#ok<AGROW>
    rectangle(ax4, 'Position', [snd.Onset_s, yPos-0.4, snd.Duration_s, 0.8], ...
        'FaceColor', col, 'EdgeColor', col*0.7, 'LineWidth', 1);
    yPos = yPos + 1;
end

% Trigger responses as vertical lines
if ~isempty(d.TriggerRTs)
    for rt = d.TriggerRTs(:)'
        xline(ax4, rt, '--k', 'LineWidth', 1.5, 'HandleVisibility', 'off');
    end
    % invisible dummy for legend
    plot(ax4, nan, nan, '--k', 'LineWidth', 1.5, 'DisplayName', ...
        sprintf('Trigger response (n=%d)', numel(d.TriggerRTs)));
    legend(ax4, 'Location', 'best');
end

yticks(ax4, yTicks);
yticklabels(ax4, yLabels);
xlim(ax4, [0 d.RecordingDuration]);
ylim(ax4, [0 yPos]);
xlabel('Time (s)'); title('Audio Events + Trigger Responses'); grid on;

%% ---- Link x-axes ------------------------------------------
linkaxes([ax1 ax2 ax3 ax4], 'x');
xlabel(ax1, ''); xlabel(ax2, ''); xlabel(ax3, '');
xlabel(ax4, 'Time (s)');

%% ---- Console summary --------------------------------------
fprintf('\nAudio events:\n');
for s = 1:numel(d.Sounds)
    snd = d.Sounds(s);
    fprintf('  [%.1f – %.1f s]  %s  "%s"  LS %d\n', ...
        snd.Onset_s, snd.Onset_s + snd.Duration_s, snd.Type, snd.File, snd.Loudspeaker);
end
if ~isempty(d.TriggerRTs)
    fprintf('\nTrigger responses (s): %s\n', ...
        strjoin(arrayfun(@(t) sprintf('%.3f', t), d.TriggerRTs, 'UniformOutput', false), ', '));
else
    fprintf('\nNo trigger responses recorded.\n');
end

%% =========================================================
function addEventLines(ax, d)
% Adds thin vertical lines for distractor onsets and trigger responses.
    for s = 1:numel(d.Sounds)
        if strcmp(d.Sounds(s).Type, 'Distraktor')
            xline(ax, d.Sounds(s).Onset_s, ':', 'Color', [1 0.4 0.2], 'LineWidth', 1, 'HandleVisibility', 'off');
        end
    end
    for rt = d.TriggerRTs(:)'
        xline(ax, rt, '--k', 'LineWidth', 1, 'HandleVisibility', 'off');
    end
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