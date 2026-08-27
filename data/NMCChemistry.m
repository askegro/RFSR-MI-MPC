classdef NMCChemistry < ChemistryBase
    %NMCCHEMISTRY Nickel Manganese Cobalt battery chemistry
    %
    % Provides NMC-specific parameters for battery modeling.
    %
    % NOMINAL PARAMETERS: Calibrated specifically for Sanyo UR18650E
    %   - 18650 cylindrical format (18.1mm dia × 64.8mm height)
    %   - 2.15Ah nominal capacity (high-rate cell)
    %   - NMC chemistry with excellent discharge capability (10A continuous)
    %
    % Key NMC characteristics:
    %   - Sloped voltage curve (3.0-4.2V) across SOC range
    %   - Moderate cycle life (1000-2000 cycles typical)
    %   - Lower thermal stability than LFP (runaway 150-200°C)
    %   - Higher energy density (180-250 Wh/kg)
    %   - Good rate capability but lower than LFP
    %
    % References:
    %   [1] Xu et al., "Calendar Aging and Cycling Aging Models...",
    %       Nature Communications 14:119, 2023
    %   [2] Representative values from multiple 21700 NMC datasheets
    
    properties (Constant)
        name        = 'NMC';
        fullName    = 'Nickel Manganese Cobalt (LiNiMnCoO2)';
        cellModel   = 'Sanyo UR18650E';  % Nominal params specific to this cell
    end
    
    methods
        function obj = NMCChemistry(varargin)
            %NMCCHEMISTRY Constructor
            obj@ChemistryBase(varargin{:});
        end
        
        function elec = getElectricalParams(obj)
            %GETELECTRICALPARAMS Returns electrical circuit parameters
            %
            % If empirical data loaded: uses interpolated values at 25°C
            % Otherwise: representative values for typical 2-3Ah NMC 21700 cell
            
            if obj.useTempDependent
                % Use empirical data at reference temperature (25°C = 298.15K)
                T_ref       = 298.15;
                elec.R0     = obj.tempParams.R0_func(T_ref);
                elec.R1     = obj.tempParams.R1_func(T_ref);
                elec.C1     = obj.tempParams.C1_func(T_ref);
                
                if obj.hasRC2
                    elec.R2 = obj.tempParams.R2_func(T_ref);
                    elec.C2 = obj.tempParams.C2_func(T_ref);
                else
                    elec.R2 = 0;
                    elec.C2 = 0;
                end
            else
                % Sanyo UR18650E parameters at 25°C
                % Source: Engels et al., Applied Energy 242 (2019) 1036-1049, Table 1
                % Parameters obtained via pulse power testing + least-squares fit
                % to first-order RC model (see Fig. 3b in paper)
                %
                % EXPERIMENTALLY VALIDATED from peer-reviewed publication
                elec.R0     = 0.0334;       % [Ohm] Ohmic resistance (33.4 mΩ, from pulse test)
                elec.R1     = 0.0114;       % [Ohm] Polarization resistance (11.4 mΩ, from pulse test)
                elec.C1     = 1867.0;       % [F] Polarization capacitance (τ = R1×C1 ≈ 21.3s)
                elec.R2     = 0;            % Single RC pair model
                elec.C2     = 0;
            end
        end
        
        function therm = getThermalParams(obj)
            %GETTHERMALPARAMS Returns thermal management parameters
            %
            % Thermal model assumes:
            %   - Lumped capacitance (cell internal temperature uniform)
            %   - Convective heat transfer to ambient
            %   - Moderate forced-air cooling in battery pack
            
            therm.T_amb = 298.15;  % [K] Standard ambient (25°C)
            
            % Heat capacity
            if obj.useTempDependent && isfield(obj.tempParams, 'm_cell') && isfield(obj.tempParams, 'c_cell')
                therm.C_th = obj.tempParams.m_cell * obj.tempParams.c_cell;  % [J/K]
            else
                % Sanyo UR18650E thermal capacity
                % Source: Engels et al., Applied Energy 242 (2019), Table 1
                % Heat capacity from Roth (2005), Sandia National Labs testing
                % VALIDATED: Cp = 40.05 J/K (experimental measurement)
                therm.C_th = 40.05;  % [J/K] Measured heat capacity of cell
            end
            
            % Convection coefficient
            % 18650 cylindrical cell dimensions: D=18.1mm, L=64.8mm
            % Lateral surface area: π × 0.0181 m × 0.0648 m ≈ 3.7e-3 m²
            %
            % Cooling configuration: Liquid cooling plate with direct contact
            %   - Assumed contact area: ~50% of lateral surface ≈ 1.85e-3 m²
            %   - Heat transfer coeff for liquid cold plate: 400-600 W/m²·K
            %     (typical range from battery thermal management literature)
            %   - Effective h_amb = h × A_contact = 500 W/m²·K × 1.85e-3 m² ≈ 0.93 W/K
            %
            % Reference: Battery liquid cooling systems typically achieve
            %   400-800 W/m²·K depending on flow rate and channel design
            %   (Boyd Corp., "Battery Cold Plates", 2022; multiple BTMS papers)
            %
            % For other cooling methods, scale h_amb appropriately:
            %   - Natural convection (5-15 W/m²·K): h_amb ≈ 0.02-0.06 W/K
            %   - Mild forced air (20-50 W/m²·K): h_amb ≈ 0.07-0.19 W/K
            %   - Strong forced air (100-200 W/m²·K): h_amb ≈ 0.37-0.74 W/K
            %   - Liquid cooling plate (400-600 W/m²·K): h_amb ≈ 0.74-1.11 W/K
            therm.h_amb = 0.93;  % [W/K] For liquid cooling plate at 500 W/m²·K
        end
        
        function age = getAgingParams(obj)
            %GETAGINGPARAMS Returns battery aging model parameters
            %
            % Model: Xu et al. (Nature Communications 14:119, 2023)
            %   - Semi-empirical degradation model for NMC/graphite cells
            %   - Calendar aging: sqrt(time) dependence with Arrhenius temperature
            %   - Cycle aging: EFC-based with DoD, C-rate, temperature stress factors
            %
            % Model form:
            %   q_loss_cal = K_cal × f_T(T) × f_Ua(SOC,T) × sqrt(t_days)
            %   q_loss_cyc = K_cyc × f_DoD(DoD) × f_Crate(C) × f_T(T) × EFC
            %
            % where:
            %   f_T: Arrhenius temperature factor
            %   f_Ua: Anode potential factor (SOC-dependent)
            %   f_DoD, f_Crate, f_T: Stress factors from empirical fits
        
            % Universal constants
            age.model_name      = 'Xu_NatCommun_2023';
            age.R_gas           = 8.3144598;    % [J/mol/K] Universal gas constant
            age.F               = 96485;        % [C/mol] Faraday constant
            age.T_ref           = 298.15;       % [K] Reference temperature (25°C)
        
            % Graphite anode lithiation bounds
            % Used to convert SOC to anode potential via Xu's empirical function
            age.xa_0            = 0.0085;       % Lithiation at SOC=0%
            age.xa_100          = 0.78;         % Lithiation at SOC=100%
        
            % NMC-specific parameters from Xu et al. Supplementary Table 3
            age.kCal_days05     = 4.0149e-4;    % [days^0.5] Calendar aging rate
            age.Ea              = 5.9178e4;     % [J/mol] Activation energy for SEI growth
            age.alpha           = -1.0;         % [-] Anode potential sensitivity factor
            
            age.kCyc            = 4.3131332e-6; % [EFC^-1] Cycle aging base rate
            age.A               = 0.3549361;    % DoD stress factor coefficient
            age.B               = 1.2308964e-4; % DoD stress factor offset
            age.C               = 0.0;          % C-rate stress (no dependence in Xu NMC fit)
            age.D               = 1.0;          % C-rate stress offset
            age.G               = 0.6149392;    % Temperature quadratic coefficient
            age.H               = 63.619859;    % Temperature offset
        
            % Anode potential model (graphite half-cell OCV from Xu)
            age.xa_from_soc = @(soc) age.xa_0 + soc .* (age.xa_100 - age.xa_0);
        
            age.Ua_from_xa = @(xa) ...
                0.6379 + 0.5416 .* exp(-305.5309 .* xa) + ...
                0.044  .* tanh(-(xa - 0.1958) ./ 0.1088) - ...
                0.1978 .* tanh( (xa - 1.0571) ./ 0.0854) - ...
                0.6875 .* tanh( (xa + 0.0117) ./ 0.0529) - ...
                0.0175 .* tanh( (xa - 0.5692) ./ 0.0875);
        
            age.Ua_from_soc = @(soc) age.Ua_from_xa(age.xa_from_soc(soc));
        
            % Reference anode potential at 50% SOC
            age.soc_ref         = 0.5;
            age.Ua_ref          = age.Ua_from_soc(age.soc_ref);
        
            % Stress factor functions
            age.f_T_arrhenius   = @(T) exp(-(age.Ea ./ age.R_gas) .* (1 ./ T - 1 ./ age.T_ref));
            age.f_Ua            = @(Ua,T) exp((age.alpha .* age.F ./ age.R_gas) .* (Ua ./ T - age.Ua_ref ./ age.T_ref));
            age.f_DoD           = @(DoD) (age.A .* DoD + age.B);
            age.f_Crate         = @(Crate) (age.C .* Crate + age.D);
            age.f_T_quad        = @(T) (age.G .* (T - age.T_ref).^2 + age.H);
        
            % Helper functions for controller integration
            age.t_sec_to_t_days = @(t_sec) t_sec / 86400;
        
            % Calendar degradation increment
            % Exact form: q_cal(t+dt) - q_cal(t) = K × [sqrt(t+dt) - sqrt(t)]
            age.dq_cal_anonFunc     = @(t_days, t_sec, T, soc) ...
                                    (age.kCal_days05 .* ...
                                    age.f_T_arrhenius(T) .* ...
                                    age.f_Ua(age.Ua_from_soc(soc), T)) .* ...
                                    (sqrt(t_days + age.t_sec_to_t_days(t_sec)) - sqrt(t_days));
        
            % Effective cycle aging rate
            age.Kcyc_eff        = @(T, DoD, Crate) ...
                                    age.kCyc .* ...
                                    age.f_DoD(DoD) .* ...
                                    age.f_Crate(Crate) .* ...
                                    age.f_T_quad(T);
        
            % Cycle degradation increment
            % delta_q_cyc = K_cyc_eff × delta_EFC
            age.dq_cyc_anonFunc     = @(dt_EFC, T, DoD, Crate) ...
                                    age.Kcyc_eff(T, DoD, Crate) .* dt_EFC;
        end
        
        function cell_char = getCellCharacteristics(obj)
            %GETCELLCHARACTERISTICS Returns physical cell properties
            
            if obj.useTempDependent
                % Use empirical data
                cell_char.Q_cell_nom_Ah = obj.tempParams.Q_cell_nom;
                cell_char.v_cell_nom    = obj.tempParams.v_cell_nom;
                
                if isfield(obj.tempParams, 'm_cell')
                    cell_char.m_cell = obj.tempParams.m_cell;
                else
                    cell_char.m_cell = 0.046;  % [kg] Default for 18650
                end
                
                if isfield(obj.tempParams, 'c_cell')
                    cell_char.cp_cell = obj.tempParams.c_cell;
                else
                    cell_char.cp_cell = 900;  % [J/kg/K] Typical NMC specific heat
                end
            else
                % Sanyo UR18650E specifications
                % Source: Engels et al., Applied Energy 242 (2019), Table 1
                % High-rate NMC 18650 cell for automotive/power tool applications
                cell_char.Q_cell_nom_Ah     = 2.05;     % [Ah] Nominal capacity (minimum rated)
                cell_char.v_cell_nom        = 3.6;      % [V] Nominal voltage
                % Mass derived from the datasheet
                cell_char.m_cell            = 0.0445;   % [kg] Cell mass 
                % Specific heat: NMC cells typically 900-1000 J/kg·K
                % Validated: 40.05 J/K / 0.0445 kg ≈ 900 J/kg·K
                cell_char.cp_cell           = 900;      % [J/kg/K] Specific heat (consistent with Cp)
            end
            
            % % Voltage limits from empirical OCV curve or defaults
            % if obj.useTempDependent && isfield(obj.tempParams, 'ocv_voltage') && ~isempty(obj.tempParams.ocv_voltage)
            %     v_ocv = obj.tempParams.ocv_voltage(:);
            %     cell_char.v_min = min(v_ocv);
            %     cell_char.v_max = max(v_ocv);
            % else
            %     % Standard NMC voltage range
            %     cell_char.v_min = 2.5;      % [V] Discharge cutoff (conservative)
            %     cell_char.v_max = 4.2;      % [V] Maximum charge voltage
            % end
        end
        
        function constr = getConstraints(obj)
            %GETCONSTRAINTS Returns operating limits and safety bounds
            % % Optional argument:
            % %   'v_cell_cv_target' - Custom CV target voltage [V]
            % %                        If not provided, uses default from OCV @ 90% SOC            
            %
            % Voltage limit hierarchy (from safe to critical):
            %   v_cell_min     : Absolute minimum (undervoltage protection trip)
            %   v_cell_cv      : Constant-voltage charge target (normal operation)
            %   v_cell_ov      : Overvoltage warning threshold
            %   v_cell_max     : Absolute maximum (overvoltage protection trip)
            %
            % SOC limit hierarchy:
            %   z_cell_min     : Emergency reserve (protection trip)
            %   z_cell_min_warn: Normal lower operating bound
            %   z_cell_max_warn: Normal upper operating bound
            %   z_cell_max     : Absolute maximum (protection trip)
            
            % % Parse optional arguments
            % p = inputParser;
            % p.addParameter('v_cell_cv_target', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
            % p.parse(varargin{:});                 

            % Current limits
            if obj.useTempDependent && isfield(obj.tempParams, 'CCCV')
                constr.C_rate_dis_max = obj.tempParams.CCCV.CC_dis_Crate;
                constr.C_rate_chg_max = abs(obj.tempParams.CCCV.CC_chg_Crate);
            else
                % Sanyo UR18650E current limits
                % Maximum continuous discharge: 10A (from product specifications)
                % With 2.05 Ah: 10A / 2.05Ah = 4.88C
                constr.C_rate_chg_max = 1.0;    % [C] 1C charge (2.05A, conservative)
                constr.C_rate_dis_max = 4.88;   % [C] 10A / 2.05Ah = 4.88C discharge
            end
            
            % SOC operating window
            % NMC requires tighter SOC window than LFP for longevity
            % Degradation accelerates above 90% and below 10% SOC
            constr.z_cell_min       = 0.05;     % Emergency reserve (protection)
            constr.z_cell_min_warn  = 0.10;     % Normal lower bound (recommended)
            constr.z_cell_min_OCV   = 0.15;     % Normal lower bound (OCV)
            constr.z_cell_max_OCV   = 0.95;     % Normal upper bound (OCV)            
            constr.z_cell_max_warn  = 0.98;     % Normal upper bound (longevity-focused)
            constr.z_cell_max       = 1.00;     % Absolute maximum (protection)
            
            % Voltage limits
            if obj.useTempDependent && ...
               isfield(obj.tempParams, 'ocv_soc') && isfield(obj.tempParams, 'ocv_voltage') && ...
               ~isempty(obj.tempParams.ocv_soc) && ~isempty(obj.tempParams.ocv_voltage)
        
                soc_data = obj.tempParams.ocv_soc(:);
                v_data   = obj.tempParams.ocv_voltage(:);
        
                % Sort in case arrays not monotonic
                [~, idx] = sort(soc_data);
                v_data = v_data(idx);
        
                % OCV extrema for reference
                constr.v_cell_min = min(v_data);
                constr.v_cell_max = max(v_data);
        
                % % CV target: use custom if provided, otherwise default
                % if ~isempty(p.Results.v_cell_cv_target)
                %     constr.v_cell_cv = p.Results.v_cell_cv_target;
                % else
                %     % Default: CV target at max_warn SOC (90%)
                %     soc_cv = constr.z_cell_max_warn;
                %     v_cv = interp1(soc_data, v_data, soc_cv, 'linear', 'extrap');
                %     constr.v_cell_cv = v_cv;
                % end
        
                % % OV trip: CV target + 20mV margin
                % constr.v_cell_ov = min(constr.v_cell_cv + 0.050, constr.v_cell_max);
        
                % Hard constraints from CCCV protocol
                if isfield(obj.tempParams, 'CCCV') && ...
                   isfield(obj.tempParams.CCCV, 'CC_chg_V_max') && ...
                   isfield(obj.tempParams.CCCV, 'CC_dis_V_min')
        
                    constr.v_cell_max = obj.tempParams.CCCV.CC_chg_V_max;
                    constr.v_cell_min = obj.tempParams.CCCV.CC_dis_V_min;
                else
                    % Fallback if CCCV missing
                    constr.v_cell_max = 4.20;
                    constr.v_cell_min = 2.75;
                end
        
                % % Safety: never exceed hard max
                % constr.v_cell_ov = min(constr.v_cell_ov, constr.v_cell_max);
        
            else
                % Standard NMC voltage constraints
                constr.v_cell_min = 2.75;       % [V] Undervoltage protection
                % constr.v_cell_cv  = 4.20;       % [V] Standard CV charge target
                % constr.v_cell_ov  = 4.25;       % [V] Overvoltage warning
                constr.v_cell_max = 4.20;       % [V] Absolute maximum (protection)
            end
            
            % Temperature operating limits
            if obj.useTempDependent && isfield(obj.tempParams, 'T_cell_min')
                constr.T_cell_min = 10 + 273.15; %obj.tempParams.T_min;
                constr.T_cell_max = 45 + 273.15; %obj.tempParams.T_max;
            else
                % NMC operational temperature range (narrower than LFP)
                % NMC is more sensitive to temperature extremes
                constr.T_cell_min = 11 + 273.15;  % [K] 15°C - optimal range starts
                constr.T_cell_max = 44 + 273.15;  % [K] 40°C - optimal range ends
            end
        end
        
        function ocv = getOCVModel(obj)
            %GETOCVMODEL Returns open-circuit voltage as function of SOC
            %
            % Provides OCV(SOC) function for:
            %   - State estimation (voltage-based SOC observable)
            %   - Terminal voltage prediction
            %   - Power capability assessment
            %
            % NMC characteristic: More sloped curve than LFP
            %   - Better observability for voltage-based SOC estimation
            %   - Approximately linear in 20-80% SOC range
            %   - Steeper slopes at extremes (0-10%, 90-100%)
            
            if obj.useTempDependent && isfield(obj.tempParams, 'ocv_func')
                % Empirical OCV data available
                ocv.soc_min      = min(obj.tempParams.ocv_soc);
                ocv.soc_max      = max(obj.tempParams.ocv_soc);
                ocv.soc_data     = obj.tempParams.ocv_soc(:);
                ocv.voltage_data = obj.tempParams.ocv_voltage(:);
                
                % Piecewise linear interpolation (accurate for plant simulation)
                ocv.func = obj.tempParams.ocv_func;
                
            else
                % Physics-based NMC OCV model
                % Captures characteristic sloped discharge curve
                ocv.soc_min = 0.0;
                ocv.soc_max = 1.0;
                
                % Breakpoints for piecewise linear approximation
                % Tuned to match typical NMC behavior:
                %   - Steep slope 0-10% (deep discharge)
                %   - Gradual slope 10-90% (main operating region)
                %   - Steep slope 90-100% (full charge)
                ocv.breakpoints_soc = [0.00, 0.05, 0.10, 0.20, 0.50, 0.80, 0.90, 0.95, 1.00];
                ocv.breakpoints_v   = [3.00, 3.30, 3.50, 3.60, 3.70, 3.90, 4.05, 4.15, 4.25];
                
                % Piecewise linear function
                ocv.func = @(soc) interp1(ocv.breakpoints_soc, ...
                                          ocv.breakpoints_v, ...
                                          soc, 'linear', 'extrap');
            end
        end
    end
end