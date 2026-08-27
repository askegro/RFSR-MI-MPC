% figure_power_solveclass.m
%
% Two-tile figure for Section VI-A.1:
%   Upper tile : Requested pack power |P_req| [W] with amber burst shading
%                (requested pack power over the cycle)
%   Lower tile : Solve-class sequence (Opt. / TO+Inc. / Fail) colour-coded stems
%                (baseline solve class per active step)
%
% DATA SOURCE
%   Results_nominal_wltc_*.mat
%   (run mainSimulationRunners/run_nominal_wltc.m first)
%
% OUTPUT
%   results/Figures/figure_power_solveclass.{eps,pdf}

clc;
close all;

% IEEEtran figure formatting: LaTeX interpreter, 9 pt
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

L     = data.Results.A.log;
Tstep = data.cfg.Tstep;

% -------------------------------------------------------------------------
% Signals
% -------------------------------------------------------------------------
n_steps = numel(L.p_pack_req);
t       = (0:n_steps-1) * Tstep;  % Time axis [s]

active  = ~logical(L.rest_skip);
opt     =  logical(L.optimality_proven) & active;
inc     =  logical(L.incumbent_timeout) & active;
hf      =  logical(L.hard_fail)         & active;
noncert = inc | hf;

p_req = L.p_pack_req;  % Requested pack power [W]

% Burst regions for upper-tile shading
[burst_starts, burst_ends] = get_bursts(noncert);

% -------------------------------------------------------------------------
% Style
% -------------------------------------------------------------------------
% IEEEtran one-column figure dimensions:
% 3.375 in = 8.573 cm
paperWidth  = 8.573;  % cm
paperHeight = 8.0;    % cm

fs     = 9;
lw_sig = 0.6;

col_burst = [1.00 0.84 0.60];  % Amber: burst shading
col_P     = [0.20 0.20 0.20];  % Dark grey: power trace
clr_opt   = [0.00 0.60 0.30];  % Green: optimal
clr_inc   = [0.90 0.65 0.00];  % Amber: incumbent timeout
clr_hf    = [0.80 0.10 0.10];  % Red: hard fail

% -------------------------------------------------------------------------
% Figure
% -------------------------------------------------------------------------
fig = figure( ...
    'Color',    'w', ...
    'Units',    'centimeters', ...
    'Position', [2 2 paperWidth paperHeight]);

tl = tiledlayout( ...
    fig, 2, 1, ...
    'TileSpacing', 'compact', ...
    'Padding',     'compact');

% --- Upper tile: requested power with burst shading ----------------------
ax_p = nexttile(tl);
hold(ax_p, 'on');

plot( ...
    ax_p, t, p_req, '-', ...
    'Color',     col_P, ...
    'LineWidth', lw_sig);

ylabel( ...
    ax_p, ...
    '$p_{\mathrm{req}}\;[\mathrm{W}]$', ...
    'Interpreter', 'latex', ...
    'FontSize',   fs);

format_ax(ax_p, fs, t);
add_burst_shading( ...
    ax_p, t, burst_starts, burst_ends, col_burst);

% Suppress x-axis tick labels on the upper tile
set(ax_p, 'XTickLabel', {});

% --- Lower tile: solve-class stems ---------------------------------------
ax_c = nexttile(tl);
hold(ax_c, 'on');

stem( ...
    ax_c, t(opt), ones(1, sum(opt)), ...
    'Marker',      'none', ...
    'Color',       clr_opt, ...
    'LineWidth',   0.5, ...
    'DisplayName', '$\mathrm{Opt.}$');

stem( ...
    ax_c, t(inc), ones(1, sum(inc)), ...
    'Marker',      'none', ...
    'Color',       clr_inc, ...
    'LineWidth',   0.8, ...
    'DisplayName', '$\mathrm{TO{+}Inc.}$');

stem( ...
    ax_c, t(hf), ones(1, sum(hf)), ...
    'Marker',      'none', ...
    'Color',       clr_hf, ...
    'LineWidth',   0.8, ...
    'DisplayName', '$\mathrm{Fail}$');

