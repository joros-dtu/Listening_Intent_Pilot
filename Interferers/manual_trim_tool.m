function manual_trim_tool(inDir, outDir, varargin)
% MANUAL_TRIM_TOOL  Listen to, manually cut, and RMS-equalize all WAV files in a folder.
%
%   manual_trim_tool(inDir, outDir)
%   manual_trim_tool(inDir, outDir, 'TargetDBFS', -30, ...)
%
% Finds all .wav files in inDir AND its subfolders (e.g. mark/, rikke/).
% For each file an automatic cut is suggested; you adjust it by clicking:
%
%   Left click ........ set START (green)
%   Right click ....... set END   (red)       (Mac: Ctrl+click)
%   Space ............. play selection
%   1 / 2 ............. play first / last 0.5 s of selection
%   F ................. play full file          S ... stop
%   A ................. automatic cut suggestion
%   X / Delete ........ exclude bad recording (press again to restore)
%   Enter ............. accept & go to next file
%   Left/Right arrow .. previous / next file
%
% Cut points are saved continuously to <outDir>/cutpoints.csv, so you can
% close MATLAB and continue later - just run the same command again.
%
% "Export all" cuts every file, scales it to TargetDBFS RMS (same level for
% all files), adds short fades, and writes it to outDir with the same
% subfolder structure. Excluded recordings are skipped (originals are never
% deleted) and listed in excluded_files.csv. It also writes processing_log.csv and
% calibration_noise.wav (same RMS as the stimuli) for the HATS calibration.
%
% Options (Name/Value):
%   'TargetDBFS'   RMS level of all output files, dBFS      (default -30)
%   'FadeMs'       fade in/out at the cut points, ms        (default 2)
%   'ThresholdDB'  auto-cut threshold re. loudest frame     (default -35)
%   'PadMs'        margin kept by the auto-cut, ms          (default 0)
%   'CalNoise'     'speech' | 'pink' | 'white' | 'none'     (default 'speech')
%   'CalDurSec'    calibration noise duration, s            (default 30)
%   'BitDepth'     output bits per sample                   (default 24)
%
% Example:
%   manual_trim_tool('sentenceRecordings', 'sentenceRecordings_eq')
%
% No toolboxes required (R2016b or newer).

p = inputParser;
p.addParameter('TargetDBFS', -30);
p.addParameter('FadeMs', 2);
p.addParameter('ThresholdDB', -35);
p.addParameter('PadMs', 0);
p.addParameter('CalNoise', 'speech');
p.addParameter('CalDurSec', 30);
p.addParameter('BitDepth', 24);
p.parse(varargin{:});
o = p.Results;

% ---------------- find files ----------------
if ~exist(inDir, 'dir'), error('Input folder not found: %s', inDir); end
if ~exist(outDir, 'dir'), mkdir(outDir); end
inAbs  = absPath(inDir);
outAbs = absPath(outDir);

files = dir(fullfile(inAbs, '**', '*.wav'));
files = files(~startsWith({files.folder}, outAbs));    % never read our own outputs
files = files(~startsWith({files.name}, '._'));        % skip macOS metadata files
n = numel(files);
if n == 0, error('No .wav files found in %s (or its subfolders).', inDir); end
fullPaths = fullfile({files.folder}, {files.name})';
rel = cellfun(@(f) f(numel(inAbs)+2:end), fullPaths, 'UniformOutput', false);

% ---------------- cut points (resume if saved) ----------------
cutFile = fullfile(outAbs, 'cutpoints.csv');
startS = nan(n,1); endS = nan(n,1); reviewed = false(n,1); excluded = false(n,1);
if exist(cutFile, 'file')
    C = readtable(cutFile, 'TextType', 'char', 'Delimiter', ',');
    for i = 1:n
        k = find(strcmp(C.RelPath, rel{i}), 1);
        if ~isempty(k)
            startS(i) = C.Start_s(k); endS(i) = C.End_s(k);
            reviewed(i) = logical(C.Reviewed(k));
            if ismember('Excluded', C.Properties.VariableNames)
                excluded(i) = logical(C.Excluded(k));
            end
        end
    end
    fprintf('Resumed: %d of %d files already reviewed.\n', sum(reviewed), n);
end

% ---------------- state shared by nested functions ----------------
cur = 1; x = []; fs = 44100; xm = []; totalDur = 0; player = [];
hS = []; hE = []; hL = []; hR = []; hHead = [];

