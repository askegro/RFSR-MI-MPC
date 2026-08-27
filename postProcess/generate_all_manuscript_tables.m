function generate_all_manuscript_tables()
% postProcess/generate_all_manuscript_tables.m
%
% CLICK-ONCE ENTRY POINT for every manuscript table (Table I through
% Table VII) plus the Appendix-A SOS2 numbers. Run this one function; it
% regenerates each of them from
% whatever results .mat files are already on disk (via the same
% analyze_*.m / report_table_*.m scripts you would otherwise run one at
% a time), and prints a single, consolidated dump of just those 7
% tables -- nothing else -- as the LAST thing written to the Command
% Window, so none of the underlying scripts' own `clc` calls can clear
% it away.
%
% How it works
%   Each component below is an existing script (an analyze_*.m that
%   also happens to print its section's manuscript table among its
%   other diagnostics, or a small standalone report_table_*.m for the
%   two tables with no natural owning script -- Tables I and II,
%   see the code-review discussion this function follows from). Each
%   manuscript-table print block in those scripts is wrapped with a
%   pair of sentinel lines:
%       fprintf('<<<MANUSCRIPT_TABLE_BEGIN tab:XXX>>>\n');
%       ... the exact table ...
%       fprintf('<<<MANUSCRIPT_TABLE_END tab:XXX>>>\n');
%   This function runs each component with evalc(), which captures
%   everything the script prints into a string (regardless of that
%   script's own clc/close all/diary behaviour), then extracts just the
%   sentinel-delimited block for the table this function cares about.
%   Everything else the component script prints (solve-classification
%   breakdowns, mask audits, MIP-tolerance checks, etc.) is still
%   generated; this function only changes what appears in the FINAL
%   console dump. The components no longer write their own
%   *_command_output.txt/.tex files: the single run log written by
%   REPRODUCE_ALL_RESULTS is the archival record.
%
% Prerequisites
%   Each component needs its own results .mat file already produced by
%   the corresponding runner in mainSimulationRunners/. A component
%   whose prerequisite is missing is reported as NOT AVAILABLE in the
%   final status summary, not fatal -- every table that CAN be produced
%   still is.
%
% Manuscript table -> component script -> sentinel tag:
%   Table I    report_table_evaluation_protocol     tab:evaluation_protocol      (Sec. V-A) 
%   Table II   report_table_robustness_case_params  tab:robustness_case_params   (Sec. V-E) 
%   Table III  analyze_solver_certification                          tab:runtime_timing           (Sec. VI-A.1)
%   Table IV   analyze_samestate_gap              tab:same_state_summary       (Sec. VI-A.2)
%   Table V    analyze_closedloop_perf       tab:closed_loop_summary      (Sec. VI-A.3)
%   Table VI   analyze_montecarlo_ics              tab:mc_bootstrap             (Sec. VI-B.1)
%   Table VII  analyze_robustness_sweeps                tab:robustness_sweeps        (Sec. VI-B.2)
%   Appendix A analyze_SOS2_curtailment_error      tab:appendix_sos2
%
% Companion script
%   postProcess/report_intext_numbers.m produces every number quoted in the
%   RUNNING TEXT of Section V. Together the two reproduce Section V in full.
%   REPRODUCE_ALL_RESULTS.m at the project root runs both, plus the figures.

    MT_thisFile    = mfilename('fullpath');
    MT_thisDir     = fileparts(MT_thisFile);          % postProcess/
    MT_projectRoot = fileparts(MT_thisDir);            % project root
    addpath(MT_projectRoot);
    addpath(MT_thisDir);
    initProjectPaths(MT_thisFile);

    % TABLE NUMBERS follow LaTeX's order-of-appearance in the manuscript
    % source, NOT the order the tables are discussed in Section V:
    %   Table I   is in Section V-A  (tab:evaluation_protocol)
    %   Table II  is in Section V-E  (tab:robustness_case_params)
    %   Tables III-VII are the five Section VI tables, in order.
    % The two Section V (Evaluation Methodology) tables come FIRST; the
    % Results and Discussion section is Section VI, not Section V. The list below is in
    % manuscript source order so that the row index equals the table number.
    %
    % TITLES are the verbatim \caption{} text of the manuscript LaTeX source.
    % If the manuscript is restructured, re-derive both the numbers and the
    % titles from the source before trusting this list.
    MT_components = { ...
        'Table I    -- Nominal Evaluation Parameters.',                                                                'report_table_evaluation_protocol',    'tab:evaluation_protocol'; ...
        'Table II   -- Initial-Dispersion Parameters for the Heterogeneity/Demand Sweep.',                              'report_table_robustness_case_params', 'tab:robustness_case_params'; ...
        'Table III  -- Solver-Time And Branch-and-Bound Statistics For The Nominal WLTC Cycle.',                        'analyze_solver_certification',                         'tab:runtime_timing'; ...
        'Table IV   -- Same-State Approximation Cost on Jointly Certified, Uncurtailed Steps K_pair.',                  'analyze_samestate_gap',             'tab:same_state_summary'; ...
        'Table V    -- Closed-Loop Performance Over The Nominal WLTC Cycle.',                                          'analyze_closedloop_perf',      'tab:closed_loop_summary'; ...
        'Table VI   -- Paired Monte Carlo Results Over 20 Initial-Condition Realizations.',                             'analyze_montecarlo_ics',             'tab:mc_bootstrap'; ...
        'Table VII  -- Robustness Results For Heterogeneity, Demand, Pack-Size, and Prediction-Horizon Variations.',    'analyze_robustness_sweeps',               'tab:robustness_sweeps'; ...
        'Appendix A -- SOS2 approximation of the inverse pack voltage (N_v, eps_SOS2, curtailment-error bound).',       'analyze_SOS2_curtailment_error',      'tab:appendix_sos2'; ...
    };

    MT_nC        = size(MT_components, 1);
    MT_tableText = cell(MT_nC, 1);
    MT_status    = cell(MT_nC, 1);

    for MT_ci = 1:MT_nC
        MT_label      = MT_components{MT_ci, 1};
        MT_scriptName = MT_components{MT_ci, 2};
        MT_tag        = MT_components{MT_ci, 3};

        fprintf('>>> [%d/%d] Running %s (%s)...\n', MT_ci, MT_nC, MT_label, MT_scriptName);
        try
            MT_txt   = evalc(MT_scriptName);
            MT_block = local_extract_block(MT_txt, MT_tag);
            if isempty(MT_block)
                MT_tableText{MT_ci} = '';
                MT_status{MT_ci}    = 'RAN, but table sentinel not found in captured output (script may have changed)';
            else
                MT_tableText{MT_ci} = MT_block;
                MT_status{MT_ci}    = 'OK';
            end
        catch MT_err
            MT_tableText{MT_ci} = '';
            MT_status{MT_ci}    = sprintf('FAILED: %s', MT_err.message);
        end
    end

    %% ------------------------------------------------------------------
    %  Final consolidated printout. This is the LAST thing this function
    %  writes, so no component script's internal clc can clear it away.
    %% ------------------------------------------------------------------
    fprintf('\n\n');
    fprintf('%s\n', repmat('#', 1, 78));
    fprintf('###  ALL MANUSCRIPT TABLES (I - VII) + APPENDIX A\n');
    fprintf('%s\n', repmat('#', 1, 78));

    for MT_ci = 1:MT_nC
        fprintf('\n%s\n', repmat('#', 1, 78));
        fprintf('# %s\n', MT_components{MT_ci, 1});
        fprintf('%s\n', repmat('#', 1, 78));
        if isempty(MT_tableText{MT_ci})
            fprintf('  [NOT AVAILABLE -- %s]\n', MT_status{MT_ci});
        else
            fprintf('%s\n', MT_tableText{MT_ci});
        end
    end

    fprintf('\n%s\n', repmat('=', 1, 78));
    fprintf('Status summary:\n');
    for MT_ci = 1:MT_nC
        fprintf('  %-45s %s\n', MT_components{MT_ci, 1}, MT_status{MT_ci});
    end
    fprintf('%s\n', repmat('=', 1, 78));
    fprintf('\nFull diagnostic output for each component (beyond its manuscript\n');
    fprintf('table) appears in the run log written by REPRODUCE_ALL_RESULTS.\n');
end

function block = local_extract_block(txt, tag)
% Extract the text between <<<MANUSCRIPT_TABLE_BEGIN tag>>> and
% <<<MANUSCRIPT_TABLE_END tag>>> sentinel lines from a captured
% transcript. Returns '' if the sentinel pair is not found.
    beginMark = ['<<<MANUSCRIPT_TABLE_BEGIN ' tag '>>>'];
    endMark   = ['<<<MANUSCRIPT_TABLE_END ' tag '>>>'];
    iBegin = strfind(txt, beginMark);
    iEnd   = strfind(txt, endMark);
    if isempty(iBegin) || isempty(iEnd)
        block = '';
        return;
    end
    startIdx = iBegin(1) + length(beginMark);
    endIdx   = iEnd(1) - 1;
    if endIdx < startIdx
        block = '';
        return;
    end
    block = strtrim(txt(startIdx:endIdx));
end
