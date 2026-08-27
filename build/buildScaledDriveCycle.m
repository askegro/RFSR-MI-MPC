function [Results, ScaledProfile, CellProfile] = ...
    buildScaledDriveCycle(DriveCycleFile, N_cycles_required, ...
    SOC_max, SOC_min, CellChemistry, CellParamFile, Ns, Np, PlotFigures)
%buildScaledDriveCycle Scale a drive cycle power profile to fit within pack constraints
%
%   [Results, ScaledProfile, CellProfile] = ScaleDriveCycleToPackLimits(DriveCycleFile, ...
%       N_cycles_required, SOC_max, SOC_min, CellChemistry, CellParamFile, ...
%       Ns, Np, PlotFigures)
%
%   This function takes a standard drive cycle (e.g., WLTC) and scales the resulting
%   power profile so that it can be executed on a given battery pack without violating
%   C-rate or energy constraints. Intended for hardware-in-the-loop testing, battery
%   cycler profile generation, or small-pack characterization.
%
%   The scaling is uniform across the entire profile, preserving the relative shape
%   of the drive cycle while ensuring the pack can physically execute it.
%
%   INPUTS:
%       DriveCycleFile    - Path to drive cycle .mat file containing:
%                           'Total_elapsed_time' [s] and 'WLTC_speed_kmh' [km/h]
%       N_cycles_required - Number of full drive cycles required (e.g., 3)
%       SOC_max           - Maximum SOC limit [-], e.g., 0.90
%       SOC_min           - Minimum SOC limit [-], e.g., 0.10
%       CellChemistry     - Cell type: 'LFP', 'NMC', 'NCA', 'LTO', or 'FILE'
%       CellParamFile     - Path to cell parameter .mat file (used if CellChemistry='FILE')
%       Ns                - Number of cells in series
%       Np                - Number of parallel strings (cells in parallel)
%       PlotFigures       - Boolean: true to generate plots, false to suppress
%
%   OUTPUTS:
%       Results           - Struct containing sizing results and constraints
%       ScaledProfile     - Struct containing scaled power profile and pack parameters
%       CellProfile       - Struct containing current profile for cell/cycler simulation
%                           Use CellProfile.I_cycler_A for battery cycler input
%
%   CONSTRAINTS ENFORCED:
%       1. Discharge C-rate: I_cell <= Q_cell * C_rate_max
%       2. Charge C-rate:    I_cell <= Q_cell * C_rate_chg
%       3. Energy:           E_total <= E_pack * DOD
%
%   EXAMPLE:
%       % Scale WLTC for a 21s1p LFP pack
%       [R, SP, CP] = ScaleDriveCycleToPackLimits('WLTC_class_3_data.mat', 3, ...
%                                                  0.90, 0.10, 'LFP', '', 21, 1, true);
%       % Use CP.I_cycler_A as input to your battery cycler
%
%       % Scale for a 14s2p custom cell pack
%       [R, SP, CP] = ScaleDriveCycleToPackLimits('WLTC_class_3_data.mat', 2, ...
%                                                  0.95, 0.10, 'FILE', 'my_cell.mat', 14, 2, true);
%
%   Author: Refactored for test profile generation
%   Date: 2024

% =========================================================================
%  INPUT VALIDATION
% =========================================================================

if nargin < 9
    error('ScaleDriveCycleToPackLimits requires 9 input arguments. Type "help ScaleDriveCycleToPackLimits" for usage.');
end

if ~isfile(DriveCycleFile)
    error('Drive cycle file not found: %s', DriveCycleFile);
end

if strcmp(CellChemistry, 'FILE') && (isempty(CellParamFile) || ~isfile(CellParamFile))
    error('CellParamFile must be a valid file path when CellChemistry = ''FILE''');
end

if SOC_max <= SOC_min
    error('SOC_max must be greater than SOC_min');
end

if Ns < 1 || Np < 1
    error('Ns and Np must be positive integers');
end

if ~islogical(PlotFigures) && ~ismember(PlotFigures, [0, 1])
    error('PlotFigures must be true or false');
end

% =========================================================================
%  VEHICLE PARAMETERS (Tesla Model 3 Long Range AWD - Reference Vehicle)
% =========================================================================
% These parameters define the reference vehicle used to convert the drive
% cycle speed profile into a power demand profile. The resulting power
% profile will then be scaled to fit your actual pack.
%
% REFERENCES:
% [1] Dimensions.com - Tesla Model 3 curb weight: 1,828 kg
% [2] InsideEVs - Drag coefficient Cd = 0.219-0.23
% [3] LinkedIn Technical Article - Frontal area Af = 2.22 m²
% [4] Chegg Academic - Crr = 0.011
% [5] Charged EVs - Drivetrain efficiency: 75-90%
% [6] Electrek - Regen efficiency: 60-70%

