%% HeartbeatDetector.m
% Semi-automated R-wave detection and interactive review for ECG tag data
%
% Version 4.0
%
% Created by: Cameron Nemeth, with Claude
% Email: ncnemeth@hawaii.edu
%
% Last modified: 31-10-2026
%
%
% HOW TO USE
%   1. Keep this script directly in the top-level project folder (e.g.
%      D:\HeartRate): the folder that contains the deployment folders. Not
%      in a subfolder, and not inside a deployment folder. The project
%      folder can have any name and be anywhere.
%
%   2. Put each deployment in its own folder next to the script (any name),
%      with a "Data" folder inside it and a "Raw" folder inside that. The
%      script creates "Processed". The Raw folder holds the raw data text
%      file (any name), which can be:
%        - a LabChart "Export As Text" file with the block header, or
%        - a file with one row of column names above the numbers, or
%        - a file of numbers only (no column names).
%      Columns can be separated by tabs, commas or spaces, and time must be
%      in seconds. Other files (e.g. the LabChart file itself) can sit in
%      Raw too; you choose which file to use in the setup window.
%
%   3. Press Run (F5). A popup asks what to do:
%
%      NEW DEPLOYMENT - each window waits for you before moving on:
%        a. Setup window: choose the deployment folder, raw data file,
%           species and columns (check them against the preview), plus
%           notes. Continue.
%        b. Overview: type the tag on/off times (press Enter) or click Set
%           on plot, then click the plot. Continue.
%        c. Filter tuning: adjust the filter while looking at the data.
%           Apply & continue.
%        d. Detection tuning: adjust the detection until the red circles
%           sit on the R waves. Apply & continue.
%        e. Review: edit the beats (instructions above the plot and in the
%           REVIEW section below). Save & keep working / Save & finish session.
%
%      EXISTING DEPLOYMENT (continue a first pass, or review):
%        Pick the deployment folder. Every setting is read from its
%        settings sheet and the review opens directly (Continue review or
%        View only). To view the data with a different filter, use the
%        Change filter... button in the review.
%
%   4. When finished, these files will exist:
%        Processed\<deployment>_Heartbeats.csv
%            Every beat: Time (s, original recording time), Certainty
%            (1 = certain, 2 = possible), NoPriorBeat (1 = no known beat
%            before it), RRInterval (s), HeartRate (bpm), Segment (1, 2,
%            3, ...: a new segment starts at each beat with NoPriorBeat = 1)
%            and Comment. RRInterval and HeartRate are empty (NaN) where
%            NoPriorBeat = 1.
%        Processed\<deployment>_Settings.csv
%            The settings used for this deployment. Existing deployments
%            are reopened with these.
%        Raw\<deployment>_imported_time_depth_ecg.mat
%            Time, ECG, depth and acceleration, copied from the raw file so
%            later runs load in seconds. Safe to delete; it is rebuilt
%            automatically.
%        HeartRate_Reference_Settings.csv (in the project folder)
%            The settings used for every deployment (sorted by species),
%            for comparison; also the source of starting values and of the
%            "species" ranges shown in the tuning windows.
%        HeartRate_Progress.csv (in the project folder)
%            Who processed and reviewed each deployment, when, how far
%            (checkpoint time) and whether each stage is complete, plus a
%            Comments column that keeps every note added (date, name and
%            role first; notes separated by semicolons).
%        HeartRate_Deployment_Information.csv (in the project folder)
%            One row per deployment, refreshed every time the review is
%            saved: tag on/off and duration, numbers of beats, segments and
%            RR intervals, segment lengths, beats per segment, % of the
%            tag-on period with clean ECG, heart rate (mean, median, SD),
%            status (from the progress sheet) and the progress comments.
%
% VALUES IN THIS SCRIPT
%   The FILTERING, AUTOMATIC R-WAVE DETECTION and REVIEW sections start with
%   values (e.g. settings.highPassHz = 1). For a new deployment these are
%   only starting values, used when no deployment of the same species has
%   been processed yet; they are adjusted in the tuning windows. Existing
%   deployments ignore them. The REVIEW section's personal preferences
%   (window length, snap distance, click tolerance) are defaults only:
%   once changed in the review panel, your own values are used.
%
% All paths are built relative to this script's location, so the whole
% project folder can be moved or shared without changing any code.
%

%% ---- START: NEW OR EXISTING DEPLOYMENT ----------------------------------
% A popup asks what to do:
%   New deployment: a setup window opens to choose the deployment folder,
%     raw data file, species and columns (nothing is typed into the script).
%   Existing deployment (continue a first pass, or review): pick the
%     deployment folder; every recorded setting is read from its settings
%     sheet, and the overview, tuning windows and automatic detection are
%     skipped.
clear; clc; close all;

% How this run starts. This is not a setting: it is not recorded in the
% settings sheets.
%   'ask'      = a popup asks each run (recommended)
%   'new'      = always a new deployment (setup window)
%   'existing' = always an existing deployment (folder picker)
run.mode = 'ask';

% --- The project folder: where this script is saved (checked again in PATHS)
try
    projectDir = fileparts(matlab.desktop.editor.getActiveFilename);   % file open in the Editor
catch
    projectDir = '';
end
if isempty(projectDir), projectDir = pwd; end

% --- New or existing?
if strcmp(run.mode, 'ask')
    modeChoice = questdlg(sprintf(['What would you like to do?\n\n' ...
        'New deployment: a setup window opens to choose the folder, file, ' ...
        'species and columns; you are then guided through each step.\n\n' ...
        'Existing deployment: continue a first pass or review. Pick the ' ...
        'deployment folder; everything is read from its saved files.']), ...
        'Heartbeat Detector', 'New deployment', ...
        'Existing deployment (continue first pass or review)', 'New deployment');
    if isempty(modeChoice)
        error('No option was chosen. Run the script again.');
    end
    if startsWith(modeChoice, 'New')
        run.mode = 'new';
    else
        run.mode = 'existing';
    end
end
if ~any(strcmp(run.mode, {'new', 'existing'}))
    error('run.mode must be ''ask'', ''new'' or ''existing''.');
end
isExisting = strcmp(run.mode, 'existing');
settings   = struct();                     % filled by the setup window or the settings sheet
sheetVals  = struct();                     % recorded settings (existing deployments only)

if isExisting
    % --- Existing deployment: pick its folder, read its settings sheet
    depDir = uigetdir(projectDir, 'Choose the deployment folder to open');
    if isequal(depDir, 0)
        error('No deployment folder was chosen. Run the script again.');
    end
    [~, depName]  = fileparts(depDir);     % the deployment folder's name
    settingsSheet = fullfile(depDir, 'Data', 'Processed', [depName '_Settings.csv']);
    beatsSheet    = fullfile(depDir, 'Data', 'Processed', [depName '_Heartbeats.csv']);
    if ~isfile(settingsSheet) || ~isfile(beatsSheet)
        error(['"%s" does not have a saved settings sheet and Heartbeats file yet:\n' ...
            '  %s\n  %s\nRun it as a new deployment instead.'], ...
            depName, settingsSheet, beatsSheet);
    end
    sheetVals = readSettingsSheet(settingsSheet);
    settings  = useSheetValues(settings, sheetVals);
    settings.deployment = depName;         % always the folder actually chosen
    fprintf('Existing deployment: %s\nSettings read from: %s\n', depName, settingsSheet);
else
    % --- New deployment: setup window (see setupWindow in LOCAL FUNCTIONS)
    settings = setupWindow(projectDir, fullfile(projectDir, 'HeartRate_Reference_Settings.csv'));
    if isempty(settings)
        error('Setup was cancelled. Run the script again.');
    end
    fprintf('New deployment: %s\nRaw file: %s\nSpecies: %s\n', ...
        settings.deployment, settings.rawFile, settings.species);
end

% Any setting missing (e.g. a sheet from before acceleration was added)
% counts as empty
for f = {'timeChannel', 'depthChannel', 'accelX', 'accelY', 'accelZ', ...
        'sampleRateHz', 'notes', 'tagOnTime', 'tagOffTime'}
    if ~isfield(settings, f{1}), settings.(f{1}) = []; end
end

%% ---- PATHS (no editing needed) --------------------------------------
% Find the project folder (MATLAB's version of R's here()): the folder that
% contains this script and the deployment folders. Some MATLAB versions run
% a temporary copy of the script (e.g. when there are unsaved changes), so a
% few likely places are checked, and the first one that contains the
% deployment folder is used.
candidates = {fileparts(mfilename('fullpath'))};            % where the script is running from
try
    candidates{end + 1} = fileparts(matlab.desktop.editor.getActiveFilename);   % file open in the Editor
catch
end
candidates{end + 1} = pwd;                                  % MATLAB's current folder

rootDir = '';
for c = 1:numel(candidates)
    if ~isempty(candidates{c}) && isfolder(fullfile(candidates{c}, settings.deployment))
        rootDir = candidates{c};
        break
    end
end
if isempty(rootDir)
    error(['Could not find the deployment folder "%s".\nFolders checked:\n  %s\n' ...
        'Make sure the script is saved in the project folder, and that ' ...
        'settings.deployment is spelled exactly like the folder name.'], ...
        settings.deployment, strjoin(candidates(~cellfun('isempty', candidates)), '\n  '));
end
fprintf('Project folder: %s\n', rootDir);

paths.root      = rootDir;
paths.raw       = fullfile(rootDir, settings.deployment, 'Data', 'Raw', settings.rawFile);
paths.processed = fullfile(rootDir, settings.deployment, 'Data', 'Processed');
if ~isfile(paths.raw)
    error('Raw file not found:\n  %s\nCheck settings.deployment and settings.rawFile.', paths.raw);
end
if ~isfolder(paths.processed)
    mkdir(paths.processed);
    fprintf('Created output folder: %s\n', paths.processed);
end

%% ---- TOOLBOX CHECK ---------------------------------------------------
% Filtering and peak detection later on need the Signal Processing Toolbox.
if isempty(ver('signal'))
    warning(['Signal Processing Toolbox is not installed. It will be needed ' ...
        'for filtering and peak detection. Install via Home > Add-Ons.']);
else
    fprintf('Signal Processing Toolbox: found\n');
end

%% ---- IMPORT -------------------------------------------------------------
% Reads time, ECG, depth and acceleration from the raw text file. Three kinds of file are
% recognized automatically:
%   1. LabChart "Export As Text" with the block header: column names come
%      from the ChannelTitle line, and the first (unnamed) column is time,
%      which the script calls 'Time'.
%   2. A file with one row of column names above the numbers
%      (e.g. Time,ECG,Depth). If there are several lines above the numbers,
%      the last one is taken as the column names.
%   3. A file of numbers only (no column names).
% Columns may be separated by tabs, commas or spaces. The columns to use
% come from the setup window (new deployment) or the settings sheet
% (existing deployment), by name or by column number. Time must be in
% seconds. ECG is required; depth is optional (none: the Depth column is
% left empty, NaN, and there is no depth strip). Acceleration is optional
% too: each axis chosen is added to the data as AccX, AccY or AccZ.
% Sampling rate: worked out from the time column (the typical gap between
% consecutive times). If there is no time column, it is the rate entered
% in the setup window, and times are counted from 0 s at the first row.
% The file type, the columns used and the sampling rate are printed in the
% Command Window on every run, so they can be checked.
%
% The first run reads the text file (slow) and saves a .mat copy of just
% the time, depth and ECG columns in the Raw folder, next to the text file
% (<deployment>_imported_time_depth_ecg.mat). Later runs load that copy
% instead (fast). If the text file has been modified since the copy was
% saved (e.g. a re-export), a popup asks whether to re-import it. The copy
% is also rebuilt automatically if the raw file name or any column setting
% changes. To force a fresh import, delete the .mat file in the Raw folder.
cacheFile = fullfile(fileparts(paths.raw), ...                      % the Raw folder
    [settings.deployment '_imported_time_depth_ecg.mat']);

% The column settings for this run, as one line of text, so the saved copy
% can be checked against them
channelKey = sprintf('time=%s | ecg=%s | depth=%s | acc=%s/%s/%s | rate=%s', ...
    settingToText(settings.timeChannel), settingToText(settings.ecgChannel), ...
    settingToText(settings.depthChannel), settingToText(settings.accelX), ...
    settingToText(settings.accelY), settingToText(settings.accelZ), ...
    settingToText(settings.sampleRateHz));

useCache = isfile(cacheFile);              % is there a saved copy?

if useCache
    % If the raw text file was modified after the saved copy was made,
    % ask whether to re-import it.
    rawInfo   = dir(paths.raw);
    cacheInfo = dir(cacheFile);
    if rawInfo.datenum > cacheInfo.datenum
        reimportChoice = questdlg(['The raw data file has changed since it was last ' ...
            'imported. Re-import it?'], ...
            'Newer raw file found', ...
            'Re-import', 'Use saved copy', 'Re-import');
        if strcmp(reimportChoice, 'Re-import')
            useCache = false;
        else
            fprintf('Using saved copy. It may not match the newer raw file.\n');
        end
    end
end

if useCache
    cached = load(cacheFile);
    % Re-read the text file if the saved copy came from a different raw
    % file, or used different column settings, than this run
    if ~isfield(cached, 'rawFile') || ~strcmp(cached.rawFile, settings.rawFile)
        fprintf('Saved copy came from a different raw file. Re-reading text file.\n');
        useCache = false;
    elseif ~isfield(cached, 'channelKey') || ~strcmp(cached.channelKey, channelKey)
        fprintf('Column settings changed since last import. Re-reading text file.\n');
        useCache = false;
    end
end

if useCache
    data       = cached.data;
    fs         = cached.fs;
    importInfo = cached.importInfo;
    fprintf('Loaded saved import: %s\n', cacheFile);
else
    % --- 1-3) The file's layout: header lines, how columns are separated,
    %     and the column names, if any (see readFileLayout in LOCAL FUNCTIONS)
    L = readFileLayout(paths.raw);
    nHeader  = L.nHeader;   sepChar = L.sepChar;   fileSep  = L.fileSep;
    nCols    = L.nCols;     names   = L.names;     interval = L.interval;
    fileType = L.fileType;

    % --- 4) Which columns hold time, ECG and depth (name or number -> number)
    timeIdx  = findColumn(settings.timeChannel,  names, nCols, 'settings.timeChannel');
    ecgIdx   = findColumn(settings.ecgChannel,   names, nCols, 'settings.ecgChannel');
    depthIdx = findColumn(settings.depthChannel, names, nCols, 'settings.depthChannel');
    accAxes  = {'X', 'Y', 'Z'};
    accIdx   = [findColumn(settings.accelX, names, nCols, 'settings.accelX'), ...
        findColumn(settings.accelY, names, nCols, 'settings.accelY'), ...
        findColumn(settings.accelZ, names, nCols, 'settings.accelZ')];   % 0 = axis not used
    if ecgIdx == 0
        error('settings.ecgChannel must be set (a column name or number).');
    end
    if timeIdx == 0 && isempty(settings.sampleRateHz)
        error(['settings.timeChannel is empty (no time column), so ' ...
            'settings.sampleRateHz is needed (e.g. 250).']);
    end

    % --- 5) Build a read format that keeps only the needed columns
    wanted = unique([timeIdx, ecgIdx, depthIdx, accIdx]);   % sorted = order in the file
    wanted = wanted(wanted > 0);                    % 0 = column not used
    fmt = repmat({'%*f'}, 1, nCols);                % %*f = skip this column
    fmt(wanted) = {'%f'};                           % %f  = keep this column
    fmt = [strjoin(fmt, '') '%*[^\n]'];             % ignore any trailing text (comments)

    % --- 6) Read the data
    fprintf('Reading %s (this may take a few minutes)...\n', settings.rawFile);
    if isempty(sepChar)
        sepArgs = {};                               % spaces: MATLAB's default splitting
    else
        sepArgs = {'Delimiter', sepChar};
    end
    fid = fopen(paths.raw, 'r');
    C = textscan(fid, fmt, sepArgs{:}, 'HeaderLines', nHeader, 'ReturnOnError', true);
    reachedEnd = feof(fid);
    fclose(fid);

    if ~reachedEnd
        warning(['Reading stopped before the end of the file. The file may ' ...
            'contain more than one LabChart block, or a line that is not ' ...
            'numbers. Only the part before it was loaded.']);
    end

    % --- 7) Pick out the columns (textscan returns them in file order)
    n = min(cellfun(@numel, C));                    % same length for every column
    getCol = @(col) C{wanted == col}(1:n);
    ecgVals   = getCol(ecgIdx);
    if depthIdx > 0
        depthVals = getCol(depthIdx);
    else
        depthVals = NaN(n, 1);                      % no depth in this file
    end
    accVals = cell(1, 3);                           % acceleration, one cell per axis
    for a = find(accIdx > 0)                        % only the axes in use
        accVals{a} = getCol(accIdx(a));
    end

    % --- 8) Time (s) and sampling rate
    if timeIdx > 0
        timeVals = getCol(timeIdx);
        fs = 1 / median(diff(timeVals));            % typical gap between samples
        rateNote = 'from the time column';
        if ~isempty(settings.sampleRateHz)
            fprintf(['Note: settings.sampleRateHz (%g) is ignored because the ' ...
                'file has a time column.\n'], settings.sampleRateHz);
        end
        if ~isnan(interval) && abs(1 / fs - interval) > 0.01 * interval
            warning(['The time column gives %g Hz, but the LabChart header says ' ...
                '%g Hz. Check the export.'], fs, 1 / interval);
        end
    else
        fs = settings.sampleRateHz;
        timeVals = (0:n - 1)' / fs;                 % 0, 1/fs, 2/fs, ... seconds
        rateNote = 'from settings.sampleRateHz';
    end
    data = table(timeVals, ecgVals, depthVals, 'VariableNames', {'Time', 'ECG', 'Depth'});
    for a = find(accIdx > 0)                        % only the axes in use
        data.(['Acc' accAxes{a}]) = accVals{a};     % new columns AccX, AccY, AccZ
    end
    clear C timeVals ecgVals depthVals accVals

    % --- 9) Summary of what was read (printed now and on every later run)
    accText = 'none';
    if any(accIdx > 0)
        accParts = arrayfun(@(a) describeColumn(['Acc ' accAxes{a}], accIdx(a), names), ...
            find(accIdx > 0), 'UniformOutput', false);
        accText = strjoin(accParts, '  |  ');
    end
    importInfo = sprintf(['File type: %s (columns separated by %s)\n' ...
        'Columns used: %s  |  %s  |  %s\n' ...
        'Acceleration: %s\n' ...
        'Sampling rate: %g Hz (%s)\n'], fileType, fileSep, ...
        describeColumn('Time',  timeIdx,  names), ...
        describeColumn('ECG',   ecgIdx,   names), ...
        describeColumn('Depth', depthIdx, names), accText, fs, rateNote);

    % --- 10) Save a fast-loading copy, recording where it came from
    rawFile = settings.rawFile;
    save(cacheFile, 'data', 'fs', 'channelKey', 'rawFile', 'importInfo', '-v7.3');
    fprintf('Saved import to: %s\n', cacheFile);
end
fprintf('%s', importInfo);                     % file type, columns used, sampling rate

% --- Basic checks
dt = diff(data.Time);
nIrregular = sum(abs(dt - 1/fs) > 0.5/fs);
fprintf('\nSamples: %d | Sampling rate: %g Hz | Duration: %.2f h\n', ...
    height(data), fs, (data.Time(end) - data.Time(1)) / 3600);
fprintf('Irregular time steps: %d\n', nIrregular);
fprintf('NaN values - ECG: %d, Depth: %d\n', sum(isnan(data.ECG)), sum(isnan(data.Depth)));








%% ---- OVERVIEW PLOT AND TAG ON/OFF -----------------------------------------
% NEW deployment: shows the whole recording, in seconds: acceleration and
% depth strips at the top (if chosen) and the raw ECG below. Type the tag
% on/off times in the boxes (press Enter) or click Set on plot and then
% click the plot; recorded times (if processed before) are pre-filled.
% Continue checks both are set and moves on.

% EXISTING deployment: no window; the recorded tag times are used.
% The data are then cropped to the tag-on period. Original recording times
% are kept throughout.

t      = data.Time;
tagOn  = settings.tagOnTime;
tagOff = settings.tagOffTime;

% --- Which thin strips to show above the ECG (top to bottom: acceleration,
% depth). These are reused by the later windows too.
accNames = intersect({'AccX', 'AccY', 'AccZ'}, data.Properties.VariableNames, 'stable');
hasDepth = ~isempty(settings.depthChannel);
nStrips  = ~isempty(accNames) + hasDepth;  % 0, 1 or 2

if isExisting
    % --- Existing deployment: no overview window; the recorded times are used
    if isempty(tagOn) || isempty(tagOff) || tagOn < t(1) || tagOff > t(end) || tagOff <= tagOn
        error(['The tag on/off times in the settings sheet (%s - %s s) do not fit ' ...
            'this recording (%.3f to %.3f s).'], settingToText(tagOn), ...
            settingToText(tagOff), t(1), t(end));
    end
    fprintf('\nUsing tag on/off times from the settings sheet: %.3f - %.3f s\n', tagOn, tagOff);
