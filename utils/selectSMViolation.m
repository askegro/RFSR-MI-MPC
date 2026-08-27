function [viol_sm_code, viol_sm_idx] = selectSMViolation(violPacked, violIdx, smState, states)
% Select one violation code + cell index for state-machine decisions.

    lowCode = uint8(bitand(violPacked, uint16(255)));           % 0..255
    vCode   = uint8(bitshift(violPacked, -8));                  % 0..255

    % Default
    viol_sm_code = uint8(0);
    viol_sm_idx  = uint16(0);

    % Priority: Voltage > Temperature > SOC
    % Also gate SOC direction depending on charge/discharge state if desired.

    % 1) Voltage always matters
    if vCode ~= 0
        viol_sm_code = vCode;
        viol_sm_idx  = violIdx.v;
        return;
    end

    % 2) Low-byte (SOC/T enum)
    if lowCode ~= 0
        % Optional gating: ignore SOC_HI in discharge, ignore SOC_LO in charge
        if (smState == states.DISCHARGE_HIGH || ...
                smState == states.DISCHARGE_LOW || ...
                smState == states.REST_AFTER_DISCHARGE)
            % In discharge-side states, SOC_HI is not really a violation worth reacting to
            if lowCode == 2  % VIOL_SOC_HI
                return;
            end
        elseif (smState == states.CHARGE_BULK || ...
                smState == states.CHARGE_BALANCE || ...
                states.REST_AFTER_CHARGE)
            if lowCode == 1  % VIOL_SOC_LO
                return;
            end
        end

        viol_sm_code = lowCode;
        viol_sm_idx  = violIdx.low;
        return;
    end
end