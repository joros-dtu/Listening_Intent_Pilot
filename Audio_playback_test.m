%% =========================================================
%  AUDIO PLAYBACK SCRIPT (simplified)
%  Plays audio for exactly 50 seconds through specified channels
%% =========================================================

% << EDIT HERE >> -------------------------------------------
audioFile       = '1. Applause.wav';      % audio file to play
fs              = 48000;           % sample rate
samplesPerFrame = 1024;
amp             = 0.20;            % amplitude scaling
%channelMapping  = [2:2:24 25:48];  % output channel mapping
channelMapping = 30 + [2];         % distractor test
playDuration    = 50;              % seconds to play

% Audio device setup
AP = audioDeviceWriter;
AP.Driver               = 'ASIO';
AP.Device               = 'ASIO MADIface USB';
AP.ChannelMappingSource = 'Property';
AP.ChannelMapping       = channelMapping;
AP.SampleRate           = fs;
AP.BitDepth             = '24-bit integer';

% Load audio file
[y, fsFile] = audioread(audioFile);
if fsFile ~= fs
    error('%s has fs = %d Hz, expected %d Hz.', audioFile, fsFile, fs);
end

% Prepare signal (repeat/loop if needed to fill 50 seconds)
nSamples = playDuration * fs;
nCh = numel(channelMapping);
sigPlay = zeros(nSamples, nCh);

% Loop audio if file is shorter than 50 seconds
nSamp = size(y, 1);
for i = 1:nSamples
    sigPlay(i, :) = repmat(y(mod(i-1, nSamp) + 1, 1), 1, nCh);
end

% Play audio for exactly 50 seconds
fprintf('Playing for %.0f seconds...\n', playDuration);
playStart = tic;

for frame = 1:ceil(nSamples / samplesPerFrame)
    startIdx = (frame - 1) * samplesPerFrame + 1;
    endIdx = min(startIdx + samplesPerFrame - 1, nSamples);
    
    data = amp * sigPlay(startIdx:endIdx, :);
    AP(data);
    
    elapsed = toc(playStart);
    if elapsed >= playDuration
        break;
    end
end

release(AP);
fprintf('Playback complete.\n');