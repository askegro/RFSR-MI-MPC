function ep = getEpisodeType(stateId, states)

    if stateId == states.DISCHARGE_HIGH || stateId == states.DISCHARGE_LOW
        ep = "DISCHARGE";
    elseif stateId == states.CHARGE_BULK || stateId == states.CHARGE_BALANCE
        ep = "CHARGE";
    else
        ep = "REST";
    end

end