m           = 1830;     % Vehicle mass [kg]
g           = 9.81;     % Gravitational acceleration [m/s²]
rho_air     = 1.2;      % Air density [kg/m³] at ~20°C, sea level
Cd          = 0.23;     % Drag coefficient [-]
Af          = 2.22;     % Frontal area [m²]
CdA         = Cd * Af;  % Drag area [m²]
Crr         = 0.011;    % Rolling resistance coefficient [-]
k_rot       = 0.04;     % Rotational inertia factor [-]
grade       = 0.00;     % Road grade [-]
eta_drive   = 0.90;     % Drivetrain efficiency [-]
eta_regen   = 0.65;     % Regenerative braking efficiency [-]
P_aux       = 300;      % Auxiliary power load [W]

% =========================================================================
%  CELL CHEMISTRY DATABASE
% =========================================================================

CellData = struct();

% Lithium Iron Phosphate (LFP)
CellData.LFP.V_nom      = 3.2;
CellData.LFP.V_max      = 3.65;
CellData.LFP.V_min      = 2.5;
CellData.LFP.C_rate_max = 3;
CellData.LFP.C_rate_chg = 1;
CellData.LFP.FullName   = 'Lithium Iron Phosphate';

% Nickel Manganese Cobalt (NMC)
CellData.NMC.V_nom      = 3.7;
CellData.NMC.V_max      = 4.2;
CellData.NMC.V_min      = 3.0;
CellData.NMC.C_rate_max = 2;
CellData.NMC.C_rate_chg = 1;
CellData.NMC.FullName   = 'Nickel Manganese Cobalt';

% Nickel Cobalt Aluminum (NCA)
CellData.NCA.V_nom      = 3.6;
CellData.NCA.V_max      = 4.2;
CellData.NCA.V_min      = 2.8;
CellData.NCA.C_rate_max = 2;
CellData.NCA.C_rate_chg = 0.7;
CellData.NCA.FullName   = 'Nickel Cobalt Aluminum';

% Lithium Titanate (LTO)
CellData.LTO.V_nom      = 2.4;
CellData.LTO.V_max      = 2.8;
CellData.LTO.V_min      = 1.8;
CellData.LTO.C_rate_max = 10;
CellData.LTO.C_rate_chg = 5;
CellData.LTO.FullName   = 'Lithium Titanate';

% =========================================================================
%  LOAD CELL PARAMETERS
% =========================================================================

% fprintf('===========================================================================\n');
% fprintf('  DRIVE CYCLE SCALING FOR PACK-CONSTRAINED TESTING\n');
% fprintf('===========================================================================\n\n');

if strcmp(CellChemistry, 'FILE')
    % fprintf('Loading cell parameters from: %s\n', CellParamFile);
    CellFileData = load(CellParamFile);
    
    Cell = struct();
    Cell.V_nom      = double(CellFileData.v_cell_nom);
    Cell.Q_nom      = double(CellFileData.Q_cell_nom);
    Cell.FullName   = sprintf('Custom Cell from %s', CellParamFile);
    
    % Override SOC limits if provided in file
    if isfield(CellFileData, 'SOC_max')
        SOC_max = double(CellFileData.SOC_max);
    end
    if isfield(CellFileData, 'SOC_min')
        SOC_min = double(CellFileData.SOC_min);
    end
    
    % Voltage limits from OCV table or defaults
    if isfield(CellFileData, 'OCV_LUT')
        Cell.V_min = min(CellFileData.OCV_LUT(:));
        Cell.V_max = max(CellFileData.OCV_LUT(:));
    else
        Cell.V_min = 2.5;
        Cell.V_max = 3.65;
    end
    
    % C-rate limits
    if isfield(CellFileData, 'CCCV') && isstruct(CellFileData.CCCV) && isfield(CellFileData.CCCV, 'CC_dis_Crate')
        Cell.C_rate_max = double(CellFileData.CCCV.CC_dis_Crate);
    else
        Cell.C_rate_max = 1;  % Conservative default
    end
    
    if isfield(CellFileData, 'CCCV') && isstruct(CellFileData.CCCV) && isfield(CellFileData.CCCV, 'CC_chg_Crate')
        Cell.C_rate_chg = double(CellFileData.CCCV.CC_chg_Crate);
    else
        Cell.C_rate_chg = 1;  % Conservative default
    end
    
    % Optional parameters for thermal modeling
    if isfield(CellFileData, 'OCV_LUT') && isfield(CellFileData, 'SOC_vec')
        Cell.OCV_LUT    = double(CellFileData.OCV_LUT(:));
        Cell.SOC_vec    = double(CellFileData.SOC_vec(:));
    end
    if isfield(CellFileData, 'R0_LUT'),  Cell.R0_LUT   = double(CellFileData.R0_LUT(:));   end
    if isfield(CellFileData, 'R1_LUT'),  Cell.R1_LUT   = double(CellFileData.R1_LUT(:));   end
    if isfield(CellFileData, 'tau1_LUT'),Cell.tau1_LUT = double(CellFileData.tau1_LUT(:)); end
    if isfield(CellFileData, 'T_vec'),   Cell.T_vec    = double(CellFileData.T_vec(:));    end
    if isfield(CellFileData, 'm_cell'),  Cell.m_cell   = double(CellFileData.m_cell);      end
    if isfield(CellFileData, 'c_cell'),  Cell.c_cell   = double(CellFileData.c_cell);      end
    
    %CellChemistryName = 'Custom (from file)';
    FixedCapacity = true;