% ---------------- GUI ----------------
fig = figure('Name', 'Manual trim tool', 'NumberTitle', 'off', 'MenuBar', 'none', ...
    'ToolBar', 'figure', 'Units', 'normalized', 'Position', [.08 .12 .84 .74], ...
    'WindowButtonDownFcn', @onClick, 'WindowKeyPressFcn', @onKey, ...
    'CloseRequestFcn', @onClose);
ax = axes('Parent', fig, 'Position', [.05 .33 .92 .56]);
infoTxt = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [.05 .915 .6 .06], 'HorizontalAlignment', 'left', 'FontSize', 11);
pop = uicontrol(fig, 'Style', 'popupmenu', 'Units', 'normalized', ...
    'Position', [.67 .93 .30 .04], 'String', {' '}, 'Callback', @(h,~) go(h.Value));

w = .125; g = .008; x0 = .05;
mk('<< Prev',             [x0+0*(w+g) .18 w .07], @prevFile);
mk('Play selection [Space]', [x0+1*(w+g) .18 w .07], @playSel);
mk('Play start [1]',      [x0+2*(w+g) .18 w .07], @playStart);
mk('Play end [2]',        [x0+3*(w+g) .18 w .07], @playEnd);
mk('Play full [F]',       [x0+4*(w+g) .18 w .07], @playFull);
mk('Stop [S]',            [x0+5*(w+g) .18 w .07], @stopPlay);
mk('Next >>',             [x0+6*(w+g) .18 w .07], @nextFile);
mk('Auto cut [A]',        [x0+0*(w+g) .09 w .07], @autoCur);
mk('Zoom on start',       [x0+1*(w+g) .09 w .07], @zoomStart);
mk('Zoom on end',         [x0+2*(w+g) .09 w .07], @zoomEnd);
mk('Full view',           [x0+3*(w+g) .09 w .07], @fullView);
mk('Exclude / restore [X]', [x0+5*(w+g) .09 w .07], @toggleExclude);
mk('Accept & next [Enter]', [x0+4*(w+g) .09 w .07], @acceptNext);
b = mk('EXPORT ALL',      [x0+6*(w+g) .09 w .07], @exportAll);
set(b, 'FontWeight', 'bold');
uicontrol(fig, 'Style', 'text', 'Units', 'normalized', 'Position', [.05 .01 .92 .05], ...
    'HorizontalAlignment', 'left', 'String', ...
    ['Left click = START (green)    Right click = END (red)    Space = play selection    ' ...
     '1/2 = play start/end    X = exclude bad take    Enter = accept & next    Arrows = prev/next    ' ...
     sprintf('All files will be set to %.1f dBFS RMS on export.', o.TargetDBFS)]);

loadFile(1);

