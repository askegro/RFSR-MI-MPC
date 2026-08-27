function generate_all_manuscript_figures()
% figureGeneration/generate_all_manuscript_figures.m
%
% CLICK-ONCE ENTRY POINT for the three figures that appear in the
% manuscript. Run this one function; it regenerates each figure from
% results/Results_nominal_wltc_*.mat and writes both an EPS
% and a PDF into results/Figures/.
%
% Manuscript figure -> generator script -> output file
%   Fig. 2  Empirical CDF of per-step solver time
%             figure_solve_time_cdf
%             -> results/Figures/figure_solve_time_cdf.{eps,pdf}
%   Fig. 3  Requested power and baseline solve class over the WLTC cycle
%             figure_power_solveclass
%             -> results/Figures/figure_power_solveclass.{eps,pdf}
%   Fig. 4  Cell engagement over the WLTC cycle (baseline vs proposed)
%             figure_engagement_heatmap
%             -> results/Figures/figure_engagement_heatmap.{eps,pdf}
%
% Fig. 1 (the pack schematic) is drawn in TikZ inside the LaTeX source and
% has no MATLAB generator.
%
% These generators set the LaTeX text interpreter and IEEE column geometry,
% and are the ones that produced the published files.
%
% Prerequisite:
%   results/Results_nominal_wltc_*.mat
%   (produced by mainSimulationRunners/run_nominal_wltc.m)

    FG_thisFile    = mfilename('fullpath');
    FG_thisDir     = fileparts(FG_thisFile);
    FG_projectRoot = fileparts(FG_thisDir);
    addpath(FG_projectRoot);
    addpath(FG_thisDir);
    initProjectPaths(FG_thisFile);

    FG_components = { ...
        'Fig. 2 -- Empirical CDF of per-step solver time', 'figure_solve_time_cdf'; ...
        'Fig. 3 -- Requested power and baseline solve class', 'figure_power_solveclass'; ...
        'Fig. 4 -- Cell engagement over the WLTC cycle', 'figure_engagement_heatmap'; ...
    };

    FG_n      = size(FG_components, 1);
    FG_status = cell(FG_n, 1);

    for FG_i = 1:FG_n
        fprintf('>>> [%d/%d] %s (%s)...\n', FG_i, FG_n, ...
            FG_components{FG_i, 1}, FG_components{FG_i, 2});
        try
            evalc(FG_components{FG_i, 2});
            FG_status{FG_i} = 'OK';
        catch FG_err
            FG_status{FG_i} = sprintf('FAILED: %s', FG_err.message);
        end
    end

    fprintf('\n%s\n', repmat('=', 1, 78));
    fprintf('Manuscript figures -- status summary\n');
    fprintf('%s\n', repmat('=', 1, 78));
    for FG_i = 1:FG_n
        fprintf('  %-52s %s\n', FG_components{FG_i, 1}, FG_status{FG_i});
    end
    fprintf('%s\n', repmat('=', 1, 78));
    fprintf('Output directory: results/Figures/\n\n');
end
