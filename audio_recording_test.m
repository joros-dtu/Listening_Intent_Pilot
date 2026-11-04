%% Configuration
SAMPLE_RATE  = 48000;
DURATION     = 10;

%% Create reader for AN 5/6 (MADI channels 1 and 2)
readerMADI = audioDeviceReader( ...
    'Device',          'MADI (1-8) (RME UFX+ USB 3.0)', ...
    'SampleRate',       SAMPLE_RATE, ...
    'NumChannels',      2, ...
    'BitDepth',         '16-bit integer', ...
    'SamplesPerFrame',  SAMPLE_RATE);

%% Create reader for Mic 11 and 12
readerANA = audioDeviceReader( ...
    'Device',          'Analog (11+12) (RME UFX+ USB 3.0)', ...
    'SampleRate',       SAMPLE_RATE, ...
    'NumChannels',      2, ...
    'BitDepth',         '16-bit integer', ...
    'SamplesPerFrame',  SAMPLE_RATE);

%% Pre-allocate
totalSamples = ceil(DURATION * SAMPLE_RATE);
allSamples   = zeros(totalSamples, 3, 'single');

%% Record
fprintf('Recording AN5, Mic11, Mic12 for %g seconds...\n', DURATION);
setup(readerMADI);
setup(readerANA);
frameIdx = 0;
tic;

while toc < DURATION
    frameMADI = readerMADI();   % ch1 = AN5, ch2 = AN6
    frameANA  = readerANA();    % ch1 = Mic11, ch2 = Mic12

    combined = [frameMADI(:,1), frameANA(:,1), frameANA(:,2)];

    r1 = frameIdx * readerMADI.SamplesPerFrame + 1;
    r2 = min(r1 + size(combined,1) - 1, totalSamples);
    allSamples(r1:r2, :) = single(combined(1:r2-r1+1, :));
    frameIdx = frameIdx + 1;
end

release(readerMADI);
release(readerANA);

%% Named channels
an5   = allSamples(:, 1);
mic11 = allSamples(:, 2);
mic12 = allSamples(:, 3);

%% Check levels
fprintf('\nPeak levels:\n');
fprintf('  AN5  : %.4f\n', max(abs(an5)));
fprintf('  Mic11: %.4f\n', max(abs(mic11)));
fprintf('  Mic12: %.4f\n', max(abs(mic12)));

%% Save
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
filename  = sprintf('recording_%s.wav', timestamp);
audiowrite(filename, double(allSamples), SAMPLE_RATE, 'BitsPerSample', 16);
fprintf('Saved: %s\n', filename);