else
    if ~isfield(CellData, CellChemistry)
        error('Unknown cell chemistry: %s. Options: LFP, NMC, NCA, LTO, FILE', CellChemistry);
    end
    
    Cell = CellData.(CellChemistry);
    %CellChemistryName = CellChemistry;
    FixedCapacity = false;
end

% fprintf('Cell Chemistry: %s\n', CellChemistryName);
if isfield(Cell, 'Q_nom')
    % fprintf('  Capacity:        %.2f Ah (fixed)\n', Cell.Q_nom);
end
% fprintf('  Nominal Voltage: %.2f V\n', Cell.V_nom);
% fprintf('  Voltage Range:   %.2f - %.2f V\n', Cell.V_min, Cell.V_max);
% fprintf('  Max Discharge:   %.1f C\n', Cell.C_rate_max);
% fprintf('  Max Charge:      %.1f C\n', Cell.C_rate_chg);
% fprintf('  SOC Window:      %.0f%% - %.0f%%\n\n', SOC_min*100, SOC_max*100);

% =========================================================================
%  LOAD AND PROCESS DRIVE CYCLE
% =========================================================================

% fprintf('Loading drive cycle: %s\n', DriveCycleFile);
data = load(DriveCycleFile);

t_cycle_s   = double(data.Total_elapsed_time(:));
v_kmh       = double(data.WLTC_speed_kmh(:));
v_mps       = v_kmh / 3.6;

dt          = t_cycle_s(2) - t_cycle_s(1);
N_points    = length(t_cycle_s);

% fprintf('  Duration:  %.0f s (%.1f min)\n', t_cycle_s(end), t_cycle_s(end)/60);
% fprintf('  Points:    %d\n', N_points);
% fprintf('  Max Speed: %.1f km/h\n\n', max(v_kmh));

% =========================================================================
%  COMPUTE REFERENCE POWER PROFILE
% =========================================================================

% fprintf('Computing reference power profile (Model 3 baseline)...\n');

a_mps2 = [0; diff(v_mps)/dt];

F_roll  = m * g * Crr * ones(N_points, 1);
F_aero  = 0.5 * rho_air * CdA * v_mps.^2;
F_grade = m * g * grade * ones(N_points, 1);
F_inert = m * (1 + k_rot) * a_mps2;
F_total = F_roll + F_aero + F_grade + F_inert;

P_wheel = F_total .* v_mps;

P_batt_ref = zeros(N_points, 1);
idx_pos = P_wheel >= 0;
idx_neg = ~idx_pos;
P_batt_ref(idx_pos) = P_wheel(idx_pos) / eta_drive;
P_batt_ref(idx_neg) = P_wheel(idx_neg) * eta_regen;
P_batt_ref = P_batt_ref + P_aux;

P_ref_max_discharge = max(P_batt_ref);
P_ref_max_charge    = abs(min(P_batt_ref));
%P_ref_avg           = mean(P_batt_ref);

% fprintf('  Reference Peak Discharge: %.2f kW\n', P_ref_max_discharge/1000);
% fprintf('  Reference Peak Regen:     %.2f kW\n', P_ref_max_charge/1000);
% fprintf('  Reference Average Power:  %.2f kW\n\n', P_ref_avg/1000);

% =========================================================================
%  ENERGY CALCULATION (REFERENCE)
% =========================================================================

E_ref_cycle_J   = trapz(t_cycle_s, P_batt_ref);
E_ref_cycle_Wh  = E_ref_cycle_J / 3600;
E_ref_total_Wh  = E_ref_cycle_Wh * N_cycles_required;

% fprintf('Reference energy requirements:\n');
% fprintf('  Energy per cycle:     %.2f Wh (%.3f kWh)\n', E_ref_cycle_Wh, E_ref_cycle_Wh/1000);
% fprintf('  Energy for %d cycles: %.2f Wh (%.3f kWh)\n\n', N_cycles_required, E_ref_total_Wh, E_ref_total_Wh/1000);

% =========================================================================
%  PACK CONFIGURATION
% =========================================================================

% fprintf('Pack configuration: %ds%dp\n', Ns, Np);

V_pack_nom = Ns * Cell.V_nom;
V_pack_min = Ns * Cell.V_min;
V_pack_max = Ns * Cell.V_max;

% fprintf('  Pack Voltage (nom): %.1f V\n', V_pack_nom);
% fprintf('  Pack Voltage Range: %.1f - %.1f V\n', V_pack_min, V_pack_max);

% Determine cell capacity
if FixedCapacity
    Q_cell = Cell.Q_nom;
    % fprintf('  Cell Capacity: %.2f Ah (from parameter file)\n', Q_cell);
