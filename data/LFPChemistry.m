classdef LFPChemistry < ChemistryBase
    %LFPCHEMISTRY Lithium Iron Phosphate battery chemistry
    %
    % Provides LFP-specific parameters for battery modeling.
    %
    % NOMINAL PARAMETERS: Calibrated specifically for Sony/Murata US26650FTC1
    %   - 26650 cylindrical format (26.2mm dia × 65.5mm height)
    %   - 3.0Ah nominal capacity (2.85Ah rated minimum)
    %   - LiFePO4 chemistry with flat voltage plateau
    %
    % Key LFP characteristics:
    %   - Flat voltage plateau (3.2-3.3V) from 10-90% SOC
    %   - Long cycle life (>1000 cycles per datasheet, >4000 typical)
    %   - High thermal stability (runaway >270°C)
    %   - Lower energy density than NMC (~120 Wh/kg)
    %   - Excellent high-rate discharge capability (8.3C continuous)
    %
    % References:
    %   [1] Murata US26650FTC1A Product Specification, Jan 2019, KU*****
    %   [2] Xu et al., "Calendar Aging and Cycling Aging Models...",
    %       Nature Communications 14:119, 2023
    
    properties (Constant)
        name        = 'LFP';
        fullName    = 'Lithium Iron Phosphate (LiFePO4)';
        cellModel   = 'Sony/Murata US26650FTC1';  % Nominal params specific to this cell
    end
    
    methods
        function obj = LFPChemistry(varargin)
            %LFPCHEMISTRY Constructor
            obj@ChemistryBase(varargin{:});
        end        

        function elec = getElectricalParams(obj)
            %GETELECTRICALPARAMS Returns electrical circuit parameters
            %
            % If empirical data loaded: uses interpolated values at 25°C
            % Otherwise: conservative values for US26650FTC1
            
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
                % US26650FTC1 parameters at 25°C
                % AC impedance: 9-15 mΩ @ 1kHz per datasheet Section 4.5.2
                %
                % IMPORTANT: These values require validation via EIS or HPPC testing
                % Current values are estimates based on:
                %   - R0: Midpoint of AC impedance range (12 mΩ)
                %   - R1, C1: Estimated to match typical LFP time constants
                %
                % For production use, characterize YOUR specific cells:
                %   - Use electrochemical impedance spectroscopy (EIS), OR
                %   - Use hybrid pulse power characterization (HPPC)
                elec.R0     = 0.012;        % [Ohm] Ohmic resistance (from AC impedance)
                elec.R1     = 0.005;        % [Ohm] Polarization resistance (ESTIMATED - needs validation)
                elec.C1     = 3000;         % [F] Polarization capacitance (τ = R1×C1 ≈ 15s, ESTIMATED)
                elec.R2     = 0;            % Single RC pair nominal model
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
                % US26650FTC1: 86g × 1100 J/kg/K = 94.6 J/K
                % Mass: Datasheet Section 2.7 (84±3g with tube)
                % Specific heat: Typical for LFP cells (1000-1200 J/kg/K)
                therm.C_th = 94.6;  % [J/K]
            end
            
            % Convection coefficient
            % 26650 cylindrical cell dimensions: D=26.2mm, L=65.5mm
            % Lateral surface area: π × 0.0262 m × 0.0655 m ≈ 5.4e-3 m²
            % 
            % Cooling configuration: Liquid cooling plate with direct contact
            %   - Assumed contact area: ~50% of lateral surface ≈ 2.7e-3 m²
            %   - Heat transfer coeff for liquid cold plate: 400-600 W/m²·K
            %     (typical range from battery thermal management literature)
            %   - Effective h_amb = h × A_contact = 500 W/m²·K × 2.7e-3 m² ≈ 1.35 W/K
            %
            % Reference: Battery liquid cooling systems typically achieve
            %   400-800 W/m²·K depending on flow rate and channel design
            %   (Boyd Corp., "Battery Cold Plates", 2022; multiple BTMS papers)
            %
            % For other cooling methods, scale h_amb appropriately:
            %   - Natural convection (5-15 W/m²·K): h_amb ≈ 0.03-0.08 W/K
            %   - Mild forced air (20-50 W/m²·K): h_amb ≈ 0.11-0.27 W/K
            %   - Strong forced air (100-200 W/m²·K): h_amb ≈ 0.54-1.08 W/K
            %   - Liquid cooling plate (400-600 W/m²·K): h_amb ≈ 1.08-1.62 W/K
            therm.h_amb = 1.35;  % [W/K] For liquid cooling plate at 500 W/m²·K
        end
        
        function age = getAgingParams(obj)
            %GETAGINGPARAMS Returns battery aging model parameters
            %
            % Model: Xu et al. (Nature Communications 14:119, 2023)
            %   - Semi-empirical degradation model for LFP/graphite cells
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
        
            % LFP-specific parameters from Xu et al. Supplementary Table 3
            age.kCal_days05     = 1.9234e-3;    % [days^0.5] Calendar aging rate
            age.Ea              = 3.0233e4;     % [J/mol] Activation energy for SEI growth
            age.alpha           = -0.05590;     % [-] Anode potential sensitivity factor
            
            age.kCyc            = 2.93583e-6;   % [EFC^-1] Cycle aging base rate
            age.A               = 1.4761e-1;    % DoD stress factor coefficient
            age.B               = 7.4008e-3;    % DoD stress factor offset
            age.C               = 0.082035;     % C-rate stress factor coefficient  
            age.D               = 0.0313111;    % C-rate stress factor offset
            age.G               = 0.33344256;   % Temperature quadratic coefficient
            age.H               = 331.652158;   % Temperature offset
        
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
                    cell_char.m_cell = 0.086;  % [kg] Default for US26650FTC1
                end
                
                if isfield(obj.tempParams, 'c_cell')
                    cell_char.cp_cell = obj.tempParams.c_cell;
                else
                    cell_char.cp_cell = 1100;  % [J/kg/K] Typical LFP specific heat
                end
            else
                % Sony/Murata US26650FTC1 specifications
                % Source: Datasheet KU*****, Jan 2019
                cell_char.Q_cell_nom_Ah     = 3.0;      % [Ah] Section 3.1 nominal capacity
                cell_char.v_cell_nom        = 3.2;      % [V] Section 3.2 nominal voltage
                cell_char.m_cell            = 0.086;    % [kg] Section 2.7 (84±3g with tube)
                % Specific heat: LFP cells typically 1000-1200 J/kg·K
                % Reference: BatteryDesign.net - "LFP nominal heat capacity ~1110 J/kg·K at 25°C"
                % Also: Battery literature shows range 800-1100 J/kg·K for Li-ion cells
                cell_char.cp_cell           = 1100;     % [J/kg/K] Validated for LFP chemistry
            end
            
            % % Voltage limits from empirical OCV curve or datasheet
            % if obj.useTempDependent && isfield(obj.tempParams, 'ocv_voltage') && ~isempty(obj.tempParams.ocv_voltage)
            %     v_ocv = obj.tempParams.ocv_voltage(:);
            %     cell_char.v_cell_min = min(v_ocv);
            %     cell_char.v_cell_max = max(v_ocv);
            % else
            %     % US26650FTC1 voltage range
            %     % Source: Datasheet Section 2.2, 2.3
            %     cell_char.v_min = 2.0;      % [V] Discharge cutoff (Section 2.3)
            %     cell_char.v_max = 3.65;     % [V] Maximum charge voltage (Section 2.2)
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
            
            % Parse optional arguments
            % p = inputParser;
            % p.addParameter('v_cell_cv_target', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
            % p.parse(varargin{:});            

            % Current limits
            if obj.useTempDependent && isfield(obj.tempParams, 'CCCV')
                constr.C_rate_dis_max = obj.tempParams.CCCV.CC_dis_Crate;
                constr.C_rate_chg_max = abs(obj.tempParams.CCCV.CC_chg_Crate);
            else
                % US26650FTC1 current limits
                % Source: Datasheet Sections 2.4, 2.5
                % Charge: 2.85A max continuous (Section 2.4) → 2.85A / 3.0Ah = 0.95C
                % Discharge: 25A max continuous (Section 2.5) → 25A / 3.0Ah = 8.33C
                constr.C_rate_chg_max = 0.95;   % [C] Conservative (0.95C = 2.85A)
                constr.C_rate_dis_max = 8.33;   % [C] High-rate discharge capability
            end
            
            % SOC operating window
            % LFP is more tolerant of full SOC excursions than NMC
            constr.z_cell_min       = 0.05;     % Emergency reserve (protection)
            constr.z_cell_min_warn  = 0.10;     % Normal lower bound (recommended)
            constr.z_cell_min_OCV   = 0.15;     % Normal lower bound (OCV)
            constr.z_cell_max_OCV   = 0.95;     % Normal upper bound (OCV)
            constr.z_cell_max_warn  = 0.98;     % Normal upper bound (recommended)
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
                % 
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
                    constr.v_cell_max = 3.65;
                    constr.v_cell_min = 2.0;
                end
        
                % % Safety: never exceed hard max
                % constr.v_cell_ov = min(constr.v_cell_ov, constr.v_cell_max);
        
            else
                % US26650FTC1 voltage constraints
                % Source: Datasheet Sections 2.2, 2.3, 3.3
                constr.v_cell_min = 2.0;        % [V] Discharge cutoff (Section 2.3)
                % constr.v_cell_cv  = 3.60;       % [V] Recommended CV charge (Section 3.3)
                % constr.v_cell_ov  = 3.65;       % [V] Overvoltage warning (datasheet max)
                constr.v_cell_max = 3.65;       % [V] Absolute maximum (Section 2.2)
            end
            
            % Temperature operating limits
            if obj.useTempDependent && isfield(obj.tempParams, 'T_min')
                constr.T_cell_min = 10 + 273.15; %obj.tempParams.T_cell_min;
                constr.T_cell_max = 45 + 273.15; %obj.tempParams.T_cell_max;
            else
                % US26650FTC1 temperature limits
                % Source: Datasheet Sections 2.6, 2.8
                % Charge: 0°C to 60°C (ambient), recommended 10-45°C
                % Discharge: -20°C to 60°C (ambient), 80°C cell surface max
                % Conservative operational range:
                constr.T_cell_min = 11 + 273.15;  % [K] 15°C - optimal range starts here
                constr.T_cell_max = 44 + 273.15;  % [K] 40°C - optimal range ends here
            end
        end
        
        function ocv = getOCVModel(obj)
            %GETOCVMODEL Returns open-circuit voltage as function of SOC
            %
            % Provides OCV(SOC) function for:
            %   - State estimation (coulomb counting + voltage-based SOC)
            %   - Terminal voltage prediction
            %   - Power capability assessment
            %
            % LFP characteristic: Flat plateau at ~3.25V from 10-90% SOC
            %   - Makes voltage-based SOC estimation challenging in mid-range
            %   - Requires coulomb counting for accurate SOC tracking
            %   - End regions (0-10%, 90-100%) have steeper slopes
            
            if obj.useTempDependent && isfield(obj.tempParams, 'ocv_func')
                % Empirical OCV data available
                ocv.soc_min      = min(obj.tempParams.ocv_soc);
                ocv.soc_max      = max(obj.tempParams.ocv_soc);
                ocv.soc_data     = obj.tempParams.ocv_soc(:);
                ocv.voltage_data = obj.tempParams.ocv_voltage(:);
                
                % Piecewise linear interpolation (accurate for plant simulation)
                ocv.func = obj.tempParams.ocv_func;
                
            else
                % Physics-based LFP OCV model
                % Captures characteristic flat discharge plateau
                ocv.soc_min = 0.0;
                ocv.soc_max = 1.0;
                
                % Breakpoints for piecewise linear approximation
                % Tuned to match typical LFP behavior:
                %   - Sharp rise from 0-5% (lithiation onset)
                %   - Flat plateau 10-90% (two-phase coexistence)
                %   - Sharp rise 95-100% (full lithiation)
                ocv.breakpoints_soc = [0.00, 0.05, 0.10, 0.90, 0.95, 1.00];
                ocv.breakpoints_v   = [2.50, 3.15, 3.25, 3.30, 3.45, 3.65];
                
                % Piecewise linear function
                ocv.func = @(soc) interp1(ocv.breakpoints_soc, ...
                                          ocv.breakpoints_v, ...
                                          soc, 'linear', 'extrap');
            end
        end
    end
end