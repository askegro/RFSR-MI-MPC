function REPRODUCE_ALL_RESULTS()
% REPRODUCE_ALL_RESULTS.m
%
% ============================ CLICK AND PLAY =============================
% Open this file in MATLAB and press Run. Nothing else is required.
%
% Reproduces EVERY number of Section VI (Results and Discussion) of
%
%   A. Skegro, Q. Ouyang, T. Wik, C. Zou,
%   "RFSR-MI-MPC: Ranking-Based Feasible-Set Restriction for Real-Time
%    Control of Reconfigurable Battery Packs",
%   submitted to IEEE Transactions on Control Systems Technology,
%
% -- both the table entries and every value quoted in the running text --
% together with the Section V inputs they are generated from, the headline
% numbers restated in the Conclusion, the Appendix SOS2 numbers, and the
% three manuscript figures.
%
% -------------------------------------------------------------------------
% OUTPUT
% -------------------------------------------------------------------------
% The report is organised by MANUSCRIPT SUBSECTION. Each part carries the
% table(s) belonging to that subsection followed by the in-text numbers of
% the same subsection, so the report can be read side by side with the
% paper:
%
%   Section V     Evaluation Methodology (inputs)          Tables I, II
%   Section VI-A.1  Solver Certification and Runtime       Table III
%   Section VI-A.2  Same-State Approximation Cost          Table IV
%   Section VI-A.3  Closed-Loop Control Performance        Table V
%   Section VI-B.1  Sensitivity to Initial Conditions      Table VI
%   Section VI-B.2  Cell Heterogeneity and Demand          Table VII
%   Section VI-B.3  Sensitivity to Pack Size
%   Section VI-B.4  Sensitivity to Prediction Horizon
%   Section VII   Conclusion (headline numbers)
%   Appendix      SOS2 approximation of the inverse pack voltage
%
% The report is printed to the MATLAB Command Window AND written verbatim
% to
%   results/textualOutputs/REPRODUCE_ALL_RESULTS_<timestamp>.txt
%
% Both come from the same string, so the file and the screen can never
% disagree. The report is assembled first and printed last, on purpose:
% several of the underlying analysis scripts call clc, which would wipe
% anything printed before them. This run log is the single archival record:
% the analysis scripts no longer open diaries or write per-component
% *_command_output.txt/.tex files of their own.
%
% Figures 2, 3 and 4 are written as EPS + PDF into results/Figures/.
%
% -------------------------------------------------------------------------
% MANUSCRIPT SECTION AND TABLE NUMBERING
% -------------------------------------------------------------------------
% Numbers follow the order of \section{} and \caption{} in the LaTeX
% source:
%   I Introduction; II Modeling; III Combinatorial Structure;
%   IV Ranking-Based Restriction; V Evaluation Methodology;
%   VI Results and Discussion; VII Conclusion.
%   Table I  (Sec. V-A), Table II (Sec. V-E),
%   Tables III-VII (Sec. VI-A.1, VI-A.2, VI-A.3, VI-B.1, VI-B.2).
% Script and result-file names describe what each experiment DOES, never
% where its output lands in the paper: section and table numbers move when a
% manuscript is restructured, and an earlier version of this code encoded
% them in filenames and went stale.
%
% -------------------------------------------------------------------------
% PREREQUISITES
% -------------------------------------------------------------------------
% Software: base MATLAB plus the Statistics and Machine Learning Toolbox
% (prctile). Gurobi and YALMIP are needed only to RE-RUN the simulations,
% not to reproduce the report from the shipped result files.
%
% Data: the five result files in results/. If any is missing, run
%   mainSimulationRunners/RUN_ALL_SIMULATIONS.m
% first (this takes hours), or fetch the archived files -- see README.md.
% A missing file is reported as NOT AVAILABLE for the affected part;
% everything that CAN be produced still is.
% =========================================================================

    RA_thisFile = mfilename('fullpath');
    RA_rootDir  = fileparts(RA_thisFile);
    addpath(RA_rootDir);
    initProjectPaths(RA_thisFile);

    % --- Components to run, and the blocks each is expected to emit -----
    RA_components = { ...
        'report_table_evaluation_protocol'; ...
        'report_table_robustness_case_params'; ...
        'analyze_solver_certification'; ...
        'analyze_samestate_gap'; ...
        'analyze_closedloop_perf'; ...
        'analyze_montecarlo_ics'; ...
        'analyze_robustness_sweeps'; ...
        'analyze_SOS2_curtailment_error'; ...
        'report_intext_numbers'; ...
    };

    % --- Report layout: {part heading, {tag, caption; ...}} -------------
    RA_layout = { ...
      'SECTION V -- EVALUATION METHODOLOGY (inputs to the results)', { ...
          'tab:evaluation_protocol',    'Table I -- Nominal Evaluation Parameters.'; ...
          'tab:robustness_case_params', 'Table II -- Initial-Dispersion Parameters for the Heterogeneity/Demand Sweep.'; ...
          'sec:V',                      'In-text numbers'}; ...
      'SECTION VI-A.1 -- SOLVER CERTIFICATION AND RUNTIME', { ...
          'tab:runtime_timing',         'Table III -- Solver-Time And Branch-and-Bound Statistics For The Nominal WLTC Cycle.'; ...
          'sec:VI-A1',                  'In-text numbers'}; ...
      'SECTION VI-A.2 -- SAME-STATE APPROXIMATION COST', { ...
          'tab:same_state_summary',     'Table IV -- Same-State Approximation Cost on Jointly Certified, Uncurtailed Steps K_pair.'; ...
          'sec:VI-A2',                  'In-text numbers'}; ...
      'SECTION VI-A.3 -- CLOSED-LOOP CONTROL PERFORMANCE', { ...
          'tab:closed_loop_summary',    'Table V -- Closed-Loop Performance Over The Nominal WLTC Cycle.'; ...
          'sec:VI-A3',                  'In-text numbers'}; ...
      'SECTION VI-B.1 -- SENSITIVITY TO INITIAL CONDITIONS', { ...
          'tab:mc_bootstrap',           'Table VI -- Paired Monte Carlo Results Over 20 Initial-Condition Realizations.'; ...
          'sec:VI-B1-ci',               'In-text numbers: do all 95% bootstrap CIs exclude zero?'; ...
          'sec:VI-B1',                  'In-text numbers: design parameters'}; ...
      'SECTION VI-B.2 -- SENSITIVITY TO CELL HETEROGENEITY AND DEMAND', { ...
          'tab:robustness_sweeps',      'Table VII -- Robustness Results For Heterogeneity, Demand, Pack-Size, and Prediction-Horizon Variations.'; ...
          'sec:VI-B2',                  'In-text numbers'}; ...
      'SECTION VI-B.3 -- SENSITIVITY TO PACK SIZE', { ...
          'sec:VI-B3',                  'In-text numbers (table rows are in Table VII above)'}; ...
      'SECTION VI-B.4 -- SENSITIVITY TO PREDICTION HORIZON', { ...
          'sec:VI-B4',                  'In-text numbers (table rows are in Table VII above)'}; ...
      'SECTION VII -- CONCLUSION (headline numbers)', { ...
          'sec:VII',                    'In-text numbers'}; ...
      'APPENDIX -- DETAILED MIXED-INTEGER CONVEX REFORMULATION', { ...
          'tab:appendix_sos2',          'SOS2 curtailment-error check (analyze_SOS2_curtailment_error)'; ...
          'sec:APP',                    'In-text numbers'}; ...
    };

    RA_stamp  = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    RA_outDir = fullfile(RA_rootDir, 'results', 'textualOutputs');
    if ~exist(RA_outDir, 'dir'), mkdir(RA_outDir); end
    RA_logFile = fullfile(RA_outDir, ['REPRODUCE_ALL_RESULTS_' RA_stamp '.txt']);

    % --- 1. Run every component once, capturing all of its output -------
    RA_nC     = numel(RA_components);
    RA_raw    = cell(RA_nC, 1);
    RA_status = cell(RA_nC, 1);
    for RA_i = 1:RA_nC
        fprintf('[%d/%d] running %s ...\n', RA_i, RA_nC, RA_components{RA_i});
        try
            RA_raw{RA_i}    = evalc(RA_components{RA_i});
            RA_status{RA_i} = 'OK';
        catch RA_err
            RA_raw{RA_i}    = '';
            RA_status{RA_i} = sprintf('FAILED: %s', RA_err.message);
            fprintf(2, '    -> %s\n', RA_status{RA_i});
        end
    end

    % --- 2. Figures ------------------------------------------------------
    fprintf('[figures] generate_all_manuscript_figures ...\n');
    try
        RA_figTxt = evalc('generate_all_manuscript_figures');
        RA_figSt  = 'OK';
    catch RA_err
        RA_figTxt = '';
        RA_figSt  = sprintf('FAILED: %s', RA_err.message);
        fprintf(2, '    -> %s\n', RA_figSt);
    end

    % --- 3. Assemble the report by manuscript subsection ----------------
    RA_all = local_assemble(RA_layout, RA_components, RA_raw, RA_status, ...
                            RA_figTxt, RA_figSt);

    % --- 4. Write the file, then print the identical string to screen ---
    RA_fid = fopen(RA_logFile, 'w');
    if RA_fid > 0
        fprintf(RA_fid, '%s', RA_all);
        fclose(RA_fid);
        RA_wrote = true;
    else
        RA_wrote = false;
    end

    fprintf('%s', RA_all);
    fprintf('\n%s\n', repmat('=', 1, 78));
    if RA_wrote
        fprintf('The identical report was written to:\n  %s\n', RA_logFile);
    else
        fprintf(2, 'WARNING: could not write the transcript to:\n  %s\n', RA_logFile);
    end
    fprintf('Figures written to:\n  %s\n', fullfile(RA_rootDir, 'results', 'Figures'));
    fprintf('%s\n\n', repmat('=', 1, 78));
