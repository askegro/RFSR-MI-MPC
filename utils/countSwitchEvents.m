function n_sw = countSwitchEvents(S_prev, S_curr)
% COUNTSWITCHEVENTS  Number of per-cell switching changes between commands.
    n_sw = sum(abs(round(double(S_curr(:))) - round(double(S_prev(:)))));
end