else
    % --- New deployment: recorded times that do not fit this recording are cleared
    if ~isempty(tagOn) && (tagOn < t(1) || tagOn > t(end))
        fprintf('Recorded tag on time (%.3f s) is outside this recording: cleared.\n', tagOn);
        tagOn = [];
    end
    if ~isempty(tagOff) && (tagOff < t(1) || tagOff > t(end))
        fprintf('Recorded tag off time (%.3f s) is outside this recording: cleared.\n', tagOff);
        tagOff = [];
    end
    if ~isempty(tagOn) && ~isempty(tagOff) && tagOff <= tagOn
        fprintf('Recorded tag off time is not after tag on: both cleared.\n');
        tagOn = [];  tagOff = [];
    end

    % --- Build the figure: strips on top, ECG panel below
    overviewFig = figure('Name', 'Overview', 'NumberTitle', 'off', ...
        'Units', 'normalized', 'Position', [0.05 0.1 0.9 0.8]);
    [stripPos, mainPos] = panelLayout(nStrips, 1, 0.14, 0.94, 0.14, 0.03);
    [stripAx, stripLines, stripSigs] = addStrips(overviewFig, stripPos, accNames, hasDepth, data);
    axECG = axes(overviewFig, 'Position', mainPos(1, :));   % tall ECG panel
    hECG  = plot(axECG, NaN, NaN, 'k');    % raw ECG: black, so the tag lines stand out
    ylabel(axECG, 'ECG');
    xlabel(axECG, 'Time (s)');
    grid(axECG, 'on');

    axAll = [stripAx axECG];               % every panel, top to bottom
    axTop = axAll(1);                      % the title goes on the top panel
    linkaxes(axAll, 'x');                  % zoom/pan all panels together
    setTimeOnlyNavigation(overviewFig, axAll);   % zoom/pan change time only
    for s = 1:numel(stripAx)               % always refit y to the visible traces
        keepYFitted(stripAx(s), stripLines([stripLines.Parent] == stripAx(s)));
    end
    keepYFitted(axECG, hECG);
    set(axAll, 'XLim', [t(1) t(end)]);

    % --- Redraw the traces whenever the visible time range changes
    hOverview    = [stripLines hECG];      % every plotted line
    sigsOverview = [stripSigs, {data.ECG}];   % the matching data columns
    addlistener(axECG, 'XLim', 'PostSet', ...
        @(~, ~) refreshTraces(axECG, hOverview, t, sigsOverview, fs));
    refreshTraces(axECG, hOverview, t, sigsOverview, fs);   % first draw

    % --- Tag on/off: type a time, or click Set on plot; then Continue
    title(axTop, ['Tag on/off: type the times (s) below and press Enter, or click ' ...
        'Set on plot and then click the plot. Zoom/pan to check, then click Continue.']);
    bg = overviewFig.Color;
    uicontrol(overviewFig, 'Style', 'text', 'String', 'Tag on (s):', 'Units', 'normalized', ...
        'Position', [0.03 0.025 0.08 0.035], 'HorizontalAlignment', 'right', ...
        'BackgroundColor', bg, 'FontSize', 10);
    S.hOn = uicontrol(overviewFig, 'Style', 'edit', 'String', settingToText(tagOn), ...
        'Units', 'normalized', 'Position', [0.12 0.025 0.09 0.04], 'FontSize', 10, ...
        'Callback', @(src, ~) tagEdited(overviewFig, 'On', src));
    uicontrol(overviewFig, 'Style', 'pushbutton', 'String', 'Set on plot', ...
        'Units', 'normalized', 'Position', [0.22 0.02 0.10 0.05], ...
        'Callback', @(~, ~) setTagTime(overviewFig, 'On'));
    uicontrol(overviewFig, 'Style', 'text', 'String', 'Tag off (s):', 'Units', 'normalized', ...
        'Position', [0.35 0.025 0.08 0.035], 'HorizontalAlignment', 'right', ...
        'BackgroundColor', bg, 'FontSize', 10);
    S.hOff = uicontrol(overviewFig, 'Style', 'edit', 'String', settingToText(tagOff), ...
        'Units', 'normalized', 'Position', [0.44 0.025 0.09 0.04], 'FontSize', 10, ...
        'Callback', @(src, ~) tagEdited(overviewFig, 'Off', src));
    uicontrol(overviewFig, 'Style', 'pushbutton', 'String', 'Set on plot', ...
        'Units', 'normalized', 'Position', [0.54 0.02 0.10 0.05], ...
        'Callback', @(~, ~) setTagTime(overviewFig, 'Off'));
    uicontrol(overviewFig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.655 0.015 0.135 0.06], 'HorizontalAlignment', 'left', ...
        'BackgroundColor', bg, 'FontSize', 9, 'ForegroundColor', [0.2 0.2 0.6], ...
        'String', {'Typed a time? Press Enter', 'to draw its line.'});
    uicontrol(overviewFig, 'Style', 'pushbutton', 'String', 'Continue', ...
        'Units', 'normalized', 'Position', [0.80 0.02 0.16 0.05], 'FontWeight', 'bold', ...
        'BackgroundColor', [0.2 0.45 0.8], 'ForegroundColor', 'w', ...
        'Callback', @(~, ~) finishTags(overviewFig));

    % --- Store what the buttons need, inside the figure
    S.axTop    = axTop;                    % panel that holds the title
    S.axAll    = axAll;                    % every panel (tag lines go on all)
    S.axECG    = axECG;
    S.t        = t;
    S.fs       = fs;
    S.tagOn    = tagOn;
    S.tagOff   = tagOff;
    S.accepted = false;
    overviewFig.UserData = S;
    drawTagLines(overviewFig);

    uiwait(overviewFig);                   % pause the script until Continue
    if ~isvalid(overviewFig) || ~overviewFig.UserData.accepted
        error('The overview was closed before Continue. Run the script again.');
    end
    tagOn  = overviewFig.UserData.tagOn;
    tagOff = overviewFig.UserData.tagOff;
    fprintf(['\nTag on/off times used: %.3f - %.3f s\n' ...
        '(recorded in the settings sheets when the review window opens)\n'], tagOn, tagOff);
end                                      % (if ~isExisting)

% --- Crop the data to the tag-on period (original times are kept)
keep = data.Time >= tagOn & data.Time <= tagOff;
data = data(keep, :);

fprintf('Cropped to %.3f - %.3f s: %d samples (%.2f h)\n', ...
    tagOn, tagOff, height(data), (tagOff - tagOn) / 3600);







%% ---- FILTERING ------------------------------------------------------------
% Makes a filtered copy of the ECG, used for beat detection and review.
% The raw ECG (data.ECG) is never changed. Band-pass filter from
% highPassHz to lowPassHz, run forward and then backward (filtfilt) so
% filtered peaks stay at the same times as the raw peaks.
%   NEW deployment: the filter tuning window opens. Change a value (press
%     Enter after typing) and the whole deployment is re-filtered and
%     redrawn. Reset returns to the starting values; Apply & continue uses
%     the current values and moves on.
%   EXISTING deployment: the recorded filter is applied; no window.

% ----- FILTER SETTINGS -----
% Starting values for a NEW deployment, used only if neither this deployment
% nor any other deployment of the same species has been processed before
% (otherwise the starting values come from those, as the window says).
% EXISTING deployments ignore these and use the values recorded in their
% settings sheet. The values used are recorded automatically.
%
% High-pass cutoff (Hz): removes slow drift (baseline wander from breathing,
%   body movement, electrode shifts, depth changes). Raising it flattens the
%   baseline more, but too high can shrink wide/slow QRS complexes.
%   Typical: 0.5-5 Hz.
settings.highPassHz = 1;

% Low-pass cutoff (Hz): removes fast jitter. Lowering it smooths more, but
%   too low can blunt sharp R peaks. Must be below half the sampling rate.
%   Typical: 25-50 Hz.
settings.lowPassHz = 40;

% Filter order: how sharply the filter cuts off around the two cutoffs.
%   Higher = sharper, but can add small ripples ("ringing") next to large
%   peaks. Typical: 2-4; 4 unless there is a reason to change it.
settings.filterOrder = 4;

% Invert ECG: true if R waves point DOWNWARD on this tag. A suggestion is
%   shown each run. Only the filtered copy is flipped; the raw ECG never is.
settings.invertECG = false;

% --- Values actually used: recorded (existing) or starting values (new)
filterFields = {'highPassHz', 'lowPassHz', 'filterOrder', 'invertECG'};
if isExisting
    settings = useSheetValues(settings, sheetVals);
else
    [startVals, startSource] = startingValues(settings, filterFields, paths);
    settings = useSheetValues(settings, startVals);
    fprintf('\nFilter starting values from: %s\n', startSource);
end

% --- Report missing values (NaN). The filter cannot run over gaps, so they
% are filled in temporarily, then set back to NaN in the filtered copy.
nNaN = sum(isnan(data.ECG));
fprintf('\nECG missing values (NaN) in tag-on period: %d (%.3f%%)\n', ...
    nNaN, 100 * nNaN / height(data));
if nNaN > 0
    fprintf('  Filled temporarily for filtering; they stay NaN in the filtered copy.\n');
end

% --- Filter: tuning window (new) or straight away (existing)
if isExisting
    [data.ECG_filtered, polarityNote] = filterECG(data.ECG, fs, settings.highPassHz, ...
        settings.lowPassHz, settings.filterOrder, settings.invertECG);
else
    rangeTxt = speciesRanges(settings, filterFields, paths);   % used for this species
    [tuned, data.ECG_filtered, polarityNote] = filterTuningWindow(data, fs, ...
        settings, startSource, accNames, hasDepth, nStrips, rangeTxt);
    settings = useSheetValues(settings, tuned);   % the values chosen in the window
end
fprintf('Polarity check: largest deflections point %s\n', polarityNote);
fprintf('Filtered ECG: %g-%g Hz band-pass, order %d, zero-phase, inverted: %s\n', ...
    settings.highPassHz, settings.lowPassHz, settings.filterOrder, ...
    mat2str(settings.invertECG));






%% ---- AUTOMATIC R-WAVE DETECTION -------------------------------------------
% Finds every upward peak in the filtered ECG, measures how much each one
% stands out from the nearby background (size, steepness, width), and keeps
% those that look like R waves.
%   NEW deployment: the detection tuning window opens. Change a value
%     (press Enter after typing) and detection reruns on the whole
%     deployment; the red circles and counts update. Reset returns to the
%     starting values; Apply & continue uses these beats and moves on.
%   EXISTING deployment: skipped; the beats come from the Heartbeats file.

% ----- DETECTION SETTINGS -----
% Starting values for a NEW deployment (adjust them in the tuning window).
% EXISTING deployments ignore these and use the values recorded in their
% settings sheet. The values used are recorded automatically.

% Stands-out ratio (AMPLITUDE): how many times taller a peak must be than
%   the typical background signal nearby. Raise it if noise bumps get red
%   circles; lower it if small real beats are missed. Typical: 3-20.
settings.minStandOut = 20;

% Steepness ratio (SLOPE): how many times steeper a peak's rise or fall must
%   be than the typical background nearby. R waves are sharp; slower bumps
%   (T waves, movement) are not. Raise it to reject rounded bumps; lower it
%   if real beats are missed. Typical: 3-20.
settings.minSteepness = 3;

% Maximum width (ms): the widest a peak can be and still count as an R wave,
%   measured at half its height above zero (the filtered ECG is centred on
%   zero, so this measures the sharp tip of the R wave). Lower it to reject
%   broad bumps; raise it if real beats are missed for being too wide.
%   Typical: 50-120 ms.
settings.maxWidthMs = 80;

% Noise window (s): how many seconds around each peak are used to judge the
%   "typical background". Shorter adapts faster to noisy patches; longer is
%   steadier. Typical: 3-10 s.
settings.noiseWindowS = 3;

% Maximum heart rate (bpm): two beats can never be closer together than
%   this allows (120 bpm = 0.5 s). If two peaks are closer, only the one
%   that stands out most is kept.
settings.maxHR = 20;


% Oversized-peak filter (removes e.g. surfacing artifacts): a detected beat
%   is removed if its prominence is more than maxRelSize times the median
%   prominence of its neighbouring beats (nNeighbors on each side).
%   Lower maxRelSize to remove more large peaks; raise it if real beats are
%   being removed. Typical: 2-5 times, 3-10 neighbours each side.
settings.maxRelSize = 3;
settings.nNeighbors = 3;


% --- Values actually used, and detection (new deployments only)
detectFields = {'minStandOut', 'minSteepness', 'maxWidthMs', 'noiseWindowS', ...
    'maxHR', 'maxRelSize', 'nNeighbors'};
if isExisting
    settings = useSheetValues(settings, sheetVals);   % recorded values; no detection
else
    [startVals, startSource] = startingValues(settings, detectFields, paths);
    settings = useSheetValues(settings, startVals);
    fprintf('\nDetection starting values from: %s\n', startSource);

    rangeTxt = speciesRanges(settings, detectFields, paths);   % used for this species
    [tuned, beats, cand, nOversized] = detectionTuningWindow(data, fs, settings, ...
        startSource, accNames, hasDepth, nStrips, rangeTxt);
    settings = useSheetValues(settings, tuned);       % the values chosen in the window

    % --- Summary
    fprintf('Candidate peaks: %d | Detected beats: %d\n', height(cand), height(beats));
    fprintf('Removed as oversized (> %gx neighbouring beats, likely surfacing artifacts): %d\n', ...
        settings.maxRelSize, nOversized);
    if height(beats) > 1
        fprintf('Typical heart rate (median gap between detected beats): %.1f bpm\n', ...
            60 / median(diff(beats.Time)));
    end
end







