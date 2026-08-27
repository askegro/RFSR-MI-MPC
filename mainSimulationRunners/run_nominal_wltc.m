% FILE: mainSimulationRunners/run_nominal_wltc.m

% --- Initial clears
clc; close all; clearvars;

fprintf('\n>>> Entering run_nominal_wltc\n');

% --- Ensure project subfolders are on path and initialise reproducible environment
rootDir = initProjectPaths(mfilename('fullpath')); 
env = prepareSimulationEnvironment();


% --- Load config (pure knobs)
cfg                 = default_config();
%cfg.Ns              = 8;    % [-] Number of cells in series
%cfg.mpc.Np          = 20;   % [-] Prediction horizon length N_p (steps)
%cfg.DEBUG.keep_diagnostics = true;
%cfg.DEBUG.solver_io = true;


% --- Build chemistry + raw structs
[chem, raw]         = buildChemistry(cfg);


% --- Build models (derived coefficients + ocv func + aging handles)
models              = buildModels(cfg, chem, raw);
ocv_pwl             = buildOCVpwl(cfg, chem);
models.ocv.ocv_pwl  = ocv_pwl;


% --- Build safe operating limits (currents/SOC/V/T + Ns_cmd bounds)
limits              = buildLimits(cfg, models, raw.constraints);
models.pwl.invVpack = buildInvVpackPWLAuto(limits.v_pack_min, limits.v_pack_max, cfg.Ns, cfg.limits.inv_vpack_max_err_mV);


% --- Build charging derived params (V_CEILING/V_REG/V_ENTER/...)
chg                 = buildChargingParams(cfg, chem, limits);


% --- Build drive cycle request
driveCycle          = buildDriveCycle(cfg, limits, models);


% --- Build state enum + init state
[states, ~, ...
    stateInitID, ...
    id2name]        = buildStateMachineEnum(cfg);


% --- Init state machine context
sm                  = buildStateMachine(states, stateInitID, ...
                        cfg.stateMachineParams, chg, id2name);


% --- Preallocate logging
log                 = buildLogging(cfg);


% --- Initial state vectors
x0                  = buildInitialState(cfg, env, models);

% --- Build scaling factors for MPC
scale               = buildScales(limits, driveCycle);


% --- Build solver options for MPC
solver              = buildSolverOptions(cfg);


% --- Runtime init (mutable sim state)
runtime             = buildRuntimeInit(cfg, sm, x0, models);


% --- Assemble constants bundle (immutable stuff)
constants           = buildConstantsBundle(cfg, env, chem, ...
    raw, models, limits, chg, states, driveCycle, scale, solver);


% --- Extract some useful constants
zeroNs              = zeros(cfg.Ns,1);
onesNs              = ones(cfg.Ns,1);
v_OC_anonFun        = constants.models.ocv.func;    

u_plant_k           = struct( ...
                        'i_cell', zeroNs, ...
                        'i_cell_bal', zeroNs, ...
                        'v_oc', zeroNs, ...
                        't_days', 0, ...
                        'SOH_cell', onesNs, ...
                        'ep', runtime.episode, ...
                        'FLAG_CycUpdate_k', false);

% Build optimizers once
opt                     = buildOptimizers(constants);



fprintf('\n========================================\n');
fprintf('  Setup Complete\n');
fprintf('========================================\n');
fprintf('  Cells: %d (series)\n', cfg.Ns);
fprintf('  Steps: %d, Ts=%.3f s\n', cfg.simSteps, cfg.Tstep);
fprintf('  Chemistry: %s\n', cfg.CHEMISTRY_TYPE);
fprintf('========================================\n\n');


% V-B requires both A (baseline) and D (proposed) on the same cycle.
variants = struct( ...
  'id',               {'A',           'D'}, ...
  'enable_sorting',   {false,          true}, ...
  'enable_monotone',  {false,          true}, ...
  'use_rho_v',        {true,           true}, ...
  'timeLimit',        {cfg.timeLimit,  cfg.timeLimit});

