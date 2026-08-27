function [rho_raw, rho_SOH, rho_SOC, rho_v] = computeRankingScore( ...
        z_k, SOH_inv_k, Q_eff_As_k, v_term, i_exp, ...
        dis_step1, dzT_max, p_req_1, Ns_ref, lambda_scale_1, cfg)
% COMPUTERANKINGSCORE  Gradient-inspired per-cell suitability score.
%
% Purpose
%   Rank cells by their marginal contribution to the MPC cost J when
%   engaged.  The score approximates the negative gradient of J with respect
%   to the binary engagement decision S_i:
%
%       rho_i  =  -dJ/dS_i  ~=  rho_SOH_i + rho_SOC_i + rho_v_i
%
%   Cells with the largest rho_i are the most beneficial to engage.
%   The objective weights w_SOH, w_SOC, w_lambda set the relative
%   magnitudes of the three gradient components.
%
% Derivation
%   J = w_SOH * J_SOH  +  w_SOC * J_SOC  +  w_lambda * J_lambda
%
%   (1) J_SOH = (1/Np) * (1/N) * sum_ell sum_i [ (SOH^EOL / SOH_i) * S_i(ell) ]
%       => -d(J_SOH_total)/d(S_i(1)) = -w_SOH * SOH^EOL * SOH_inv_i / (Np * N)
%       => rho_SOH_i = -w_SOH * SOH^EOL * SOH_inv_i / (Np * N)
%       Ordering: healthier cells (lower SOH_inv) rank higher.
%
%   (2) J_SOC one-step-ahead proxy (horizon-averaged):
%       SOC_i(k+1) = SOC_i(k) - (Dt / Q_i) * i_exp * S_i(k)
%       J_SOC ~ (1/Np) * (1/N) * sum_i [ (SOC_i(k+1) - SOC_bar)^2 / DeltaSOCmax^2 ]
%       => rho_SOC_i = -2*Dt*i_exp / (Np * N * Q_i * DeltaSOCmax^2) * (SOC_i - SOC_bar)
%       Approximation: one-step proxy only; does not account for later horizon steps.
%       Discharge: engage high-SOC cells first (rho_SOC_i > 0 when SOC_i > SOC_bar)
%       Charge:    sign flips — engage low-SOC cells first
%
%   (3) Voltage-headroom sensitivity:
%       The sign follows from operating-direction voltage headroom.
%       During discharge, a cell with higher terminal voltage v_i has larger
%       headroom before the lower voltage limit: h_i^dis = v_i - v_min.
%       During charge, a cell with lower terminal voltage has larger headroom
%       before the upper limit: h_i^chg = v_max - v_i.
%       Centering and dropping constants gives the signed score:
%           rho_v_i = +alpha_v * v_i   (discharge, prefer high-voltage cells)
%           rho_v_i = -alpha_v * v_i   (charge,    prefer low-voltage cells)
%       The scaling alpha_v = w_lambda * lambda_scale_1 / Np * i_exp^2 / |P_req|
%       is dimensionally consistent with rho_SOH and rho_SOC and varies
%       sensibly with operating conditions.  It is not derived as the active
%       gradient of the curtailment objective (which is zero when lambda = 0).
%       For |P_req| <= cfg.NUMERICS.TRACKING_POWER_EPS the component is set to
%       zero exactly, matching the p_req = 0 case of the manuscript score.
%       Set cfg.ranking.use_rho_v = false to zero this component entirely.
%
% Inputs
%   z_k            [N x 1]  Cell SOC at current step (fractional, 0–1)
%   SOH_inv_k      [N x 1]  1/SOH_i  (pre-computed in runtime struct)
%   Q_eff_As_k     [N x 1]  Effective cell capacity [A·s]  (= Q_nominal * SOH_i)
%   v_term         [N x 1]  Estimated loaded terminal voltage [V]
%   i_exp          scalar   Representative per-cell current magnitude [A] (>0)
%   dis_step1      logical  true = discharging at horizon step 1, false = charging
%   dzT_max        scalar   DeltaSOC_max (terminal SOC-spread allowance)
%   p_req_1        scalar   First-horizon power request [W] (signed)
%   Ns_ref         scalar   Reference number of engaged cells
%   lambda_scale_1 scalar   Curtailment normalisation at step 1: 1/I_scale_1
%                             (= lambda_scale(1) from controller_step.m)
%   cfg            struct   Config struct with fields:
%                             cfg.Ns              — total number of cells N
%                             cfg.mpc.Np          — prediction horizon N_p
%                             cfg.Tstep           — sampling interval [s]
%                             cfg.w.SOH           — w_SOH
%                             cfg.w.SOC           — w_SOC
%                             cfg.w.lambda        — w_lambda
%                             cfg.EOL.threshold   — SOH^EOL
%                             cfg.ranking.use_rho_v — (optional) gate rho_v
%
% Outputs
%   rho_raw    [N x 1]  Total ranking score
%   rho_SOH    [N x 1]  SOH gradient component  (exact)
%   rho_SOC    [N x 1]  SOC gradient component  (one-step-ahead approximation)
%   rho_v      [N x 1]  Voltage/curtailment component (prospective; zero when inactive)

    %% --- Parameters -------------------------------------------------------
    N        = cfg.Ns;
    Np       = cfg.mpc.Np;
    Dt       = cfg.Tstep;
    w_SOH    = cfg.w.SOH;
    w_SOC    = cfg.w.SOC;
    w_lambda = cfg.w.lambda;
    SOH_EOL  = cfg.EOL.threshold;

    % Guarded representative per-cell current used in the rho_v numerator.
    % NOTE ON NAMING: this is the manuscript's i_exp (eq:iexp_rank), NOT the
    % manuscript's i_scale (eq:iscale, = i_pack^max or |i_pack^min|). The latter
    % enters this function through lambda_scale_1 = 1 / I_scale.
    i_exp_safe = max(i_exp, 1e-6);

    % Zero-power detection threshold (manuscript eq:rho_v, p_req = 0 case).
    if isfield(cfg, 'NUMERICS') && isfield(cfg.NUMERICS, 'TRACKING_POWER_EPS')
        p_eps = cfg.NUMERICS.TRACKING_POWER_EPS;
    else
        p_eps = 1e-9;
    end

    %% --- Component 1: SOH gradient ----------------------------------------
    %  Full averaged-horizon gradient: -d(J_SOH_total)/d(S_i(1))
    %    = -w_SOH * SOH^EOL * SOH_inv_i / (Np * N)
    %  More degraded cells (high SOH_inv) get a more negative score => ranked lower.
    %  The ordering is the same as the single-stage gradient; Np scales the magnitude.
    rho_SOH = -w_SOH * SOH_EOL * SOH_inv_k(:) / (Np * N);

    %% --- Component 2: SOC gradient ----------------------------------------
    %  One-step-ahead proxy for -d(J_SOC_total)/d(S_i(1)), horizon-averaged.
    %  SOC_i(k+1) = SOC_i(k) - (Dt/Q_i) * i_exp * S_i(k)
    %  Differentiating the one-step J_SOC proxy and dividing by Np:
    %    coeff_i = 2 * Dt * i_exp / (Np * N * Q_i * DeltaSOCmax^2)
    %  Approximation: captures only the immediate SOC effect; later-step
    %  propagation through the horizon is neglected.
    SOC_bar = mean(z_k);
    dSOC    = z_k(:) - SOC_bar;                            % deviation from pack mean

    coeff = 2 * Dt * i_exp ./ (Np * N * Q_eff_As_k(:) * dzT_max^2);

    if dis_step1
        % Discharge: engage high-SOC cells to reduce spread — rho_SOC > 0 when SOC_i > SOC_bar
        rho_SOC = w_SOC * coeff .* dSOC;
    else
        % Charge: engage low-SOC cells to reduce spread — sign flips
        rho_SOC = -w_SOC * coeff .* dSOC;
    end

    %% --- Component 3: Voltage-headroom sensitivity -------------------------
    %  rho_v_i = sgn(p_req) * alpha_v * v_term_i
    %  alpha_v = w_lambda * lambda_scale_1 / Np * i_exp^2 / |p_req|
    %
    %  Discharge (+): prefer high-voltage cells (more headroom above v_min).
    %  Charge    (-): prefer low-voltage cells (more headroom below v_max).
    %
    %  Guard against zero power request (rest steps).
    abs_p_req_safe = max(abs(p_req_1), 1e-6);
    if abs(p_req_1) <= p_eps
        % Manuscript eq:rho_v, zero-power case: rho_v = 0 exactly.
        % Without this branch the two numerical guards (i_exp_safe and
        % abs_p_req_safe) leave a residue of order 1e-5 rather than 0.
        rho_v = zeros(size(z_k));
    elseif dis_step1
        rho_v =  w_lambda * lambda_scale_1 / Np * i_exp_safe^2 / abs_p_req_safe * v_term(:);
    else
        rho_v = -w_lambda * lambda_scale_1 / Np * i_exp_safe^2 / abs_p_req_safe * v_term(:);
    end

    %% --- Voltage component gate --------------------------------------------
    %  cfg.ranking.use_rho_v = false zeros this component, leaving only
    %  rho_SOH + rho_SOC to drive the ranking (Option C diagnostic).
    %  Default true preserves existing behaviour.
    if isfield(cfg, 'ranking') && isfield(cfg.ranking, 'use_rho_v') ...
            && ~cfg.ranking.use_rho_v
        rho_v = zeros(size(rho_v));
    end

    %% --- Total score -------------------------------------------------------
    rho_raw = rho_SOH + rho_SOC + rho_v;

end