%% ---- REVIEW: EDIT BEATS AND MARK BREAKS -----------------------------------
% Edits are saved to <deployment>_Heartbeats.csv in the Processed folder
% when you click Save & keep working or Save & finish session (bottom right). Save
% every few minutes: unsaved edits are lost if MATLAB closes unexpectedly.
% The CSV can be open in Excel while you work, but close it there before
% saving, or the save is blocked (a warning says so; your edits are kept).
%
% MARKERS
%   Red circle    = certain beat  (Certainty 1)
%   Green circle  = possible beat (Certainty 2; You are ~80% sure that beat is real)
%   Red x         = certain beat with no known beat before it (NoPriorBeat 1).
%                   Its RRInterval and HeartRate are NaN. The next beat
%                   after an x DOES get an RR interval, measured from the x.
%   The first beat of the deployment is always an x (nothing comes before it).
%
% MOUSE AND KEYS
%   Click on empty space        -> add a red circle
%   Shift + click               -> add a green circle
%   Ctrl + click                -> add a red x
%   Click on any marker         -> remove it (any color or shape)
%   Drag / scroll               -> move / zoom in time
%   Shift + drag                -> select a time span (shaded blue band)
%   Delete or Backspace         -> remove every marker in the selected span;
%                                  the first beat AFTER the span becomes an x
%   Esc (or any click)          -> cancel the selection
%   Left / right arrow keys     -> move back / forward by most of a window
%   Z                           -> undo the last edit (repeat to undo more)
%   C (pointer over a marker)   -> add, edit or remove a comment on that beat
%                                  (beats with a comment get a black ring)
%   Save & keep working button  -> save now and carry on (orange = unsaved
%                                  changes, green = everything saved)
%   Save & finish session button -> save, record progress, and close
%   Closing the window (X)      -> asks to save first if there are unsaved changes
%   Panel on the right          -> Min heart rate (gaps longer than 60/min HR s
%                                  always become x's, after every edit), your
%                                  preferences, and Change filter... (view the
%                                  data with a different filter; beats stay put)
%   After typing in the panel, press Enter, then click the plot to use the
%   keyboard shortcuts again.
%   When a saved review opens, a popup shows where an unfinished first pass
%   or review reached, and can go there (60 s on each side).
%   New markers snap to the highest point of the filtered ECG near the click.
%   NOTE: MATLAB treats a RIGHT click the same as Ctrl + click (adds a red x)
%   and a MIDDLE click the same as Shift + click (adds a green circle).

% SAVING
%   Save & keep working saves to <deployment>_Heartbeats.csv in the
%   Processed folder, with columns: Time, Certainty, NoPriorBeat,
%   RRInterval, HeartRate, Segment, Comment. The button is orange while
%   there are unsaved changes and green once everything is saved.
%   Save & finish session saves, asks for progress details (recorded in
%   HeartRate_Progress.csv in the project folder), and closes the window.

% ---- REVIEW SETTINGS ------------------------------------------------------
% minHR, breakFactor and breakNeighbors: values for a NEW deployment.
% EXISTING deployments ignore these and use the values recorded in their
% settings sheet. The personal preferences further down (window length,
% snap distance, click tolerance, marker height) are defaults: values you
% set in the review panel are used instead.

% PRE-PLACED x's: when a review STARTS from the automatic detections, a
%   beat starts as an x if the gap before it is EITHER:
%     - longer than the slowest plausible heart rate allows (minHR), OR
%     - more than breakFactor times the typical gap between nearby beats
%       (median of breakNeighbors gaps on each side). This catches single
%       missed beats.
%
% Minimum heart rate (bpm): any beat whose gap from the previous beat is
%   longer than 60 / minHR seconds is an x (e.g. 3 bpm = gaps over 20 s).
%   Used when a review starts AND after every edit in the review; it only
%   ever adds x's. Set it slightly below the slowest real heart rate you
%   expect, so real slow beats (e.g. deep dives) are not flagged. Can be
%   changed in the review panel (recorded in the settings sheets).

settings.minHR = 3;

% Break factor: how much longer than the typical nearby gap a gap must be to
%   get an x. Example: beats every 1.5 s, factor 1.5 -> any gap over
%   1.5 x 1.5 = 2.25 s gets an x. One missed beat doubles the gap (3.0 s),
%   so it is caught; normal variation (e.g. 1.4-1.7 s) is not.
%   Lower it to catch more missed beats (but more x's on real slowdowns);
%   raise it for fewer x's on real slowdowns (but some missed beats may be
%   missed). Typical: ~ 1.4-2.
settings.breakFactor = 1.5;

% Break neighbours: how many gaps on each side define the "typical gap".
%   Typical: 3-10.
settings.breakNeighbors = 5;

% --- Values actually used: recorded (existing) or starting values (new)
reviewFields = {'minHR', 'breakFactor', 'breakNeighbors'};
if isExisting
    settings = useSheetValues(settings, sheetVals);
else
    [startVals, startSource] = startingValues(settings, reviewFields, paths);
    settings = useSheetValues(settings, startVals);
    fprintf('Review x-placement values from: %s\n', startSource);
end

% Personal preferences: how the review window behaves for you. These are
% defaults only: once you change them in the review panel (Preferences),
% your values are saved for you on this computer and used instead. 

% Review window length (s) when the window first opens. Zoom freely after.
% Really not much of an effect here.
settings.reviewWindowS = 20;

% Snap distance (ms): a new marker is placed on the highest point of the
%   filtered ECG within this distance of your click. Raise it if markers land
%   beside the peak; lower it if they jump to a neighboring bump.
%   Typical: 50-150 ms.
settings.snapMs = 100;

% Click tolerance (pixels): how close a click must be to a marker to count
%   as clicking ON it (which removes it). Raise it if removing markers takes
%   precise aim; lower it if clicks near a marker remove it by accident.
%   Typical: 5-12 px.
settings.clickTolerancePx = 8;


% Marker gap (% of plot height): the space between each peak and its
%   marker, as a percentage of the height of the trace on screen, so it
%   looks the same however far you zoom. Raise it if markers cover the
%   peaks; lower it if they float too far above them. Typical: 2-10.
settings.markerGapPct = 5;


% --- Your saved preferences (set in the review panel) replace the defaults
prefNames = {'reviewWindowS', 'snapMs', 'clickTolerancePx', 'markerGapPct'};
for j = 1:numel(prefNames)
    if ispref('HeartbeatDetector', prefNames{j})
        settings.(prefNames{j}) = getpref('HeartbeatDetector', prefNames{j});
    end
end

% ---- Record the settings used: deployment sheet + reference sheet ---------
% Every setting that can change from deployment to deployment is written to:
%   <deployment>\Data\Processed\<deployment>_Settings.csv   (this deployment)
%   HeartRate_Reference_Settings.csv in the project folder    (all deployments,
%     sorted by Species, then Deployment)
% Tag on/off are the times actually used (from the overview or the sheet).
% If this deployment's sheet already exists and any value differs from this
% run, a popup lists the differences and offers to update the sheets,
% continue without updating (e.g. to try a different filter), or stop
% (e.g. to fix a value that was copied into the script incorrectly).
recNames = {'Species', 'Deployment', 'settings.rawFile', 'settings.tagOnTime', ...
    'settings.tagOffTime', 'settings.timeChannel', 'settings.ecgChannel', ...
    'settings.depthChannel', 'settings.accelX', 'settings.accelY', ...
    'settings.accelZ', 'settings.sampleRateHz', ...
    'settings.highPassHz', 'settings.lowPassHz', 'settings.filterOrder', ...
    'settings.invertECG', 'settings.minStandOut', 'settings.minSteepness', ...
    'settings.maxWidthMs', 'settings.noiseWindowS', 'settings.maxHR', ...
    'settings.maxRelSize', 'settings.nNeighbors', 'settings.minHR', ...
    'settings.breakFactor', 'settings.breakNeighbors', 'Notes'};
recVals  = {settings.species, settings.deployment, settings.rawFile, tagOn, ...
    tagOff, settings.timeChannel, settings.ecgChannel, ...
    settings.depthChannel, settings.accelX, settings.accelY, ...
    settings.accelZ, settings.sampleRateHz, ...
    settings.highPassHz, settings.lowPassHz, settings.filterOrder, ...
    settings.invertECG, settings.minStandOut, settings.minSteepness, ...
    settings.maxWidthMs, settings.noiseWindowS, settings.maxHR, ...
    settings.maxRelSize, settings.nNeighbors, settings.minHR, ...
    settings.breakFactor, settings.breakNeighbors, settings.notes};
recVals  = cellfun(@settingToText, recVals, 'UniformOutput', false);   % all as text

settingsFile  = fullfile(paths.processed, [settings.deployment '_Settings.csv']);
referenceFile = fullfile(paths.root, 'HeartRate_Reference_Settings.csv');

% --- Compare with this deployment's existing sheet, if there is one
recordSettings = true;                     % false = leave both sheets untouched this run
if isfile(settingsFile)
    old       = readcell(settingsFile, 'Delimiter', ',', 'DatetimeType', 'text');   % keep dates as text
    oldHeader = cellfun(@settingToText, old(1, :), 'UniformOutput', false);
    diffs     = {};
    for c = 1:numel(recNames)
        col = find(strcmp(oldHeader, recNames{c}), 1);
        if isempty(col) || size(old, 1) < 2
            oldVal = '(missing)';
        else
            oldVal = settingToText(old{2, col});
        end
        if ~strcmpi(oldVal, recVals{c})                % ignores TRUE vs true
            diffs{end + 1} = sprintf('%s:   sheet = %s,   this run = %s', ...
                recNames{c}, oldVal, recVals{c});        %#ok<AGROW>
        end
    end
    if ~isempty(diffs)
        settingsChoice = questdlg(sprintf(['These settings differ from the saved ' ...
            'settings sheet for %s:\n\n%s\n\n' ...
            'Update sheets: record this run''s settings.\n' ...
            'Continue without updating: use this run''s settings but keep the ' ...
            'saved record unchanged (e.g. to try a different filter).\n' ...
            'Stop: end the run without changing anything.'], settings.deployment, ...
            strjoin(diffs, '\n')), 'Settings differ from saved sheet', ...
            'Update sheets', 'Continue without updating', 'Stop', 'Stop');
        switch settingsChoice
            case 'Update sheets'
                % recordSettings stays true: both sheets are rewritten below
            case 'Continue without updating'
                recordSettings = false;
                fprintf('Continuing WITHOUT updating the settings sheets.\n');
            otherwise                      % 'Stop', or the popup was closed
                error(['Stopped: settings differ from %s\nNothing was changed. Run ' ...
                    'again and choose another option to carry on.'], settingsFile);
        end
    end
end

if recordSettings
    % --- Write this deployment's sheet (header row + one row of values)
    try
        writecell([recNames; recVals], settingsFile);
        fprintf('Settings recorded in: %s\n', settingsFile);
    catch
        warning(['Could not write %s. Is it open in Excel? Close it and run ' ...
            'again to record the settings.'], settingsFile);
    end

    % --- Update the reference sheet: replace or add this deployment's row, then sort
    refRows = cell(0, numel(recNames));
    if isfile(referenceFile)
        ref       = readcell(referenceFile, 'Delimiter', ',', 'DatetimeType', 'text');   % keep dates as text
        ref       = cellfun(@settingToText, ref, 'UniformOutput', false);
        refHeader = ref(1, :);
        for r = 2:size(ref, 1)                         % match columns by name
            row = repmat({''}, 1, numel(recNames));
            for c = 1:numel(recNames)
                col = find(strcmp(refHeader, recNames{c}), 1);
                if ~isempty(col), row{c} = ref{r, col}; end
            end
            refRows(end + 1, :) = row;                 %#ok<AGROW>
        end
    end
    refRows(strcmp(refRows(:, 2), settings.deployment), :) = [];   % drop old row for this deployment
    refRows(end + 1, :) = recVals;                                 % add the current one
    sortKey = cellfun(@(s, d) lower([s char(1) d]), refRows(:, 1), refRows(:, 2), ...
        'UniformOutput', false);                                   % Species, then Deployment
    [~, order] = sort(sortKey);
    refRows = refRows(order, :);
    try
        writecell([recNames; refRows], referenceFile);
        fprintf('Reference sheet updated: %s\n', referenceFile);
    catch
        warning(['Could not write %s. Is it open in Excel? Close it and run ' ...
            'again to update the reference sheet.'], referenceFile);
    end
end                                        % (if recordSettings)

% ---- Starting beats: saved review or automatic detections -----------------
reviewFile = fullfile(paths.processed, [settings.deployment '_Heartbeats.csv']);
viewOnly   = false;
startFresh = true;

if isfile(reviewFile)
    if isExisting                          % existing deployment: no Start over
        reviewChoice = questdlg(sprintf(['Saved beats found:\n%s\n\n' ...
            'Continue the review (edit), or view it only?'], reviewFile), ...
            'Existing deployment', 'Continue review', 'View only', 'Continue review');
    else
        reviewChoice = questdlg(sprintf(['A saved review was found:\n%s\n\n' ...
            'Continue it, view it only, or start over from the automatic detections?'], ...
            reviewFile), 'Saved review found', ...
            'Continue review', 'View only', 'Start over', 'Continue review');
    end
    switch reviewChoice
        case 'Continue review'
            startFresh = false;
        case 'Start over'
            confirmChoice = questdlg(sprintf(['Start over?\n\n%s will be OVERWRITTEN ' ...
                'with the automatic detections.\nAll edits made in the current review ' ...
                'will be lost.'], [settings.deployment '_Heartbeats.csv']), ...
                'Confirm overwrite', 'Yes, overwrite', 'Cancel', 'Cancel');
            if ~strcmp(confirmChoice, 'Yes, overwrite')
                startFresh = false;        % cancelled: continue the saved review
                fprintf('Start over cancelled. Continuing the saved review.\n');
            end
        otherwise                          % 'View only', or the popup was closed
            startFresh = false;
            viewOnly   = true;
    end
end

if startFresh
    bTime    = beats.Time;                 % from the automatic detection
    bCert    = ones(size(bTime));          % all start as certain (red)
    bNoPrior = preplaceBreaks(bTime, settings.minHR, ...
        settings.breakFactor, settings.breakNeighbors);
    bComment = repmat({''}, numel(bTime), 1);   % no comments yet
    fprintf('Starting review from %d automatic detections (%d pre-placed x''s).\n', ...
        numel(bTime), sum(bNoPrior));
else
    opts = detectImportOptions(reviewFile);
    if any(strcmp(opts.VariableNames, 'Comment'))
        opts = setvartype(opts, 'Comment', 'string');   % read comments as text
    end
    saved    = readtable(reviewFile, opts);
    bTime    = saved.Time;
    bCert    = saved.Certainty;
    bNoPrior = saved.NoPriorBeat == 1;
    if any(strcmp(saved.Properties.VariableNames, 'Comment'))
        cm = saved.Comment;
        cm(ismissing(cm)) = "";                         % empty cell = no comment
        bComment = cellstr(cm);
    else
        bComment = repmat({''}, numel(bTime), 1);       % older files: no comments
    end
    fprintf('Loaded saved review (%d beats): %s\n', numel(bTime), reviewFile);
end

% ---- Any beat after a gap longer than minHR allows is an x (adds x's only)
nNewX = 0;
if ~viewOnly
    [bNoPrior, nNewX] = enforceMinHR(bTime, bNoPrior, settings.minHR);
    if nNewX > 0 && ~startFresh
        fprintf('%d beat(s) after gaps over %.3g s were made x''s (min heart rate %g bpm).\n', ...
            nNewX, 60 / settings.minHR, settings.minHR);
    end
end

% ---- Review window: acceleration/depth strips + filtered ECG with markers --
reviewFig  = figure('Name', ['Review: ' settings.deployment], 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);
[stripPos, mainPos] = panelLayout(nStrips, 1, 0.08, 0.87, 0.11, 0.03, 0.78);   % room above for instructions, panel on the right
[rStripAx, rStripLines, rStripSigs] = addStrips(reviewFig, stripPos, accNames, hasDepth, data);
revAxECG = axes(reviewFig, 'Position', mainPos(1, :));

revECG   = plot(revAxECG, NaN, NaN, 'k');
hold(revAxECG, 'on');
revRed   = plot(revAxECG, NaN, NaN, 'o', 'LineStyle', 'none', 'MarkerSize', 7, ...
    'MarkerFaceColor', [0.85 0 0], 'MarkerEdgeColor', [0.85 0 0]);
revGreen = plot(revAxECG, NaN, NaN, 'o', 'LineStyle', 'none', 'MarkerSize', 7, ...
    'MarkerFaceColor', [0 0.6 0], 'MarkerEdgeColor', [0 0.6 0]);
revX     = plot(revAxECG, NaN, NaN, 'x', 'LineStyle', 'none', 'MarkerSize', 11, ...
    'LineWidth', 2, 'Color', [0.85 0 0]);
revRing  = plot(revAxECG, NaN, NaN, 'o', 'LineStyle', 'none', 'MarkerSize', 14, ...
    'LineWidth', 1.5, 'Color', 'k');               % black ring = beat has a comment
hold(revAxECG, 'off');
set([revECG revRed revGreen revX revRing], 'PickableParts', 'none');   % clicks go to the panel itself
revSel = patch(revAxECG, NaN(4, 1), NaN(4, 1), [0.3 0.5 1], ...   % selection band, hidden until used
    'FaceAlpha', 0.2, 'EdgeColor', 'none', 'PickableParts', 'none');

ylabel(revAxECG, 'Filtered ECG');
xlabel(revAxECG, 'Time (s)');
grid(revAxECG, 'on');
revAll = [rStripAx revAxECG];              % every panel, top to bottom
linkaxes(revAll, 'x');
setTimeOnlyNavigation(reviewFig, revAll);
for a = revAll                             % MATLAB's own mouse tools are off here;
    a.Interactions = [];                   % dragging and scrolling are handled below
end
for s = 1:numel(rStripAx)                  % always refit y to the visible traces
    keepYFitted(rStripAx(s), rStripLines([rStripLines.Parent] == rStripAx(s)));
end
keepYFitted(revAxECG, [revECG revRed revGreen revX]);

% --- Everything the mouse/key functions need, stored inside the figure
R.axTop    = revAll(1);                    % top panel: holds the instructions title
R.axECG    = revAxECG;
R.hECG     = revECG;
R.hRed     = revRed;
R.hGreen   = revGreen;
R.hX       = revX;
R.t        = data.Time;
R.ecg      = data.ECG_filtered;
R.fs       = fs;
R.time     = bTime;
R.cert     = bCert;
R.noPrior  = bNoPrior;
R.comment  = bComment;                     % one comment per beat ('' = none)
R.hRing    = revRing;                      % black rings on commented beats
R.undo     = {};                           % previous states, for Z (undo)
R.viewOnly = viewOnly;
R.file     = reviewFile;
R.deployment   = settings.deployment;
R.progressFile = fullfile(paths.root, 'HeartRate_Progress.csv');
R.infoFile     = fullfile(paths.root, 'HeartRate_Deployment_Information.csv');
R.species      = settings.species;
R.tagOn        = tagOn;                    % tag times actually used (typed or clicked)
R.tagOff       = tagOff;
R.snapN    = round(settings.snapMs / 1000 * fs);    % snap distance in samples
R.tolPx    = settings.clickTolerancePx;
R.downPos  = [];
R.downType = '';
R.downXLim = [];
R.downX    = [];                           % time under the pointer when pressed
R.hSel     = revSel;                       % the selection band
R.selRange = [];                           % selected time span [start end], empty if none
R.unsaved  = false;                        % true = edits not yet saved
R.hTraces  = [rStripLines revECG];         % strip lines, then the ECG (last)
R.sigs     = [rStripSigs, {data.ECG_filtered}];   % their data (the ECG can be re-filtered)
R.data     = data;                         % for the Change filter window
R.accNames = accNames;
R.hasDepth = hasDepth;
R.nStrips  = nStrips;
R.filter   = struct('highPassHz', settings.highPassHz, 'lowPassHz', settings.lowPassHz, ...
    'filterOrder', settings.filterOrder, 'invertECG', logical(settings.invertECG));
R.rangeTxt = speciesRanges(settings, filterFields, paths);   % ranges used for this species
R.settingsFile  = settingsFile;            % where a new filter is recorded
R.referenceFile = referenceFile;
R.minHR    = settings.minHR;               % gaps longer than 60/minHR s -> x
rngHR      = speciesRanges(settings, {'minHR'}, paths);
R.minHRRange = rngHR.minHR;                % range used for this species
R.snapMs   = settings.snapMs;              % preferences, shown in the panel
R.windowS  = settings.reviewWindowS;
R.markerPct = settings.markerGapPct;       % marker gap, % of plot height
reviewFig.UserData = R;

% --- Connect the mouse, keys and Save buttons
reviewFig.WindowButtonDownFcn   = @(~, ~) reviewMouseDown(reviewFig);
reviewFig.WindowButtonMotionFcn = @(~, ~) reviewMouseMove(reviewFig);   % drag to move in time
reviewFig.WindowButtonUpFcn     = @(~, ~) reviewMouseUp(reviewFig);
reviewFig.WindowScrollWheelFcn  = @(~, evt) reviewScroll(reviewFig, evt);   % scroll to zoom in time
reviewFig.WindowKeyPressFcn = @(~, evt) reviewKey(reviewFig, evt);
R = reviewFig.UserData;
R.hSave = uicontrol(reviewFig, 'Style', 'pushbutton', 'String', 'Save & keep working', ...
    'Units', 'normalized', 'Position', [0.56 0.005 0.22 0.04], 'FontWeight', 'bold', ...
    'Callback', @(~, ~) saveReview(reviewFig));
R.hFinish = uicontrol(reviewFig, 'Style', 'pushbutton', 'String', 'Save & finish session', ...
    'Units', 'normalized', 'Position', [0.79 0.005 0.18 0.04], 'FontWeight', 'bold', ...
    'BackgroundColor', [0.2 0.45 0.8], 'ForegroundColor', 'w', ...
    'Callback', @(~, ~) finishReview(reviewFig));
reviewFig.UserData = R;
reviewPanel(reviewFig);                    % settings panel on the right
updateSaveButton(reviewFig);

% --- First draw, starting at the beginning of the tag-on period
addlistener(revAxECG, 'XLim', 'PostSet', @(~, ~) reviewRefresh(reviewFig));
set(revAxECG, 'XLim', [data.Time(1), ...
    min(data.Time(end), data.Time(1) + settings.reviewWindowS)]);
if (startFresh || nNewX > 0) && ~viewOnly
    afterEdit(reviewFig);                  % applies the x rules; marks as unsaved
else
    drawReviewMarkers(reviewFig);
end
if ~startFresh
    reviewCheckpointPopup(reviewFig);      % where the last unfinished session reached
end

reviewFig.CloseRequestFcn = @(~, ~) closeReview(reviewFig);   % X: asks to save if needed
uiwait(reviewFig);                         % wait here until the window closes
if isvalid(reviewFig), closeReview(reviewFig); end
if isfile(reviewFile)
    heartbeats = readtable(reviewFile);    % the final datasheet, for later steps
    fprintf('Review closed. %d beats in: %s\n', height(heartbeats), reviewFile);
end




















%% ---- LOCAL FUNCTIONS -------------------------------------------------------
% Helper functions used by the sections above. MATLAB requires these to be
% at the very END of the script, so all new sections go ABOVE this one.


function [tt, yy] = minMaxDecimate(t, y, nPix)
% Reduces a long trace to the min and max of each of ~nPix slices.
% If there are already few enough points, returns them unchanged.
n = numel(t);
if n <= 2 * nPix
    tt = t; yy = y;
    return
end
binSize = floor(n / nPix);
nBins   = floor(n / binSize);
m       = nBins * binSize;
Y  = reshape(y(1:m), binSize, nBins);     % one column per slice
T  = reshape(t(1:m), binSize, nBins);
tt = [T(1, :); T(end, :)];
yy = [min(Y, [], 1); max(Y, [], 1)];
tt = tt(:);
yy = yy(:);
end

function setTagTime(overviewFig, which)
% Set on plot buttons: wait for one click on the plot, snap it to the
% nearest sample, and show it in the matching box. 'which' is 'On' or 'Off'.
S = overviewFig.UserData;
zoom(overviewFig, 'off');                 % turn off zoom/pan so the click registers
pan(overviewFig, 'off');
oldTitle = S.axTop.Title.String;
title(S.axTop, sprintf('Click on the plot to set TAG %s', upper(which)));
[x, ~] = ginput(1);                       % wait for one click
i = round((x - S.t(1)) * S.fs) + 1;       % snap to the nearest sample
i = min(max(i, 1), numel(S.t));
S.(['tag' which]) = S.t(i);               % stores in S.tagOn or S.tagOff
set(S.(['h' which]), 'String', sprintf('%.3f', S.t(i)));   % fill in the box
overviewFig.UserData = S;
drawTagLines(overviewFig);
title(S.axTop, oldTitle);
end

function drawTagLines(overviewFig)
% Draws green (tag on) and red (tag off) vertical lines on every panel.
S = overviewFig.UserData;
delete(findobj(overviewFig, 'Tag', 'tagLine'));   % remove old lines
for ax = S.axAll
    if ~isempty(S.tagOn)
        xline(ax, S.tagOn, '-', 'Tag on', 'Color', [0 0.6 0], ...
            'LineWidth', 1.5, 'Tag', 'tagLine');
    end
    if ~isempty(S.tagOff)
        xline(ax, S.tagOff, '-', 'Tag off', 'Color', [0.8 0 0], ...
            'LineWidth', 1.5, 'Tag', 'tagLine');
    end
end
end

function tagEdited(overviewFig, which, hEdit)
% A tag time was typed in a box: check it and draw its line. An empty box
% clears it; an invalid time puts the previous value back.
S   = overviewFig.UserData;
txt = strtrim(hEdit.String);
v   = str2double(txt);
if isempty(txt)
    S.(['tag' which]) = [];
elseif isnan(v) || v < S.t(1) || v > S.t(end)
    warndlg(sprintf('Tag %s must be a time in seconds between %.3f and %.3f.', ...
        lower(which), S.t(1), S.t(end)), 'Check time', 'modal');
    hEdit.String = settingToText(S.(['tag' which]));   % back to the previous value
    return
else
    S.(['tag' which]) = v;
end
overviewFig.UserData = S;
drawTagLines(overviewFig);
end

function finishTags(overviewFig)
% Continue: checks both tag times are set and in order, then lets the
% script carry on.
S = overviewFig.UserData;
if isempty(S.tagOn) || isempty(S.tagOff)
    warndlg('Please set both Tag on and Tag off before clicking Continue.', 'Missing time');
    return
end
if S.tagOff <= S.tagOn
    warndlg('Tag off must be later than Tag on.', 'Check times');
    return
end
S.accepted = true;
overviewFig.UserData = S;
uiresume(overviewFig);                    % let the script continue
end

function refreshTraces(ax, hLines, t, signals, fs)
% Redraws every panel for the time range currently visible in ax.
% Zoomed out: plots only the min and max of each pixel-wide slice.
% Zoomed in:  plots every sample. Display only - data are not changed.
% hLines:  one plotted line per panel
% signals: the matching data columns, in a cell array {depth, raw, ...}
xl   = ax.XLim;
span = xl(2) - xl(1);
if span > 20
    labelFmt = '%.0f';
elseif span > 2
    labelFmt = '%.1f';
else
    labelFmt = '%.2f';
end
ax.XAxis.Exponent        = 0;              % bottom panel holds the time labels
ax.XAxis.TickLabelFormat = labelFmt;
i1 = max(1, floor((xl(1) - t(1)) * fs) + 1);
i2 = min(numel(t), ceil((xl(2) - t(1)) * fs) + 1);
if i2 <= i1, return; end
pos  = getpixelposition(ax);
nPix = max(100, round(pos(3)));
for k = 1:numel(hLines)
    [tt, yy] = minMaxDecimate(t(i1:i2), signals{k}(i1:i2), nPix);
    set(hLines(k), 'XData', tt, 'YData', yy);
end
for k = 1:numel(hLines)                   % fit each panel to ALL of its lines
    axk = hLines(k).Parent;               % (a panel can hold several, e.g. X/Y/Z)
    fitToVisible(axk, hLines([hLines.Parent] == axk));
end
end

function fitYAxis(ax, y)
% Sets the y-axis of panel ax to fit the values y, with a 5% margin
% above and below, like LabChart's autoscale.
y = y(~isnan(y));                         % ignore missing values
if isempty(y), return; end
lo = min(y);
hi = max(y);
if hi == lo                               % flat line: avoid a zero-height axis
    lo = lo - 1;
    hi = hi + 1;
end
pad = 0.05 * (hi - lo);                   % 5% margin
newLim = [lo - pad, hi + pad];
if any(abs(ax.YLim - newLim) > 1e-9 * max(1, max(abs(newLim))))
    ax.YLim = newLim;                     % only change it if the fit differs
end
end

function setTimeOnlyNavigation(fig, axList)
% Makes zooming and panning change only the time (x) axis. The y-axes are
% then always set by auto-fit, so no peaks get cut off.
z = zoom(fig);  z.Motion = 'horizontal';  % magnifying-glass tool: time only
p = pan(fig);   p.Motion = 'horizontal';  % hand tool: time only
for a = axList
    % Mouse actions that work without picking a tool:
    % drag = pan in time, scroll = zoom in time, hover = data tips
    a.Interactions = [panInteraction('Dimensions', 'x'), ...
        zoomInteraction('Dimensions', 'x'), ...
        dataTipInteraction];
end
end

function keepYFitted(ax, hLines)
% Watches the y-axis of panel ax. If anything else changes it (e.g. MATLAB
% holding the y-axis fixed during a drag), it is refitted straight away
% to everything drawn in hLines (one or more lines/markers).
addlistener(ax, 'YLim', 'PostSet', @(~, ~) fitToVisible(ax, hLines));
end

function fitToVisible(ax, hLines)
% Fits the y-axis of panel ax to the parts of hLines inside the visible
% time range (traces and markers alike).
xl = ax.XLim;
y  = [];
for h = hLines
    inView = h.XData >= xl(1) & h.XData <= xl(2);
    y = [y, h.YData(inView)];             %#ok<AGROW>
end
fitYAxis(ax, y);
end

function refreshDetection(ax, hTraces, hBeats, t, signals, fs)
% Redraws the traces for the visible time range, then fits the ECG panel
% (the last trace) to include the red beat circles.
refreshTraces(ax, hTraces, t, signals, fs);
fitToVisible(ax, [hTraces(end), hBeats]);
end

function noPrior = preplaceBreaks(time, minHR, factor, k)
% Decides which beats START as x's: the first beat, plus any beat whose gap
% from the previous beat is too long (see REVIEW SETTINGS).
n = numel(time);
noPrior = false(n, 1);
if n == 0, return; end
noPrior(1) = true;                         % nothing before the first beat
gaps = diff(time);                         % gaps(j) = gap before beat j+1
for j = 1:numel(gaps)
    nb = [max(1, j - k) : j - 1, j + 1 : min(numel(gaps), j + k)];   % nearby gaps
    typical = median(gaps(nb));            % NaN if there are no neighbours
    if gaps(j) > 60 / minHR || gaps(j) > factor * typical
        noPrior(j + 1) = true;
    end
end
end

function reviewMouseDown(fig)
% Remembers where and how the mouse button was pressed, which time window
% was showing (for dragging), and the time under the pointer (for selecting).
R = fig.UserData;
R.downPos  = get(groot, 'PointerLocation');   % screen position, in pixels
R.downType = fig.SelectionType;               % 'normal' click, 'extend' Shift, 'alt' Ctrl, 'open' double
R.downXLim = R.axECG.XLim;                    % time window at the moment of pressing
cp = R.axECG.CurrentPoint;
R.downX = cp(1, 1);                           % time under the pointer
fig.UserData = R;
end

function reviewMouseUp(fig)
% On release: if the mouse barely moved it was a click (edit); if it moved,
% it was a drag (pan), which is ignored here.
R = fig.UserData;
if isempty(R.downPos), return; end
moved   = norm(get(groot, 'PointerLocation') - R.downPos);
selType = R.downType;
R.downPos = [];
fig.UserData = R;
if moved > 3 || strcmp(selType, 'open'), return; end    % drag/selection or double-click: no edit
if R.viewOnly, return; end                              % view only: no edits
if ~isempty(R.selRange)                                 % a click while a span is selected
    R.selRange = [];                                    % just cancels the selection
    fig.UserData = R;
    reviewTitleAndBand(fig);
    return
end

ax = R.axECG;
cp = ax.CurrentPoint;
xc = cp(1, 1);  yc = cp(1, 2);                          % click position in data units
if xc < ax.XLim(1) || xc > ax.XLim(2) || yc < ax.YLim(1) || yc > ax.YLim(2)
    return                                              % outside the ECG panel
end

R.undo{end + 1} = {R.time, R.cert, R.noPrior, R.comment};   % remember state for undo
if numel(R.undo) > 200, R.undo(1) = []; end

pos = getpixelposition(ax);
tol = R.tolPx * diff(ax.XLim) / pos(3);                 % click tolerance in seconds
[dist, k] = min(abs(R.time - xc));                      % nearest marker
if ~isempty(dist) && dist <= tol
    % --- Clicked ON a marker: remove it
    R.time(k) = [];  R.cert(k) = [];  R.noPrior(k) = [];  R.comment(k) = [];
else
    % --- Clicked on empty space: add a marker at the nearby peak
    i0 = round((xc - R.t(1)) * R.fs) + 1;               % clicked sample
    i1 = max(1, i0 - R.snapN);
    i2 = min(numel(R.t), i0 + R.snapN);
    [~, m] = max(R.ecg(i1:i2));                         % highest point nearby
    newT = R.t(i1 + m - 1);
    if any(abs(R.time - newT) < 0.5 / R.fs)             % a marker is already on that peak
        R.undo(end) = [];
        fig.UserData = R;
        return
    end
    switch selType
        case 'extend', c = 2; np = false;               % Shift+click: green circle
        case 'alt',    c = 1; np = true;                % Ctrl+click: red x
        otherwise,     c = 1; np = false;               % plain click: red circle
    end
    R.time    = [R.time; newT];
    R.cert    = [R.cert; c];
    R.noPrior = [R.noPrior; np];
    R.comment = [R.comment; {''}];                      % new beat: no comment
    [R.time, order] = sort(R.time);                     % keep beats in time order
    R.cert    = R.cert(order);
    R.noPrior = R.noPrior(order);
    R.comment = R.comment(order);
end
fig.UserData = R;
afterEdit(fig);
end

function reviewKey(fig, evt)
% Arrow keys move through time; Z undoes the last edit.
fo = fig.CurrentObject;                    % typing in a panel box: keys belong to the box
if isa(fo, 'matlab.ui.control.UIControl') && strcmp(fo.Style, 'edit'), return; end
R    = fig.UserData;
ax   = R.axECG;
span = diff(ax.XLim);
switch evt.Key
    case 'rightarrow'
        newLim = ax.XLim + 0.8 * span;
    case 'leftarrow'
        newLim = ax.XLim - 0.8 * span;
    case 'z'
        if R.viewOnly || isempty(R.undo), return; end
        [R.time, R.cert, R.noPrior, R.comment] = deal(R.undo{end}{:});   % restore previous state
        R.undo(end) = [];
        fig.UserData = R;
        afterEdit(fig);
        return
    case {'delete', 'backspace'}
        if R.viewOnly || isempty(R.selRange), return; end
        inSel = R.time >= R.selRange(1) & R.time <= R.selRange(2);   % markers in the span
        if any(inSel)
            R.undo{end + 1} = {R.time, R.cert, R.noPrior, R.comment};   % one undo step
            if numel(R.undo) > 200, R.undo(1) = []; end
            R.time(inSel) = [];  R.cert(inSel) = [];  R.noPrior(inSel) = [];
            R.comment(inSel) = [];
            nextBeat = find(R.time > R.selRange(2), 1);              % first beat after the span
            if ~isempty(nextBeat), R.noPrior(nextBeat) = true; end   % becomes an x
        end
        R.selRange = [];
        fig.UserData = R;
        afterEdit(fig);                                              % redraw (button turns orange)
        return
    case 'c'
        editComment(fig);                                    % comment on the beat under the pointer
        return
    case 'escape'
        R.selRange = [];
        fig.UserData = R;
        reviewTitleAndBand(fig);
        return
    otherwise
        return
end
lo = R.t(1);  hi = R.t(end);                            % stay inside the recording
if newLim(1) < lo, newLim = [lo, lo + span]; end
if newLim(2) > hi, newLim = [hi - span, hi]; end
ax.XLim = newLim;
end

function afterEdit(fig)
% Runs after every change: the first beat, and every beat after a gap
% longer than 60/minHR s, is an x; the Save button
% turns orange (unsaved changes), and the markers are redrawn.
R = fig.UserData;
R.noPrior = enforceMinHR(R.time, R.noPrior, R.minHR);   % long gaps -> x
if ~isempty(R.noPrior), R.noPrior(1) = true; end
R.unsaved = true;
fig.UserData = R;
updateSaveButton(fig);
drawReviewMarkers(fig);
end

function ok = saveReview(fig)
% Writes the heartbeat datasheet (CSV). Returns true if it was saved. If
% the file cannot be written (usually because it is open in Excel), a
% warning is shown and the edits stay in the window.
R  = fig.UserData;
ok = false;
if R.viewOnly, return; end
try
    writetable(buildHeartbeatTable(R.time, R.cert, R.noPrior, R.comment), R.file);
catch
    msg = sprintf(['Could not save:\n%s\n\nIs it open in Excel? Close it there, ' ...
        'then click Save again.\nYour edits are kept in the window.'], R.file);
    fprintf(2, '%s\n', msg);               % red text in the Command Window
    warndlg(msg, 'Could not save', 'modal');
    return
end
ok = true;
R.unsaved = false;
fig.UserData = R;
updateSaveButton(fig);
fprintf('Saved %d beats to %s\n', numel(R.time), R.file);
printSegmentSummary(R.time, R.noPrior, R.t(end) - R.t(1));
updateDeploymentInfo(fig);                 % refresh HeartRate_Deployment_Information.csv
end

function closeReview(fig)
% Runs when the window's X is clicked. If there are unsaved changes, asks
% whether to save them first.
R = fig.UserData;
if ~R.viewOnly && R.unsaved
    closeChoice = questdlg('There are unsaved changes. Save them before closing?', ...
        'Unsaved changes', 'Save', 'Close without saving', 'Cancel', 'Save');
    switch closeChoice
        case 'Save'
            if ~saveReview(fig), return; end   % save failed: keep the window open
        case 'Close without saving'
            % unsaved edits are discarded
        otherwise                              % Cancel, or the popup was closed
            return
    end
end
delete(fig);
end

function T = buildHeartbeatTable(time, cert, noPrior, comment)
% The final datasheet: one row per beat.
%   RRInterval = time since the previous beat (s); NaN for x's
%   HeartRate  = 60 / RRInterval (bpm);          NaN for x's
%   Segment    = 1, 2, 3, ...: a new segment starts at every x, so each
%                segment is a stretch of beats with no known gap in it
%   Comment    = the beat's comment (empty if none)
if isempty(time)
    rr  = zeros(0, 1);
    seg = zeros(0, 1);
else
    rr = [NaN; diff(time)];
    rr(noPrior) = NaN;
    np = noPrior(:);
    np(1) = true;                          % the first beat always starts segment 1
    seg = cumsum(np);                      % +1 at every x
end
T = table(time, cert, double(noPrior), rr, 60 ./ rr, seg, comment(:), ...
    'VariableNames', {'Time', 'Certainty', 'NoPriorBeat', 'RRInterval', ...
    'HeartRate', 'Segment', 'Comment'});
end

function drawReviewMarkers(fig)
% Places red circles, green circles and red x's, then updates the title
% and selection band, and refits the y-axis.
R   = fig.UserData;
idx = round((R.time - R.t(1)) * R.fs) + 1;              % sample of each beat
idx = min(max(idx, 1), numel(R.t));
y   = R.ecg(idx) + markerOffset(R);                     % just above the peak
isX     = R.noPrior;
isRed   = ~isX & R.cert == 1;
isGreen = ~isX & R.cert == 2;
set(R.hRed,   'XData', R.time(isRed),   'YData', y(isRed));
set(R.hGreen, 'XData', R.time(isGreen), 'YData', y(isGreen));
set(R.hX,     'XData', R.time(isX),     'YData', y(isX));
hasComment = ~cellfun('isempty', R.comment);            % beats with a comment
set(R.hRing,  'XData', R.time(hasComment), 'YData', y(hasComment));
reviewTitleAndBand(fig);
fitToVisible(R.axECG, [R.hECG R.hRed R.hGreen R.hX]);
end

function reviewMouseMove(fig)
% While the mouse button is held down:
%   Shift + drag -> draws the selection band
%   plain drag   -> moves the window through time
R = fig.UserData;
if isempty(R.downPos), return; end                % button not pressed: do nothing
dxPix = get(groot, 'PointerLocation') - R.downPos;
if abs(dxPix(1)) <= 3, return; end                % tiny movement: still counts as a click

if strcmp(R.downType, 'extend') && ~R.viewOnly
    % --- Shift + drag: selection from where the button was pressed to here
    cp = R.axECG.CurrentPoint;
    R.selRange = sort([R.downX, cp(1, 1)]);
    fig.UserData = R;
    reviewTitleAndBand(fig);
    return
end

% --- Plain drag: move through time
pos    = getpixelposition(R.axECG);               % panel size in pixels
span   = diff(R.downXLim);                        % seconds shown
newLim = R.downXLim - dxPix(1) * span / pos(3);   % pixels moved -> seconds moved
lo = R.t(1);  hi = R.t(end);                      % stay inside the recording
if newLim(1) < lo, newLim = [lo, lo + span]; end
if newLim(2) > hi, newLim = [hi - span, hi]; end
R.axECG.XLim = newLim;
end


function reviewScroll(fig, evt)
% Scroll wheel zooms in time around the mouse pointer, like the other
% windows: scroll up = zoom in, scroll down = zoom out. The y-axis keeps
% auto-fitting.
R  = fig.UserData;
ax = R.axECG;
xl = ax.XLim;
cp = ax.CurrentPoint;
xc = cp(1, 1);                                    % time under the pointer
if xc < xl(1) || xc > xl(2), xc = mean(xl); end   % pointer outside: zoom around the centre
factor = 1.2 ^ evt.VerticalScrollCount;           % each scroll step zooms 20%
newLim = xc + (xl - xc) * factor;                 % point under the pointer stays put
lo = R.t(1);  hi = R.t(end);
span = diff(newLim);
if span < 0.5                                     % closest zoom: 0.5 s on screen
    newLim = xc + [-0.25 0.25];
    span   = 0.5;
end
if span >= hi - lo                                % furthest zoom: the whole recording
    newLim = [lo hi];
else                                              % stay inside the recording
    if newLim(1) < lo, newLim = [lo, lo + span]; end
    if newLim(2) > hi, newLim = [hi - span, hi]; end
end
ax.XLim = newLim;
end


function reviewTitleAndBand(fig)
% Draws the selection band (if any) and updates the instructions and
% counts shown above the plot.
R = fig.UserData;
if isempty(R.selRange)
    set(R.hSel, 'XData', NaN(4, 1), 'YData', NaN(4, 1));          % hide the band
else
    a = R.selRange(1);  b = R.selRange(2);
    set(R.hSel, 'XData', [a; b; b; a], 'YData', [-1e9; -1e9; 1e9; 1e9]);   % full height
end

isX     = R.noPrior;
isRed   = ~isX & R.cert == 1;
isGreen = ~isX & R.cert == 2;
if R.viewOnly
    line1 = '\bfVIEW ONLY\rm - editing is switched off';
    line2 = '\bfDrag / scroll:\rm move / zoom in time   |   \bfLeft / right arrows:\rm move';
else
    line1 = ['\bfClick:\rm add red beat   |   \bfShift+click:\rm add green (possible)   |   ' ...
        '\bfCtrl+click:\rm add red x (no prior beat)   |   \bfClick a marker:\rm remove'];
    line2 = ['\bfDrag / scroll:\rm move / zoom   |   \bfShift+drag:\rm select a span   |   ' ...
        '\bfArrows:\rm move   |   \bfZ:\rm undo   |   \bfC\rm (pointer over a marker): comment'];
end
counts = sprintf('Beats: %d   (red %d   |   green %d   |   x %d)', ...
    numel(R.time), sum(isRed), sum(isGreen), sum(isX));
if ~isempty(R.selRange)
    nSel   = sum(R.time >= R.selRange(1) & R.time <= R.selRange(2));
    counts = [counts sprintf('      >>  %d selected: \\bfDelete\\rm to remove, \\bfEsc\\rm to cancel', nSel)];
end
title(R.axTop, {line1, line2, counts}, 'FontWeight', 'normal');
end

function txt = settingToText(v)
% Turns a setting value into text for the settings sheets, so saved and
% current values can be compared exactly: numbers with up to 10 significant
% digits, true/false as 'true'/'false', and empty or missing values as ''.
% Commas become semicolons so they cannot split a CSV column.
if isempty(v)
    txt = '';
elseif iscell(v)
    txt = settingToText(v{1});
elseif islogical(v)
    txt = mat2str(v(1));
elseif isnumeric(v)
    if isnan(v(1)), txt = ''; else, txt = sprintf('%.10g', v(1)); end
elseif isstring(v)
    if ismissing(v(1)), txt = ''; else, txt = char(v(1)); end
elseif isdatetime(v)                       % a date read from a sheet: keep it as text
    if isnat(v(1)), txt = ''; else, txt = char(v(1), 'yyyy-MM-dd'); end
elseif ischar(v)
    txt = v;
else
    txt = '';                              % e.g. an empty cell read from a CSV
end
txt = strrep(strtrim(txt), ',', ';');
end


function fields = splitFields(line, sepChar)
% Splits one line of the raw file into its fields. sepChar is a tab or a
% comma; empty means "separated by one or more spaces".
if isempty(sepChar)
    fields = regexp(strtrim(line), '\s+', 'split');
else
    fields = strtrim(strsplit(line, sepChar));
end
end

function idx = findColumn(spec, names, nCols, settingName)
% Turns a column setting (a name in quotes, or a column number) into a
% column number. Empty ([] or '') returns 0, meaning "no such column".
if isempty(spec)
    idx = 0;
elseif isnumeric(spec)
    idx = spec(1);
    if idx < 1 || idx > nCols || idx ~= round(idx)
        error('%s = %g, but the file has %d columns.', settingName, idx, nCols);
    end
else
    spec = char(spec);
    if isempty(names)
        error(['%s = ''%s'', but this file has no column names. Use a column ' ...
            'number instead (counting from the left, 1 = first column).'], ...
            settingName, spec);
    end
    idx = find(strcmp(names, spec), 1);
    if isempty(idx)
        list = arrayfun(@(i) sprintf('%d = %s', i, names{i}), 1:numel(names), ...
            'UniformOutput', false);
        error('%s = ''%s'' was not found. Columns in this file:\n  %s', ...
            settingName, spec, strjoin(list, '\n  '));
    end
end
end

function txt = describeColumn(label, idx, names)
% Text such as 'ECG = column 2 (ECG)' for the import summary.
if idx == 0 && strcmp(label, 'Time')
    txt = 'Time = none (built from settings.sampleRateHz)';
elseif idx == 0
    txt = sprintf('%s = none (not in this file)', label);
elseif idx <= numel(names)
    txt = sprintf('%s = column %d (%s)', label, idx, names{idx});
else
    txt = sprintf('%s = column %d', label, idx);
end
end

function printSegmentSummary(time, noPrior, tagOnDuration)
% Prints how the beats split into segments (a segment starts at each x and
% runs to the beat before the next x), and how much of the tag-on period
% the segments cover (from each segment's first beat to its last).
if isempty(time), return; end
np = noPrior(:);
np(1) = true;
seg    = cumsum(np);
segDur = accumarray(seg, time(:), [], @(v) max(v) - min(v));   % seconds per segment
fprintf(['Segments: %d | median length %.1f min | beats cover %.0f%% of ' ...
    'the tag-on period\n'], max(seg), median(segDur) / 60, ...
    100 * sum(segDur) / tagOnDuration);
end


function editComment(fig)
% C key: add, edit or remove the comment on the marker nearest the mouse
% pointer. An empty comment removes it; Cancel changes nothing.
R = fig.UserData;
if R.viewOnly || isempty(R.time), return; end
ax = R.axECG;
cp = ax.CurrentPoint;
xc = cp(1, 1);                                     % time under the pointer
if xc < ax.XLim(1) || xc > ax.XLim(2), return; end
pos = getpixelposition(ax);
tol = 2 * R.tolPx * diff(ax.XLim) / pos(3);        % a little more generous than clicking
[dist, k] = min(abs(R.time - xc));                 % nearest marker
if dist > tol
    fprintf('To comment, hover the pointer over a marker, then press C.\n');
    return
end
answer = inputdlg(sprintf('Comment for the beat at %.3f s (leave empty to remove):', ...
    R.time(k)), 'Beat comment', [1 70], R.comment(k));
if isempty(answer), return; end                    % Cancel: no change
newComment = strtrim(answer{1});
if strcmp(newComment, R.comment{k}), return; end   % unchanged
R.undo{end + 1} = {R.time, R.cert, R.noPrior, R.comment};   % Z can undo it
if numel(R.undo) > 200, R.undo(1) = []; end
R.comment{k} = newComment;
fig.UserData = R;
afterEdit(fig);
end


function updateSaveButton(fig)
% Colours the Save button: orange = unsaved changes, green = all saved.
% In view-only mode there is nothing to save, so only Close is shown.
R = fig.UserData;
if R.viewOnly
    set(R.hSave, 'Visible', 'off');
    set(R.hFinish, 'String', 'Close');
    return
end
if R.unsaved
    set(R.hSave, 'String', 'Save & keep working (unsaved changes)', ...
        'BackgroundColor', [1 0.6 0.2]);
else
    set(R.hSave, 'String', 'Save & keep working (all saved)', ...
        'BackgroundColor', [0.45 0.8 0.45]);
end
end

function finishReview(fig)
% Save & finish session: saves, records progress in HeartRate_Progress.csv, and
% closes the window. If the save fails, the window stays open.
R = fig.UserData;
if R.viewOnly
    delete(fig);
    return
end
if ~saveReview(fig), return; end
logProgress(fig);
updateDeploymentInfo(fig);                 % again, so status and comments are current
delete(fig);
end

function logProgress(fig)
% After Save & finish session: asks who worked on this deployment, how far they got
% and for an optional comment, then records it in HeartRate_Progress.csv in
% the project folder (one row per deployment; first pass and review have
% their own columns). Comments are never overwritten: each new one is added
% to the end of the Comments column as "date name (role): comment", with
% semicolons between comments.
R = fig.UserData;
role = questdlg('Record this session in the progress sheet as:', ...
    'Progress', 'First pass', 'Review', 'Skip', 'First pass');
if ~any(strcmp(role, {'First pass', 'Review'})), return; end   % Skip, or closed

checkpoint = R.axECG.XLim(2);              % right edge of the current view
answer = inputdlg({'Your name:', ...
    'Checkpoint time (s): how far through the deployment you worked', ...
    'Comments (optional):'}, ...
    ['Progress: ' role], [1 60], {'', sprintf('%.0f', checkpoint), ''});
if isempty(answer), return; end            % Cancel: nothing recorded
complete = questdlg(sprintf('Is the %s of this deployment complete?', lower(role)), ...
    'Complete?', 'Yes', 'No', 'No');
if isempty(complete), complete = 'No'; end

cols = {'Deployment', 'ProcessedBy', 'ProcessedDate', 'CheckpointTime', ...
    'FirstPassComplete', 'ReviewedBy', 'ReviewDate', 'ReviewCheckpointTime', ...
    'ReviewComplete', 'Comments'};
dateStr = char(datetime('today', 'Format', 'yyyy-MM-dd'));
vals = cellfun(@settingToText, {answer{1}, dateStr, answer{2}, complete}, ...
    'UniformOutput', false);               % trims spaces; commas -> semicolons

% --- Existing sheet, matched by column name
rows = cell(0, numel(cols));
if isfile(R.progressFile)
    old = readcell(R.progressFile, 'Delimiter', ',', 'DatetimeType', 'text');   % keep dates as text
    old = cellfun(@settingToText, old, 'UniformOutput', false);
    for r = 2:size(old, 1)
        row = repmat({''}, 1, numel(cols));
        for c = 1:numel(cols)
            col = find(strcmp(old(1, :), cols{c}), 1);
            if ~isempty(col), row{c} = old{r, col}; end
        end
        rows(end + 1, :) = row;            %#ok<AGROW>
    end
end

% --- Update this deployment's row (add it if new)
k = find(strcmp(rows(:, 1), R.deployment), 1);
if isempty(k)
    rows(end + 1, :) = repmat({''}, 1, numel(cols));
    k = size(rows, 1);
    rows{k, 1} = R.deployment;
end
if strcmp(role, 'First pass')
    rows(k, 2:5) = vals;                   % ProcessedBy ... FirstPassComplete
else
    rows(k, 6:9) = vals;                   % ReviewedBy ... ReviewComplete
end
newComment = settingToText(answer{3});    % trims spaces; commas -> semicolons
if ~isempty(newComment)
    entry = sprintf('%s %s (%s): %s', dateStr, vals{1}, role, newComment);
    if isempty(rows{k, 10})                % column 10 = Comments
        rows{k, 10} = entry;               % first comment for this deployment
    else
        rows{k, 10} = [rows{k, 10} '; ' entry];   % add to the end, keep the rest
    end
end
[~, order] = sort(lower(rows(:, 1)));      % deployments in alphabetical order
rows = rows(order, :);

% --- Write, with a retry if the sheet is open in Excel
while true
    try
        writecell([cols; rows], R.progressFile);
        fprintf('Progress recorded in: %s\n', R.progressFile);
        return
    catch
        retryChoice = questdlg(sprintf(['Could not write:\n%s\n\nIs it open in ' ...
            'Excel? Close it there, then click Retry.'], R.progressFile), ...
            'Could not save progress', 'Retry', 'Skip', 'Retry');
        if ~strcmp(retryChoice, 'Retry')
            fprintf(2, 'Progress was NOT recorded.\n');
            return
        end
    end
end
end

function [stripPos, mainPos] = panelLayout(nStrips, nMain, bottom, top, stripH, gap, width)
% Works out where each panel goes in a window: nStrips thin strips at the
% top (acceleration, depth) above nMain ECG panels, all the same width.
% Each position is [left bottom width height], as fractions of the window.
%   nStrips : 0, 1 or 2 thin strips (top to bottom: acceleration, depth)
%   nMain   : number of ECG panels below them (1, or 2 in the filter check)
%   bottom  : lowest edge of the bottom panel (room for time labels/buttons)
%   top     : highest edge of the top panel (room for the title above)
%   stripH  : height of a strip when there is only one
%   gap     : space between the strips and the ECG panel(s)
% With one strip, sizes are exactly those used before acceleration was
% added. With two strips, each strip is 80% as tall and the ECG panels are
% a little shorter, so everything fits. With none, ECG fills the space.
left = 0.07;
if nargin < 7, width = 0.9; end            % optional: narrower, to leave room for a panel
stripGap = 0.015;                          % space between two strips
mainGap  = 0.02;                           % space between two ECG panels
if nStrips == 2
    h = 0.8 * stripH;                      % two strips: each a bit thinner
else
    h = stripH;
end

stripPos = zeros(nStrips, 4);
y = top;
for s = 1:nStrips                          % strips, from the top down
    y = y - h;
    stripPos(s, :) = [left y width h];
    y = y - stripGap;
end
if nStrips > 0
    mainTop = y + stripGap - gap;          % below the last strip, plus the gap
else
    mainTop = top;                         % no strips: ECG starts at the top
end

mainH   = (mainTop - bottom - (nMain - 1) * mainGap) / nMain;
mainPos = zeros(nMain, 4);
for m = 1:nMain                            % ECG panels, from the top down
    mainPos(m, :) = [left, mainTop - m * mainH - (m - 1) * mainGap, width, mainH];
end
end


function [stripAx, stripLines, stripSigs] = addStrips(fig, stripPos, accNames, hasDepth, data)
% Creates the thin strips at the top of a window, from the top down:
% acceleration (one coloured line per axis in use) and/or depth. Returns
% the strip panels, their lines and the matching data columns, ready for
% refreshTraces (the lines start empty; refreshTraces fills them).
%   stripPos : strip positions from panelLayout (one row per strip)
%   accNames : acceleration columns in use, e.g. {'AccX','AccY','AccZ'}
%   hasDepth : true if a depth strip should be shown
accColors = struct('AccX', [0.85 0.33 0.10], ...   % X: orange
    'AccY', [0.47 0.67 0.19], ...   % Y: green
    'AccZ', [0.49 0.18 0.56]);      % Z: purple
stripAx    = gobjects(0);
stripLines = gobjects(0);
stripSigs  = {};
s = 0;                                     % strips made so far
if ~isempty(accNames)
    s  = s + 1;
    ax = axes(fig, 'Position', stripPos(s, :));
    hold(ax, 'on');
    labelParts = cell(1, numel(accNames));
    for a = 1:numel(accNames)
        c = accColors.(accNames{a});
        stripLines(end + 1) = plot(ax, NaN, NaN, 'Color', c);   %#ok<AGROW>
        stripSigs{end + 1}  = data.(accNames{a});               %#ok<AGROW>
        labelParts{a} = sprintf('\\color[rgb]{%g %g %g}%s', c, accNames{a}(end));
    end
    hold(ax, 'off');
    ylabel(ax, {'Accel', strjoin(labelParts, ' ')});   % 'X Y Z' in the line colours
    grid(ax, 'on');
    stripAx(end + 1) = ax;
end
if hasDepth
    s  = s + 1;
    ax = axes(fig, 'Position', stripPos(s, :));
    stripLines(end + 1) = plot(ax, NaN, NaN, 'b');
    stripSigs{end + 1}  = data.Depth;
    set(ax, 'YDir', 'reverse');            % deeper = lower on the plot
    ylabel(ax, 'Depth (m)');
    grid(ax, 'on');
    stripAx(end + 1) = ax;
end
set(stripAx, 'XTickLabel', {});            % time labels only on the bottom panel
end


function updateDeploymentInfo(fig)
% Refreshes this deployment's row in HeartRate_Deployment_Information.csv
% (project folder): summary numbers from the beats just saved, plus the
% status and comments from HeartRate_Progress.csv. One row per deployment,
% sorted alphabetically by Deployment. Runs after every successful save.
% If the sheet cannot be written (e.g. it is open in Excel), a warning is
% printed; the heartbeat file itself has already been saved.
R = fig.UserData;

% --- Summary numbers from the beats in the window (= the file just saved)
time   = R.time(:);
cert   = R.cert(:);
np     = logical(R.noPrior(:));
nBeats = numel(time);
if nBeats > 0
    np(1)    = true;                       % the first beat always starts segment 1
    seg      = cumsum(np);                 % segment number of each beat
    segDurS  = accumarray(seg, time, [], @(v) max(v) - min(v));   % seconds per segment
    segBeats = accumarray(seg, 1);         % beats per segment
    rr       = [NaN; diff(time)];
    rr(np)   = NaN;                        % no RR interval for x's
    hr       = 60 ./ rr(~isnan(rr));       % heart rate of each usable interval (bpm)
else
    segDurS = zeros(0, 1);  segBeats = zeros(0, 1);  hr = zeros(0, 1);
end
tagOnDur = R.tagOff - R.tagOn;             % tag-on period (s)
segMin   = segDurS / 60;                   % segment durations in minutes

% --- Status and comments, from this deployment's row in the progress sheet
status   = 'In progress';
comments = '';
if isfile(R.progressFile)
    prog = readcell(R.progressFile, 'Delimiter', ',', 'DatetimeType', 'text');
    prog = cellfun(@settingToText, prog, 'UniformOutput', false);
    hdr  = prog(1, :);
    dCol = find(strcmp(hdr, 'Deployment'), 1);
    r    = [];
    if ~isempty(dCol)
        r = find(strcmp(prog(2:end, dCol), R.deployment), 1) + 1;   % row in the sheet
    end
    if ~isempty(r)
        fpCol  = find(strcmp(hdr, 'FirstPassComplete'), 1);
        revCol = find(strcmp(hdr, 'ReviewComplete'), 1);
        cmCol  = find(strcmp(hdr, 'Comments'), 1);
        if ~isempty(revCol) && strcmpi(prog{r, revCol}, 'Yes')
            status = 'Review complete';
        elseif ~isempty(fpCol) && strcmpi(prog{r, fpCol}, 'Yes')
            status = 'First pass complete';
        end
        if ~isempty(cmCol), comments = prog{r, cmCol}; end
    end
end

% --- This deployment's row (all as text, like the other sheets)
cols = {'Deployment', 'Species', 'Complete', 'TagOnTime_s', 'TagOffTime_s', ...
    'DeploymentDuration_h', 'NumHeartbeats', 'NumCertainBeats', 'NumPossibleBeats', ...
    'NumSegments', 'NumRRIntervals', 'MeanSegmentDuration_min', ...
    'MedianSegmentDuration_min', 'SDSegmentDuration_min', 'MeanBeatsPerSegment', ...
    'MedianBeatsPerSegment', 'SDBeatsPerSegment', 'PercentCleanECG', ...
    'MeanHeartRate_bpm', 'MedianHeartRate_bpm', 'SDHeartRate_bpm', ...
    'LastUpdated', 'Comments'};
vals = {R.deployment, R.species, status, R.tagOn, R.tagOff, ...
    round(tagOnDur / 3600, 3), ...                          % hours
    nBeats, sum(cert == 1), sum(cert == 2), numel(segDurS), numel(hr), ...
    twoDecimals(mean(segMin)), twoDecimals(median(segMin)), twoDecimals(std(segMin)), ...
    twoDecimals(mean(segBeats)), twoDecimals(median(segBeats)), twoDecimals(std(segBeats)), ...
    twoDecimals(100 * sum(segDurS) / tagOnDur), ...         % % of tag-on with clean ECG
    twoDecimals(mean(hr)), twoDecimals(median(hr)), twoDecimals(std(hr)), ...
    char(datetime('today', 'Format', 'yyyy-MM-dd')), comments};
vals = cellfun(@settingToText, vals, 'UniformOutput', false);   % empty/NaN -> ''

% --- Existing sheet, matched by column name; replace or add this row; sort
rows = cell(0, numel(cols));
if isfile(R.infoFile)
    old = readcell(R.infoFile, 'Delimiter', ',', 'DatetimeType', 'text');   % keep dates as text
    old = cellfun(@settingToText, old, 'UniformOutput', false);
    for r = 2:size(old, 1)
        row = repmat({''}, 1, numel(cols));
        for c = 1:numel(cols)
            col = find(strcmp(old(1, :), cols{c}), 1);
            if ~isempty(col), row{c} = old{r, col}; end
        end
        rows(end + 1, :) = row;            %#ok<AGROW>
    end
end
rows(strcmp(rows(:, 1), R.deployment), :) = [];   % drop the old row for this deployment
rows(end + 1, :) = vals;                          % add the current one
[~, order] = sort(lower(rows(:, 1)));             % deployments in alphabetical order
rows = rows(order, :);

try
    writecell([cols; rows], R.infoFile);
    fprintf('Deployment information updated: %s\n', R.infoFile);
catch
    warning(['Could not write %s. Is it open in Excel? Close it; it will be ' ...
        'updated at the next save.'], R.infoFile);
end
end

function txt = twoDecimals(x)
% Number as text with exactly two decimal places (e.g. 1.8 -> '1.80');
% missing values (NaN) become ''.
if isempty(x) || isnan(x)
    txt = '';
else
    txt = sprintf('%.2f', x);
end
end

function [ecgFilt, polarityNote] = filterECG(ecg, fs, highPassHz, lowPassHz, order, invert)
% Band-pass filters the ECG and returns a filtered copy (the input is never
% changed). Runs forward and then backward (filtfilt), so filtered peaks
% stay at the same times as the raw peaks. Missing values (NaN) are filled
% in temporarily for the filter, then set back to NaN.
% Also returns a polarity suggestion (do the biggest deflections point up
% or down?), judged before any inversion. If invert is true, the filtered
% copy is flipped so R waves point up.
nanECG = isnan(ecg);
if any(nanECG)
    ecg = fillmissing(ecg, 'linear');      % the filter cannot run over gaps
end

nyq = fs / 2;                              % highest frequency the data can hold
if highPassHz <= 0 || lowPassHz >= nyq || highPassHz >= lowPassHz
    error('Check filter cutoffs: need 0 < highPassHz < lowPassHz < %g Hz.', nyq);
end
[z, p, k] = butter(order, [highPassHz lowPassHz] / nyq, 'bandpass');
[sos, g]  = zp2sos(z, p, k);               % numerically stable form of the filter
ecgFilt   = filtfilt(sos, g, ecg);         % forward and backward: no time shift
ecgFilt(nanECG) = NaN;                     % put missing values back

% --- Polarity suggestion, from the 0.1% most extreme values each way
vals = sort(ecgFilt(~isnan(ecgFilt)));
hi   = vals(max(1, round(0.999 * numel(vals))));
lo   = vals(max(1, round(0.001 * numel(vals))));
if abs(lo) > 1.2 * abs(hi)
    polarityNote = 'DOWNWARD - consider settings.invertECG = true';
elseif abs(hi) > 1.2 * abs(lo)
    polarityNote = 'UPWARD - settings.invertECG = false';
else
    polarityNote = 'UNCLEAR - check the plot by eye';
end

if invert
    ecgFilt = -ecgFilt;                    % flip the filtered copy only
end
end

function [beats, cand, nOversized] = detectBeats(t, x, fs, settings)
% Automatic R-wave detection on the filtered ECG x (times t, rate fs),
% using the detection values in settings (minStandOut, minSteepness,
% maxWidthMs, noiseWindowS, maxHR, maxRelSize, nNeighbors).
% Returns the detected beats, every candidate peak with its measurements
% (cand), and how many beats were removed as oversized.
if any(isnan(x))
    x = fillmissing(x, 'linear');          % detection cannot run over gaps
end

% 1) Typical background size, second by second: the median of the absolute
%    values, for the signal itself (amplitude) and its rate of change (slope)
dx         = [0; diff(x)] * fs;            % rate of change, units per second
blockLen   = round(fs);                    % 1-second blocks
nBlocks    = floor(numel(x) / blockLen);
nUse       = nBlocks * blockLen;
ampNoise   = median(abs(reshape(x(1:nUse),  blockLen, nBlocks)), 1);
slopeNoise = median(abs(reshape(dx(1:nUse), blockLen, nBlocks)), 1);
nWin       = max(1, round(settings.noiseWindowS));   % window, in 1-s blocks
ampNoise   = movmedian(ampNoise,   nWin);  % smooth over the noise window
slopeNoise = movmedian(slopeNoise, nWin);
blockTime  = t(1) + ((1:nBlocks) - 0.5) * blockLen / fs;   % centre of each block

% 2) Every upward peak, ignoring tiny wiggles (less than half the typical
%    background size)
minProm = 0.5 * median(ampNoise);
[pkHeight, pkIdx, pkWidth, pkProm] = findpeaks(x, 'MinPeakProminence', minProm, ...
    'WidthReference', 'halfheight');       % width at half the peak's height above zero

% 3) Measurements for each candidate
pkTime     = t(pkIdx);
noiseAmp   = interp1(blockTime, ampNoise,   pkTime, 'nearest', 'extrap');
noiseSlope = interp1(blockTime, slopeNoise, pkTime, 'nearest', 'extrap');
halfWin    = max(1, round(settings.maxWidthMs / 2 / 1000 * fs));
win        = min(max(pkIdx + (-halfWin:halfWin), 1), numel(dx));   % samples around each peak
pkSlope    = max(abs(dx(win)), [], 2);     % steepest rise/fall near each peak