else
    % Select standard capacity that meets energy requirement
    StandardCapacities = [2.5, 3.0, 5.0, 6.0, 10.0, 15.0, 20.0, 25.0, 30.0, 50.0, 100.0, 150.0, 200.0, 280.0];
    DOD = SOC_max - SOC_min;
    Q_min_energy = E_ref_total_Wh / (Ns * Cell.V_nom * DOD * Np);
    
    idx_capacity = find(StandardCapacities >= Q_min_energy, 1, 'first');
    if isempty(idx_capacity)
        Q_cell = ceil(Q_min_energy / 10) * 10;
        % fprintf('  Cell Capacity: %.1f Ah (custom, no standard size sufficient)\n', Q_cell);
    else
        Q_cell = StandardCapacities(idx_capacity);
        % fprintf('  Cell Capacity: %.1f Ah (standard size)\n', Q_cell);
    end
end

% Pack capacity (parallel strings increase capacity)
Q_pack = Q_cell * Np;
% fprintf('  Pack Capacity: %.2f Ah (Np=%d)\n', Q_pack, Np);

% Pack energy
DOD = SOC_max - SOC_min;
E_pack_Wh = Ns * Cell.V_nom * Q_pack;
E_pack_usable_Wh = E_pack_Wh * DOD;

% fprintf('  Pack Energy: %.2f Wh (%.3f kWh)\n', E_pack_Wh, E_pack_Wh/1000);
% fprintf('  Usable Energy (%.0f%% DOD): %.2f Wh\n\n', DOD*100, E_pack_usable_Wh);

% =========================================================================
%  CURRENT LIMITS (CELL LEVEL)
% =========================================================================

% Maximum cell currents based on C-rate
I_cell_max_discharge = Q_cell * Cell.C_rate_max;
I_cell_max_charge    = Q_cell * Cell.C_rate_chg;

% Maximum pack currents (parallel strings share current)
I_pack_max_discharge = I_cell_max_discharge * Np;
I_pack_max_charge    = I_cell_max_charge * Np;

% fprintf('Current limits:\n');
% fprintf('  Cell max discharge: %.2f A (%.1f C)\n', I_cell_max_discharge, Cell.C_rate_max);
% fprintf('  Cell max charge:    %.2f A (%.1f C)\n', I_cell_max_charge, Cell.C_rate_chg);
% fprintf('  Pack max discharge: %.2f A (Np=%d)\n', I_pack_max_discharge, Np);
% fprintf('  Pack max charge:    %.2f A (Np=%d)\n\n', I_pack_max_charge, Np);

% =========================================================================
%  COMPUTE SCALE FACTOR
% =========================================================================

% fprintf('Computing scale factor...\n');

% Compute reference currents from power profile
% Discharge: worst case at V_min (lowest voltage = highest current for given power)
% Charge: use V_nom (regen occurs at mid-to-high SOC, voltage closer to nominal)
%         This is more realistic than V_min and avoids over-constraining.

I_ref_discharge = zeros(N_points, 1);
I_ref_charge    = zeros(N_points, 1);

idx_discharge = P_batt_ref >= 0;
idx_charge    = P_batt_ref < 0;

I_ref_discharge(idx_discharge) = P_batt_ref(idx_discharge) / V_pack_min;  % Worst case
I_ref_charge(idx_charge)       = abs(P_batt_ref(idx_charge)) / V_pack_nom; % Realistic

I_ref_peak_discharge = max(I_ref_discharge);
I_ref_peak_charge    = max(I_ref_charge);

% fprintf('  Reference peak discharge current: %.2f A (at V_pack_min)\n', I_ref_peak_discharge);
% fprintf('  Reference peak charge current:    %.2f A (at V_pack_nom)\n', I_ref_peak_charge);

% Scale factors for each constraint
scale_for_discharge = I_pack_max_discharge / I_ref_peak_discharge;
scale_for_charge    = I_pack_max_charge / I_ref_peak_charge;
scale_for_energy    = E_pack_usable_Wh / E_ref_total_Wh;

% fprintf('\n  Scale factor for discharge C-rate: %.4f\n', scale_for_discharge);
% fprintf('  Scale factor for charge C-rate:    %.4f\n', scale_for_charge);
% fprintf('  Scale factor for energy:           %.4f\n', scale_for_energy);

% Take the most restrictive constraint
scale_factor = min([scale_for_discharge, scale_for_charge, scale_for_energy, 1.0]);

% Identify limiting constraint
if scale_factor == scale_for_discharge
    limiting_constraint = 'discharge C-rate';
elseif scale_factor == scale_for_charge
    limiting_constraint = 'charge C-rate';
elseif scale_factor == scale_for_energy
    limiting_constraint = 'energy capacity';
else
    limiting_constraint = 'none (profile fits without scaling)';
end

% fprintf('\n  LIMITING CONSTRAINT: %s\n', upper(limiting_constraint));
% fprintf('  Initial scale factor: %.4f (%.2f%%)\n', scale_factor, scale_factor*100);