end

%% =======================================================================
function txt = local_assemble(layout, comps, raw, status, figTxt, figSt)
    L  = {};
    nl = newline;
    bar1 = repmat('#', 1, 78);
    bar2 = repmat('=', 1, 78);
    bar3 = repmat('-', 1, 78);

    L{end+1} = bar1;
    L{end+1} = '###  RFSR-MI-MPC -- reproduction of the manuscript results';
    L{end+1} = ['###  generated ' char(datetime('now'))];
    L{end+1} = '###';
    L{end+1} = '###  Organised by manuscript subsection. Each part carries the table(s)';
    L{end+1} = '###  of that subsection followed by the numbers quoted in its running text.';
    L{end+1} = bar1;

    allTxt  = strjoin(raw, nl);
    missing = {};

    for i = 1:size(layout, 1)
        L{end+1} = ''; %#ok<AGROW>
        L{end+1} = bar2; %#ok<AGROW>
        L{end+1} = ['  ' layout{i, 1}]; %#ok<AGROW>
        L{end+1} = bar2; %#ok<AGROW>
        blocks = layout{i, 2};
        for j = 1:size(blocks, 1)
            tag = blocks{j, 1};
            cap = blocks{j, 2};
            L{end+1} = ''; %#ok<AGROW>
            L{end+1} = ['  ' cap]; %#ok<AGROW>
            L{end+1} = ['  ' bar3(1:min(numel(bar3), 76))]; %#ok<AGROW>
            body = local_extract(allTxt, tag);
            if isempty(body)
                L{end+1} = ['  [BLOCK NOT PRODUCED -- tag ' tag ']']; %#ok<AGROW>
                missing{end+1} = tag; %#ok<AGROW>
            else
                L{end+1} = body; %#ok<AGROW>
            end
        end
    end

    L{end+1} = '';
    L{end+1} = bar2;
    L{end+1} = '  MANUSCRIPT FIGURES';
    L{end+1} = bar2;
    if isempty(figTxt)
        L{end+1} = ['  [NOT PRODUCED -- ' figSt ']'];
    else
        L{end+1} = strtrim(figTxt);
    end

    L{end+1} = '';
    L{end+1} = bar2;
    L{end+1} = '  COMPONENT STATUS';
    L{end+1} = bar2;
    for i = 1:numel(comps)
        L{end+1} = sprintf('  %-40s %s', comps{i}, status{i}); %#ok<AGROW>
    end
    L{end+1} = sprintf('  %-40s %s', 'generate_all_manuscript_figures', figSt);
    if isempty(missing)
        L{end+1} = '';
        L{end+1} = '  All report blocks were produced.';
    else
        L{end+1} = '';
        L{end+1} = sprintf('  %d report block(s) were NOT produced:', numel(missing));
        for i = 1:numel(missing)
            L{end+1} = ['    ' missing{i}]; %#ok<AGROW>
        end
        L{end+1} = '  A missing block usually means its result .mat file is absent';
        L{end+1} = '  (see the COMPONENT STATUS lines above and README.md).';
    end
    L{end+1} = bar2;

    txt = strjoin(L, nl);
end

%% =======================================================================
function block = local_extract(txt, tag)
% Extract the text between the <<<MANUSCRIPT_TABLE_BEGIN tag>>> and
% <<<MANUSCRIPT_TABLE_END tag>>> sentinel lines. Returns '' if absent.
    beginMark = ['<<<MANUSCRIPT_TABLE_BEGIN ' tag '>>>'];
    endMark   = ['<<<MANUSCRIPT_TABLE_END ' tag '>>>'];
    iB = strfind(txt, beginMark);
    iE = strfind(txt, endMark);
    if isempty(iB) || isempty(iE)
        block = '';
        return;
    end
    s = iB(1) + length(beginMark);
    e = iE(1) - 1;
    if e < s
        block = '';
        return;
    end
    block = strtrim(txt(s:e));
end