cand = table(pkTime, pkIdx, pkHeight, pkProm, ...
    pkProm ./ noiseAmp, pkSlope ./ noiseSlope, pkWidth / fs * 1000, ...
    [NaN; diff(pkTime)], [diff(pkTime); NaN], ...
    'VariableNames', {'Time', 'Index', 'Height', 'Prominence', ...
    'StandOut', 'Steepness', 'WidthMs', 'GapBefore', 'GapAfter'});

% 4) Keep candidates that pass ALL three criteria
pass = cand.StandOut  >= settings.minStandOut & ...
    cand.Steepness >= settings.minSteepness & ...
    cand.WidthMs   <= settings.maxWidthMs;

% 5) Minimum gap: if passing peaks are closer than the maximum heart rate
%    allows, keep the one that stands out most
minGap  = round(60 / settings.maxHR * fs);          % in samples
passIdx = find(pass);
[~, order] = sort(cand.StandOut(passIdx), 'descend');
blocked = false(numel(x), 1);              % samples too close to a kept beat
isBeat  = false(height(cand), 1);
for j = passIdx(order)'
    s = cand.Index(j);
    if ~blocked(s)
        isBeat(j) = true;
        blocked(max(1, s - minGap + 1) : min(numel(x), s + minGap - 1)) = true;
    end
