S = load('an5_test.mat');   % load into a struct
disp(S)                   % list the variables in the file

x  = S.an5;      % replace with your signal's variable name
fs = 48000;     % replace with your sampling-rate variable name



soundsc(micData(:,1), 48000);   % soundsc scales the level to avoid clipping