% Warning for very low scale factors
% if scale_factor < 0.05
%     warning('Scale factor is %.1f%%. The resulting profile may not be representative of realistic driving conditions.', scale_factor*100);
% elseif scale_factor < 0.10
%     % fprintf('  NOTE: Scale factor below 10%%. Profile is significantly derated.\n');
% end

% =========================================================================
%  APPLY SCALING AND VERIFY
% =========================================================================

% fprintf('\nApplying scale factor and verifying constraints...\n');

P_batt_scaled = P_batt_ref * scale_factor;

% Iterative verification and correction
max_iterations = 10;
tolerance = 0.001;  % 0.1% tolerance

for iter = 1:max_iterations
    % Compute scaled currents
    I_scaled_discharge = zeros(N_points, 1);
    I_scaled_charge    = zeros(N_points, 1);
    
    idx_dis = P_batt_scaled >= 0;
    idx_chg = P_batt_scaled < 0;
    
    I_scaled_discharge(idx_dis) = P_batt_scaled(idx_dis) / V_pack_min;
    I_scaled_charge(idx_chg)    = abs(P_batt_scaled(idx_chg)) / V_pack_nom;
    
    I_peak_discharge = max(I_scaled_discharge);
    I_peak_charge    = max(I_scaled_charge);
    
    % Check violations
    discharge_ratio = I_peak_discharge / I_pack_max_discharge;
    charge_ratio    = I_peak_charge / I_pack_max_charge;
    max_violation   = max(discharge_ratio, charge_ratio);
    
    if max_violation <= (1 + tolerance)
        % fprintf('  Iteration %d: PASS (max current ratio: %.4f)\n', iter, max_violation);
        break;
    else
        correction = 1 / max_violation;
        P_batt_scaled = P_batt_scaled * correction;
        scale_factor = scale_factor * correction;
        % fprintf('  Iteration %d: Correcting by %.4f (violation: %.2f%%)\n', ...
        %    iter, correction, (max_violation-1)*100);
    end
    
    if iter == max_iterations
        warning('Max iterations reached. Small constraint violation may remain.');
    end
end

% =========================================================================
%  FINAL VERIFICATION
% =========================================================================

% fprintf('\n---------------------------------------------------------------------------\n');
% fprintf('  FINAL VERIFICATION\n');
% fprintf('---------------------------------------------------------------------------\n');

% Recompute final currents
I_final_discharge = zeros(N_points, 1);
I_final_charge    = zeros(N_points, 1);

idx_dis = P_batt_scaled >= 0;
idx_chg = P_batt_scaled < 0;

I_final_discharge(idx_dis) = P_batt_scaled(idx_dis) / V_pack_min;
I_final_charge(idx_chg)    = abs(P_batt_scaled(idx_chg)) / V_pack_nom;

I_peak_discharge_final = max(I_final_discharge);
I_peak_charge_final    = max(I_final_charge);
P_peak_discharge_final = max(P_batt_scaled);
P_peak_charge_final    = abs(min(P_batt_scaled));

% Cell-level currents (pack current divided by Np)
I_cell_discharge_final = I_peak_discharge_final / Np;
I_cell_charge_final    = I_peak_charge_final / Np;

% fprintf('Final scale factor: %.4f (%.2f%% of reference)\n\n', scale_factor, scale_factor*100);

% fprintf('Power:\n');
% fprintf('  Peak discharge: %.2f kW (was %.2f kW)\n', P_peak_discharge_final/1000, P_ref_max_discharge/1000);
% fprintf('  Peak charge:    %.2f kW (was %.2f kW)\n\n', P_peak_charge_final/1000, P_ref_max_charge/1000);

% fprintf('Pack current:\n');
% fprintf('  Peak discharge: %.2f A (limit: %.2f A)\n', I_peak_discharge_final, I_pack_max_discharge);
% fprintf('  Peak charge:    %.2f A (limit: %.2f A)\n\n', I_peak_charge_final, I_pack_max_charge);

% fprintf('Cell current (per string):\n');
% fprintf('  Peak discharge: %.2f A (%.2f C, limit: %.1f C)\n', ...
    %I_cell_discharge_final, I_cell_discharge_final/Q_cell, Cell.C_rate_max);
% fprintf('  Peak charge:    %.2f A (%.2f C, limit: %.1f C)\n\n', ...
    %I_cell_charge_final, I_cell_charge_final/Q_cell, Cell.C_rate_chg);

% Verify constraints
discharge_ok = I_cell_discharge_final <= I_cell_max_discharge * (1 + tolerance);
charge_ok    = I_cell_charge_final <= I_cell_max_charge * (1 + tolerance);

if discharge_ok
    % fprintf('  [PASS] Discharge C-rate constraint\n');
else
    % fprintf('  [FAIL] Discharge C-rate exceeds limit by %.2f%%\n', ...
        %(I_cell_discharge_final/I_cell_max_discharge - 1)*100);
end