end

% 6) Remove oversized peaks (e.g. surfacing artifacts): compare each beat's
%    prominence with the median prominence of its neighbouring beats
beatRows = find(isBeat);                   % rows of cand that are beats, in time order
prom     = cand.Prominence(beatRows);      % their prominences
nB       = numel(beatRows);                % number of beats so far
k        = settings.nNeighbors;            % neighbours on each side
neighbourMed = NaN(nB, 1);                 % will hold each beat's neighbour median
for b = 1:nB
    nb = [max(1, b - k) : b - 1, b + 1 : min(nB, b + k)];   % neighbours, not itself
    if ~isempty(nb)
        neighbourMed(b) = median(prom(nb));
    end
end
tooBig = prom > settings.maxRelSize * neighbourMed;   % true = oversized
isBeat(beatRows(tooBig)) = false;          % drop them from the beats
nOversized = sum(tooBig);

cand.Oversized = false(height(cand), 1);   % record which candidates were removed
cand.Oversized(beatRows(tooBig)) = true;
cand.IsBeat = isBeat;
beats = cand(isBeat, :);                   % the automatically detected beats
end


function vals = readSettingsSheet(file)
% Reads a <deployment>_Settings.csv sheet into a struct of setting values,
% e.g. vals.highPassHz = 1, vals.invertECG = true, vals.depthChannel = [].
% 'Species', 'Deployment' and 'Notes' become species, deployment and notes.
c    = readcell(file, 'Delimiter', ',', 'DatetimeType', 'text');
vals = struct();
if size(c, 1) < 2, return; end            % header only: nothing recorded
for j = 1:size(c, 2)
    name = settingToText(c{1, j});         % column name, e.g. 'settings.lowPassHz'
    txt  = settingToText(c{2, j});         % its recorded value, as text
    if startsWith(name, 'settings.')
        field = extractAfter(name, 'settings.');
    elseif any(strcmp(name, {'Species', 'Deployment', 'Notes'}))
        field = lower(name);
    else
        continue                           % any other column is ignored
    end
    vals.(field) = textToSetting(txt);