% ======================= nested functions =======================
    function h = mk(label, pos, fn)
        h = uicontrol(fig, 'Style', 'pushbutton', 'String', label, 'Units', 'normalized', ...
            'Position', pos, 'Callback', @(src,~) runBtn(src, fn));
    end

    function runBtn(src, fn)
        % give keyboard focus back to the figure so shortcuts keep working
        set(src, 'Enable', 'off'); drawnow; set(src, 'Enable', 'on');
        fn();
    end

    function loadFile(i)
        stopPlay();
        cur = i;
        [x, fs] = audioread(fullPaths{i});
        xm = mean(x, 2);
        totalDur = size(x,1) / fs;
        if isnan(startS(i)) || isnan(endS(i))
            [startS(i), endS(i)] = autoTrim(x, fs, o);
        end
        cla(ax);
        t = (0:numel(xm)-1)' / fs;
        yl = max(abs(xm)) * 1.05; if yl == 0, yl = 1; end
        hold(ax, 'on');
        plot(ax, t, xm, 'Color', [.15 .35 .75], 'HitTest', 'off');
        hL = patch(ax, [0 0 0 0], [-yl -yl yl yl], [.4 .4 .4], 'FaceAlpha', .35, ...
            'EdgeColor', 'none', 'HitTest', 'off');
        hR = patch(ax, [0 0 0 0], [-yl -yl yl yl], [.4 .4 .4], 'FaceAlpha', .35, ...
            'EdgeColor', 'none', 'HitTest', 'off');
        hS = line(ax, [0 0], [-yl yl], 'Color', [0 .65 0], 'LineWidth', 2, 'HitTest', 'off');
        hE = line(ax, [0 0], [-yl yl], 'Color', [.85 0 0], 'LineWidth', 2, 'HitTest', 'off');
        hHead = line(ax, [0 0], [-yl yl], 'Color', 'k', 'LineWidth', 1, 'Visible', 'off', 'HitTest', 'off');
        hold(ax, 'off');
        xlim(ax, [0 totalDur]); ylim(ax, [-yl yl]);
        xlabel(ax, 'Time (s)'); box(ax, 'on'); grid(ax, 'on');
        updateView();
    end

    function updateView()
        s = startS(cur); e = endS(cur);
        set(hS, 'XData', [s s]); set(hE, 'XData', [e e]);
        set(hL, 'XData', [0 s s 0]); set(hR, 'XData', [e totalDur totalDur e]);
        [i1, i2] = idx(s, e);
        seg = x(i1:i2, :);
        r = 20*log10(sqrt(mean(seg(:).^2)) + eps);
        gn = o.TargetDBFS - r;
        pk = 20*log10(max(abs(seg(:))) + eps) + gn;
        clipTxt = ''; if pk >= 0, clipTxt = '   << WILL CLIP'; end
        status = 'not reviewed'; if reviewed(cur), status = 'REVIEWED'; end
        if excluded(cur), status = 'EXCLUDED - will not be exported'; end
        set(infoTxt, 'ForegroundColor', [0 0 0] + [.8 0 0]*excluded(cur));
        set(infoTxt, 'String', { ...
            sprintf('%d/%d   %s   [%s]', cur, n, rel{cur}, status), ...
            sprintf('Cut %.3f - %.3f s (%.2f s)   |   RMS %.1f dBFS -> gain %+.1f dB, peak after %.1f dBFS%s', ...
                    s, e, e-s, r, gn, pk, clipTxt)});
        marks = repmat({'[  ] '}, n, 1); marks(reviewed) = {'[x] '}; marks(excluded) = {'[DEL] '};
        set(pop, 'String', strcat(marks, rel), 'Value', cur);
    end

    function [i1, i2] = idx(s, e)
        i1 = max(1, round(s*fs) + 1);
        i2 = min(size(x,1), max(i1, round(e*fs)));
    end

    function onClick(~, ~)
        cp = get(ax, 'CurrentPoint'); xx = cp(1,1); yy = cp(1,2);
        xl = xlim(ax); yl = ylim(ax);
        if xx < xl(1) || xx > xl(2) || yy < yl(1) || yy > yl(2), return; end
        xx = min(max(xx, 0), totalDur);
        switch get(fig, 'SelectionType')
            case 'normal'   % left click
                startS(cur) = min(xx, endS(cur) - 1/fs);
            case 'alt'      % right click / ctrl+click
                endS(cur) = max(xx, startS(cur) + 1/fs);
            otherwise
                return
        end
        updateView(); saveCuts();
    end

    function onKey(~, ev)
        switch ev.Key
            case 'space',       playSel();
            case '1',           playStart();
            case '2',           playEnd();
            case 'f',           playFull();
            case 's',           stopPlay();
            case 'a',           autoCur();
            case {'x', 'delete'}, toggleExclude();
            case 'return',      acceptNext();
            case 'rightarrow',  nextFile();
            case 'leftarrow',   prevFile();
        end
    end

    function go(i)
        if i < 1 || i > n, return; end
        loadFile(i);
    end

    function autoCur()
        [startS(cur), endS(cur)] = autoTrim(x, fs, o);
        updateView(); saveCuts();
    end

    function zoomAt(tc)
        xlim(ax, [max(0, tc-0.3), min(totalDur, tc+0.3)]);
    end
    function toggleExclude()
        excluded(cur) = ~excluded(cur);
        reviewed(cur) = true;
        saveCuts();
        if excluded(cur) && cur < n
            go(cur+1);
        else
            updateView();
        end
    end
    function zoomStart(), zoomAt(startS(cur)); end
    function zoomEnd(),   zoomAt(endS(cur));   end
    function fullView(),  xlim(ax, [0 totalDur]); end
    function nextFile(),  go(cur+1); end
    function prevFile(),  go(cur-1); end

    function acceptNext()
        reviewed(cur) = true; saveCuts();
        if cur < n
            go(cur+1);
        else
            updateView();
            msgbox(sprintf('All done! %d of %d files reviewed.\nClick "EXPORT ALL" to write the files.', ...
                sum(reviewed), n), 'Finished');
        end
    end

    % ---------- playback ----------
    function playRange(i1, i2)
        stopPlay();
        player = audioplayer(x(i1:i2, :), fs);
        offset = (i1-1)/fs;
        player.TimerPeriod = 0.03;
        player.TimerFcn = @(pl,~) moveHead(offset + pl.CurrentSample/fs);
        player.StopFcn  = @(~,~) hideHead();
        play(player);
    end
    function playSel(),   [i1,i2] = idx(startS(cur), endS(cur)); playRange(i1, i2); end
    function playFull(),  playRange(1, size(x,1)); end
    function playStart()
        [i1,i2] = idx(startS(cur), endS(cur)); playRange(i1, min(i2, i1 + round(0.5*fs)));
    end
    function playEnd()
        [i1,i2] = idx(startS(cur), endS(cur)); playRange(max(i1, i2 - round(0.5*fs)), i2);
    end
    function stopPlay()
        try
            if ~isempty(player) && isplaying(player), stop(player); end
        catch
        end
    end
    function moveHead(tt)
        if ishghandle(hHead), set(hHead, 'XData', [tt tt], 'Visible', 'on'); end
    end
    function hideHead()
        if ishghandle(hHead), set(hHead, 'Visible', 'off'); end
    end

    % ---------- saving ----------
    function saveCuts()
        T = table(rel, startS, endS, double(reviewed), double(excluded), ...
            'VariableNames', {'RelPath', 'Start_s', 'End_s', 'Reviewed', 'Excluded'});
        writetable(T, cutFile);
    end

    function onClose(~, ~)
        stopPlay();
        try, saveCuts(); catch, end
        delete(fig);
    end

    % ---------- export ----------
    function exportAll()
        stopPlay();
        keep = find(~excluded)';
        if isempty(keep), errordlg('All files are excluded - nothing to export.'); return; end
        if any(~reviewed(keep))
            a = questdlg(sprintf(['%d of %d files are not reviewed.\n' ...
                'Export anyway (using automatic cuts for unvisited files)?'], sum(~reviewed(keep)), numel(keep)), ...
                'Export', 'Export', 'Cancel', 'Cancel');
            if ~strcmp(a, 'Export'), return; end
        end
        wb = waitbar(0, 'Analysing levels...');
        segs = cell(n,1); fsAll = zeros(n,1); s0 = startS; e0 = endS;
        rmsDB = nan(n,1); peakDB = -inf(n,1);
        for i = keep
            [xi, fi] = audioread(fullPaths{i});
            if isnan(s0(i)) || isnan(e0(i)), [s0(i), e0(i)] = autoTrim(xi, fi, o); end
            i1 = max(1, round(s0(i)*fi) + 1); i2 = min(size(xi,1), max(i1, round(e0(i)*fi)));
            segs{i} = xi(i1:i2, :); fsAll(i) = fi;
            rmsDB(i)  = 20*log10(sqrt(mean(segs{i}(:).^2)) + eps);
            peakDB(i) = 20*log10(max(abs(segs{i}(:))) + eps) + (o.TargetDBFS - rmsDB(i));
            waitbar(i/(2*n), wb);
        end
        if max(peakDB) >= -0.1
            close(wb);
            nc = sum(peakDB >= -0.1);
            errordlg(sprintf(['%d file(s) would clip at %.1f dBFS RMS (worst peak %+.1f dBFS).\n\n' ...
                'Nothing was written. Close the tool and run it again with e.g.\n' ...
                '''TargetDBFS'', %d   (your cut points are saved).'], ...
                nc, o.TargetDBFS, max(peakDB), floor(o.TargetDBFS - max(peakDB) - 1)), 'Clipping');
            return
        end

        waitbar(0.5, wb, 'Writing files...');
        tgt = 10^(o.TargetDBFS/20);
        sumPow = []; fsRef = mode(fsAll(keep)); nfft = 4096;
        for i = keep
            y = segs{i} * (tgt / 10^(rmsDB(i)/20));
            y = applyFades(y, fsAll(i), o.FadeMs);
            outPath = fullfile(outAbs, rel{i});
            if ~exist(fileparts(outPath), 'dir'), mkdir(fileparts(outPath)); end
            audiowrite(outPath, y, fsAll(i), 'BitsPerSample', o.BitDepth);
            peakDB(i) = 20*log10(max(abs(y(:))) + eps);
            if fsAll(i) == fsRef
                P = ltass(mean(y,2), nfft);
                if isempty(sumPow), sumPow = P; else, sumPow = sumPow + P; end
            end
            waitbar(0.5 + i/(2*n), wb);
        end
        close(wb);

        logT = table(rel, fsAll, s0, e0, e0 - s0, rmsDB, o.TargetDBFS - rmsDB, peakDB, double(reviewed), ...
            'VariableNames', {'RelPath','Fs','Start_s','End_s','Dur_s', ...
            'RMSorig_dBFS','Gain_dB','PeakOut_dBFS','Reviewed'});
        writetable(logT(keep, :), fullfile(outAbs, 'processing_log.csv'));
        % excluded: list them, and remove any copy left over from an earlier export
        for i = find(excluded)'
            old = fullfile(outAbs, rel{i});
            if exist(old, 'file'), delete(old); end
        end
        writetable(table(rel(excluded), 'VariableNames', {'RelPath'}), ...
            fullfile(outAbs, 'excluded_files.csv'));

        calMsg = '';
        if ~strcmpi(o.CalNoise, 'none')
            N = round(o.CalDurSec * fsRef);
            switch lower(o.CalNoise)
                case 'white',  c = randn(N, 1);
                case 'pink',   c = shapeNoise(N, fsRef, @(f) 1 ./ sqrt(max(f, 20)));
                case 'speech'
                    fP = (0:nfft-1)' * fsRef / nfft;
                    c = shapeNoise(N, fsRef, @(f) sqrt(interp1(fP, sumPow, f, 'linear', 0)));
                otherwise, error('Unknown CalNoise "%s".', o.CalNoise);
            end
            c = applyFades(c / sqrt(mean(c.^2)), fsRef, 50);
            c = c / sqrt(mean(c.^2)) * tgt;
            audiowrite(fullfile(outAbs, 'calibration_noise.wav'), c, fsRef, 'BitsPerSample', o.BitDepth);
            calMsg = sprintf('\ncalibration_noise.wav (%s-shaped, %.1f dBFS RMS) written.', o.CalNoise, o.TargetDBFS);
        end
        msgbox(sprintf('Exported %d files (%d excluded) to\n%s\n\nAll at %.1f dBFS RMS, max peak %.1f dBFS.%s', ...
            numel(keep), sum(excluded), outAbs, o.TargetDBFS, max(peakDB), calMsg), 'Export done');
    end
end

% ======================= local functions =======================
function a = absPath(d)
    L = dir(d);
    a = L(strcmp({L.name}, '.')).folder;
end

function [s, e] = autoTrim(x, fs, o)
    L = max(1, round(0.005 * fs));          % 5 ms frames
    nF = floor(size(x,1) / L);
    if nF < 1, s = 0; e = size(x,1)/fs; return; end
    en = zeros(nF, 1);
    for i = 1:nF
        seg = x((i-1)*L+1 : i*L, :);
        en(i) = mean(seg(:).^2);
    end
    eDB = 10*log10(en + eps);
    act = find(eDB > max(eDB) + o.ThresholdDB);
    pad = o.PadMs / 1000;
    s = max(0, (act(1)-1)*L/fs - pad);
    e = min(size(x,1)/fs, act(end)*L/fs + pad);
end

function y = applyFades(y, fs, fadeMs)
    nf = min(round(fadeMs/1000*fs), floor(size(y,1)/2));
    if nf < 1, return; end
    w = 0.5 - 0.5*cos(pi*(0:nf-1)'/nf);
    y(1:nf, :) = y(1:nf, :) .* w;
    y(end-nf+1:end, :) = y(end-nf+1:end, :) .* flipud(w);
end

function P = ltass(x, nfft)
    w = 0.5 - 0.5*cos(2*pi*(0:nfft-1)'/nfft);
    hop = nfft/2;
    if numel(x) < nfft, x(end+1:nfft) = 0; end
    nSeg = floor((numel(x)-nfft)/hop) + 1;
    P = zeros(nfft, 1);
    for i = 1:nSeg
        P = P + abs(fft(x((i-1)*hop + (1:nfft)) .* w)).^2;
    end
    P = P / nSeg;
end

function c = shapeNoise(N, fs, magFun)
    Nfft = 2^nextpow2(N);
    f = (0:Nfft/2)' * fs / Nfft;
    mag = magFun(f); mag(1) = 0;
    X = mag .* exp(1i*2*pi*rand(size(f)));
    X(end) = real(X(end));
    c = real(ifft([X; conj(X(end-1:-1:2))]));
    c = c(1:N);
end