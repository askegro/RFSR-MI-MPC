function models = buildModels(cfg, chem, raw)

    models = struct();
    
    %% Electrical
    elec = raw.elec;
    assert_has_fields(elec, {'R0','R1','C1'}, 'chem.electrical');
    
    R1 = elec.R1; C1 = elec.C1;
    if ~(isfinite(R1) && R1 > 0 && isfinite(C1) && C1 > 0)
        error('Invalid RC1 params: R1=%.3g C1=%.3g', R1, C1);
    end
    tau1 = R1*C1;
    
    has_RC2 = isfield(elec,'R2') && isfield(elec,'C2') && ...
              isfinite(elec.R2) && isfinite(elec.C2) && elec.R2 > 0 && elec.C2 > 0;
    
    a1 = exp(-cfg.Tstep/tau1);
    b1 = 1 - a1;
    
    if has_RC2
        R2 = elec.R2; C2 = elec.C2; 
        tau2 = R2*C2;
        a2 = exp(-cfg.Tstep/tau2);
        b2 = 1 - a2;
    else
        a2 = 0; b2 = 0;
    end
    
    models.elec = elec;
    models.elec.a1 = a1; models.elec.b1 = b1;
    models.elec.a2 = a2; models.elec.b2 = b2;
    models.elec.has_RC2 = has_RC2;
    
    %% OCV
    if isprop(chem,'useTempDependent') && chem.useTempDependent && ...
            isfield(chem.tempParams,'ocv_func')
        models.ocv.func = chem.tempParams.ocv_func;
    else
        models.ocv.func = chem.ocvModel.func;
    end
    
    
    %% Cell
    cell = raw.cell;
    if ~isfield(cell,'Q_cell_nom_Ah') || ~isfield(cell,'v_cell_nom')
        error('chem.cell must contain Q_cell_nom_Ah and v_cell_nom.');
    end
    models.cell = struct();
    models.cell.Q_cell_nom_Ah = cell.Q_cell_nom_Ah;
    models.cell.Q_cell_nom_As = cell.Q_cell_nom_Ah * 3600;
    models.cell.v_cell_nom    = cell.v_cell_nom;
    
    %% Thermal
    therm = raw.therm;
    assert_has_fields(therm, {'C_th','h_amb','T_amb'}, 'chem.thermal');
    
    C_th  = therm.C_th;
    h_amb = therm.h_amb;
    
    if ~(isfinite(C_th) && C_th > 0), error('Invalid C_th'); end
    if ~(isfinite(h_amb) && h_amb > 0), error('Invalid h_amb'); end
    if ~isfinite(therm.T_amb), error('Invalid T_amb'); end
    
    a_th = exp(-(h_amb/C_th)*cfg.Tstep);
    b_th = (1 - a_th) / h_amb;
    
    models.therm = therm;
    models.therm.a_th = a_th;
    models.therm.b_th = b_th;
    
    %% Aging
    aging = raw.aging;
    assert_has_fields(aging, { ...
        'kCal_days05','Ea','alpha','T_ref', ...
        'kCyc','A','B','C','D','G','H', ...
        'dq_cal_anonFunc','dq_cyc_anonFunc','t_sec_to_t_days'}, 'chem.aging');
    aging.dt_days = cfg.Tstep / 86400;   % scalar, constant
    % Pack numeric-only parameters for fast calendar kernel
    aging.p = struct( ...
        'kCal_days05', aging.kCal_days05, ...
        'Ea',          aging.Ea, ...
        'R_gas',       aging.R_gas, ...
        'T_ref',       aging.T_ref, ...
        'alpha',       aging.alpha, ...
        'F',           aging.F, ...
        'Ua_ref',      aging.Ua_ref, ...
        'xa_0',        aging.xa_0, ...
        'xa_100',      aging.xa_100 );
    models.aging = aging;
    
    fprintf('\n========================================\n');
    fprintf('  Models built\n');
    fprintf('========================================\n');
    fprintf('  Elec: 1RC%s | Thermal: 1st-order | Aging: calendar+cycling\n', ternary(has_RC2,'+2RC',''));
    fprintf('========================================\n');

end
