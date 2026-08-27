function profile = buildDriveCycle(cfg, limits, models)
    
    profile = struct();
    nSteps = cfg.simSteps;
    
    % --- Constant power override ---
    if isfield(cfg, 'driveCycle') && ...
       isfield(cfg.driveCycle, 'type') && ...
       strcmp(cfg.driveCycle.type, 'constant')

        P_const           = cfg.driveCycle.P_const;
        profile.p_req_vec = P_const * ones(nSteps, 1);
        profile.t_profile = (0:nSteps-1)' * cfg.Tstep;
        profile.P_profile = profile.p_req_vec;

        fprintf('\n========================================\n');
        fprintf('  Drive cycle: CONSTANT %.1f W\n', P_const);
        fprintf('========================================\n');
        report_min_abs_power(profile, cfg);
        return;


    % In buildDriveCycle, add a branch:
    elseif strcmp(cfg.driveCycle.type, 'diagnostic')
        profile = buildSyntheticDiagnosticProfile(cfg, limits, models);
        return;    

    end    

    if exist('buildScaledDriveCycle','file') ~= 2
        warning('buildScaledDriveCycle not found. Using zero power request.');
        profile.p_req_vec = zeros(nSteps,1);
        profile.t_profile = (0:nSteps-1)' * cfg.Tstep;
        profile.P_profile = zeros(size(profile.t_profile));
        return;
    end
    
    % Optional: warning SOC bounds if present in some constraint sets
    z_max = limits.z_cell_max;
    z_min = limits.z_cell_min;
    
    % Scale the drive cycle to the pack limits
    [~, ScaledProfile, ~] = buildScaledDriveCycle( ...
        cfg.DriveCycleFile, cfg.N_cycles_required, z_max, z_min, ...
        cfg.CellChemistry, cfg.CellParamFile, cfg.Ns, cfg.Np, cfg.PlotFigures);
    
    % Build a uniform time grid for interpolation (limited by profile length)
    t_end_profile = min(cfg.Tsimtotal, ScaledProfile.time_s(end));
    t_profile     = (0:cfg.Tstep:t_end_profile).';
    P_profile     = interp1(ScaledProfile.time_s, ScaledProfile.P_batt_scaled_W, ...
                            t_profile, 'linear', 'extrap');
    
    % Wrap the profile if simulation is longer than one cycle segment
    Tcycle    = t_profile(end) - t_profile(1);

    % Precompute discharge power request for all steps (wrapped)
    t_sim     = (0:nSteps-1)'*cfg.Tstep;
    t_wrapped = t_profile(1) + mod(t_sim, max(Tcycle, cfg.Tstep));
    
    % Use 'previous' so the request is held constant over each control interval
    p_req_vec = interp1(t_profile, P_profile, t_wrapped, 'previous', 'extrap');
    
    profile.p_req_vec = p_req_vec;
    profile.t_profile = t_profile;
    profile.P_profile = P_profile;
    
    fprintf('\n========================================\n');
    fprintf('  Drive cycle built\n');
    fprintf('========================================\n');
    fprintf('  P_peak=%.1f W | P_mean=%.1f W | P_rms=%.1f W\n', max(P_profile), mean(P_profile), rms(P_profile));
    fprintf('  E=%.3f Wh\n', sum(P_profile)*cfg.Tstep/3600);
    fprintf('========================================\n');

    report_min_abs_power(profile, cfg);

end


% -------------------------------------------------------------------------
function report_min_abs_power(profile, cfg)
% REPORT_MIN_ABS_POWER  Log and assert that the request is nonzero everywhere.
%
% Purpose
%   Two code paths are specified only for a nonzero power request:
%     - the zero-power branch of computeRankingScore (rho_v = 0), and
%     - the discharge convention for sgn(P_req) = 0 in build_power_horizon.
%   Neither is exercised by the profiles used for the reported results, because
%   the scaled drive cycle carries a constant auxiliary load. This check records
%   that fact in the run log instead of leaving it as an implicit assumption,
%   and it also establishes K_act = {k : P_req(k) ~= 0} = all simulated steps.

    if isfield(cfg, 'NUMERICS') && isfield(cfg.NUMERICS, 'TRACKING_POWER_EPS')
        p_eps = cfg.NUMERICS.TRACKING_POWER_EPS;
    else
        p_eps = 1e-9;
    end

    min_abs_p = min(abs(profile.p_req_vec));

    fprintf('  min |P_req| over profile: %.4f W (TRACKING_POWER_EPS = %.1e W)\n', ...
            min_abs_p, p_eps);

    assert(min_abs_p > p_eps, ...
        ['buildDriveCycle: profile contains a zero-power step ' ...
         '(min |P_req| = %.3e W <= %.1e W). The zero-power branches of ' ...
         'computeRankingScore and build_power_horizon are then exercised, ' ...
         'and K_act no longer equals the set of all simulated steps.'], ...
        min_abs_p, p_eps);

end