end
end

function v = textToSetting(txt)
% Turns text from a settings sheet back into a setting value:
% '' -> [], 'true'/'false' -> true/false, numbers -> numbers, other -> text.
if isempty(txt)
    v = [];
elseif any(strcmpi(txt, {'true', 'false'}))
    v = strcmpi(txt, 'true');
else
    num = str2double(txt);
    if isnan(num), v = txt; else, v = num; end
end
end

function settings = useSheetValues(settings, sheetVals)
% Existing deployments: overwrites settings with the values recorded in the
% deployment's settings sheet. Settings not in the sheet are left as they
% are. New deployments: sheetVals is empty, so nothing changes.
f = fieldnames(sheetVals);
for j = 1:numel(f)
    settings.(f{j}) = sheetVals.(f{j});
end
end

function L = readFileLayout(rawPath)
% Reads only the top of a raw data file and works out its layout: the
% header lines, how the columns are separated, the column names (if any),
% LabChart's sampling interval (if any), and a preview (20 rows at each of
% 20 points through the file) for the setup window. Used by the setup
% window and IMPORT.

% --- 1) Every line before the first line that starts with a number is a
%     header line; that first numeric line is the first row of data
fid = fopen(rawPath, 'r');
if fid < 0, error('Could not open %s.', rawPath); end
nHeader = 0;  header = {};  firstData = '';
while true
    txt = fgetl(fid);
    if ~ischar(txt), break; end                          % end of file
    if ~isempty(regexp(txt, '^\s*[-+]?\.?\d', 'once'))   % starts with a number
        firstData = txt;
        break
    end
    nHeader = nHeader + 1;
    header{end + 1} = txt;                               %#ok<AGROW>
    if nHeader > 1000                                    % e.g. a binary file
        break
    end
end
fclose(fid);
[~, fname, fext] = fileparts(rawPath);
if isempty(firstData)
    error(['No rows of numbers were found near the top of %s. Is it a text ' ...
        'export (e.g. LabChart "Export As Text")?'], [fname fext]);
end

% --- 2) How the columns are separated (judged from the first data row)
if contains(firstData, char(9))
    sepChar = char(9);  fileSep = 'tabs';
elseif contains(firstData, ',')
    sepChar = ',';      fileSep = 'commas';
else
    sepChar = '';       fileSep = 'spaces';              % one or more spaces
end
dataFields = splitFields(firstData, sepChar);
nCols = find(~cellfun('isempty', dataFields), 1, 'last');   % columns of numbers

% --- 3) Column names, if the file has them
names    = {};
interval = NaN;                                % LabChart's Interval line, if present
if ~isempty(header) && any(startsWith(header, 'ChannelTitle='))
    fileType = 'LabChart export';
    for hh = 1:numel(header)
        if startsWith(header{hh}, 'Interval=')
            tok = regexp(header{hh}, 'Interval=\s*([-+\d\.eE]+)', 'tokens', 'once');
            if ~isempty(tok), interval = str2double(tok{1}); end
        elseif startsWith(header{hh}, 'ChannelTitle=')
            parts  = strtrim(strsplit(header{hh}, char(9)));   % split on tabs
            titles = parts(2:end);
            titles = titles(~cellfun('isempty', titles));
            names  = [{'Time'}, titles];       % LabChart leaves the time column unnamed
        end
    end
    nCols = numel(names);                      % time + one column per channel
elseif nHeader > 0
    fileType = 'row of column names';
    names = strrep(splitFields(header{end}, sepChar), '"', '');   % last header line
    if numel(names) ~= nCols
        warning(['The column-name row has %d names but the data rows have %d ' ...
            'columns, so names may not line up with the right columns. ' ...
            'If so, choose columns by their numbers in the preview.'], numel(names), nCols);
    end
else
    fileType = 'numbers only (no column names)';
end

% --- 4) Preview: 20 consecutive rows at each of 20 points through the file
%     (0%, 5%, ... 95% of the way through). The script jumps straight to
%     each point instead of reading everything, so even huge files take a
%     moment. The first row of each block is labeled with its position.
if isempty(sepChar)
    sepArgs = {};
else
    sepArgs = {'Delimiter', sepChar};
end
fmt = [repmat('%f', 1, nCols) '%*[^\n]'];
fid = fopen(rawPath, 'r');
fseek(fid, 0, 'eof');
fileBytes = ftell(fid);                    % size of the file in bytes
frewind(fid);
for hh = 1:nHeader, fgetl(fid); end        % skip the header lines
dataStart = ftell(fid);                    % where the numbers begin
preview     = zeros(0, nCols);
previewRows = {};
for p = 0:5:95
    fseek(fid, dataStart + round(p / 100 * (fileBytes - dataStart)), 'bof');
    if p > 0, fgetl(fid); end              % skip the partial line landed in
    C = textscan(fid, fmt, 20, sepArgs{:}, 'ReturnOnError', true);
    n = min(cellfun(@numel, C));
    if n == 0, continue; end               % e.g. landed in a non-number line
    block = NaN(n, nCols);
    for j = 1:nCols
        block(:, j) = C{j}(1:n);
    end
    preview     = [preview; block];                                  %#ok<AGROW>
    previewRows = [previewRows, {sprintf('%d%%', p)}, repmat({''}, 1, n - 1)];   %#ok<AGROW>
end
fclose(fid);

L.nHeader     = nHeader;
L.sepChar     = sepChar;
L.fileSep     = fileSep;
L.nCols       = nCols;
L.names       = names;
L.interval    = interval;
L.fileType    = fileType;
L.preview     = preview;
L.previewRows = previewRows;               % row labels: '0%', '', '', ..., '5%', ...
end


function cfg = setupWindow(projectDir, referenceFile)
% NEW deployment: a window for choosing the deployment folder, raw data
% file, species, columns, sampling rate (only if there is no time column)
% and notes, with a preview of rows from throughout the file. Returns them
% with the same names as the settings (cfg.deployment, cfg.rawFile, ...),
% or [] if the window is cancelled or closed.

% --- Species already in the reference sheet, for the dropdown
speciesList = {};
if isfile(referenceFile)
    ref = readcell(referenceFile, 'Delimiter', ',', 'DatetimeType', 'text');
    ref = cellfun(@settingToText, ref, 'UniformOutput', false);
    col = find(strcmp(ref(1, :), 'Species'), 1);
    if ~isempty(col) && size(ref, 1) > 1
        sp = ref(2:end, col);
        sp = sp(~cellfun('isempty', sp));
        [~, iu] = unique(lower(sp));       % one entry per species, ignoring capitals
        speciesList = sort(sp(iu))';
    end
end

% --- The window
fig = figure('Name', 'New deployment: setup', 'NumberTitle', 'off', ...
    'MenuBar', 'none', 'ToolBar', 'none', 'Units', 'normalized', ...
    'Position', [0.15 0.08 0.7 0.84]);
bg  = fig.Color;
mk  = @(style, str, pos, varargin) uicontrol(fig, 'Style', style, 'String', str, ...
    'Units', 'normalized', 'Position', pos, 'FontSize', 10, varargin{:});
lbl = @(str, pos) mk('text', str, pos, 'HorizontalAlignment', 'left', 'BackgroundColor', bg);

mk('text', 'Set up a new deployment', [0.03 0.94 0.9 0.04], 'FontSize', 13, ...
    'FontWeight', 'bold', 'HorizontalAlignment', 'left', 'BackgroundColor', bg);

lbl('Deployment folder:', [0.03 0.885 0.16 0.035]);
h.dep = mk('edit', '(click Browse... to choose)', [0.20 0.89 0.56 0.035], ...
    'Enable', 'inactive', 'HorizontalAlignment', 'left');
mk('pushbutton', 'Browse...', [0.78 0.888 0.12 0.04], 'Callback', @(~, ~) setupBrowse(fig));

lbl('Raw data file:', [0.03 0.835 0.16 0.035]);
h.raw = mk('popupmenu', {' '}, [0.20 0.84 0.56 0.035], 'Callback', @(~, ~) setupRawChanged(fig));

lbl('Species:', [0.03 0.785 0.16 0.035]);
h.speciesPick = mk('popupmenu', [{'(pick an existing species, or type a new one ->)'}, speciesList], ...
    [0.20 0.79 0.33 0.035], 'Callback', @(~, ~) setupSpeciesPicked(fig));
h.speciesEdit = mk('edit', '', [0.55 0.79 0.35 0.035], 'HorizontalAlignment', 'left');

h.info = mk('text', 'Choose the deployment folder to see the columns in its raw data file.', ...
    [0.03 0.735 0.94 0.035], 'HorizontalAlignment', 'left', 'BackgroundColor', bg, ...
    'ForegroundColor', [0.2 0.2 0.6]);

colLabels = {'Time', 'ECG', 'Depth', 'Accel X', 'Accel Y', 'Accel Z'};
colKeys   = {'time', 'ecg', 'depth', 'ax', 'ay', 'az'};
for j = 1:6                                % two rows of three column choices
    r = floor((j - 1) / 3);  c = mod(j - 1, 3);
    y = 0.685 - r * 0.05;
    lbl([colLabels{j} ':'], [0.03 + c * 0.31, y - 0.005, 0.08, 0.035]);
    h.(colKeys{j}) = mk('popupmenu', {'(none)'}, [0.11 + c * 0.31, y, 0.21, 0.035]);
end
h.time.Callback = @(~, ~) setupTimeChanged(fig);

lbl('Sampling rate (Hz):', [0.03 0.58 0.16 0.035]);
h.rate = mk('edit', '', [0.20 0.585 0.10 0.035], 'Enable', 'off');
lbl('only needed if Time = (none); times then start at 0 s', [0.32 0.58 0.6 0.035]);

lbl('Notes (optional):', [0.03 0.53 0.16 0.035]);
h.notes = mk('edit', '', [0.20 0.535 0.70 0.035], 'HorizontalAlignment', 'left');

lbl(['Preview: 20 rows from each of 20 points through the file (0%, 5% ... 95%). ' ...
    'Check that each column holds what you chose above.'], [0.03 0.48 0.94 0.035]);
h.table = uitable(fig, 'Units', 'normalized', 'Position', [0.03 0.09 0.94 0.39], ...
    'RowName', 'numbered', 'FontSize', 9);

mk('pushbutton', 'Cancel', [0.60 0.02 0.15 0.05], 'Callback', @(~, ~) uiresume(fig));
mk('pushbutton', 'Continue', [0.77 0.02 0.20 0.05], 'FontWeight', 'bold', ...
    'BackgroundColor', [0.2 0.45 0.8], 'ForegroundColor', 'w', ...
    'Callback', @(~, ~) setupContinue(fig));

% --- Everything the buttons need, stored inside the window
U.projectDir  = projectDir;
U.speciesList = speciesList;
U.depDir      = '';
U.depName     = '';
U.prefill     = struct();                  % values from the folder's settings sheet, if any
U.usePrefill  = false;                     % true when the chosen file matches that sheet
U.L           = [];                        % layout of the chosen raw file
U.h           = h;
U.result      = [];
fig.UserData  = U;
fig.CloseRequestFcn = @(~, ~) uiresume(fig);   % closing the window = Cancel

uiwait(fig);                               % wait for Continue or Cancel
cfg = [];
if isvalid(fig)
    cfg = fig.UserData.result;             % [] if cancelled
    delete(fig);
end
end


function setupBrowse(fig)
% Browse...: choose the deployment folder, list its raw data files, and
% pre-fill from its settings sheet if it has been processed before.
U = fig.UserData;
d = uigetdir(U.projectDir, 'Choose the deployment folder');
if isequal(d, 0), return; end              % cancelled
[parent, name] = fileparts(d);
if ~strcmpi(fullfile(parent), fullfile(U.projectDir))
    warndlg(sprintf(['The deployment folder must be directly inside the project ' ...
        'folder (the folder this script is saved in):\n%s'], U.projectDir), ...
        'Wrong folder', 'modal');
    return
end
rawDir = fullfile(d, 'Data', 'Raw');
if ~isfolder(rawDir)
    warndlg(sprintf('This folder has no Data\\Raw folder:\n%s', d), 'No Raw folder', 'modal');
    return
end

% --- Files in the Raw folder (text files first; the script's own copy is left out)
f  = dir(rawDir);
fn = {f(~[f.isdir]).name};
fn = fn(~startsWith(fn, '.') & ~endsWith(fn, '_imported_time_depth_ecg.mat'));
if isempty(fn)
    warndlg(sprintf('The Raw folder is empty:\n%s', rawDir), 'No files', 'modal');
    return
end
isText = endsWith(lower(fn), {'.txt', '.csv'});
fn = [sort(fn(isText)), sort(fn(~isText))];

% --- Pre-fill from this deployment's settings sheet, if there is one
U.depDir  = d;
U.depName = name;
U.prefill = struct();
sheet = fullfile(d, 'Data', 'Processed', [name '_Settings.csv']);
if isfile(sheet)
    U.prefill = readSettingsSheet(sheet);
end
U.h.dep.String = name;
k = 1;                                     % first file (a text file, if any)
if isfield(U.prefill, 'rawFile')
    kk = find(strcmp(fn, settingToText(U.prefill.rawFile)), 1);
    if ~isempty(kk), k = kk; end
end
set(U.h.raw, 'String', fn, 'Value', k);
if isfield(U.prefill, 'species') && ~isempty(U.prefill.species)
    U.h.speciesEdit.String = settingToText(U.prefill.species);
end
if isfield(U.prefill, 'notes')
    U.h.notes.String = settingToText(U.prefill.notes);
end
if isfield(U.prefill, 'sampleRateHz')
    U.h.rate.String = settingToText(U.prefill.sampleRateHz);
end
fig.UserData = U;
setupRawChanged(fig);
end


function setupRawChanged(fig)
% A raw data file was chosen: read the top of it, fill in the column lists
% (from the settings sheet if it was recorded with this file, otherwise
% best guesses) and the preview table.
U = fig.UserData;
h = U.h;
files = h.raw.String;
if isempty(U.depDir) || isempty(files), return; end
if ischar(files), files = {files}; end
rawFile   = files{h.raw.Value};
colKeys   = {'time', 'ecg', 'depth', 'ax', 'ay', 'az'};
colFields = {'timeChannel', 'ecgChannel', 'depthChannel', 'accelX', 'accelY', 'accelZ'};

try
    L = readFileLayout(fullfile(U.depDir, 'Data', 'Raw', rawFile));
catch err
    U.L = [];
    fig.UserData = U;
    set(h.info, 'String', ['Cannot read this file: ' err.message], 'ForegroundColor', [0.8 0 0]);
    for j = 1:6, set(h.(colKeys{j}), 'String', {'(none)'}, 'Value', 1); end
    set(h.table, 'Data', [], 'ColumnName', {});
    return
end

% --- One label per column: its name if it has one, otherwise its number
labels = cell(1, L.nCols);
for j = 1:L.nCols
    if j <= numel(L.names) && ~isempty(L.names{j})
        labels{j} = sprintf('%d: %s', j, L.names{j});
    else
        labels{j} = sprintf('Column %d', j);
    end
end

% --- Choices: as recorded (same file), or best guesses
U.usePrefill = isfield(U.prefill, 'rawFile') && ...
    strcmp(settingToText(U.prefill.rawFile), rawFile);
guess = setupGuessColumns(L);
for j = 1:6
    if U.usePrefill && isfield(U.prefill, colFields{j})
        idx = setupColumnIndex(U.prefill.(colFields{j}), L);
    else
        idx = guess(j);
    end
    set(h.(colKeys{j}), 'String', [{'(none)'}, labels], 'Value', idx + 1);
end
set(h.table, 'Data', L.preview, 'ColumnName', labels, 'RowName', L.previewRows);

infoTxt = sprintf('%s, columns separated by %s, %d columns', L.fileType, L.fileSep, L.nCols);
if ~isnan(L.interval)
    infoTxt = sprintf('%s  |  sampling rate in the file header: %g Hz', infoTxt, 1 / L.interval);
end
if U.usePrefill
    infoTxt = [infoTxt '  |  pre-filled from this deployment''s settings sheet'];
end
set(h.info, 'String', infoTxt, 'ForegroundColor', [0.2 0.2 0.6]);
U.L = L;
fig.UserData = U;
setupTimeChanged(fig);
end


function setupTimeChanged(fig)
% The sampling rate box is only used when there is no time column.
h = fig.UserData.h;
if h.time.Value == 1                       % (none)
    set(h.rate, 'Enable', 'on');
else
    set(h.rate, 'Enable', 'off');
end
end


function setupSpeciesPicked(fig)
% Picking an existing species copies it into the species box.
h = fig.UserData.h;
if h.speciesPick.Value > 1
    h.speciesEdit.String = h.speciesPick.String{h.speciesPick.Value};
end
end


function setupContinue(fig)
% Continue: checks the choices, then returns them as the settings.
U = fig.UserData;  h = U.h;  L = U.L;
if isempty(U.depDir)
    warndlg('Choose the deployment folder first (Browse...).', 'Setup', 'modal');
    return
end
if isempty(L)
    warndlg('Choose a raw data file that the script can read.', 'Setup', 'modal');
    return
end
species = strtrim(h.speciesEdit.String);
if isempty(species)
    warndlg('Enter the species (pick an existing one, or type a new one).', 'Setup', 'modal');
    return
end
k = find(strcmpi(U.speciesList, species), 1);
if ~isempty(k), species = U.speciesList{k}; end   % same spelling and capitals as before

sel = [h.time.Value, h.ecg.Value, h.depth.Value, h.ax.Value, h.ay.Value, h.az.Value] - 1;   % 0 = none
if sel(2) == 0
    warndlg('Choose the ECG column.', 'Setup', 'modal');
    return
end
used = sel(sel > 0);
if numel(unique(used)) < numel(used)
    warndlg('The same column is chosen more than once. Each column can only be used once.', ...
        'Setup', 'modal');
    return
end
rate = [];
if sel(1) == 0
    rate = str2double(h.rate.String);
    if isnan(rate) || rate <= 0
        warndlg('Time is (none), so enter the sampling rate in Hz (e.g. 250).', 'Setup', 'modal');
        return
    end
end

% --- Column settings: kept exactly as recorded if unchanged; otherwise
%     the column's name (if the names are clear) or its number
files = h.raw.String;
if ischar(files), files = {files}; end
colFields = {'timeChannel', 'ecgChannel', 'depthChannel', 'accelX', 'accelY', 'accelZ'};
useNames  = ~isempty(L.names) && numel(L.names) == L.nCols && ...
    numel(unique(L.names)) == numel(L.names);
cfg.species    = species;
cfg.deployment = U.depName;
cfg.rawFile    = files{h.raw.Value};
for j = 1:6
    i = sel(j);
    if U.usePrefill && isfield(U.prefill, colFields{j}) && ...
            setupColumnIndex(U.prefill.(colFields{j}), L) == i
        spec = U.prefill.(colFields{j});   % unchanged: exactly as recorded
    elseif i == 0
        spec = [];
    elseif useNames
        spec = L.names{i};
    else
        spec = i;
    end
    cfg.(colFields{j}) = spec;
end
cfg.sampleRateHz = rate;
cfg.notes        = strtrim(h.notes.String);
cfg.tagOnTime    = [];                     % clicked on the overview, unless recorded
cfg.tagOffTime   = [];
if isfield(U.prefill, 'tagOnTime'),  cfg.tagOnTime  = U.prefill.tagOnTime;  end
if isfield(U.prefill, 'tagOffTime'), cfg.tagOffTime = U.prefill.tagOffTime; end

U.result = cfg;
fig.UserData = U;
uiresume(fig);
end


function idx = setupColumnIndex(spec, L)
% Turns a recorded column setting (a name or a number) into a column number
% in this file; 0 if empty or not found.
idx = 0;
if isempty(spec), return; end
if isnumeric(spec)
    if spec(1) >= 1 && spec(1) <= L.nCols && spec(1) == round(spec(1))
        idx = spec(1);
    end
else
    k = find(strcmp(L.names, char(spec)), 1);
    if ~isempty(k) && k <= L.nCols, idx = k; end
end
end


function g = setupGuessColumns(L)
% Best guesses for [time ecg depth accX accY accZ] (0 = none): from the
% column names if the file has them; otherwise time = the first column if
% it rises evenly, and ECG = the first column that is not time.
g  = zeros(1, 6);
nm = lower(L.names);
match = @(pat) find(~cellfun('isempty', regexp(nm, pat, 'once')));
if ~isempty(nm)
    k = match('time');   if ~isempty(k), g(1) = k(1); end
    k = match('ecg');    if ~isempty(k), g(2) = k(1); end
    k = match('depth');  if ~isempty(k), g(3) = k(1); end
    k = match('acc');                      % up to three acceleration columns
    nA = min(3, numel(k));
    g(4:3 + nA) = k(1:nA);
end
if g(1) == 0 && size(L.preview, 1) > 2     % first column rising evenly = time
    d = diff(L.preview(1:min(20, end), 1));     % first block only (consecutive rows)
    if all(d > 0) && max(d) - min(d) < 0.01 * median(d), g(1) = 1; end
end
if g(2) == 0                               % ECG: first column that is not time
    k = find((1:L.nCols) ~= g(1), 1);
    if ~isempty(k), g(2) = k; end
end
g(g > L.nCols) = 0;
end


function [vals, source] = startingValues(settings, fieldList, paths)
% NEW deployments: starting values for the settings in fieldList, from
%   1) this deployment's own settings sheet, if it was processed before;
%   2) otherwise the most recently recorded deployment of the same species
%      (the one whose settings sheet was saved most recently);
%   3) otherwise the values in the script.
% Returns the values and a short description of where they came from.
vals = struct();
for j = 1:numel(fieldList)
    vals.(fieldList{j}) = settings.(fieldList{j});   % script values, by default