if charge_ok
    % fprintf('  [PASS] Charge C-rate constraint\n');
else
    % fprintf('  [FAIL] Charge C-rate exceeds limit by %.2f%%\n', ...
        %(I_cell_charge_final/I_cell_max_charge - 1)*100);
end

% Energy verification
E_scaled_cycle_Wh = trapz(t_cycle_s, P_batt_scaled) / 3600;
E_scaled_total_Wh = E_scaled_cycle_Wh * N_cycles_required;

% fprintf('\nEnergy:\n');
% fprintf('  Scaled energy per cycle: %.2f Wh\n', E_scaled_cycle_Wh);
% fprintf('  Scaled energy for %d cycles: %.2f Wh\n', N_cycles_required, E_scaled_total_Wh);
% fprintf('  Available pack energy: %.2f Wh\n', E_pack_usable_Wh);

if E_scaled_total_Wh <= E_pack_usable_Wh * (1 + tolerance)
    % fprintf('  [PASS] Energy constraint\n');
else
    % energy_deficit = E_scaled_total_Wh - E_pack_usable_Wh;
    % fprintf('  [FAIL] Energy exceeds capacity by %.2f Wh (%.1f%%)\n', ...
       % energy_deficit, energy_deficit/E_pack_usable_Wh*100);
    error('Energy constraint violated. Reduce N_cycles_required or increase pack size.');
end

% =========================================================================
%  BUILD OUTPUT STRUCTURES
% =========================================================================

% --- Results structure ---
Results = struct();
Results.scale_factor            = scale_factor;
Results.limiting_constraint     = limiting_constraint;

Results.E_ref_cycle_Wh          = E_ref_cycle_Wh;
Results.E_ref_total_Wh          = E_ref_total_Wh;
Results.E_scaled_cycle_Wh       = E_scaled_cycle_Wh;
Results.E_scaled_total_Wh       = E_scaled_total_Wh;
Results.E_pack_Wh               = E_pack_Wh;
Results.E_pack_usable_Wh        = E_pack_usable_Wh;

Results.Q_cell_Ah               = Q_cell;
Results.Q_pack_Ah               = Q_pack;
Results.Ns                      = Ns;
Results.Np                      = Np;

Results.V_pack_nom              = V_pack_nom;
Results.V_pack_min              = V_pack_min;
Results.V_pack_max              = V_pack_max;

Results.P_ref_max_discharge_W   = P_ref_max_discharge;
Results.P_ref_max_charge_W      = P_ref_max_charge;
Results.P_scaled_max_discharge_W= P_peak_discharge_final;
Results.P_scaled_max_charge_W   = P_peak_charge_final;

Results.I_pack_max_discharge_A  = I_pack_max_discharge;
Results.I_pack_max_charge_A     = I_pack_max_charge;
Results.I_cell_max_discharge_A  = I_cell_max_discharge;
Results.I_cell_max_charge_A     = I_cell_max_charge;

Results.I_peak_discharge_A      = I_peak_discharge_final;
Results.I_peak_charge_A         = I_peak_charge_final;
Results.I_cell_peak_discharge_A = I_cell_discharge_final;
Results.I_cell_peak_charge_A    = I_cell_charge_final;

Results.SOC_min                 = SOC_min;
Results.SOC_max                 = SOC_max;
Results.DOD                     = DOD;
Results.N_cycles                = N_cycles_required;

% --- ScaledProfile structure ---
ScaledProfile = struct();
ScaledProfile.time_s                = t_cycle_s;
ScaledProfile.P_batt_scaled_W       = P_batt_scaled;
ScaledProfile.P_batt_reference_W    = P_batt_ref;
ScaledProfile.scale_factor          = scale_factor;

ScaledProfile.Ns                    = Ns;
ScaledProfile.Np                    = Np;
ScaledProfile.Q_cell_Ah             = Q_cell;
ScaledProfile.Q_pack_Ah             = Q_pack;

ScaledProfile.V_pack_nom            = V_pack_nom;
ScaledProfile.V_pack_min            = V_pack_min;
ScaledProfile.V_pack_max            = V_pack_max;
ScaledProfile.V_cell_nom            = Cell.V_nom;
ScaledProfile.V_cell_min            = Cell.V_min;
ScaledProfile.V_cell_max            = Cell.V_max;

ScaledProfile.SOC_min               = SOC_min;
ScaledProfile.SOC_max               = SOC_max;
ScaledProfile.N_cycles              = N_cycles_required;

% Copy cell model parameters if available
if isfield(Cell, 'OCV_LUT'),  ScaledProfile.OCV_LUT  = Cell.OCV_LUT;  end
if isfield(Cell, 'SOC_vec'),  ScaledProfile.SOC_vec  = Cell.SOC_vec;  end
if isfield(Cell, 'R0_LUT'),   ScaledProfile.R0_LUT   = Cell.R0_LUT;   end
if isfield(Cell, 'R1_LUT'),   ScaledProfile.R1_LUT   = Cell.R1_LUT;   end
if isfield(Cell, 'tau1_LUT'), ScaledProfile.tau1_LUT = Cell.tau1_LUT; end
if isfield(Cell, 'T_vec'),    ScaledProfile.T_vec    = Cell.T_vec;    end
if isfield(Cell, 'm_cell'),   ScaledProfile.m_cell   = Cell.m_cell;   end
if isfield(Cell, 'c_cell'),   ScaledProfile.c_cell   = Cell.c_cell;   end

