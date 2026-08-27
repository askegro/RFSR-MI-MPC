classdef (Abstract) ChemistryBase < handle
    %CHEMISTRYBASE Abstract base class for battery cell chemistry
    
    properties (Abstract, Constant)
        name
        fullName
    end
    

    properties (SetAccess = protected)
        electrical
        thermal
        aging
        cell
        constraints
        ocvModel
        
        % Temperature-dependent parameter storage
        tempParams          % Structure with interpolants
        useTempDependent    % Flag
        
        % Original data file content
        rawData             % Store original loaded data

        hasEmpirical        = false
        hasRC2              = false
        hasR0               = false
        hasR1               = false
        hasR2               = false
        hasC1               = false
        hasC2               = false
        hasOCV              = false        
    end
    

    methods (Abstract)
        elec        = getElectricalParams(obj)
        therm       = getThermalParams(obj)
        age         = getAgingParams(obj)
        cell_char   = getCellCharacteristics(obj)
        constr      = getConstraints(obj)
        ocv         = getOCVModel(obj)
    end
    
    
    methods
        function obj = ChemistryBase(varargin)
            %CHEMISTRYBASE Constructor
            %
            % Optional name-value arguments:
            %   'UseEmpirical' - true (default) or false to disable empirical data
            
            % Parse optional arguments
            p = inputParser;
            p.addParameter('UseEmpirical', true, @islogical);
            p.parse(varargin{:});
            
            % Try to load empirical data (unless explicitly disabled)
            if p.Results.UseEmpirical
                obj.loadEmpiricalData();
            else
                fprintf('  Empirical data loading disabled by user\n');
                fprintf('  Using nominal constant parameters\n');
                obj.resetEmpiricalFlags();
                obj.useTempDependent = false;
                obj.tempParams = [];
                obj.rawData = [];
            end
            
            % Get nominal/default parameters
            obj.electrical      = obj.getElectricalParams();
            obj.thermal         = obj.getThermalParams();
            obj.aging           = obj.getAgingParams();
            obj.cell            = obj.getCellCharacteristics();
            obj.constraints     = obj.getConstraints();
            obj.ocvModel        = obj.getOCVModel();
        end

        function resetEmpiricalFlags(obj)
            obj.hasEmpirical    = false;
            obj.hasRC2          = false;
            obj.hasR0           = false;
            obj.hasR1           = false;
            obj.hasR2           = false;
            obj.hasC1           = false;
            obj.hasC2           = false;
            obj.hasOCV          = false;
        end
        
        

        function loadEmpiricalData(obj)
            %loadEmpiricalData Load .mat file with your specific structure
            
            % obj.resetEmpiricalFlags();
            % obj.useTempDependent = false;
            % obj.tempParams = [];
            % obj.rawData = [];

            dataFile   = sprintf('data/%s_cell_data.mat', lower(obj.name));
            

            if (~exist(dataFile, 'file'))
                fprintf('  No empirical data found (%s)\n', dataFile);
                fprintf('  Using nominal constant parameters\n');
                obj.resetEmpiricalFlags();
                obj.useTempDependent = false;
                obj.tempParams = [];
                obj.rawData = [];
                return;
            end
            

            fprintf('  Cell Model: Loading empirical cell parameters from %s\n', dataFile);            
            try
                data            = load(dataFile);
                obj.rawData     = data;
                
                % Validate required fields
                required_fields = {'OCV_LUT', 'SOC_vec', 'Q_cell_nom', 'T_vec', ...
                                  'R0_LUT', 'R1_LUT', 'tau1_LUT'};
                missing         = setdiff(required_fields, fieldnames(data));
                if ~isempty(missing)
                    error('Missing required fields: %s', strjoin(missing, ', '));
                end
                
                % Process temperature vector
                T_vec           = data.T_vec;
                if (max(T_vec) < 200)  % Assume Celsius if max < 200
                    fprintf('  Note: Temperature in Celsius, converting to Kelvin\n');
                    T_vec_K     = T_vec + 273.15;
                else
                    T_vec_K     = T_vec;
                end

                % Validate dimensions
                n_temps = length(T_vec);
                if length(data.R0_LUT) ~= n_temps
                    error('R0_LUT length (%d) does not match T_vec length (%d)', ...
                          length(data.R0_LUT), n_temps);
                end
                
                % Validate physical ranges
                if any(data.R0_LUT <= 0)
                    error('R0_LUT contains non-positive values');
                end
                if any(data.SOC_vec < 0) || any(data.SOC_vec > 1)
                    error('SOC_vec contains values outside [0, 1]');
                end
                if ~issorted(data.SOC_vec)
                    warning('SOC_vec is not sorted - sorting automatically');
                end                
                

                % Store processed temperature
                obj.tempParams.T_vec_K      = T_vec_K;
                obj.tempParams.T_vec_C      = T_vec_K - 273.15;
                obj.tempParams.T_cell_min        = min(T_vec_K);
                obj.tempParams.T_cell_max        = max(T_vec_K);
                
                % Ensure LUTs are column vectors
                R0_LUT = data.R0_LUT(:);
                R1_LUT = data.R1_LUT(:);
                tau1_LUT = data.tau1_LUT(:);
                
                % Check if we have multiple temperature points
                n_temps = length(T_vec_K);                


                if n_temps == 1
                    % ===== SINGLE TEMPERATURE: Use constant functions =====
                    fprintf('  Note: Single temperature data only (%.1f°C). Using constant parameters\n', ...
                            obj.tempParams.T_vec_C(1));
                    
                    % Create constant functions that return the single value
                    R0_val = R0_LUT(1);
                    R1_val = R1_LUT(1);
                    tau1_val = tau1_LUT(1);
                    C1_val = tau1_val / R1_val;
                    
                    obj.tempParams.R0_func = @(T) R0_val * ones(size(T));
                    obj.tempParams.R0_LUT = R0_LUT;
                    
                    obj.tempParams.R1_func = @(T) R1_val * ones(size(T));
                    obj.tempParams.R1_LUT = R1_LUT;
                    
                    obj.tempParams.tau1_func = @(T) tau1_val * ones(size(T));
                    obj.tempParams.tau1_LUT = tau1_LUT;
                    
                    obj.tempParams.C1_func = @(T) C1_val * ones(size(T));
                    obj.tempParams.C1_LUT = C1_val;
                    
                    % R2/C2 for single temperature
                    existR2 = isfield(data, 'R2_LUT');
                    existtau2 = isfield(data, 'tau2_LUT');
                    if existR2 && existtau2
                        fprintf('  Found R2/tau2 in data - using 2RC model\n');
                        %obj.tempParams.has_RC2 = true;
                        
                        R2_val = data.R2_LUT(1);
                        tau2_val = data.tau2_LUT(1);
                        C2_val = tau2_val / R2_val;
                        
                        obj.tempParams.R2_func = @(T) R2_val * ones(size(T));
                        obj.tempParams.R2_LUT = data.R2_LUT(:);
                        
                        obj.tempParams.tau2_func = @(T) tau2_val * ones(size(T));
                        obj.tempParams.tau2_LUT = data.tau2_LUT(:);
                        
                        obj.tempParams.C2_func = @(T) C2_val * ones(size(T));
                        obj.tempParams.C2_LUT = C2_val;
                    else
                        fprintf('  Note: R2/tau2 not found - using 1RC model\n');
                        %obj.tempParams.has_RC2 = false;
                    end                


                else
                    % ===== MULTIPLE TEMPERATURES: Use interpolants =====
                    fprintf('  Multiple temperature points (%d) - using interpolants\n', n_temps);
                        
                    % Create R0 interpolant
                    obj.tempParams.R0_func          = griddedInterpolant(T_vec_K, data.R0_LUT, 'linear', 'nearest');
                    obj.tempParams.R0_LUT           = data.R0_LUT;
                    
                    % Create R1 interpolant
                    obj.tempParams.R1_func          = griddedInterpolant(T_vec_K, data.R1_LUT, 'linear', 'nearest');
                    obj.tempParams.R1_LUT           = data.R1_LUT;
                    
                    % Create tau1 interpolant
                    obj.tempParams.tau1_func        = griddedInterpolant(T_vec_K, data.tau1_LUT, 'linear', 'nearest');
                    obj.tempParams.tau1_LUT         = data.tau1_LUT;
                    
                    % Compute C1 from tau1 and R1: C1 = tau1 / R1
                    if any(data.R1_LUT <= 0)
                        error('R1_LUT contains non-positive values');
                    end                    
                    C1_LUT                          = data.tau1_LUT ./ data.R1_LUT;
                    obj.tempParams.C1_func          = griddedInterpolant(T_vec_K, C1_LUT, 'linear', 'nearest');
                    obj.tempParams.C1_LUT           = C1_LUT;
                    
                    % R2 and C2: Only use if explicitly provided in data
                    existR2                         = isfield(data, 'R2_LUT');
                    existtau2                       = isfield(data, 'tau2_LUT');
                    if (existR2 && existtau2)
                        fprintf('  Found R2/tau2 in data - using 2RC model\n');
                        %obj.tempParams.has_RC2      = true;
    
                        obj.tempParams.R2_func      = griddedInterpolant(T_vec_K, data.R2_LUT, 'linear', 'nearest');
                        obj.tempParams.R2_LUT       = data.R2_LUT;
                        
                        obj.tempParams.tau2_func    = griddedInterpolant(T_vec_K, data.tau2_LUT, 'linear', 'nearest');
                        obj.tempParams.tau2_LUT     = data.tau2_LUT;
                        
                        if any(data.R2_LUT <= 0)
                            error('R2_LUT contains non-positive values');
                        end                        
                        C2_LUT                      = data.tau2_LUT ./ data.R2_LUT;
                        obj.tempParams.C2_func      = griddedInterpolant(T_vec_K, C2_LUT, 'linear', 'nearest');
                        obj.tempParams.C2_LUT       = C2_LUT;
                        
                    else
                        fprintf('  R2/tau2 not found - using 1RC model\n');
                        %obj.tempParams.has_RC2      = false;
                        % Do NOT create R2/C2/tau2 fields
                    end
                end
                    
    
                % OCV interpolant (SOC-based, 1D) - always works since SOC has multiple points
                SOC_vec = data.SOC_vec(:);
                OCV_LUT = data.OCV_LUT(:);
                
                % Ensure SOC is strictly increasing
                [SOC_vec_sorted, sort_idx] = sort(SOC_vec);
                OCV_LUT_sorted = OCV_LUT(sort_idx);
                
                obj.tempParams.ocv_soc = SOC_vec_sorted;
                obj.tempParams.ocv_voltage = OCV_LUT_sorted;
                obj.tempParams.ocv_func         = griddedInterpolant(SOC_vec_sorted, OCV_LUT_sorted, 'linear', 'nearest');
                

                % Store cell characteristics
                obj.tempParams.Q_cell_nom       = data.Q_cell_nom;
                obj.tempParams.v_cell_nom       = data.v_cell_nom;
                
                if isfield(data, 'm_cell')
                    obj.tempParams.m_cell       = data.m_cell;
                end
                if isfield(data, 'c_cell')
                    obj.tempParams.c_cell       = data.c_cell;
                end
                
                % Store CCCV constraints
                if isfield(data, 'CCCV')
                    obj.tempParams.CCCV         = data.CCCV;
                end
                    
                obj.useTempDependent            = true;

                obj.hasEmpirical = true;                
                obj.hasR0  = isfield(obj.tempParams,'R0_func');
                obj.hasR1  = isfield(obj.tempParams,'R1_func');
                obj.hasR2  = isfield(obj.tempParams,'R2_func');
                obj.hasC1  = isfield(obj.tempParams,'C1_func');
                obj.hasC2  = isfield(obj.tempParams,'C2_func');
                obj.hasRC2 = obj.hasR2 && obj.hasC2 && isfield(obj.tempParams,'tau2_func');                
                obj.hasOCV = isfield(obj.tempParams,'ocv_func');                

                
                % Print summary
                fprintf('========================================\n');
                fprintf('\nConfiguring cell electrical model...\n');
                fprintf('========================================\n');                
                if obj.hasRC2
                    modelType                   = '2RC';
                else
                    modelType                   = '1RC';
                end
                fprintf('    - Model type: %s\n', modelType);
                if n_temps == 1
                    fprintf('    - Temperature range: %.1f °C (only one temperature available)\n', obj.tempParams.T_vec_C(1));
                else
                    fprintf('    - Temperature range: %.1f to %.1f °C\n', ...
                            min(obj.tempParams.T_vec_C), max(obj.tempParams.T_vec_C));
                end
                fprintf('    - OCV: %d points from SOC %.2f to %.2f (piecewise linear)\n', length(data.SOC_vec), min(data.SOC_vec), max(data.SOC_vec));
                fprintf('    - R0 range: %.4f to %.4f Ohm\n', min(data.R0_LUT), max(data.R0_LUT));
                fprintf('    - R1 range: %.4f to %.4f Ohm\n', min(data.R1_LUT), max(data.R1_LUT));
                fprintf('    - Nominal capacity: %.2f Ah\n', data.Q_cell_nom);
                fprintf('    - Nominal voltage: %.2f V\n', data.v_cell_nom);
                
            catch ME
                warning(ME.identifier, 'Failed to load empirical data: %s', ME.message);
                obj.resetEmpiricalFlags();
                obj.useTempDependent = false;
                obj.tempParams = [];
                obj.rawData = [];
            end
        end
        

        function R0 = get_R0(obj, T)
            if obj.useTempDependent && obj.hasR0
                R0 = obj.tempParams.R0_func(T);
            else
                R0 = obj.electrical.R0 + zeros(size(T));
            end
        end
        

        function R1 = get_R1(obj, T)
            %GET_R1 Get R1 value for given temperature(s)
            if obj.useTempDependent && obj.hasR1
                R1 = obj.tempParams.R1_func(T);
            else
                R1 = obj.electrical.R1 + zeros(size(T));
            end
        end
        

        function C1 = get_C1(obj, T)
            %GET_C1 Get C1 value for given temperature(s)
            if obj.useTempDependent && obj.hasC1
                C1 = obj.tempParams.C1_func(T);
            else
                C1 = obj.electrical.C1 + zeros(size(T));
            end
        end


        function tau1 = get_tau1(obj, T)
            %GET_TAU1 Get tau1 time constant for given temperature(s)
            if obj.useTempDependent && isfield(obj.tempParams,'tau1_func')
                tau1 = obj.tempParams.tau1_func(T);
            else
                tau1 = obj.electrical.R1 * obj.electrical.C1 + zeros(size(T));
            end
        end        
        

        function R2 = get_R2(obj, T)
            if obj.useTempDependent && obj.hasRC2
                R2 = obj.tempParams.R2_func(T);
            else
                if isfield(obj.electrical,'R2') && ~isempty(obj.electrical.R2)
                    R2 = obj.electrical.R2 + zeros(size(T));
                else
                    R2 = [];
                end
            end
        end
        

        function C2 = get_C2(obj, T)
            if obj.useTempDependent && obj.hasRC2
                C2 = obj.tempParams.C2_func(T);
            else
                if isfield(obj.electrical,'C2') && ~isempty(obj.electrical.C2)
                    C2 = obj.electrical.C2 + zeros(size(T));
                else
                    C2 = [];
                end
            end
        end


        function tau2 = get_tau2(obj, T)
            if obj.useTempDependent && obj.hasRC2
                tau2 = obj.tempParams.tau2_func(T);
            else
                tau2 = [];              % <-- empty means “no RC2”
            end
        end
        

        function v_oc = computeOCV(obj, soc)
            %computeOCV Calculate open-circuit voltage for given SOC(s)
            % Uses piecewise linear interpolation
            %
            % Inputs:
            %   soc - State of charge [0-1], can be scalar or vector
            %
            % Returns:
            %   v_oc - Open-circuit voltage [V], same size as soc
            
            if obj.useTempDependent && obj.hasOCV
                % Use empirical OCV curve (piecewise linear)
                v_oc = obj.tempParams.ocv_func(soc);
            else
                % Use model-based OCV
                soc_clamped = max(obj.ocvModel.soc_min, min(obj.ocvModel.soc_max, soc));
                v_oc        = obj.ocvModel.func(soc_clamped);
            end
        end
        

        function params = getParamsAtTemperature(obj, T, Tstep)
            %GET_PARAMS_AT_TEMPERATURE Get all electrical parameters at given temperature(s)
            %
            % Inputs:
            %   T     - Temperature [K], can be scalar or vector [Ns x 1]
            %   Tstep - Discretization timestep [s]
            %
            % Returns:
            %   params - Structure with RC parameters and discrete coefficients
            %           - Only includes R2/C2 if present in data
            
            params.R0 = obj.get_R0(T);
            params.R1 = obj.get_R1(T);
            params.C1 = obj.get_C1(T);
            
            % Compute discrete-time coefficients for first RC pair
            params.a1 = exp(-Tstep ./ (params.R1 .* params.C1));
            params.b1 = 1 - params.a1;
            params.tau1 = params.R1 .* params.C1;
            
            % Only include R2/C2 if they exist
            R2 = obj.get_R2(T);
            if ~isempty(R2)
                params.R2 = R2;
                params.C2 = obj.get_C2(T);
                params.a2 = exp(-Tstep ./ (params.R2 .* params.C2));
                params.b2 = 1 - params.a2;
                params.tau2 = params.R2 .* params.C2;
            end
            % Otherwise, R2/C2/a2/b2/tau2 fields simply don't exist
        end
        

        function displayInfo(obj)
            %displayInfo Print chemistry information
            %fprintf('\n=== %s (%s) ===\n', obj.fullName, obj.name);
            
            if obj.useTempDependent
                % fprintf('Using empirical temperature-dependent parameters\n');
                % if obj.tempParams.has_RC2
                %     fprintf('Model type: %s\n', '2RC');
                % else
                %     fprintf('Model type: %s\n', '1RC');
                % end
                % 
                % fprintf('Nominal voltage: %.2f V\n', obj.tempParams.v_cell_nom);
                % fprintf('Nominal capacity: %.1f Ah\n', obj.tempParams.Q_cell_nom);
                
                if isfield(obj.tempParams, 'CCCV')
                    fprintf('    - Discharge C-rate: %.1fC\n', obj.tempParams.CCCV.CC_dis_Crate);
                    fprintf('    - Charge C-rate: %.1fC\n', obj.tempParams.CCCV.CC_chg_Crate);
                    fprintf('    - Allowed cell voltage range: %.2f to %.2f V\n', ...
                        obj.tempParams.CCCV.CC_dis_V_min, ...
                        obj.tempParams.CCCV.CC_chg_V_max);
                end
                
                fprintf('    - Allowed cell temperature range: %.1f to %.1f °C\n', ...
                    min(obj.tempParams.T_vec_C), max(obj.tempParams.T_vec_C));
            else
                fprintf('Using nominal constant parameters\n');
                fprintf('Nominal voltage: %.2f V\n', obj.cell.v_cell_nom);
                fprintf('Nominal capacity: %.1f Ah\n', obj.cell.Q_cell_nom_Ah);
            end

            % fprintf('  WARNING: Resistance model uses temperature only\n');
            % fprintf('           Accuracy degrades at SOC < 20%% or > 80%%\n');
            % fprintf('           For critical applications, validate against data\n');            
        end
        

        function displayTempSensitivity(obj)
            %displayTempSensitivity Plot parameter variation with temperature
            
            if ~obj.useTempDependent
                fprintf('No temperature-dependent data available\n');
                return;
            end
            
            % Determine if we have 2RC or 1RC model
            has_RC2 = obj.hasRC2;
            
            figure('Name', sprintf('%s Temperature Sensitivity', obj.name), ...
                   'Position', [100 100 1400 900]);
            
            % Use actual temperature range from data
            T_range_K = obj.tempParams.T_vec_K;
            T_range_C = obj.tempParams.T_vec_C;
            
            % Get parameters
            R0 = obj.get_R0(T_range_K);
            R1 = obj.get_R1(T_range_K);
            C1 = obj.get_C1(T_range_K);
            tau1 = obj.get_tau1(T_range_K);
            
            if has_RC2
                R2 = obj.get_R2(T_range_K);
                C2 = obj.get_C2(T_range_K);
                tau2 = obj.get_tau2(T_range_K);
            end
            
            % 1. R0 vs Temperature
            subplot(2,3,1);
            plot(T_range_C, R0*1000, 'b-', 'LineWidth', 2, 'DisplayName', 'R_0 Interpolant');
            hold on;
            plot(obj.tempParams.T_vec_C, obj.tempParams.R0_LUT*1000, ...
                'ro', 'MarkerSize', 2, 'MarkerFaceColor', 'r', 'DisplayName', 'R_0 Datapoints');
            xlabel('Temperature [°C]');
            ylabel('R_0 [mΩ]');
            title('Ohmic Resistance vs Temperature');
            grid on;
            legend('Location', 'best');
            
            % 2. R1 (and R2 if present) vs Temperature
            subplot(2,3,2);
            plot(T_range_C, R1*1000, 'b-', 'LineWidth', 2, 'DisplayName', 'R_1 Interpolant');
            hold on;
            plot(obj.tempParams.T_vec_C, obj.tempParams.R1_LUT*1000, ...
                'ro', 'MarkerSize', 2, 'MarkerFaceColor', 'r', 'DisplayName', 'R_1 Datapoints');
            if has_RC2 && isfield(obj.tempParams,'R2_LUT')
                plot(T_range_C, R2*1000, 'k-', 'LineWidth', 2, 'DisplayName', 'R_2 Interpolant');
                plot(obj.tempParams.T_vec_C, obj.tempParams.R2_LUT*1000, ...
                    'go', 'MarkerSize', 2, 'MarkerFaceColor', 'g', 'DisplayName', 'R_2 Datapoints');
            end
            xlabel('Temperature [°C]');
            ylabel('Resistance [mΩ]');
            title('RC Resistances vs Temperature');
            grid on;
            legend('Location', 'best');
            
            % 3. Time constants
            subplot(2,3,3);
            plot(T_range_C, tau1, 'b-', 'LineWidth', 2, 'DisplayName', '\tau_1 Interpolant');
            hold on;
            plot(obj.tempParams.T_vec_C, obj.tempParams.tau1_LUT, ...
                'ro', 'MarkerSize', 2, 'MarkerFaceColor', 'r', 'DisplayName', '\tau_1 Datapoints');
            if has_RC2  && isfield(obj.tempParams,'tau2_LUT')
                plot(T_range_C, tau2, 'k-', 'LineWidth', 2, 'DisplayName', '\tau_2');
                plot(obj.tempParams.T_vec_C, obj.tempParams.tau2_LUT, ...
                    'go', 'MarkerSize', 2, 'MarkerFaceColor', 'g', 'DisplayName', '\tau_2 Datapoints');
            end
            xlabel('Temperature [°C]');
            ylabel('Time Constant [s]');
            title('RC Time Constants vs Temperature');
            grid on;
            legend('Location', 'best');
            
            % 4. Capacitances
            subplot(2,3,4);
            plot(T_range_C, C1/1000, 'b-', 'LineWidth', 2, 'DisplayName', 'C_1 Interpolant');
            hold on;
            plot(obj.tempParams.T_vec_C, obj.tempParams.C1_LUT/1000, ...
                'ro', 'MarkerSize', 2, 'MarkerFaceColor', 'r', 'DisplayName', 'C_1 Datapoints');
            if has_RC2  && isfield(obj.tempParams,'C2_LUT')
                plot(T_range_C, C2/1000, 'k-', 'LineWidth', 2, 'DisplayName', 'C_2 Interpolant');
                plot(obj.tempParams.T_vec_C, obj.tempParams.C2_LUT/1000, ...
                    'go', 'MarkerSize', 2, 'MarkerFaceColor', 'g', 'DisplayName', 'C_2 Datapoints');                
            end
            xlabel('Temperature [°C]');
            ylabel('Capacitance [kF]');
            title('RC Capacitances vs Temperature');
            grid on;
            legend('Location', 'best');
            
            % 5. OCV curve
            subplot(2,3,5);
            plot(obj.tempParams.ocv_soc, obj.tempParams.ocv_voltage, 'LineWidth', 2);
            xlabel('SOC [-]');
            ylabel('OCV [V]');
            title('Open-Circuit Voltage (Piecewise Linear)');
            grid on;
            xlim([0 1]);
            
            % 6. Total resistance
            subplot(2,3,6);
            if has_RC2
                R_total_ss = R0 + R1 + R2;  % Steady-state total
                title_str = 'Total Steady-State Resistance (R_0 + R_1 + R_2)';
            else
                R_total_ss = R0 + R1;  % 1RC model
                title_str = 'Total Steady-State Resistance (R_0 + R_1)';
            end
            plot(T_range_C, R_total_ss*1000, 'k-', 'LineWidth', 2);
            xlabel('Temperature [°C]');
            ylabel('R_{total,ss} [mΩ]');
            title(title_str);
            grid on;
            
            if has_RC2
                model_type = '2RC';
            else
                model_type = '1RC';
            end

            sgtitle(sprintf('%s: Temperature-Dependent Parameters (%s Model)', ...
                    obj.fullName, model_type), ...
                    'FontSize', 14, 'FontWeight', 'bold');
        end


        function [P_pack_dis_max, I_pack_dis_max, limiting_cell] = ...
                getPackMaxDischargePower(obj, z_cell_vec, T_cell_vec, SOH_cell_vec, ...
                                          i_RC_1_vec, i_RC_2_vec, ~, Np, varargin)
            %GETPACKMAXDISCHARGEPOWER Vectorized pack-level discharge limit
            %
            % INPUTS:
            %   z_cell_vec    - [n_cells x 1] State of charge per cell [0-1]
            %   T_cell_vec    - [n_cells x 1] Cell temperatures [K]
            %   SOH_cell_vec  - [n_cells x 1] State of health per cell [0-1]
            %   i_RC_1_vec    - [n_cells x 1] RC pair 1 current states [A]
            %   i_RC_2_vec    - [n_cells x 1] RC pair 2 current states [A]
            %   Ns            - Number of cells in series
            %   Np            - Number of parallel strings
            %
            % OUTPUTS:
            %   P_pack_dis_max  - Maximum discharge power [W]
            %   I_pack_dis_max  - Maximum pack current [A]
            %   limiting_cell   - Index of the limiting cell
            
            % % Ensure column vectors
            % z_cell_vec   = z_cell_vec;
            % T_cell_vec   = T_cell_vec;
            % SOH_cell_vec = SOH_cell_vec;
            % i_RC_1_vec   = i_RC_1_vec;
            % i_RC_2_vec   = i_RC_2_vec;

            % Fast SOC hard-stop
            con = obj.constraints;
            z_cell_min = con.z_cell_min;
            hit = (z_cell_vec <= z_cell_min);
            if any(hit)
                limiting_cell = find(hit, 1);
                P_pack_dis_max = 0;
                I_pack_dis_max = 0;
                return;
            end            

            % Cache scalars
            v_cell_min          = con.v_cell_min;
            Q_cell_nom_Ah       = obj.cell.Q_cell_nom_Ah;
            C_rate_dis_max      = con.C_rate_dis_max;
            
            
            % --- Vectorized parameter lookup ---
            % Assuming get_R0, get_R1, get_R2 can accept vectors, otherwise use arrayfun
            R0_vec = obj.get_R0(T_cell_vec);  % See helper below if needed
            R1_vec = obj.get_R1(T_cell_vec);
            R2_vec = obj.get_R2(T_cell_vec);
            if isempty(R2_vec)
                R2_vec = zeros(size(T_cell_vec));
            end
            
            % --- OCV for all cells ---
            if ~isempty(varargin)
                V_OC_vec = varargin{1};
            else
                V_OC_vec = obj.computeOCV(z_cell_vec);
            end
            
            % --- Fixed voltage components ---
            V_fixed_vec = V_OC_vec - R1_vec .* i_RC_1_vec - R2_vec .* i_RC_2_vec;
            
            % --- CONSTRAINT 1: Voltage floor ---
            % V_cell = V_fixed - R0*I >= v_cell_min
            % => I <= (V_fixed - v_cell_min) / R0
            I_max_voltage = (V_fixed_vec - v_cell_min) ./ R0_vec;
            
            % --- CONSTRAINT 2: C-rate ---
            Q_cell_vec = Q_cell_nom_Ah .* SOH_cell_vec;
            I_max_Crate = C_rate_dis_max .* Q_cell_vec;
            
            % --- CONSTRAINT 3: SOC floor (hard cutoff) ---
            SOC_limited = z_cell_vec <= z_cell_min;
            
            % --- Combine constraints ---
            I_max_vec = min(I_max_voltage, I_max_Crate);
            I_max_vec = max(0, I_max_vec);           % No negative currents
            I_max_vec(SOC_limited) = 0;              % Zero out SOC-limited cells
            
            % --- Find limiting cell ---
            [I_cell_max, limiting_cell] = min(I_max_vec);
            
            % --- Pack power calculation ---
            % V_pack = sum(V_fixed) - I * sum(R0)
            % P_pack = V_pack * I * Np
            V_pack_fixed = sum(V_fixed_vec);
            R0_total     = sum(R0_vec);
            
            V_pack_at_limit = V_pack_fixed - R0_total * I_cell_max;
            P_pack_dis_max  = V_pack_at_limit * I_cell_max * Np;
            I_pack_dis_max  = I_cell_max * Np;
            
            % Safety clamp
            P_pack_dis_max = max(0, P_pack_dis_max);
        end
        
        
        function [P_pack_chg_max, I_pack_chg_max, limiting_cell] = ...
                getPackMaxChargePower(obj, z_cell_vec, T_cell_vec, SOH_cell_vec, ...
                                      i_RC_1_vec, i_RC_2_vec, ~, Np, varargin)
            %GETPACKMAXCHARGEPOWER Vectorized pack-level charge/regen limit
            %
            % OUTPUTS:
            %   P_pack_chg_max  - Maximum charge power [W] (positive value)
            %   I_pack_chg_max  - Maximum charge current magnitude [A]
            %   limiting_cell   - Index of the limiting cell
            
            % Fast SOC hard-stop
            con = obj.constraints;
            z_cell_max = con.z_cell_max;
            hit = (z_cell_vec >= z_cell_max);
            if any(hit)
                limiting_cell = find(hit, 1);
                P_pack_chg_max = 0;
                I_pack_chg_max = 0;
                return;
            end            

            % Cache scalars
            v_cell_max          = con.v_cell_max;
            Q_cell_nom_Ah       = obj.cell.Q_cell_nom_Ah;
            C_rate_chg_max      = con.C_rate_chg_max;            

            % Ensure column vectors
            % z_cell_vec   = z_cell_vec(:);
            % T_cell_vec   = T_cell_vec(:);
            % SOH_cell_vec = SOH_cell_vec(:);
            % i_RC_1_vec   = i_RC_1_vec(:);
            % i_RC_2_vec   = i_RC_2_vec(:);
            
            % --- Vectorized parameter lookup ---
            R0_vec = obj.get_R0(T_cell_vec);
            R1_vec = obj.get_R1(T_cell_vec);
            R2_vec = obj.get_R2(T_cell_vec);
            if isempty(R2_vec)
                R2_vec = zeros(size(T_cell_vec));
            end
            
            % --- OCV and fixed voltage ---
            if ~isempty(varargin)
                V_OC_vec = varargin{1};
            else
                V_OC_vec = obj.computeOCV(z_cell_vec);
            end
            V_fixed_vec = V_OC_vec - R1_vec .* i_RC_1_vec - R2_vec .* i_RC_2_vec;
            
            % --- CONSTRAINT 1: Voltage ceiling ---
            % V_cell = V_fixed + R0*|I| <= v_cell_max
            % => |I| <= (v_cell_max - V_fixed) / R0
            I_max_voltage = (v_cell_max - V_fixed_vec) ./ R0_vec;
            
            % --- CONSTRAINT 2: C-rate ---
            Q_cell_vec  = Q_cell_nom_Ah .* SOH_cell_vec;
            I_max_Crate = C_rate_chg_max .* Q_cell_vec;
            
            % --- CONSTRAINT 3: SOC ceiling ---
            SOC_limited = z_cell_vec >= z_cell_max;
            
            % --- Combine constraints ---
            I_max_vec = min(I_max_voltage, I_max_Crate);
            I_max_vec = max(0, I_max_vec);
            I_max_vec(SOC_limited) = 0;
            
            % --- Find limiting cell ---
            [I_cell_max, limiting_cell] = min(I_max_vec);
            
            % --- Pack power calculation ---
            % During charge: V_pack = sum(V_fixed) + sum(R0)*|I|
            V_pack_fixed = sum(V_fixed_vec);
            R0_total     = sum(R0_vec);
            
            V_pack_at_limit = V_pack_fixed + R0_total * I_cell_max;
            P_pack_chg_max  = V_pack_at_limit * I_cell_max * Np;
            I_pack_chg_max  = I_cell_max * Np;
            
            % Safety clamp
            P_pack_chg_max = max(0, P_pack_chg_max);
        end        
        
        % ... rest of existing methods ...
    end
end