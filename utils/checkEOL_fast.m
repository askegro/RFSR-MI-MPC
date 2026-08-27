function [reached, cell_idx, soh_value, reason] = checkEOL_fast(SOH_cell_vec, EOL_cfg)
% Return scalars only; caller decides what to log/print.

    thr = EOL_cfg.threshold;

    % Recommend: set EOL_cfg.mode_id once at setup: 1=any_cell, 2=pack_mean
    mode_id = EOL_cfg.mode_id;

    reached = false;
    cell_idx = uint16(0);
    soh_value = NaN;
    reason = 0; % 1=any_cell, 2=pack_mean

    if mode_id == 1
        [soh_min, idx] = min(SOH_cell_vec);   % SOH_cell_vec should already be column
        if soh_min < thr
            reached = true;
            cell_idx = uint16(idx);
            soh_value = soh_min;
            reason = 1;
        end
    else % mode_id == 2
        soh_mean = mean(SOH_cell_vec);
        if soh_mean < thr
            reached = true;
            soh_value = soh_mean;
            reason = 2;
        end
    end
end
