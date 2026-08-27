function m = extract_robustness_metrics(log_struct, cfg)
% EXTRACT_ROBUSTNESS_METRICS  Standard V-C metric set from a single log.
%
% Given the log struct produced by run_robustness_sweeps.m's run_one (or by
% tcst_run_variant.m), returns a struct with the metrics quoted in
% Section VI-B of the manuscript:
%
%   tracking_mae        mean relative |p_pack_meas - p_pack_req| / |p_pack_req|
%                       over active steps with |p_req| > 1e-9 W, in percent.
%                       Uses log.p_pack_meas (plant-measured: v_pack_meas *
%                       i_pack_cmd) to match Sec. V-D, eq:trackingErrorCL.
%                       Falls back to i_pack_cmd*v_pack for legacy result
%                       files that pre-date the p_pack_meas logging field.
%   curt_frac           fraction of active steps where the MPC optimizer
%                       returned a positive curtailment slack (slack_mag > 0.01) [%].
%                       NOTE: this counts optimizer-slack incidence only.
%                       Steps where the solver failed and the zero-current
%                       fallback was applied contribute to tracking_mae but
%                       are NOT counted here. Do not describe this metric as
%                       "total unserved-power frequency" in the manuscript.
%   fail_frac           fraction of active steps with no usable solution at
%                       all (zero-current fallback applied) [%]. Distinct
%                       from curt_frac (optimizer-slack incidence only).
%   soc_std_mean        mean cross-sectional SOC standard deviation [%]
%                       (averaged over all stored states except the unset
%                        first slot)
%   efc_spread          (max - min) of EFC_cell_vec(:, end) across cells
%   p95_solve_ms        95th-percentile Gurobi internal solver time, milliseconds
%   med_solve_ms        median Gurobi internal solver time, milliseconds
%   opt_rate            share of active steps with proven optimality [%]
%   n_active            number of active steps
%   J_SOH_mean, J_SOC_mean, J_curt_mean  time-averaged stage-cost components
%                       on usable steps (proven optimal or incumbent)
%
% Notes
%   - Tracking uses log.p_pack_meas (v_pack_meas * i_pack_cmd) when present,
%     consistent with Sec. V-D eq:trackingErrorCL.  Falls back to
%     i_pack_cmd*v_pack (MPC-predicted voltage) for pre-fix result files.
%   - Switching cost (legacy J_sw, J_sw_prev) is intentionally excluded
%     to match the manuscript objective, eq:ContrOBJ.

    L = log_struct;

    % --- Masks ----------------------------------------------------------
    active   = ~L.rest_skip;
    opt      = L.optimality_proven & active;
    inc      = L.incumbent_timeout & active;
    usable   = (opt | inc) & active;

    m.n_active = sum(active);

    % --- Tracking error -------------------------------------------------
    p_req  = L.p_pack_req;
    % Use plant-measured delivered power (v_pack_meas * i_pack_cmd) to match
    % the manuscript tracking-metric definition (Sec. V-D, eq:trackingErrorCL).
    % Fall back to i_pack_cmd*v_pack only for legacy result files that pre-date
    % the p_pack_meas logging field.
    if isfield(L, 'p_pack_meas') && any(isfinite(L.p_pack_meas))
        p_del  = L.p_pack_meas;
    else
        p_del  = L.i_pack_cmd .* L.v_pack;   % legacy fallback: MPC-predicted voltage
    end
    nz     = active & (abs(p_req) > 1e-9);
    if any(nz)
        rel = abs(p_req(nz) - p_del(nz)) ./ max(abs(p_req(nz)), 1e-9);
        m.tracking_mae = mean(rel, 'omitnan') * 100;
    else
        m.tracking_mae = NaN;
    end

    % --- Curtailment ----------------------------------------------------
    if any(active)
        Curt = computeCurtailmentMetric(L, active);
        m.curt_frac = 100 * Curt;
    else
        m.curt_frac = NaN;
    end

    % --- Hard failure rate ------------------------------------------------
    % Steps where no usable solution was returned at all (zero-current
    % fallback applied). Distinct from curt_frac, which only counts
    % optimizer-reported curtailment slack on usable solves.
    if any(active)
        m.fail_frac = 100 * mean(L.hard_fail(active));
    else
        m.fail_frac = NaN;
    end    

    % --- SOC dispersion -------------------------------------------------
    z = L.z_cell_vec;
    if size(z, 2) >= 2
        sig = std(z(:, 2:end), 1, 1) * 100;   % population std (1/N); col 1 is x0 (pre-control), excluded from closed-loop mean
        sig = sig(isfinite(sig));
        if ~isempty(sig)
            m.soc_std_mean = mean(sig);
        else
            m.soc_std_mean = NaN;
        end
    else
        m.soc_std_mean = NaN;
    end

    % --- EFC spread -----------------------------------------------------
    if isfield(L, 'EFC_cell_vec') && size(L.EFC_cell_vec, 2) >= 1
        efc_end       = L.EFC_cell_vec(:, end);
        efc_end       = efc_end(isfinite(efc_end));
        if ~isempty(efc_end)
            m.efc_spread = max(efc_end) - min(efc_end);
        else
            m.efc_spread = NaN;
        end
    else
        m.efc_spread = NaN;
    end

    % --- Solver runtimes ------------------------------------------------
    % Use solver_time (Gurobi internal time) as the canonical runtime metric.
    % run_montecarlo_ics.m must also use solver_time for cross-section
    % comparability.
    sw_active = L.solver_time(active);
    sw_active = sw_active(isfinite(sw_active));
    if ~isempty(sw_active)
        m.med_solve_ms = median(sw_active) * 1e3;
        m.p95_solve_ms = prctile(sw_active, 95) * 1e3;
    else
        m.med_solve_ms = NaN;
        m.p95_solve_ms = NaN;
    end

    % --- Optimality rate ------------------------------------------------
    if any(active)
        m.opt_rate = 100 * mean(L.optimality_proven(active));
    else
        m.opt_rate = NaN;
    end

    % --- Stage-cost components, time-averaged on usable steps -----------
    if any(usable)
        m.J_SOH_mean  = mean(L.J_SOH(usable),  'omitnan');
        m.J_SOC_mean  = mean(L.J_SOC(usable),  'omitnan');
        m.J_curt_mean = mean(L.J_curt(usable), 'omitnan');
        m.J_obj_mean = computeWeightedObjective( ...
            m.J_SOH_mean, m.J_SOC_mean, m.J_curt_mean, cfg);        
    else
        m.J_SOH_mean  = NaN;
        m.J_SOC_mean  = NaN;
        m.J_curt_mean = NaN;
        m.J_obj_mean = NaN;
    end
end