end
source = sprintf('the script (no earlier %s deployment)', settings.species);
sv = struct();

own = fullfile(paths.processed, [settings.deployment '_Settings.csv']);
refFile = fullfile(paths.root, 'HeartRate_Reference_Settings.csv');
if isfile(own)
    sv = readSettingsSheet(own);
    source = 'this deployment''s own settings sheet (processed before)';
elseif isfile(refFile)
    ref = readcell(refFile, 'Delimiter', ',', 'DatetimeType', 'text');
    ref = cellfun(@settingToText, ref, 'UniformOutput', false);
    sc  = find(strcmp(ref(1, :), 'Species'), 1);
    dc  = find(strcmp(ref(1, :), 'Deployment'), 1);
    if ~isempty(sc) && ~isempty(dc) && size(ref, 1) > 1
        rows = find(strcmpi(ref(2:end, sc), settings.species)) + 1;   % same species
        best = [];  bestDate = -Inf;
        for r = rows(:)'
            dep = ref{r, dc};
            d = dir(fullfile(paths.root, dep, 'Data', 'Processed', [dep '_Settings.csv']));
            if isempty(d), dn = -1; else, dn = d.datenum; end    % no sheet found: oldest
            if dn > bestDate, bestDate = dn; best = r; end
        end
        if ~isempty(best)
            for j = 1:size(ref, 2)         % that deployment's row, as settings
                if startsWith(ref{1, j}, 'settings.')
                    sv.(extractAfter(ref{1, j}, 'settings.')) = textToSetting(ref{best, j});
                end
            end
            source = sprintf('%s (most recent %s deployment)', ref{best, dc}, settings.species);
        end
    end
end

% --- Use the recorded values where there are any
for j = 1:numel(fieldList)
    f = fieldList{j};
    if isfield(sv, f) && ~isempty(sv.(f))
        vals.(f) = sv.(f);
    end
end
end


function [vals, ecgFilt, polarityNote] = filterTuningWindow(data, fs, settings, ...
    startSource, accNames, hasDepth, nStrips, rangeTxt)
% The filter tuning window, used for new deployments (FILTERING section)
% and by Change filter... in the review. Acceleration/depth strips, raw
% ECG and filtered ECG, with the filter settings in a panel on the right.
% Changing a value (then Enter) re-filters the whole deployment and redraws
% whatever stretch is on screen. Reset returns to the starting values.
% Apply & continue returns the values chosen (vals), the filtered ECG and
% the polarity note. Closing the window raises an error with the ID
% HeartbeatDetector:filterClosed: during a run it stops the script; from
% the review it simply means "no change".
t = data.Time;
fig = figure('Name', 'Filter tuning', 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.03 0.05 0.94 0.85]);
[stripPos, mainPos] = panelLayout(nStrips, 2, 0.08, 0.93, 0.12, 0.02, 0.72);
[sAx, sLines, sSigs] = addStrips(fig, stripPos, accNames, hasDepth, data);
axR = axes(fig, 'Position', mainPos(1, :));    % raw ECG
axF = axes(fig, 'Position', mainPos(2, :));    % filtered ECG
hR  = plot(axR, NaN, NaN, 'Color', [0.8 0 0]); % raw ECG: red
hF  = plot(axF, NaN, NaN, 'k');                % filtered ECG: black
ylabel(axR, 'Raw ECG');
ylabel(axF, 'Filtered ECG');
xlabel(axF, 'Time (s)');
grid(axR, 'on');  grid(axF, 'on');
allAx = [sAx axR axF];                     % every panel, top to bottom
linkaxes(allAx, 'x');
axR.XTickLabel = {};                       % time labels only on the bottom panel
setTimeOnlyNavigation(fig, allAx);
for s = 1:numel(sAx)                       % always refit y to the visible traces
    keepYFitted(sAx(s), sLines([sLines.Parent] == sAx(s)));
end
keepYFitted(axR, hR);
keepYFitted(axF, hF);
set(axF, 'XLim', [t(1) t(end)]);

% --- Settings panel on the right
pnl = uipanel(fig, 'Units', 'normalized', 'Position', [0.81 0.02 0.18 0.95], ...
    'Title', 'Filter settings', 'FontSize', 10, 'FontWeight', 'bold');
pc  = @(style, str, pos, varargin) uicontrol(pnl, 'Style', style, 'String', str, ...
    'Units', 'normalized', 'Position', pos, 'FontSize', 10, varargin{:});
ptx = @(str, pos, varargin) pc('text', str, pos, 'HorizontalAlignment', 'left', varargin{:});
nyq = fs / 2;
grey = [0.35 0.35 0.35];

ptx(sprintf('Starting values from: %s\nAfter typing a value, press Enter.', startSource), ...
    [0.03 0.925 0.94 0.065], 'FontSize', 8, 'ForegroundColor', [0.2 0.2 0.6]);

dHP = 'Removes slow drift (breathing, movement, depth changes). Raise to flatten the baseline; too high shrinks wide QRS.';
tipR = 'Range used in other deployments of the same species (n = number of deployments)';
blue = [0.2 0.2 0.6];
ptx('High-pass (Hz)', [0.05 0.875 0.50 0.03], 'Tooltip', dHP, 'FontSize', 9, 'FontWeight', 'bold');
ptx(rangeTxt.highPassHz, [0.57 0.875 0.41 0.03], 'FontSize', 8, 'ForegroundColor', blue, 'Tooltip', tipR);
h.hp = pc('edit', '', [0.05 0.839 0.38 0.033], 'Tooltip', dHP);
ptx('typical 0.5-5', [0.46 0.837 0.52 0.03], 'FontSize', 9);
ptx(dHP, [0.05 0.778 0.93 0.056], 'FontSize', 8, 'ForegroundColor', grey);

dLP = 'Removes fast jitter. Lower to smooth more; too low blunts sharp R peaks.';
ptx('Low-pass (Hz)', [0.05 0.745 0.50 0.03], 'Tooltip', dLP, 'FontSize', 9, 'FontWeight', 'bold');
ptx(rangeTxt.lowPassHz, [0.57 0.745 0.41 0.03], 'FontSize', 8, 'ForegroundColor', blue, 'Tooltip', tipR);
h.lp = pc('edit', '', [0.05 0.709 0.38 0.033], 'Tooltip', dLP);
ptx(sprintf('typical 25-50 (< %g)', nyq), [0.46 0.707 0.52 0.03], 'FontSize', 9);
ptx(dLP, [0.05 0.648 0.93 0.056], 'FontSize', 8, 'ForegroundColor', grey);

dOrd = 'How sharply the filter cuts off. Higher is sharper but can add ripples ("ringing") beside big peaks.';
ptx('Order', [0.05 0.615 0.50 0.03], 'Tooltip', dOrd, 'FontSize', 9, 'FontWeight', 'bold');
ptx(rangeTxt.filterOrder, [0.57 0.615 0.41 0.03], 'FontSize', 8, 'ForegroundColor', blue, 'Tooltip', tipR);
h.order = pc('edit', '', [0.05 0.579 0.38 0.033], 'Tooltip', dOrd);
ptx('typical 2-4', [0.46 0.577 0.52 0.03], 'FontSize', 9);
ptx(dOrd, [0.05 0.518 0.93 0.056], 'FontSize', 8, 'ForegroundColor', grey);

dInv = 'Flips the filtered ECG so R waves point up. Tick it if they point down (see the polarity check below).';
h.inv = pc('checkbox', 'Invert (R waves point down)', [0.05 0.47 0.90 0.04], 'Tooltip', dInv);
ptx(dInv, [0.05 0.41 0.93 0.056], 'FontSize', 8, 'ForegroundColor', grey);

h.polarity = ptx('', [0.05 0.28 0.90 0.11], 'FontSize', 9);
pc('pushbutton', 'Reset to starting values', [0.05 0.065 0.90 0.045], ...
    'Callback', @(~, ~) filterTuneRun(fig, fig.UserData.start));
pc('pushbutton', 'Apply & continue', [0.05 0.01 0.90 0.05], 'FontWeight', 'bold', ...
    'BackgroundColor', [0.2 0.45 0.8], 'ForegroundColor', 'w', ...
    'Callback', @(~, ~) filterTuneApply(fig));
set([h.hp h.lp h.order h.inv], 'Callback', @(~, ~) filterTuneUpdate(fig));

% --- Everything the callbacks need, stored inside the window
F.t        = t;
F.fs       = fs;
F.raw      = data.ECG;
F.axF      = axF;
F.axTop    = allAx(1);
F.hLines   = [sLines hR hF];               % strip lines, raw, filtered (last)
F.sigs     = [sSigs, {data.ECG, []}];      % filtered ECG is filled in below
F.start    = struct('highPassHz', settings.highPassHz, 'lowPassHz', settings.lowPassHz, ...
    'filterOrder', settings.filterOrder, 'invertECG', logical(settings.invertECG));
F.vals     = F.start;
F.polarity = '';
F.h        = h;
F.accepted = false;
fig.UserData = F;
fig.CloseRequestFcn = @(~, ~) uiresume(fig);   % closing = stop (see below)
addlistener(axF, 'XLim', 'PostSet', @(~, ~) filterTuneRefresh(fig));

filterTuneRun(fig, F.start);               % first filter and draw
uiwait(fig);                               % wait for Apply & continue
if ~isvalid(fig) || ~fig.UserData.accepted
    if isvalid(fig), delete(fig); end
    error('HeartbeatDetector:filterClosed', ...
        'The filter tuning window was closed before Apply & continue. Run the script again.');
end
F = fig.UserData;
vals         = F.vals;
ecgFilt      = F.sigs{end};
polarityNote = F.polarity;
delete(fig);
end


function ok = filterTuneRun(fig, v)
% Filters the whole ECG with the values in v and redraws. If the values
% are not valid, shows a message, changes nothing and returns false.
F   = fig.UserData;
nyq = F.fs / 2;
ok  = false;
if ~(v.highPassHz > 0 && v.highPassHz < v.lowPassHz && v.lowPassHz < nyq)   % NaN fails too
    warndlg(sprintf(['Need 0 < high-pass < low-pass < %g Hz (half the ' ...
        'sampling rate).'], nyq), 'Check filter values', 'modal');
    return
end
if ~(v.filterOrder >= 1 && v.filterOrder <= 10 && v.filterOrder == round(v.filterOrder))
    warndlg('Order must be a whole number from 1 to 10 (typical 2-4).', ...
        'Check filter values', 'modal');
    return
end
title(F.axTop, 'Filtering... (a few seconds)', 'Color', [0.8 0.4 0]);
drawnow;
[ecgF, pol] = filterECG(F.raw, F.fs, v.highPassHz, v.lowPassHz, v.filterOrder, v.invertECG);
F.sigs{end} = ecgF;
F.vals      = v;
F.polarity  = pol;
fig.UserData = F;

filterTuneShow(F.h, v);                    % boxes show the values in use
pol = strrep(pol, 'consider settings.invertECG = true', 'consider ticking Invert');
pol = strrep(pol, 'settings.invertECG = false', 'leave Invert unticked');
set(F.h.polarity, 'String', sprintf('Polarity check (before Invert): largest deflections point %s', pol));
desc = sprintf('%g-%g Hz, order %d, inverted: %s', v.highPassHz, v.lowPassHz, ...
    v.filterOrder, mat2str(v.invertECG));
title(F.axTop, ['Filter tuning: ' desc], 'Color', [0 0.45 0]);
filterTuneRefresh(fig);
ok = true;
end


function filterTuneUpdate(fig)
% A value was changed in the panel: re-filter with the new values, or put
% the last good values back if they are not valid.
F = fig.UserData;
v.highPassHz  = str2double(F.h.hp.String);
v.lowPassHz   = str2double(F.h.lp.String);
v.filterOrder = str2double(F.h.order.String);
v.invertECG   = logical(F.h.inv.Value);
if isequal(v, F.vals), return; end         % nothing actually changed
if ~filterTuneRun(fig, v)
    filterTuneShow(F.h, F.vals);
end
end


function filterTuneShow(h, v)
% Shows the values in v in the panel's boxes.
set(h.hp,    'String', sprintf('%g', v.highPassHz));
set(h.lp,    'String', sprintf('%g', v.lowPassHz));
set(h.order, 'String', sprintf('%g', v.filterOrder));
set(h.inv,   'Value', v.invertECG);
end


function filterTuneRefresh(fig)
% Redraws every panel for the stretch on screen, with the current filter.
if ~isvalid(fig), return; end
F = fig.UserData;
if isempty(F.sigs{end}), return; end       % not filtered yet
refreshTraces(F.axF, F.hLines, F.t, F.sigs, F.fs);
end


function filterTuneApply(fig)
% Apply & continue: keep the current values and let the script carry on.
F = fig.UserData;
F.accepted = true;
fig.UserData = F;
uiresume(fig);
end


function [vals, beats, cand, nOversized] = detectionTuningWindow(data, fs, settings, ...
    startSource, accNames, hasDepth, nStrips, rangeTxt)
% NEW deployments: the detection tuning window. Acceleration/depth strips
% and the filtered ECG with red circles on the detected beats, with the
% detection settings in a panel on the right. Changing a value (then Enter)
% reruns detection on the whole deployment and redraws. Reset returns to
% the starting values. Apply & continue returns the values chosen (vals)
% and their detection results. Closing the window stops the script.
t = data.Time;
fig = figure('Name', 'Detection tuning', 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.03 0.05 0.94 0.85]);
[stripPos, mainPos] = panelLayout(nStrips, 1, 0.08, 0.93, 0.11, 0.03, 0.72);
[sAx, sLines, sSigs] = addStrips(fig, stripPos, accNames, hasDepth, data);
axE = axes(fig, 'Position', mainPos(1, :));    % filtered ECG
hE  = plot(axE, NaN, NaN, 'k');
hold(axE, 'on');
hB  = plot(axE, NaN, NaN, 'o', 'LineStyle', 'none', 'MarkerSize', 6, ...
    'MarkerFaceColor', [0.85 0 0], 'MarkerEdgeColor', [0.85 0 0]);   % red circles
hold(axE, 'off');
ylabel(axE, 'Filtered ECG');
xlabel(axE, 'Time (s)');
grid(axE, 'on');
allAx = [sAx axE];                         % every panel, top to bottom
linkaxes(allAx, 'x');
setTimeOnlyNavigation(fig, allAx);
for s = 1:numel(sAx)                       % always refit y to the visible traces
    keepYFitted(sAx(s), sLines([sLines.Parent] == sAx(s)));
end
keepYFitted(axE, [hE hB]);                 % fit the trace AND the circles
set(axE, 'XLim', [t(1) t(end)]);

% --- Settings panel on the right: one box per detection value
spec = { ...                               % field, label, typical range, description
    'minStandOut',  'Stands-out ratio',                'typical 3-30', ...
    'Times taller than the background (typical level between beats). Raise: fewer noise bumps; lower: catches small beats.';
    'minSteepness', 'Steepness ratio',                 'typical 3-20', ...
    'Times steeper its rise/fall must be than the background. Raise to reject rounded bumps (T waves, movement).';
    'maxWidthMs',   'Max width (ms)',                  'typical 50-120', ...
    'Widest a peak can be (at half its height) and still count. Lower to reject broad bumps; raise for wide QRS.';
    'noiseWindowS', 'Noise window (s)',                'typical 3-10', ...
    'Seconds used to measure the background (typical level between beats). Shorter adapts faster to noisy patches.';
    'maxHR',        'Max heart rate (bpm)',            'approx. upper limit', ...
    'Beats can never be closer than this allows (60/bpm s). If two peaks are closer, only the biggest is kept.';
    'maxRelSize',   'Oversized size (x)',              'typical 2-5', ...
    'A beat this many times bigger than its neighbours is removed (e.g. surfacing). Lower removes more.';
    'nNeighbors',   'Neighbours each side',            'typical 3-10', ...
    'How many beats on each side it is compared with, for the oversized check above.'};
pnl = uipanel(fig, 'Units', 'normalized', 'Position', [0.81 0.02 0.18 0.95], ...
    'Title', 'Detection settings', 'FontSize', 10, 'FontWeight', 'bold');
pc  = @(style, str, pos, varargin) uicontrol(pnl, 'Style', style, 'String', str, ...
    'Units', 'normalized', 'Position', pos, 'FontSize', 10, varargin{:});
ptx = @(str, pos, varargin) pc('text', str, pos, 'HorizontalAlignment', 'left', varargin{:});

ptx(sprintf('Starting values from: %s\nAfter typing a value, press Enter.', startSource), ...
    [0.03 0.925 0.94 0.065], 'FontSize', 8, 'ForegroundColor', [0.2 0.2 0.6]);
for k = 1:size(spec, 1)
    y = 0.885 - (k - 1) * 0.112;           % name; box + typical range; description
    ptx(spec{k, 2}, [0.05 y 0.50 0.03], 'Tooltip', spec{k, 4}, 'FontSize', 9, 'FontWeight', 'bold');
    ptx(rangeTxt.(spec{k, 1}), [0.57 y 0.41 0.03], 'FontSize', 8, ...
        'ForegroundColor', [0.2 0.2 0.6], 'Tooltip', ...
        'Range used in other deployments of the same species (n = number of deployments)');
    h.(spec{k, 1}) = pc('edit', '', [0.05 y - 0.036 0.38 0.033], 'Tooltip', spec{k, 4}, ...
        'Callback', @(~, ~) detectTuneUpdate(fig));
    ptx(spec{k, 3}, [0.46 y - 0.038 0.52 0.03], 'FontSize', 9);
    ptx(spec{k, 4}, [0.05 y - 0.094 0.93 0.056], 'FontSize', 8, 'ForegroundColor', [0.35 0.35 0.35]);
end
pc('pushbutton', 'Reset to starting values', [0.05 0.065 0.90 0.045], ...
    'Callback', @(~, ~) detectTuneRun(fig, fig.UserData.start));
pc('pushbutton', 'Apply & continue', [0.05 0.01 0.90 0.05], 'FontWeight', 'bold', ...
    'BackgroundColor', [0.2 0.45 0.8], 'ForegroundColor', 'w', ...
    'Callback', @(~, ~) detectTuneApply(fig));

% --- Everything the callbacks need, stored inside the window
start = struct();
for k = 1:size(spec, 1)
    start.(spec{k, 1}) = settings.(spec{k, 1});
end
D.t          = t;
D.fs         = fs;
D.x          = data.ECG_filtered;
D.axE        = axE;
D.axTop      = allAx(1);
D.hLines     = [sLines hE];                % strip lines, then the ECG (last)
D.hB         = hB;
D.sigs       = [sSigs, {data.ECG_filtered}];
D.fields     = spec(:, 1)';
D.start      = start;
D.vals       = start;
D.beats      = [];
D.cand       = [];
D.nOversized = 0;
D.h          = h;
D.accepted   = false;
fig.UserData = D;
fig.CloseRequestFcn = @(~, ~) uiresume(fig);   % closing = stop (see below)
addlistener(axE, 'XLim', 'PostSet', @(~, ~) detectTuneRefresh(fig));

