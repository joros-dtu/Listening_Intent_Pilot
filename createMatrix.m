function [outputMatrix] = createMatrix(datastream_output, inputType)
% This function takes the individual segment output from
% 'ViconDataStreamSDK_MATLABTest.m' and converts the data into a matrix,
% where each column represents a coordinate set and each row represents the
% number of recorded datapoints.

% Transpose matrix
datastream_output = datastream_output';

% Set the value of x based on the input type
if strcmp(inputType, 'translation')
    x = 3;
elseif strcmp(inputType, 'quaternion')
    x = 4;
else
    error('Invalid input type. Must be either ''translation'' or ''quaternion''.');
end

n = numel(datastream_output);
outputMatrix = zeros(n, x); % Preallocate matrix based on the type

for i = 1:n
    outputMatrix(i, :) = cell2mat(datastream_output(i));
end

end