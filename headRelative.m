function H = headRelative(S)
% HEADRELATIVE  Head position/direction and gaze relative to the head reference.
%   S = load('recording_....mat');  H = headRelative(S);
%   Reference frame: x = forward, y = left, z = up (as the head faced
%   during the reference). Angles in degrees, + azimuth = to the left.
%   Positions in mm. NaN where the glasses / eye tracker were occluded.
    ref  = S.HeadReference;
    R0   = ref.R0;
    wrap = @(a) mod(a + 180, 360) - 180;

    % Head position relative to the reference head (mm)
    H.pos = (S.GlobalTranslation - ref.p0') * R0;

    % Head direction: the head's forward axis, rotated into the reference frame
    Q = S.GlobalRotationQuaternion;            % [x y z w]
    n = size(Q, 1);
    f = nan(n, 3);
    for i = 1:n
        if all(isfinite(Q(i, :)))
            f(i, :) = (R0' * quatToRot(Q(i, :)) * ref.fwdLocal)';
        end
    end
    H.headAz = atan2d(f(:, 2), f(:, 1));
    H.headEl = asind(f(:, 3) ./ vecnorm(f, 2, 2));

    % Gaze direction in the reference frame
    g = S.EyeTrackerGlobalGazeVector;
    g = g ./ vecnorm(g, 2, 2);
    H.gaze   = g * R0;
    H.gazeAz = atan2d(H.gaze(:, 2), H.gaze(:, 1));
    H.gazeEl = asind(H.gaze(:, 3));

    % Eyes relative to the head (horizontal; approximate for small head tilt)
    H.eyeInHeadAz = wrap(H.gazeAz - H.headAz);

    H.t = S.FrameTime;
end

function R = quatToRot(q)
% q = [x y z w] (Vicon SDK order) -> 3x3 rotation matrix (segment -> lab)
    x = q(1); y = q(2); z = q(3); w = q(4);
    R = [1-2*(y^2+z^2)  2*(x*y-z*w)    2*(x*z+y*w);
         2*(x*y+z*w)    1-2*(x^2+z^2)  2*(y*z-x*w);
         2*(x*z-y*w)    2*(y*z+x*w)    1-2*(x^2+y^2)];
end