Results = struct();

for v = 1:numel(variants)

    % Reset persistent state in controller (ranking LPF uses persistent score_prev)
    rng(1337,'twister');
    env_v = struct();
    env_v.sSOH = RandStream('Threefry','Seed',42);
    env_v.sSOC = RandStream('Threefry','Seed',4242);

    cfg_v                       = cfg;
    cfg_v.timeLimit             = variants(v).timeLimit;
    % Set variant flags on cfg_v.mpc so that buildConstantsBundle propagates
    % them into constants_v.cfg automatically (same pattern as tcst_run_variant).
    cfg_v.mpc.enable_sorting    = variants(v).enable_sorting;
    cfg_v.mpc.enable_monotone   = variants(v).enable_monotone;
    % Also set top-level aliases for backward compatibility with any code that
    % reads cfg_v.enable_sorting / cfg_v.enable_monotone directly.
    cfg_v.enable_sorting        = variants(v).enable_sorting;
    cfg_v.enable_monotone       = variants(v).enable_monotone;
    cfg_v.ranking.use_rho_v     = variants(v).use_rho_v;

    solver_v                    = buildSolverOptions(cfg_v);

    % Reset runtime + log (fresh initial conditions each variant)
    x0_v                        = buildInitialState(cfg, env_v, models);

    runtime_v = buildRuntimeInit(cfg, sm, x0_v, models);
    log_v     = buildLogging(cfg);
    log_v.z_cell_vec(:,1)   = x0_v.z(:);
    log_v.i_RC_1_vec(:,1)   = x0_v.iRC1(:);
    log_v.i_RC_2_vec(:,1)   = x0_v.iRC2(:);
    log_v.T_cell_vec(:,1)   = x0_v.T(:);
    log_v.EFC_cell_vec(:,1) = x0_v.EFC(:);
    log_v.SOH_cell_vec(:,1) = x0_v.SOH(:);

    constants_v = buildConstantsBundle(cfg_v, env_v, chem, ...
        raw, models, limits, chg, states, driveCycle, scale, solver_v);

    % Also set as top-level fields for backward compatibility with controller
    % code that reads constants_v.enable_sorting / constants_v.enable_monotone.
    constants_v.enable_sorting      = variants(v).enable_sorting;
    constants_v.enable_monotone     = variants(v).enable_monotone;
    constants_v.ranking.use_rho_v   = variants(v).use_rho_v;


    % IMPORTANT: rebuild optimizer per variant (monotone changes constraints)
    yalmip('clear');                 % safest; avoids cached optimizer structure issues
    opt_v = buildOptimizers(constants_v);

    fprintf('\n=== Running variant %s (sorting=%d, monotone=%d, use_rho_v=%d) ===\n', ...
        variants(v).id, constants_v.enable_sorting, constants_v.enable_monotone, ...
        variants(v).use_rho_v);

    % ---- MAIN LOOP: copy your existing run_sim loop, but use runtime_v/constants_v/opt_v/log_v ----
    for k = 1:cfg_v.simSteps
        
        
            % ====================================================================
            % 0. EXPLICITLY LABEL THE STATES
            % ====================================================================   
            x_k                             = runtime_v.x;
            y_prev                          = runtime_v.meas;
            %cmd_prev                        = runtime_v.prev;
        
        
        
            % ====================================================================
            % 1. COMPUTE METRICS FOR STATE MACHINE
            % ====================================================================
            % Simulation time
            t_current                       = (k-1)*cfg_v.Tstep;
            t_cal_days_k                    = t_current / 86400; 
        
            % v_OC
            v_OC_k                          = v_OC_anonFun(x_k.z);
             
            % Cell SOH
            SOH_cell_vec_k                  = x_k.SOH; 
        
            % ===== EOL CHECK ===== 
            [reached, cell_idx, soh_value, reason_id] = checkEOL_fast(SOH_cell_vec_k, cfg_v.EOL);
            if reached

                log_v.eol_reached   = true;
                log_v.eol_cell_idx  = cell_idx;
                log_v.eol_step      = k;
                log_v.eol_soh_value = soh_value;
                log_v.eol_reason    = ternary(reason_id==1, "any_cell", "pack_mean");
                fprintf('\nEOL reached at step %d (%s): value=%.4f, thr=%.4f', ...
                        k, log_v.eol_reason, soh_value, cfg_v.EOL.threshold);
                if cell_idx ~= 0
                    fprintf(', cell=%d', cell_idx);
                end
                fprintf('\n');
                break;
            end   
        
        
        
            % ====================================================================
            % 2. CHECK FOR VIOLATIONS ON CURRENT STATES
            % ====================================================================
            % Pre-violations (SOC/T) packed
            [violPacked, lowIdx, vIdx]   = packViolationCode_fast(x_k, y_prev, constants_v.limits);
            violIdx.low = lowIdx; violIdx.v = vIdx;
        
        
        
            % ====================================================================
            % 3. EVALUATE STATE TRANSITIONS BEFORE COMPUTING CONTROL
            % ==================================================================== 
            % Old state
            smOld                   = runtime_v.sm;
            currentState            = smOld.currentState;
            currentEpisodeType      = getEpisodeType(currentState, smOld.states);
        
            % State transition: old state -> new state
            smNew                   = evaluateStateTransitions(smOld, ...
                                        x_k, y_prev, constants_v, k, ...
                                        violPacked, violIdx);
            newState                = smNew.currentState;
            newEpisodeType          = getEpisodeType(newState, smNew.states);  
        
            % Check if episode type changed 
            FLAG_CycUpdate_k = ~strcmp(newEpisodeType, currentEpisodeType);
        
            % Update runtime_v > state machine
            runtime_v.sm                      = smNew;
        
        
        
            % ====================================================================
            % 4. CONTROL
            % ====================================================================       
            [runtime_v, p_pack_req, u_mpc, J_SOH, J_SOC, J_sw, J_sw_prev, J_curt] = ...
                controller_step(runtime_v, constants_v, opt_v, ...
                                        driveCycle, k, v_OC_k);
        
        

            % ====================================================================
            % 7. PLANT UPDATE
            % ====================================================================      
            % Plant inputs
            u_plant_k.S_cmd                 = u_mpc.S; 
            u_plant_k.i_pack_cmd            = u_mpc.i_pack_cmd;
            u_plant_k.i_cell_bal            = zeroNs;
            u_plant_k.v_oc                  = v_OC_k; 
            u_plant_k.t_days                = t_cal_days_k;
            u_plant_k.SOH_cell              = SOH_cell_vec_k;
            u_plant_k.ep                    = runtime_v.episode;     
            u_plant_k.FLAG_CycUpdate_k      = FLAG_CycUpdate_k;
            u_plant_k.episodeType           = newEpisodeType;
        
            % Plant update
            [x_new, y_k, ep, epEnd]         = advancePlantState(x_k, u_plant_k, constants_v);
            if y_k.invalid
                fprintf('\n*** TERMINATING: invalid plant state at step %d ***\n', k);
                break;
            end    
        
        
        
            % ====================================================================
            % 8. PLANT MEASUREMENTS
            % ====================================================================    
            % Violations (V) packed
            [violPacked, lowIdx, vIdx]   = packViolationCode_fast(x_k, y_k, constants_v.limits);  
            violIdx.low = lowIdx; violIdx.v = vIdx;
        
            % Update runtime_v > measurements    
            runtime_v.meas            = y_k;    
        
        
        
            % ====================================================================
            % 9. LOGGING
            % ==================================================================== 
            log_v.p_pack_req(k)                 = p_pack_req;
            log_v.i_pack_cmd(k)                 = u_mpc.i_pack_cmd;
            log_v.v_pack(k)                     = u_mpc.v_pack;
            log_v.p_pack_cmd(k)                 = u_mpc.i_pack_cmd * u_mpc.v_pack;
            log_v.S(:, k)                       = u_mpc.S;

            % Solution / solver status
            log_v.solve_wall(k)               = u_mpc.solve_wall;
            log_v.solver_time(k)              = u_mpc.solver_time;
            log_v.t_ctrl_wall(k)              = u_mpc.controller_wall;   % controller only: prepare + solve + extract
            log_v.t_prepare(k)                = u_mpc.t_prepare;          % ranking, sort, param build
            log_v.t_extract(k)                = u_mpc.t_extract;          % solution unpack + unsort
            log_v.problem_code(k)             = u_mpc.problem_code;  
            log_v.fail_type(k)                = string(u_mpc.fail_type);
            log_v.termination_class(k)        = string(u_mpc.termination_class);
            log_v.solution_source(k)          = string(u_mpc.solution_source);

            log_v.solution_usable(k)          = u_mpc.solution_usable;
            log_v.optimality_proven(k)        = u_mpc.optimality_proven;
            log_v.used_incumbent(k)           = u_mpc.used_incumbent;
            log_v.used_fallback(k)            = u_mpc.used_fallback;    

            log_v.timeout(k)                  = (u_mpc.termination_class == "timeout");
            log_v.infeasible(k)               = (u_mpc.termination_class == "infeasible");
            log_v.hard_fail(k)                = (u_mpc.solution_source == "fallback_failure");
            log_v.non_timeout_fail(k)         = (u_mpc.used_fallback && u_mpc.termination_class ~= "timeout");
            log_v.rest_skip(k)                = (u_mpc.solution_source == "fallback_rest");
            log_v.incumbent_timeout(k)        = (u_mpc.solution_source == "incumbent_timeout");            

            log_v.mip_gap(k)                  = u_mpc.mip_gap;
            log_v.obj_val(k)                  = u_mpc.obj_val; 
            log_v.node_count(k)               = u_mpc.node_count;
            log_v.best_bound(k)               = u_mpc.best_bound;
            log_v.incumbent_obj(k)            = u_mpc.incumbent_obj;

            log_v.n_engaged(k)                = u_mpc.n_engaged;
            if isfield(u_mpc, 'n_engaged_min_feasible')
                log_v.n_engaged_min_feasible(k) = u_mpc.n_engaged_min_feasible;
                log_v.Ns_min_stage_first(k)     = u_mpc.n_engaged_min_feasible;
            end            
            log_v.slack_mag(k)                = u_mpc.lambda_slack;
            % log_v.v_pack(k) and log_v.p_pack_cmd(k) logged above already
            log_v.status_str(k)               = string(u_mpc.status_str);
            
            log_v.J_SOH(k)   = J_SOH;
            log_v.J_SOC(k)      = J_SOC;           
            log_v.J_curt(k)  = J_curt;

            [J_obj, J_SOH_w, J_SOC_w, J_curt_w] = ...
                computeWeightedObjective(J_SOH, J_SOC, J_curt, constants_v.cfg);
            
            log_v.J_SOH_weighted(k)  = J_SOH_w;
            log_v.J_SOC_weighted(k)  = J_SOC_w;
            log_v.J_curt_weighted(k) = J_curt_w;
            log_v.J_obj(k)           = J_obj;
            
            log_v.J_sum_unweighted(k) = J_SOH + J_SOC + J_curt;
            
            log_v.J_SOH_raw(k)  = J_SOH;
            log_v.J_SOC_raw(k)  = J_SOC;
            log_v.J_curt_raw(k) = J_curt;

            log_v.dzT(k)                  = u_mpc.dzT;
            log_v.dzT_max(k)              = u_mpc.dzT_max;            


            log_v.score.rho_v(:,k)    = u_mpc.score.rho_v;
            log_v.score.rho_SOC(:,k)        = u_mpc.score.rho_SOC;            
            log_v.score.rho_SOH(:,k)        = u_mpc.score.rho_SOH;            
            log_v.score.raw(:,k)        = u_mpc.score.raw;
            log_v.score.smoothed(:,k)   = u_mpc.score.smoothed;
            log_v.rank_idx(:,k)         = u_mpc.rank_idx(:);
            % Prefix exactness is meaningful only for ranked/sorted variants.
            % For unsorted Variant A, physical-index prefix structure is not a manuscript metric.
            if constants_v.enable_sorting
                log_v.exact_prefix(k) = u_mpc.exact_prefix;
                log_v.prefix_break(k) = u_mpc.prefix_break;
            end
            if k == 1
                log_v.switch_events(k) = 0;  % no prior state; zero switches by definition
            else
                log_v.switch_events(k) = countSwitchEvents(log_v.S(:,k-1), u_mpc.S);
            end
        
        
            % ===== OUTPUTS =====
            % -------------------------
            % Electrical
            % ------------------------- 
            v_cell_meas_vec_k               = y_k.v_cell_meas_vec;
            log_v.v_cell_meas_vec(:,k)        = v_cell_meas_vec_k;
            log_v.v_pack_meas(k)              = y_k.v_pack_meas;    % actual plant pack voltage
            log_v.p_pack_meas(k)              = y_k.p_pack_meas;    % actual delivered power
            p_cell_loss_tot_vec_k           = y_k.p_cell_loss_tot_vec;
            log_v.p_cell_loss_tot_vec(:,k)    = p_cell_loss_tot_vec_k;

        
            % ===== STATES =====    
            % -------------------------
            % Electrical and thermal
            % ------------------------- 
            z_cell_vec_new                  = x_new.z;
            log_v.z_cell_vec(:,k+1)           = z_cell_vec_new; 
            iRC1_cell_vec_new               = x_new.iRC1;
            log_v.i_RC_1_vec(:,k+1)           = iRC1_cell_vec_new;
            iRC2_cell_vec_new               = x_new.iRC2;    
            log_v.i_RC_2_vec(:,k+1)           = iRC2_cell_vec_new;   
            T_cell_vec_new                  = x_new.T;
            log_v.T_cell_vec(:,k+1)           = T_cell_vec_new;
            EFC_cell_vec_new                = x_new.EFC;
            log_v.EFC_cell_vec(:,k+1)         = EFC_cell_vec_new;
            log_v.SOH_cell_vec(:,k+1)         = x_new.SOH;


            % ===== VIOLATIONS =====
            log_v.state(k)                    = double(smNew.currentState);
            log_v.viol_packed(k)              = violPacked;
            log_v.viol_idx(k)                 = lowIdx;
        
        
        
            % ====================================================================
            % 10. PROGRESS INDICATOR
            % ==================================================================== 
            if cfg_v.LOGGING.progress_every_steps > 0 && mod(k, cfg_v.LOGGING.progress_every_steps) == 0
                fprintf('Step: %4d/%d | State: %-20s | z_cell=[%.3f,%.3f] | i_pack_cmd=%.3fA | p_pack_req=%.3fW\n', ...
                    k, cfg_v.simSteps, string(smNew.name), min(x_k.z), ...
                    max(x_k.z), u_mpc.i_pack_cmd, p_pack_req);
            end    
        
        
        
            % ====================================================================
            % 11. UPDATE runtime_v
            % ====================================================================    
            % Update runtime_v
            runtime_v.x                 = x_new;
            runtime_v.prev.S            = u_mpc.S;
            runtime_v.prev.i_pack_cmd   = u_mpc.i_pack_cmd; 
            runtime_v.episode           = ep;


    end

    Results.(variants(v).id).log = log_v;
    Results.(variants(v).id).constants_v = constants_v;
end

% -------------------------------------------------------------------------
% SAVE RESULTS
% -------------------------------------------------------------------------
timestamp = string(datetime("today","Format","yyyyMMdd"));

resultsDir = ensureResultsDir(rootDir);
fname = fullfile(resultsDir, sprintf('Results_nominal_wltc_%s.mat', timestamp));

save(fname, ...
    'Results', ...
    'cfg', ...
    'variants', ...
    '-v7.3');

fprintf('\nSaved results to:\n  %s\n', fname);