detectTuneRun(fig, start);                 % first detection and draw
uiwait(fig);                               % wait for Apply & continue
if ~isvalid(fig) || ~fig.UserData.accepted
    if isvalid(fig), delete(fig); end
    error('The detection tuning window was closed before Apply & continue. Run the script again.');
end
D = fig.UserData;
vals       = D.vals;
beats      = D.beats;
cand       = D.cand;
nOversized = D.nOversized;
delete(fig);
end


function ok = detectTuneRun(fig, v)
% Runs detection on the whole deployment with the values in v and redraws.
% If a value is not valid, shows a message, changes nothing, returns false.
D  = fig.UserData;
ok = false;
vv = cellfun(@(f) v.(f), D.fields);        % all values, in panel order
if any(~isfinite(vv)) || any(vv <= 0) || v.nNeighbors ~= round(v.nNeighbors)
    warndlg(['Every value must be a number above 0, and "neighbours each ' ...
        'side" a whole number.'], 'Check detection values', 'modal');
    return
end
title(D.axTop, 'Detecting... (a few seconds)', 'Color', [0.8 0.4 0]);
drawnow;
[beats, cand, nOv] = detectBeats(D.t, D.x, D.fs, v);

% --- Red circles, just above each peak
if isempty(beats)
    offset = 0;
else
    offset = 0.15 * median(beats.Prominence);
end
set(D.hB, 'XData', beats.Time, 'YData', beats.Height + offset);

D.vals = v;  D.beats = beats;  D.cand = cand;  D.nOversized = nOv;
fig.UserData = D;
for k = 1:numel(D.fields)                  % boxes show the values in use
    set(D.h.(D.fields{k}), 'String', sprintf('%g', v.(D.fields{k})));
end
hrTxt = 'n/a';
if height(beats) > 1
    hrTxt = sprintf('%.1f bpm', 60 / median(diff(beats.Time)));
end
title(D.axTop, {sprintf(['Detected beats: %d   |   candidate peaks: %d   |   ' ...
    'removed as oversized: %d   |   typical heart rate: %s'], ...
    height(beats), height(cand), nOv, hrTxt), ...
    sprintf(['stands-out >= %g, steepness >= %g, width <= %g ms, noise window %g s, ' ...
    'max HR %g bpm, oversized > %gx (%g each side)'], v.minStandOut, v.minSteepness, ...
    v.maxWidthMs, v.noiseWindowS, v.maxHR, v.maxRelSize, v.nNeighbors)}, ...
    'Color', [0 0.45 0]);
detectTuneRefresh(fig);
ok = true;
end


function detectTuneUpdate(fig)
% A value was changed in the panel: rerun detection with the new values,
% or put the last good values back if they are not valid.
D = fig.UserData;
v = struct();
for k = 1:numel(D.fields)
    v.(D.fields{k}) = str2double(D.h.(D.fields{k}).String);
end
if isequal(v, D.vals), return; end         % nothing actually changed
if ~detectTuneRun(fig, v)
    for k = 1:numel(D.fields)              % put the last good values back
        set(D.h.(D.fields{k}), 'String', sprintf('%g', D.vals.(D.fields{k})));
    end
end
end


function detectTuneRefresh(fig)
% Redraws every panel for the stretch on screen, including the circles.
if ~isvalid(fig), return; end
D = fig.UserData;
refreshDetection(D.axE, D.hLines, D.hB, D.t, D.sigs, D.fs);
end


function detectTuneApply(fig)
% Apply & continue: keep the current values and beats; let the script carry on.
D = fig.UserData;
D.accepted = true;
fig.UserData = D;
uiresume(fig);
end


function txt = speciesRanges(settings, fieldList, paths)
% For each setting in fieldList, text such as 'species: 15-20 (n=3)': the
% range of values used for this species in OTHER deployments, read from
% HeartRate_Reference_Settings.csv (n = number of deployments). Shown in
% the tuning panels. 'species: none yet' if there are none.
txt = struct();
for j = 1:numel(fieldList)
    txt.(fieldList{j}) = 'species: none yet';
end
refFile = fullfile(paths.root, 'HeartRate_Reference_Settings.csv');
if ~isfile(refFile), return; end
ref = readcell(refFile, 'Delimiter', ',', 'DatetimeType', 'text');
ref = cellfun(@settingToText, ref, 'UniformOutput', false);
sc  = find(strcmp(ref(1, :), 'Species'), 1);
dc  = find(strcmp(ref(1, :), 'Deployment'), 1);
if isempty(sc) || isempty(dc) || size(ref, 1) < 2, return; end
rows = find(strcmpi(ref(2:end, sc), settings.species) & ...
    ~strcmp(ref(2:end, dc), settings.deployment)) + 1;   % same species, other deployments
if isempty(rows), return; end
for j = 1:numel(fieldList)
    col = find(strcmp(ref(1, :), ['settings.' fieldList{j}]), 1);
    if isempty(col), continue; end
    v = str2double(ref(rows, col));
    v = v(~isnan(v));
    if isempty(v), continue; end
    if min(v) == max(v)
        r = sprintf('%g', v(1));
    else
        r = sprintf('%g-%g', min(v), max(v));
    end
    txt.(fieldList{j}) = sprintf('species: %s (n=%d)', r, numel(v));
end
end


function reviewRefresh(fig)
% Redraws the review window for the stretch on screen: the traces (using
% the filtered ECG stored in the window), then the markers, whose gap above
% the peaks depends on the height of the trace on screen.
if ~isvalid(fig), return; end
R = fig.UserData;
refreshTraces(R.axECG, R.hTraces, R.t, R.sigs, R.fs);
drawReviewMarkers(fig);                    % also refits the ECG panel to include them
end


function reviewChangeFilter(fig)
% Change filter... button: opens the filter tuning window with the filter
% in use. Apply & continue re-filters the deployment and redraws the review
% (beats stay at their times; unsaved edits are kept), then offers to record
% the new filter in the settings sheets. Closing the window changes nothing.
R = fig.UserData;
try
    [v, ecgF] = filterTuningWindow(R.data, R.fs, R.filter, ...
        'the filter in use in this review', R.accNames, R.hasDepth, R.nStrips, R.rangeTxt);
catch err
    if strcmp(err.identifier, 'HeartbeatDetector:filterClosed')
        fprintf('Filter window closed: filter unchanged.\n');
        return
    end
    rethrow(err);
end
if ~isvalid(fig), return; end
R = fig.UserData;                          % read again, in case anything changed
if isequal(v, R.filter)
    fprintf('Filter unchanged.\n');
    return
end

% --- Use the new filtered ECG in the review
R.filter    = v;
R.ecg       = ecgF;                        % for snapping new markers and marker heights
R.sigs{end} = ecgF;                        % for drawing the trace
fig.UserData = R;
reviewRefresh(fig);
drawReviewMarkers(fig);
desc = sprintf('%g-%g Hz, order %d, inverted: %s', v.highPassHz, v.lowPassHz, ...
    v.filterOrder, mat2str(v.invertECG));
fprintf('Review now uses: %s\n', desc);

% --- Record it?
if R.viewOnly
    fprintf('View only: the settings sheets are not changed.\n');
    return
end
choice = questdlg(sprintf(['The review now uses a different filter:\n%s\n\n' ...
    'Update sheets: record it in this deployment''s settings sheet and the ' ...
    'reference sheet.\nJust for this session: use it now; the recorded ' ...
    'settings stay as they are.'], desc), 'Record new filter?', ...
    'Update sheets', 'Just for this session', 'Update sheets');
if strcmp(choice, 'Update sheets')
    if updateRecordedFilter(R, v)
        fprintf('New filter recorded in the settings sheets.\n');
    end
else
    fprintf('New filter used for this session only; settings sheets unchanged.\n');
end
end


function ok = updateRecordedFilter(R, v)
% Writes the filter values in v into the settings sheets.
ok = updateRecordedSettings(R, {'settings.highPassHz', 'settings.lowPassHz', ...
    'settings.filterOrder', 'settings.invertECG'}, ...
    {v.highPassHz, v.lowPassHz, v.filterOrder, v.invertECG});
end


function ok = updateRecordedSettings(R, names, values)
% Writes the given settings (names such as 'settings.minHR', and their
% values) into this deployment's settings sheet and its row in
% HeartRate_Reference_Settings.csv. Every other value is left exactly as it
% was. Returns false if a sheet could not be written.
ok = true;
newVals = cellfun(@settingToText, values, 'UniformOutput', false);
files = {R.settingsFile, R.referenceFile};
for f = 1:2
    if ~isfile(files{f}), continue; end
    c = readcell(files{f}, 'Delimiter', ',', 'DatetimeType', 'text');   % keep dates as text
    c = cellfun(@settingToText, c, 'UniformOutput', false);
    if f == 1
        rows = 2:size(c, 1);               % this deployment's sheet: its one row
    else
        dc = find(strcmp(c(1, :), 'Deployment'), 1);
        if isempty(dc), continue; end
        rows = find(strcmp(c(2:end, dc), R.deployment)) + 1;   % this deployment's row
    end
    for j = 1:numel(names)
        col = find(strcmp(c(1, :), names{j}), 1);
        if ~isempty(col), c(rows, col) = newVals(j); end
    end
    try
        writecell(c, files{f});
    catch
        ok = false;
        warning('Could not write %s. Is it open in Excel? The change was not recorded there.', ...
            files{f});
    end
end
end

function [noPrior, nNew] = enforceMinHR(time, noPrior, minHR)
% Any beat whose gap from the previous beat is longer than minHR allows
% (60/minHR s) becomes an x. Only adds x's; never removes them. Returns the
% updated x's and how many were added.
noPrior = logical(noPrior(:));
nNew = 0;
if numel(time) < 2 || isempty(minHR) || minHR <= 0, return; end
longGap = [false; diff(time(:)) > 60 / minHR];   % gap before each beat
nNew = sum(longGap & ~noPrior);
noPrior(longGap) = true;
end


function reviewPanel(fig)
% The settings panel on the right of the review window: Breaks (min heart
% rate; recorded in the settings sheets), Preferences (saved for you on
% this computer) and Change filter...
R = fig.UserData;
pnl = uipanel(fig, 'Units', 'normalized', 'Position', [0.86 0.06 0.13 0.92], ...
    'Title', 'Review settings', 'FontSize', 10, 'FontWeight', 'bold');
pc  = @(style, str, pos, varargin) uicontrol(pnl, 'Style', style, 'String', str, ...
    'Units', 'normalized', 'Position', pos, 'FontSize', 10, varargin{:});
ptx = @(str, pos, varargin) pc('text', str, pos, 'HorizontalAlignment', 'left', varargin{:});
blue = [0.2 0.2 0.6];  grey = [0.35 0.35 0.35];
tipR = 'Range used in other deployments of the same species (n = number of deployments)';

% --- Breaks: min heart rate
ptx('Breaks', [0.05 0.955 0.90 0.035], 'FontWeight', 'bold');
dHR = ['Any beat after a gap longer than 60 / min HR seconds becomes an x, ' ...
    'after every edit (x''s are never removed). Set slightly below the ' ...
    'slowest real heart rate expected.'];
ptx('Min heart rate (bpm)', [0.05 0.92 0.90 0.03], 'FontSize', 9, 'FontWeight', 'bold', 'Tooltip', dHR);
ptx(R.minHRRange, [0.05 0.893 0.90 0.027], 'FontSize', 8, 'ForegroundColor', blue, 'Tooltip', tipR);
h.minHR = pc('edit', sprintf('%g', R.minHR), [0.05 0.855 0.45 0.035], 'Tooltip', dHR, ...
    'Callback', @(~, ~) reviewSetMinHR(fig));
h.gap = ptx(sprintf('= gaps > %.3g s', 60 / R.minHR), [0.53 0.853 0.45 0.033], 'FontSize', 9);
ptx(dHR, [0.05 0.745 0.93 0.105], 'FontSize', 8, 'ForegroundColor', grey);
if R.viewOnly, set(h.minHR, 'Enable', 'off'); end

% --- Preferences: saved for you on this computer
ptx('Preferences', [0.05 0.70 0.90 0.035], 'FontWeight', 'bold');
ptx('Saved for you on this computer.', [0.05 0.672 0.90 0.028], 'FontSize', 8, 'ForegroundColor', blue);
spec = { ...                               % field, label, typical, description, current value
    'snapMs', 'Snap distance (ms)', 'typ. 50-150', ...
    'New markers jump to the highest peak within this distance of the click.', R.snapMs;
    'clickTolerancePx', 'Click tolerance (px)', 'typ. 5-12', ...
    'How close a click must be to a marker to remove it.', R.tolPx;
    'markerGapPct', 'Marker gap (%)', 'typ. 2-10', ...
    'Space above each peak, as % of the plot height on screen.', R.markerPct;
    'reviewWindowS', 'Window length (s)', 'e.g. 10-60', ...
    'Width of the view when a review opens (applies from the next review).', R.windowS};
for k = 1:size(spec, 1)
    y = 0.63 - (k - 1) * 0.115;
    ptx(spec{k, 2}, [0.05 y 0.90 0.03], 'FontSize', 9, 'FontWeight', 'bold', 'Tooltip', spec{k, 4});
    h.(spec{k, 1}) = pc('edit', sprintf('%g', spec{k, 5}), [0.05 y - 0.04 0.45 0.035], ...
        'Tooltip', spec{k, 4}, 'Callback', @(~, ~) reviewSetPref(fig, spec{k, 1}));
    ptx(spec{k, 3}, [0.53 y - 0.042 0.45 0.033], 'FontSize', 9);
    ptx(spec{k, 4}, [0.05 y - 0.11 0.93 0.068], 'FontSize', 8, 'ForegroundColor', grey);
end

% --- Hint and Change filter...
ptx(['After typing a value, press Enter. Then click the plot to use the ' ...
    'keyboard shortcuts again.'], [0.05 0.08 0.90 0.085], 'FontSize', 8, 'ForegroundColor', blue);
pc('pushbutton', 'Change filter...', [0.05 0.02 0.90 0.05], ...
    'Tooltip', 'Open the filter tuning window to view the data with a different filter', ...
    'Callback', @(~, ~) reviewChangeFilter(fig));

R.hPanel = h;
fig.UserData = R;
end


function reviewSetMinHR(fig)
% Min heart rate changed in the panel: beats after gaps longer than the new
% threshold become x's (none are removed; Z undoes it), and the new value
% is recorded in the settings sheets.
R = fig.UserData;
v = str2double(R.hPanel.minHR.String);
if isnan(v) || v <= 0
    warndlg('Min heart rate must be a number above 0 (bpm).', 'Check value', 'modal');
    set(R.hPanel.minHR, 'String', sprintf('%g', R.minHR));
    return
end
if v == R.minHR, return; end
[np, nNew] = enforceMinHR(R.time, R.noPrior, v);
if nNew > 0                                % one undo step for the new x's
    R.undo{end + 1} = {R.time, R.cert, R.noPrior, R.comment};
    if numel(R.undo) > 200, R.undo(1) = []; end
    R.noPrior = np;
end
R.minHR = v;
set(R.hPanel.gap, 'String', sprintf('= gaps > %.3g s', 60 / v));
fig.UserData = R;
if nNew > 0, afterEdit(fig); end
fprintf('Min heart rate now %g bpm (gaps over %.3g s are x''s): %d new x''s.\n', v, 60 / v, nNew);
if updateRecordedSettings(R, {'settings.minHR'}, {v})
    fprintf('Recorded in the settings sheets.\n');
end
end


function reviewSetPref(fig, field)
% A preference changed in the panel: use it now (snap distance, click
% tolerance, marker height) or from the next review (window length), and
% save it for this
% user with MATLAB's preferences (setpref).
R  = fig.UserData;
hE = R.hPanel.(field);
cur = struct('snapMs', R.snapMs, 'clickTolerancePx', R.tolPx, 'reviewWindowS', R.windowS, ...
    'markerGapPct', R.markerPct);
v  = str2double(hE.String);
if isnan(v) || v <= 0
    warndlg('Please enter a number above 0.', 'Check value', 'modal');
    set(hE, 'String', sprintf('%g', cur.(field)));
    return
end
switch field
    case 'snapMs'
        R.snapMs = v;
        R.snapN  = round(v / 1000 * R.fs); % snap distance in samples
    case 'clickTolerancePx'
        R.tolPx = v;
    case 'reviewWindowS'
        R.windowS = v;
    case 'markerGapPct'
        R.markerPct = v;
end
fig.UserData = R;
if strcmp(field, 'markerGapPct'), drawReviewMarkers(fig); end   % move the markers now
setpref('HeartbeatDetector', field, v);
fprintf('Preference saved: %s = %g\n', field, v);
end


function off = markerOffset(R)
% The gap between each peak and its marker: R.markerPct % of the height of
% the filtered ECG currently on screen (its highest minus lowest value), so
% it looks the same at any zoom.
xl = R.axECG.XLim;
i1 = max(1, floor((xl(1) - R.t(1)) * R.fs) + 1);
i2 = min(numel(R.t), ceil((xl(2) - R.t(1)) * R.fs) + 1);
seg = R.ecg(i1:i2);
rng = max(seg, [], 'omitnan') - min(seg, [], 'omitnan');
if isempty(rng) || ~isfinite(rng) || rng <= 0, rng = 1; end
off = R.markerPct / 100 * rng;
end

function reviewCheckpointPopup(fig)
% When a saved review opens: if the progress sheet shows a first pass or a
% review of this deployment that is not complete, a popup says who reached
% where, and offers to go there (60 s on each side of the checkpoint).
% Complete stages are ignored; with nothing incomplete (or no row in the
% progress sheet yet) there is no popup.
R = fig.UserData;
if ~isfile(R.progressFile), return; end
prog = readcell(R.progressFile, 'Delimiter', ',', 'DatetimeType', 'text');
prog = cellfun(@settingToText, prog, 'UniformOutput', false);
hdr  = prog(1, :);
dCol = find(strcmp(hdr, 'Deployment'), 1);
if isempty(dCol) || size(prog, 1) < 2, return; end
r = find(strcmp(prog(2:end, dCol), R.deployment), 1) + 1;   % this deployment's row
if isempty(r), return; end

% --- Each stage: label, then its columns (name, date, checkpoint, complete)
stages = {'First pass', 'ProcessedBy', 'ProcessedDate', 'CheckpointTime', 'FirstPassComplete';
    'Review', 'ReviewedBy', 'ReviewDate', 'ReviewCheckpointTime', 'ReviewComplete'};
lines = {};  buttons = {};  times = [];
for s = 1:size(stages, 1)
    v = repmat({''}, 1, 4);
    for j = 1:4
        c = find(strcmp(hdr, stages{s, j + 1}), 1);
        if ~isempty(c), v{j} = prog{r, c}; end
    end
    cp = str2double(v{3});
    if strcmpi(v{4}, 'Yes') || isnan(cp), continue; end   % complete, or no checkpoint
    note = '';                                           % checkpoint outside the tag-on period?
    if cp < R.t(1)
        note = sprintf(' This is before tag on (%.0f s), so Go shows the start', R.t(1));
    elseif cp > R.t(end)
        note = sprintf(' This is after tag off (%.0f s), so Go shows the end', R.t(end));
    end
    cpRaw = cp;                                          % as recorded, for the message
    cp = min(max(cp, R.t(1)), R.t(end));                 % inside the tag-on period
    who = v{1};
    if isempty(who), who = 'Someone'; end
    when = '';
    if ~isempty(v{2}), when = [' on ' v{2}]; end
    lines{end + 1}   = sprintf('%s (not complete): %s%s reached %.0f s.%s', ...
        stages{s, 1}, who, when, cpRaw, note);             %#ok<AGROW>
    buttons{end + 1} = sprintf('Go to %s checkpoint', lower(stages{s, 1}));   %#ok<AGROW>
    times(end + 1)   = cp;                                 %#ok<AGROW>
end
if isempty(times), return; end

% --- Ask, then go there
msg = sprintf(['Where this deployment was left off:\n\n%s\n\n' ...
    'Go there (60 s on each side), or start at the beginning?'], strjoin(lines, '\n'));
if numel(times) == 1
    choice = questdlg(msg, 'Where you left off', buttons{1}, 'Start at beginning', buttons{1});
else
    choice = questdlg(msg, 'Where you left off', buttons{1}, buttons{2}, ...
        'Start at beginning', buttons{1});
end
k = find(strcmp(buttons, choice), 1);
if isempty(k), return; end                 % Start at beginning, or closed
lo = R.t(1);  hi = R.t(end);
newLim = times(k) + [-60 60];              % 60 s on each side
if newLim(1) < lo, newLim = [lo, min(hi, lo + 120)]; end   % stay inside the recording
if newLim(2) > hi, newLim = [max(lo, hi - 120), hi]; end
R.axECG.XLim = newLim;
fprintf('%s: moved to %.0f s.\n', buttons{k}, times(k));
end