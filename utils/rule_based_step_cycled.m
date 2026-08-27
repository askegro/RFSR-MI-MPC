function [i_pack_cmd, S_cmd, p_pack_req, v_pack] = ...
        rule_based_step_cycled(x_k, sm, constants, driveCycle, cycle_offset, n_engage)
% RULE_BASED_STEP_CYCLED  Deterministic plant driver with rotating engagement set.
%
% Identical to RULE_BASED_STEP except that the discharge engagement set is
% rotated by CYCLE_OFFSET (0-indexed) modulo Ns.  This prevents the
% systematic SOC imbalance that arises when physical cells 1..m are always
% engaged, while preserving the controller's fundamental properties: it
% remains memoryless, SOC-agnostic, and SOH-agnostic.
%
% Engagement rules
%   REST      : i_pack = 0, S = zeros(Ns,1).
%   CHARGE    : all cells engaged (S = ones); i_pack from quadratic.
%   DISCHARGE : n_engage cells engaged, starting at physical cell
%               mod(cycle_offset, Ns) + 1  and wrapping modulo Ns.
%               i_pack from quadratic.
%
% Cycling convention
%   cycle_offset is 0-indexed.  Step 1 → offset 0 → cells {1..n_engage}.
%   Step 2 → offset 1 → cells {2..n_engage+1}.  Wraps at Ns.
%   The run script increments cycle_offset at every discharge step and
%   passes the current value here.
%
% Inputs
%   x_k          Plant state at step k
%   sm           State-machine struct (current state, step_in_state, …)
%   constants    Constants bundle (from buildConstantsBundle)
%   driveCycle   Drive-cycle struct (p_req_vec, …)
%   cycle_offset Non-negative integer, 0-indexed rotation of the engagement
%                set.  Caller must wrap modulo Ns if desired; this function
%                uses mod(cycle_offset, Ns) internally.
%   n_engage     Number of cells to engage during discharge.  Must satisfy
%                n_engage >= limits.Ns_min_voltage_safe.  If omitted,
%                defaults to limits.Ns_min_voltage_safe (backward compatible).
%
% Outputs
%   i_pack_cmd   [A]   Pack current (positive = discharge, negative = charge)
%   S_cmd        Ns×1  Binary engagement vector
%   p_pack_req   [W]   Requested pack power at this step
%   v_pack       [V]   Estimated pack voltage (consistent with i_pack_cmd)

    %% Unpack constants
    Ns         = constants.cfg.Ns;
    elec       = constants.models.elec;
    R0         = elec.R0;
    R1         = elec.R1;
    R2         = elec.R2;
    r_s        = elec.r_s;
    limits     = constants.limits;
    i_pack_min = limits.i_pack_min;
    i_pack_max = limits.i_pack_max;
    states     = constants.states;

    %% Drive-cycle request at this step
    step_in_state = sm.step_in_state;
    p_req_vec     = driveCycle.p_req_vec(:);
    idx           = 1 + mod(step_in_state - 1, numel(p_req_vec));
    p_pack_req    = p_req_vec(idx);

    %% REST — return zeros immediately
    if is_rest_state(sm.currentState, states)
        i_pack_cmd = 0;
        S_cmd      = zeros(Ns, 1);
        v_pack     = 0;
        p_pack_req = 0;
        return;
    end

    %% Choose engagement set
    if p_pack_req >= 0
        % Discharge: engage n_engage cells starting at the rotated offset.
        if nargin < 6 || isempty(n_engage)
            m = max(1, limits.Ns_min_voltage_safe);
        else
            m = max(limits.Ns_min_voltage_safe, min(Ns, n_engage));
        end
        offset    = mod(cycle_offset, Ns);                  % 0-indexed start
        cell_idx  = mod((0:m-1) + offset, Ns) + 1;         % 1-indexed, wrapped
        S_cmd     = zeros(Ns, 1);
        S_cmd(cell_idx) = 1;
    else
        % Charge: engage all cells (cycle_offset has no effect).
        m     = Ns;
        S_cmd = ones(Ns, 1);
    end

    %% Cell-state vectors
    v_OC_k = constants.models.ocv.func(x_k.z(:));   % Ns×1
    iRC1_k = x_k.iRC1(:);                            % Ns×1
    iRC2_k = x_k.iRC2(:);                            % Ns×1

    %% Effective voltage and resistance for engaged subset
    S_log = logical(S_cmd);
    V_eff = sum(v_OC_k(S_log)) ...
          - R1 * sum(iRC1_k(S_log)) ...
          - R2 * sum(iRC2_k(S_log));
    R_eff = (R0 + r_s) * m;

    %% Quadratic: R_eff*i^2 - V_eff*i + p_req = 0
    %  Physical root: i = (V_eff - sqrt(disc)) / (2*R_eff)
    %  Works for both discharge (p_req>0) and charge (p_req<0).
    disc = V_eff^2 - 4 * R_eff * p_pack_req;

    if disc >= 0
        i_pack_cmd = (V_eff - sqrt(disc)) / (2 * R_eff);
    else
        % Requested power exceeds capability; fall back to current limit.
        if p_pack_req >= 0
            i_pack_cmd = i_pack_max;
        else
            i_pack_cmd = i_pack_min;
        end
    end

    %% Clamp to hardware limits
    i_pack_cmd = max(i_pack_min, min(i_pack_max, i_pack_cmd));

    %% Estimated pack voltage (consistent with i_pack_cmd and engaged set)
    v_pack = V_eff - R_eff * i_pack_cmd;

end
