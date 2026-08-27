function dq = dq_cal_update_xu2023(t_days, dt_days, T, soc, p)
% dq_cal_update_xu2023
% Calendar aging increment for Xu et al. (Nat Commun 2023) LFP/graphite
%
% Exact model (increment form):
%   dq = K_cal * fT(T) * fUa(Ua(soc),T) * (sqrt(t+dt) - sqrt(t))
%
% Uses stable identity:
%   sqrt(t+dt) - sqrt(t) = dt / (sqrt(t+dt) + sqrt(t))

    % --- SOC -> xa (graphite lithiation)
    xa = p.xa_0 + soc .* (p.xa_100 - p.xa_0);

    % --- xa -> Ua (Xu graphite half-cell OCV fit)
    Ua = 0.6379 + 0.5416 .* exp(-305.5309 .* xa) + ...
         0.044  .* tanh(-(xa - 0.1958) ./ 0.1088) - ...
         0.1978 .* tanh( (xa - 1.0571) ./ 0.0854) - ...
         0.6875 .* tanh( (xa + 0.0117) ./ 0.0529) - ...
         0.0175 .* tanh( (xa - 0.5692) ./ 0.0875);

    % --- Stress factors
    invT = 1 ./ T;
    fT   = exp(-(p.Ea./p.R_gas) .* (invT - 1./p.T_ref));
    fUa  = exp((p.alpha.*p.F./p.R_gas) .* (Ua .* invT - p.Ua_ref./p.T_ref));

    % --- Time increment factor (scalar)
    dt_sqrt = dt_days ./ (sqrt(t_days + dt_days) + sqrt(t_days));

    % --- Increment
    dq = (p.kCal_days05 .* fT .* fUa) .* dt_sqrt;
end
