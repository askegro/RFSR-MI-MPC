function [violPacked, lowIdx, vIdx] = packViolationCode_fast(x_k, y_k, limits)
% limits passed directly (avoid constants.limits deref)

    lowCode = uint16(0);
    vCode   = uint16(0);
    lowIdx  = uint16(0);
    vIdx    = uint16(0);

    % SOC (only compute max if min not violated)
    [zmin, izmin] = min(x_k.z);
    if zmin < limits.z_cell_min
        lowCode = uint16(1); lowIdx = uint16(izmin);  % SOC_LO
    else
        [zmax, izmax] = max(x_k.z);
        if zmax > limits.z_cell_max
            lowCode = uint16(2); lowIdx = uint16(izmax); % SOC_HI
        end
    end

    % Temperature
    [Tmin, iTmin] = min(x_k.T);
    if Tmin < limits.T_cell_min
        lowCode = uint16(3); lowIdx = uint16(iTmin);  % T_LO
    else
        [Tmax, iTmax] = max(x_k.T);
        if Tmax > limits.T_cell_max
            lowCode = uint16(4); lowIdx = uint16(iTmax); % T_HI
        end
    end

    % Voltage
    [vmin, ivmin] = min(y_k.v_cell_meas_vec);
    if vmin < limits.v_cell_min
        vCode = uint16(5); vIdx = uint16(ivmin);      % V_LO
    else
        [vmax, ivmax] = max(y_k.v_cell_meas_vec);
        if vmax > limits.v_cell_max
            vCode = uint16(6); vIdx = uint16(ivmax);  % V_HI
        end
    end

    violPacked = bitor(lowCode, bitshift(vCode, 8));
end