xlabel( ...
    ax_c, ...
    '$\mathrm{Time}\;[\mathrm{s}]$', ...
    'Interpreter', 'latex', ...
    'FontSize',   fs);

ylabel( ...
    ax_c, ...
    '$\mathrm{Solve\ class}$', ...
    'Interpreter', 'latex', ...
    'FontSize',   fs);

xlim(ax_c, [0 1800]);
ylim(ax_c, [0 1.3]);

set( ...
    ax_c, ...
    'YTick',                [], ...
    'FontSize',             fs, ...
    'TickLabelInterpreter', 'latex', ...
    'GridAlpha',            0.15, ...
    'GridLineStyle',        ':');

lg = legend( ...
    ax_c, ...
    'Location',    'best', ...
    'Interpreter', 'latex', ...
    'FontSize',    fs, ...
    'NumColumns',  3);

lg.ItemTokenSize = [10 18];

grid(ax_c, 'on');
box(ax_c, 'on');

linkaxes([ax_p ax_c], 'x');

set(ax_c, 'XTick', 0:300:1800);
xlim(ax_p, [0 1800]);

% -------------------------------------------------------------------------
% Export
% -------------------------------------------------------------------------
drawnow;

set( ...
    fig, ...
    'Units',             'centimeters', ...
    'Position',          [2 2 paperWidth paperHeight], ...
    'PaperUnits',        'centimeters', ...
    'PaperSize',         [paperWidth paperHeight], ...
    'PaperPosition',     [0 0 paperWidth paperHeight], ...
    'PaperPositionMode', 'manual', ...
    'Color',             'w');

outFile = fullfile( ...
    figuresDir, ...
    'figure_power_solveclass');

exportgraphics( ...
    fig, ...
    [outFile '.pdf'], ...
    'ContentType',     'vector', ...
    'BackgroundColor', 'white');

exportgraphics( ...
    fig, ...
    [outFile '.eps'], ...
    'ContentType',     'vector', ...
    'BackgroundColor', 'white');

fprintf( ...
    'Saved figure_power_solveclass.eps and .pdf\n');


%% =========================================================================
% Local functions
%% =========================================================================

function add_burst_shading(ax, t, starts, ends_, col)
%ADD_BURST_SHADING Shade burst regions with amber patches behind the data.

    if isempty(starts)
        return;
    end

    yl   = ylim(ax);
    dy   = yl(2) - yl(1);
    y_lo = yl(1) - 0.05 * dy;
    y_hi = yl(2) + 0.05 * dy;

    for i = 1:numel(starts)
        si = starts(i);
        ei = min(ends_(i), numel(t));

        patch( ...
            ax, ...
            [t(si) t(ei) t(ei) t(si)], ...
            [y_lo y_lo y_hi y_hi], ...
            col, ...
            'FaceAlpha',       0.40, ...
            'EdgeColor',       'none', ...
            'HandleVisibility', 'off');
    end

    % Move patches behind signal lines.
    ch       = ax.Children;
    is_patch = arrayfun( ...
        @(h) isa(h, 'matlab.graphics.primitive.Patch'), ch);

    ax.Children = [ch(~is_patch); ch(is_patch)];

    ylim(ax, yl);
end


function format_ax(ax, fs, t)
%FORMAT_AX Apply common axis formatting.

    grid(ax, 'on');
    box(ax, 'on');

    set( ...
        ax, ...
        'FontSize',             fs, ...
        'TickLabelInterpreter', 'latex', ...
        'GridAlpha',            0.18, ...
        'GridLineStyle',        ':', ...
        'XTick',                0:300:t(end));

    xlim(ax, [0 t(end)]);
end


function [starts, ends_] = get_bursts(mask)
%GET_BURSTS Return the start and end indices of contiguous true regions.

    mask = logical(mask(:)');
    d    = diff([false mask false]);

    starts = find(d == 1);
    ends_  = find(d == -1) - 1;
end