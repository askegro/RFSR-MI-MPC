% FILE: rbs_sim/build/buildSyntheticDiagnosticProfile.m
% Generates a power profile designed to uniformly exercise all
% cardinality regimes from m=1 to m=N.
% Useful for diagnosing the cardinality vs power relationship
% without confounding from drive cycle structure.

function profile = buildSyntheticDiagnosticProfile(cfg, limits, models)

    Ns        = cfg.Ns;
    nSteps    = cfg.simSteps;
    Tstep     = cfg.Tstep;
    
    % Parameters
    v_cell_nom = models.cell.v_cell_nom;
    i_max      = limits.i_pack_max;         % max discharge current
    %v_pack_nom = v_cell_nom * Ns;           % nominal pack voltage

    % Power levels that correspond to each cardinality m = 1..N
    % Target: deliver enough power to require exactly m cells
    % P_target(m) = m * v_cell_nom * i_max * 0.85  (0.85 = load factor)
    load_factor = 0.85;
    m_targets   = 1:Ns;
    P_targets   = m_targets * v_cell_nom * i_max * load_factor;

    % --- Option A: Staircase ---
    % Hold each power level for a fixed dwell time, sweep up then down
    % This ensures each cardinality is visited multiple times
    dwell_steps = max(30, floor(nSteps / (2 * Ns)));  % steps per level
    
    % Ascending then descending
    P_seq = [P_targets, fliplr(P_targets)];
    P_staircase = repelem(P_seq, dwell_steps);
    
    % Trim or pad to nSteps
    if numel(P_staircase) >= nSteps
        P_staircase = P_staircase(1:nSteps);
    else
        P_staircase = [P_staircase, P_staircase(end) * ones(1, nSteps - numel(P_staircase))];
    end

    % --- Option B: Random uniform draw from power levels ---
    % Each step independently samples a power level uniformly
    % This gives good statistical coverage but no temporal structure
    rng(9999);  % fixed seed for reproducibility
    idx_rand    = randi(numel(P_targets), nSteps, 1);
    P_random    = P_targets(idx_rand)';
    
    % Add small Gaussian noise to avoid exact discrete values
    noise_frac  = 0.05;
    P_random    = P_random .* (1 + noise_frac * randn(nSteps, 1));
    P_random    = max(P_random, P_targets(1));   % clip to minimum

    % --- Choose which to use ---
    % Staircase is better for temporal plots (Figure hard segment)
    % Random is better for scatter plots (Plots 1-4 in diagnostic)
    % Default: staircase
    P_profile   = P_staircase(:);

    % Build output struct matching buildDriveCycle output format
    t_profile        = (0:nSteps-1)' * Tstep;
    profile.p_req_vec = P_profile;
    profile.t_profile = t_profile;
    profile.P_profile = P_profile;
    profile.P_staircase = P_staircase(:);
    profile.P_random    = P_random(:);
    profile.m_targets   = m_targets;
    profile.P_targets   = P_targets;

    fprintf('\n========================================\n');
    fprintf('  Diagnostic profile built\n');
    fprintf('========================================\n');
    fprintf('  Type: staircase over m = 1..%d\n', Ns);
    fprintf('  Dwell: %d steps per level\n', dwell_steps);
    fprintf('  P range: [%.1f, %.1f] W\n', min(P_profile), max(P_profile));
    fprintf('  Total steps: %d\n', nSteps);
    fprintf('========================================\n');
end