% --- CellProfile structure (for cycler/simulation) ---

% Compute current profiles
% I_cycler_A: Use this for battery cycler input (computed at nominal voltage)
% I_worstcase_A: Conservative estimate (discharge at V_min, charge at V_nom)

I_pack_nominal = P_batt_scaled / V_pack_nom;

I_pack_worstcase = zeros(N_points, 1);
idx_dis = P_batt_scaled >= 0;
idx_chg = P_batt_scaled < 0;
I_pack_worstcase(idx_dis) = P_batt_scaled(idx_dis) / V_pack_min;
I_pack_worstcase(idx_chg) = P_batt_scaled(idx_chg) / V_pack_nom;

% Cell-level currents (divide by Np)
I_cell_nominal   = I_pack_nominal / Np;
I_cell_worstcase = I_pack_worstcase / Np;

CellProfile = struct();
CellProfile.time_s              = t_cycle_s;

% PRIMARY OUTPUT: Use this for your cycler
CellProfile.I_cycler_A          = I_cell_nominal;
CellProfile.I_cycler_notes      = 'Cell current at V_nom. Use this for battery cycler input.';

% Alternative profiles
CellProfile.I_cell_worstcase_A  = I_cell_worstcase;
CellProfile.I_pack_nominal_A    = I_pack_nominal;
CellProfile.I_pack_worstcase_A  = I_pack_worstcase;

CellProfile.P_pack_W            = P_batt_scaled;
CellProfile.scale_factor        = scale_factor;

CellProfile.V_cell_nom          = Cell.V_nom;
CellProfile.V_cell_min          = Cell.V_min;
CellProfile.V_cell_max          = Cell.V_max;
CellProfile.V_pack_nom          = V_pack_nom;
CellProfile.V_pack_min          = V_pack_min;
CellProfile.V_pack_max          = V_pack_max;

CellProfile.Q_cell_Ah           = Q_cell;
CellProfile.Q_pack_Ah           = Q_pack;
CellProfile.Ns                  = Ns;
CellProfile.Np                  = Np;

CellProfile.I_cell_max_discharge_A = I_cell_max_discharge;
CellProfile.I_cell_max_charge_A    = I_cell_max_charge;
CellProfile.I_pack_max_discharge_A = I_pack_max_discharge;
CellProfile.I_pack_max_charge_A    = I_pack_max_charge;

CellProfile.SOC_min             = SOC_min;
CellProfile.SOC_max             = SOC_max;

% Copy cell model parameters if available
if isfield(Cell, 'OCV_LUT'),  CellProfile.OCV_LUT  = Cell.OCV_LUT;  end
if isfield(Cell, 'SOC_vec'),  CellProfile.SOC_vec  = Cell.SOC_vec;  end
if isfield(Cell, 'R0_LUT'),   CellProfile.R0_LUT   = Cell.R0_LUT;   end
if isfield(Cell, 'R1_LUT'),   CellProfile.R1_LUT   = Cell.R1_LUT;   end
if isfield(Cell, 'tau1_LUT'), CellProfile.tau1_LUT = Cell.tau1_LUT; end
if isfield(Cell, 'T_vec'),    CellProfile.T_vec    = Cell.T_vec;    end
if isfield(Cell, 'm_cell'),   CellProfile.m_cell   = Cell.m_cell;   end
if isfield(Cell, 'c_cell'),   CellProfile.c_cell   = Cell.c_cell;   end

% =========================================================================
%  FINAL SUMMARY
% =========================================================================

% fprintf('\n===========================================================================\n');
% fprintf('  SUMMARY\n');
% fprintf('===========================================================================\n');
% fprintf('  Pack: %ds%dp, %.2f Ah cells, %.1f V nominal\n', Ns, Np, Q_cell, V_pack_nom);
% fprintf('  Pack Energy: %.2f Wh (%.2f Wh usable at %.0f%% DOD)\n', E_pack_Wh, E_pack_usable_Wh, DOD*100);
% fprintf('\n');
% fprintf('  Scale Factor: %.2f%% of reference WLTC\n', scale_factor*100);
% fprintf('  Limiting Constraint: %s\n', limiting_constraint);
% fprintf('\n');
% fprintf('  Scaled Peak Power: %.2f kW discharge / %.2f kW charge\n', ...
    %P_peak_discharge_final/1000, P_peak_charge_final/1000);
% fprintf('  Scaled Peak Cell Current: %.2f A (%.2f C) / %.2f A (%.2f C)\n', ...
    %I_cell_discharge_final, I_cell_discharge_final/Q_cell, ...
    %I_cell_charge_final, I_cell_charge_final/Q_cell);
