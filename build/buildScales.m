function scale = buildScales(limits, driveCycle)

    % typical scales (optional; used for MPC normalization)
    P_profile   = driveCycle.P_profile;
    if isempty(P_profile)
        P_scale = 100;
    else
        P_scale = max(rms(P_profile), 100);
    end
    
    scale       = struct();
    scale.P     = P_scale;
    scale.Ns    = limits.Ns_max; 
    scale.z     = 1;

end