% figureGeneration/figure_engagement_heatmap.m
% Manuscript Fig. 4 (cell-engagement heat map), Section VI-A.3:
% Binary cell engagement S_{i,k} over the WLTC cycle for Variants A and D.
% X-axis: time [s] starting at t = 0. Y-axis: cell index.

clc;
close all;

% IEEEtran figure formatting: LaTeX interpreter, 9 pt text
set(groot, 'DefaultAxesTickLabelInterpreter', 'latex');
set(groot, 'DefaultTextInterpreter',          'latex');
set(groot, 'DefaultLegendInterpreter',        'latex');

set(groot, 'DefaultAxesFontName',   'Helvetica');
set(groot, 'DefaultTextFontName',   'Helvetica');
set(groot, 'DefaultLegendFontName', 'Helvetica');

set(groot, 'DefaultAxesFontSize',   9);
set(groot, 'DefaultTextFontSize',   9);
set(groot, 'DefaultLegendFontSize', 9);

rootDir    = initProjectPaths(mfilename('fullpath'));
resultsDir = ensureResultsDir(rootDir);
figuresDir = fullfile(resultsDir, 'Figures');

if ~exist(figuresDir, 'dir')
    mkdir(figuresDir);
end

latestFile = findLatestResultFile( ...
    fullfile(rootDir, 'results', ...
    'Results_nominal_wltc_*.mat'), ...
    'Run mainSimulationRunners/run_nominal_wltc.m first.');

data = load(latestFile);
fprintf('Loaded %s\n', latestFile);

R     = data.Results;
Tstep = data.cfg.Tstep;
Ns    = data.cfg.Ns;

S_A = double(R.A.log.S);   % Ns-by-n_steps binary matrix
S_D = double(R.D.log.S);

n_steps = size(S_A, 2);
t       = (0:n_steps - 1) * Tstep;   % Time [s], starting at zero

col_A = [0.00 0.45 0.70];
col_D = [0.80 0.40 0.00];

% IEEEtran one-column figure dimensions:
% 3.375 in = approximately 8.573 cm
paperWidth  = 8.573;   % cm
paperHeight = 8.0;     % cm
fs          = 9;

fig = figure( ...
    'Color',    'w', ...
    'Units',    'centimeters', ...
    'Position', [2 2 paperWidth paperHeight]);

tl = tiledlayout(fig, 2, 1, ...
    'TileSpacing', 'compact', ...
    'Padding',     'compact');

% --- Top tile: Variant A -----------------------------------------------------
ax1 = nexttile(tl);

imagesc(ax1, t, 1:Ns, S_A);
colormap(ax1, [1 1 1; col_A]);
clim(ax1, [0 1]);

set(ax1, ...
    'YDir',                 'normal', ...
    'FontSize',             fs, ...
    'TickLabelInterpreter', 'latex', ...
    'XTickLabel',           {}, ...
    'YTick',                [1 5 10 15 20]);

ylabel(ax1, '$\mathrm{Cell}$', ...
    'Interpreter', 'latex', ...
    'FontSize',    fs);

xlim(ax1, [0 1800]);
ylim(ax1, [0.5 Ns + 0.5]);
box(ax1, 'on');

% --- Bottom tile: Variant D --------------------------------------------------
ax2 = nexttile(tl);

imagesc(ax2, t, 1:Ns, S_D);
colormap(ax2, [1 1 1; col_D]);
clim(ax2, [0 1]);

set(ax2, ...
    'YDir',                 'normal', ...
    'FontSize',             fs, ...
    'TickLabelInterpreter', 'latex', ...
    'YTick',                [1 5 10 15 20]);

ylabel(ax2, '$\mathrm{Cell}$', ...
    'Interpreter', 'latex', ...
    'FontSize',    fs);

xlabel(ax2, '$\mathrm{Time}\;[\mathrm{s}]$', ...
    'Interpreter', 'latex', ...
    'FontSize',    fs);

xlim(ax2, [0 1800]);
ylim(ax2, [0.5 Ns + 0.5]);
box(ax2, 'on');

linkaxes([ax1 ax2], 'x');

% Set shared x-axis ticks after linking
set(ax2, 'XTick', 0:300:1800);

% --- Export ------------------------------------------------------------------
drawnow;

set(fig, ...
    'Units',             'centimeters', ...
    'Position',          [2 2 paperWidth paperHeight], ...
    'PaperUnits',        'centimeters', ...
    'PaperSize',         [paperWidth paperHeight], ...
    'PaperPosition',     [0 0 paperWidth paperHeight], ...
    'PaperPositionMode', 'manual', ...
    'Color',             'w');

outFile = fullfile(figuresDir, ...
    'figure_engagement_heatmap');

exportgraphics(fig, [outFile '.pdf'], ...
    'ContentType',     'vector', ...
    'BackgroundColor', 'white');

exportgraphics(fig, [outFile '.eps'], ...
    'ContentType',     'vector', ...
    'BackgroundColor', 'white');

fprintf('Saved figure_engagement_heatmap.eps and .pdf\n');