% fprintf('\n');
% fprintf('  Energy per Scaled Cycle: %.2f Wh\n', E_scaled_cycle_Wh);
% fprintf('  Energy for %d Cycles: %.2f Wh\n', N_cycles_required, E_scaled_total_Wh);
% fprintf('\n');
% fprintf('  OUTPUT: Use CellProfile.I_cycler_A for battery cycler input\n');
% fprintf('===========================================================================\n');

% =========================================================================
%  PLOTS (OPTIONAL)
% =========================================================================

if PlotFigures
    % Figure 1: Reference vs Scaled Comparison
    figure('Name', 'Drive Cycle Scaling Analysis', 'Position', [100 100 1200 800]);
    
    subplot(2,2,1);
    plot(t_cycle_s/60, v_kmh, 'b', 'LineWidth', 1.2);
    xlabel('Time [min]');
    ylabel('Speed [km/h]');
    title('WLTC Class 3 Speed Profile');
    grid on;
    xlim([0 t_cycle_s(end)/60]);
    
    subplot(2,2,2);
    hold on;
    plot(t_cycle_s/60, P_batt_ref/1000, 'b-', 'LineWidth', 0.8, 'DisplayName', 'Reference');
    plot(t_cycle_s/60, P_batt_scaled/1000, 'r-', 'LineWidth', 1.2, 'DisplayName', sprintf('Scaled (%.1f%%)', scale_factor*100));
    yline(0, 'k--', "HandleVisibility","off");
    xlabel('Time [min]');
    ylabel('Battery Power [kW]');
    title('Power Profile: Reference vs Scaled');
    legend('Location', 'best');
    grid on;
    xlim([0 t_cycle_s(end)/60]);
    
    subplot(2,2,3);
    hold on;
    plot(t_cycle_s/60, I_cell_nominal, 'r-', 'LineWidth', 1, 'DisplayName', 'Cell Current');
    yline(I_cell_max_discharge, 'r--', 'LineWidth', 1.5, 'DisplayName', sprintf('Max Discharge (%.1fC)', Cell.C_rate_max));
    yline(-I_cell_max_charge, 'g--', 'LineWidth', 1.5, 'DisplayName', sprintf('Max Charge (%.1fC)', Cell.C_rate_chg));
    xlabel('Time [min]');
    ylabel('Cell Current [A]');
    title(sprintf('Cell Current Profile (%.2f Ah cell)', Q_cell));
    legend('Location', 'best');
    grid on;
    xlim([0 t_cycle_s(end)/60]);
    
    subplot(2,2,4);
    E_cumulative = cumtrapz(t_cycle_s, P_batt_scaled) / 3600;
    SOC_profile = SOC_max - E_cumulative / E_pack_Wh;
    plot(t_cycle_s/60, SOC_profile*100, 'm', 'LineWidth', 1.5);
    hold on;
    yline(SOC_min*100, 'r--', 'LineWidth', 1.5);
    yline(SOC_max*100, 'g--', 'LineWidth', 1.5);
    xlabel('Time [min]');
    ylabel('State of Charge [%]');
    title('SOC Profile (Single Cycle)');
    ylim([0 100]);
    grid on;
    xlim([0 t_cycle_s(end)/60]);
    
    sgtitle(sprintf('Drive Cycle Scaling: %ds%dp Pack, %.2f%% of Reference', Ns, Np, scale_factor*100));
    
    % Figure 2: Multi-cycle SOC
    if N_cycles_required > 1
        figure('Name', 'Multi-Cycle SOC Profile', 'Position', [150 150 1000 400]);
        
        % Build multi-cycle time and power vectors
        t_multi = [];
        P_multi = [];
        for cyc = 1:N_cycles_required
            t_offset = (cyc-1) * t_cycle_s(end);
            t_multi = [t_multi; t_cycle_s + t_offset]; %#ok<AGROW>
            P_multi = [P_multi; P_batt_scaled];        %#ok<AGROW>
        end
        
        E_multi = cumtrapz(t_multi, P_multi) / 3600;
        SOC_multi = SOC_max - E_multi / E_pack_Wh;
        
        plot(t_multi/60, SOC_multi*100, 'r', 'LineWidth', 1.5);
        hold on;
        yline(SOC_min*100, 'g--', 'LineWidth', 1.5, 'DisplayName', sprintf('SOC_{min} (%.0f%%)', SOC_min*100));
        yline(SOC_max*100, 'r--', 'LineWidth', 1.5, 'DisplayName', sprintf('SOC_{max} (%.0f%%)', SOC_max*100));
        xlabel('Time [min]');
        ylabel('State of Charge [%]');
        title(sprintf('SOC Over %d Cycles (%ds%dp, %.2f Ah)', N_cycles_required, Ns, Np, Q_cell));
        ylim([0 100]);
        grid on;
        xlim([0 t_multi(end)/60]);
        legend('Location', 'best');
    end
end

end