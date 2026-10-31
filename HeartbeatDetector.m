%% HeartbeatDetector.m
% Semi-automated R-wave detection and interactive review for ECG tag data
%
% CHANGES IN VERSION 3.3 (31-10-2026)
%   - Fixed: HeartRate_Progress.csv lost the ProcessedDate / ReviewDate of
%     other deployments whenever a new session was recorded. Sheets are now
%     read with dates kept as text, so existing dates are preserved.
%   - Clearer Command Window message after clicking tag on/off: the times
%     are saved automatically to the settings sheets when the review opens;
%     pasting them into SETTINGS is optional (avoids clicking next time).
%   - New sheet HeartRate_Deployment_Information.csv in the project folder:
%     one row per deployment, refreshed after every save (and again after
%     the progress popup at Save & finish). Columns: Deployment, Species,
%     Complete (from the progress sheet), tag on/off (s) and duration (h),
%     numbers of heartbeats (all / certain / possible), segments and RR
%     intervals; segment duration (min) and beats per segment (mean,
%     median, SD); PercentCleanECG (total segment duration / tag-on
%     duration x 100); heart rate (bpm: mean, median, SD); LastUpdated;
%     Comments (copied from the progress sheet). Sorted by Deployment.
%   - Older deployments get a row the next time they are saved (Continue
%     review, then Save & keep working; no edits needed).
%
% Created by: Cameron Nemeth, with Claude
% Email: ncnemeth@hawaii.edu
%
% Last modified: 28-10-2026
%
% HOW TO USE
%   1. Keep this script directly in the top-level project folder (e.g.
%      D:\HeartRate): the folder that contains the deployment folders. Not
%      in a subfolder, and not inside a deployment folder. The project
%      folder can have any name and be anywhere.
%
%   2. Put each deployment in its own folder next to the script (any name).
%      Create a "Data" folder with another folder inside called "Raw". The
%      script will create "Processed".
%      The Raw folder holds the raw data text file (any name). It can be:
%        - a LabChart "Export As Text" file with the block header, or
%        - a file with one row of column names above the numbers, or
%        - a file of numbers only (no column names).
%      Columns can be separated by tabs, commas or spaces, and time must be
%      in seconds. If there is no time column, the sampling rate is entered
%      in SETTINGS instead. Other files (e.g. the LabChart file itself) can
%      sit in Raw too; the script only reads the file named in SETTINGS.
%
%   3. Edit the SETTINGS section below: enter the deployment folder name and
%      the text file name exactly as they appear in the folders, which
%      columns hold time, ECG, depth and acceleration (by name or column
%      number; depth and acceleration are optional), plus tag on/off (if known) and notes. The FILTERING, AUTOMATIC R-WAVE
%      DETECTION and REVIEW sections each start with their own tuning values.
%
%   4. Save (Ctrl+S), then run SECTION BY SECTION, IN ORDER from the top:
%      click inside the SETTINGS section and press Ctrl+Shift+Enter (Run and
%      Advance), which runs that section and moves to the next. Repeat for
%      each section, checking each step before moving on.
%
%   5. When finished, these files will exist:
%        Processed\<deployment>_Heartbeats.csv
%            Every beat: Time (s, original recording time), Certainty
%            (1 = certain, 2 = possible), NoPriorBeat (1 = no known beat
%            before it), RRInterval (s), HeartRate (bpm), Segment (1, 2,
%            3, ...: a new segment starts at each beat with NoPriorBeat = 1)
%            and Comment. RRInterval and HeartRate are empty (NaN) where
%            NoPriorBeat = 1.
%        Processed\<deployment>_Settings.csv
%            The settings used for this deployment, for reference and review.
%        Raw\<deployment>_imported_time_depth_ecg.mat
%            Time, depth and ECG for the whole recording, copied from the
%            LabChart export so later runs load in seconds. Safe to delete;
%            it is rebuilt automatically.
%        HeartRate_Reference_Settings.csv (in the project folder)
%            A running list of the settings used for every deployment.
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
%
% All paths are built relative to this script's location, so the whole
% project folder can be moved or shared without changing any code.
%
% IF REVIEWING HEARTBEATS FOR AN EXISTING DEPLOYMENT:
%   Copy the values from <deployment>\Data\Processed\<deployment>_Settings.csv
%   into the settings in this script before running, so the data are
%   processed exactly as they were originally. If any value differs from the
%   sheet, a popup lists the differences and offers to update the sheets,
%   continue without updating (e.g. to try a different filter), or stop.
%   HeartRate_Reference_Settings.csv (in the project folder) lists the
%   settings used for every deployment, for comparison across deployments
%   and species.
%

%% ---- SETTINGS (edit this section for each deployment) ---------------
clear; clc; close all;

settings.species    = 'Loggerhead Turtle';          % Species. This is recorded in the settings sheets
settings.deployment = '6-Oct-2026-Nando-1suctioncup';      % Folder name inside project
settings.rawFile    = 'SevillaTurtle_06102026.txt';  % raw data text export, .txt or .csv

% Tag on/off times, in seconds from the start of the recording.
% If known, enter them here. If left empty [], you will click them
% on the overview plot.
settings.tagOnTime  = [0.184];
settings.tagOffTime = [23261.64];

% Columns to use. Give each one EITHER as a NAME in quotes, exactly as it
% is written in the file, OR as a column NUMBER, counting the columns of
% numbers from the left (1 = first column).
%   LabChart export: use names from the ChannelTitle line. The first
%     column is time, which LabChart leaves unnamed: use 'Time' (or 1).
%     Careful with numbers here: because time comes first, the first name
%     on the ChannelTitle line is column 2, not column 1.
%   File with a row of column names (e.g. Time,ECG,Depth): use the names.
%   File of numbers only: use column numbers.
% The script prints which columns it used, so check that after importing.
% Depth is optional: if the file has no depth, set depthChannel = []. The
% depth strips in the windows are then left empty; nothing else changes.
settings.timeChannel  = 1;        % time column (seconds), or [] if the file has none
settings.ecgChannel   = 'ecg';         % raw ECG values
settings.depthChannel = 'depth';   % depth values, or [] if the file has none

% Acceleration (optional): one setting per axis, each a column name or
%   number, or [] if that axis is not in the file. Fill in all three for a
%   3-axis tag, just one for a single-axis tag, or leave all three [] for
%   none. Acceleration is for display only (a strip above depth, to help
%   spot movement, e.g. muscle noise in the ECG); it is not used for
%   detection.
settings.accelX = [];                 % X axis
settings.accelY = [];                  % Y axis
settings.accelZ = [];                  % Z axis

% Sampling rate (Hz): ONLY needed if the file has no time column
%   (settings.timeChannel = []). Times are then counted from 0 s at the
%   first row. If the file does have a time column, the rate is worked out
%   from it and this value is ignored (a note is printed). Example: 250.
settings.sampleRateHz = [];

% Notes for this deployment, saved in the settings sheets (e.g. 'ECG shifted
% 17 s in LabChart to align with CATS depth'). Leave as '' if none.
settings.notes = '';

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
% are chosen in SETTINGS (timeChannel, ecgChannel, depthChannel), by name
% or by column number. Time must be in seconds. ECG is required; depth is
% optional (settings.depthChannel = []: the Depth column is left empty, NaN,
% and the depth strips in the windows are blank). Acceleration is optional
% too: each axis set in settings.accelX/Y/Z is added to the data as AccX,
% AccY or AccZ; axes left as [] are not loaded.
% Sampling rate: worked out from the time column (the typical gap between
% consecutive times). If there is no time column, it comes from
% settings.sampleRateHz, and times are counted from 0 s at the first row.
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
    % --- 1) Read the top of the file: every line before the first line that
    %     starts with a number is a header line; that first numeric line is
    %     the first row of data
    fid = fopen(paths.raw, 'r');
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
    end
    fclose(fid);
    if isempty(firstData)
        error('No rows of numbers were found in %s.', settings.rawFile);
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
    interval = NaN;                            % LabChart's Interval line, if present
    if ~isempty(header) && any(startsWith(header, 'ChannelTitle='))
        fileType = 'LabChart export';
        for h = 1:numel(header)
            if startsWith(header{h}, 'Interval=')
                tok = regexp(header{h}, 'Interval=\s*([-+\d\.eE]+)', 'tokens', 'once');
                if ~isempty(tok), interval = str2double(tok{1}); end
            elseif startsWith(header{h}, 'ChannelTitle=')
                parts  = strtrim(strsplit(header{h}, char(9)));   % split on tabs
                titles = parts(2:end);
                titles = titles(~cellfun('isempty', titles));
                names  = [{'Time'}, titles];   % LabChart leaves the time column unnamed
            end
        end
        nCols = numel(names);                  % time + one column per channel
    elseif nHeader > 0
        fileType = 'row of column names';
        names = strrep(splitFields(header{end}, sepChar), '"', '');   % last header line
        if numel(names) ~= nCols
            warning(['The column-name row has %d names but the data rows have %d ' ...
                'columns, so names may not line up with the right columns. ' ...
                'If so, use column numbers in SETTINGS instead.'], numel(names), nCols);
        end
    else
        fileType = 'numbers only (no column names)';
    end

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
% Shows the whole recording, in seconds: acceleration and depth strips at
% the top (whichever are set in SETTINGS) and the ECG below.
% If both tag times are set in SETTINGS, they are drawn and used.
% Otherwise: use the zoom/pan tools to find each time, click Set Tag On
% or Set Tag Off and then click on the plot, and finally click Done.
% Original recording times are kept throughout.

t      = data.Time;
tagOn  = settings.tagOnTime;
tagOff = settings.tagOffTime;

% --- Check any tag times given in SETTINGS
if ~isempty(tagOn) && (tagOn < t(1) || tagOn > t(end))
    error('settings.tagOnTime (%.3f s) is outside the recording (%.3f to %.3f s).', tagOn, t(1), t(end));
end
if ~isempty(tagOff) && (tagOff < t(1) || tagOff > t(end))
    error('settings.tagOffTime (%.3f s) is outside the recording (%.3f to %.3f s).', tagOff, t(1), t(end));
end
if ~isempty(tagOn) && ~isempty(tagOff) && tagOff <= tagOn
    error('settings.tagOffTime must be later than settings.tagOnTime.');
end

% --- Which thin strips to show above the ECG (top to bottom: acceleration,
% depth). These are reused by the later windows too.
accNames = intersect({'AccX', 'AccY', 'AccZ'}, data.Properties.VariableNames, 'stable');
hasDepth = ~isempty(settings.depthChannel);
nStrips  = ~isempty(accNames) + hasDepth;  % 0, 1 or 2

% --- Build the figure: strips on top, ECG panel below
overviewFig = figure('Name', 'Overview', 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.05 0.1 0.9 0.8]);
[stripPos, mainPos] = panelLayout(nStrips, 1, 0.14, 0.94, 0.14, 0.03);
[stripAx, stripLines, stripSigs] = addStrips(overviewFig, stripPos, accNames, hasDepth, data);
axECG = axes(overviewFig, 'Position', mainPos(1, :));   % tall ECG panel
hECG  = plot(axECG, NaN, NaN, 'k');        % raw ECG: black, so the tag lines stand out
ylabel(axECG, 'ECG');
xlabel(axECG, 'Time (s)');
grid(axECG, 'on');

axAll = [stripAx axECG];                   % every panel, top to bottom
axTop = axAll(1);                          % the title goes on the top panel
linkaxes(axAll, 'x');                      % zoom/pan all panels together
setTimeOnlyNavigation(overviewFig, axAll); % zoom/pan change time only
for s = 1:numel(stripAx)                   % always refit y to the visible traces
    keepYFitted(stripAx(s), stripLines([stripLines.Parent] == stripAx(s)));
end
keepYFitted(axECG, hECG);
set(axAll, 'XLim', [t(1) t(end)]);

% --- Redraw the traces whenever the visible time range changes
hOverview    = [stripLines hECG];          % every plotted line
sigsOverview = [stripSigs, {data.ECG}];    % the matching data columns
addlistener(axECG, 'XLim', 'PostSet', ...
    @(~, ~) refreshTraces(axECG, hOverview, t, sigsOverview, fs));
refreshTraces(axECG, hOverview, t, sigsOverview, fs);   % first draw

% --- Store what the buttons need, inside the figure
S.axTop    = axTop;                        % panel that holds the title
S.axAll    = axAll;                        % every panel (tag lines go on all)
S.axECG    = axECG;
S.t        = t;
S.fs       = fs;
S.tagOn    = tagOn;
S.tagOff   = tagOff;
S.accepted = false;
overviewFig.UserData = S;
drawTagLines(overviewFig);

if isempty(tagOn) || isempty(tagOff)
    % --- One or both times missing: show buttons and wait for the user
    title(axTop, 'Zoom/pan to find tag on/off, then use the buttons below');

    enableOn  = 'on';  if ~isempty(tagOn),  enableOn  = 'off'; end
    enableOff = 'on';  if ~isempty(tagOff), enableOff = 'off'; end

    uicontrol(overviewFig, 'Style', 'pushbutton', 'String', 'Set Tag On', ...
        'Units', 'normalized', 'Position', [0.25 0.02 0.14 0.05], ...
        'Enable', enableOn, 'Callback', @(~, ~) setTagTime(overviewFig, 'On'));
    uicontrol(overviewFig, 'Style', 'pushbutton', 'String', 'Set Tag Off', ...
        'Units', 'normalized', 'Position', [0.43 0.02 0.14 0.05], ...
        'Enable', enableOff, 'Callback', @(~, ~) setTagTime(overviewFig, 'Off'));
    uicontrol(overviewFig, 'Style', 'pushbutton', 'String', 'Done', ...
        'Units', 'normalized', 'Position', [0.61 0.02 0.14 0.05], ...
        'Callback', @(~, ~) finishTags(overviewFig));

    uiwait(overviewFig);    % pause the script until Done > Accept

    if ~isvalid(overviewFig) || ~overviewFig.UserData.accepted
        error('Tag on/off times were not accepted. Run the script again to set them.');
    end
    tagOn  = overviewFig.UserData.tagOn;
    tagOff = overviewFig.UserData.tagOff;

    fprintf('\nTag times accepted and used for this run:\n');
    fprintf('  settings.tagOnTime  = %.3f;\n', tagOn);
    fprintf('  settings.tagOffTime = %.3f;\n', tagOff);
    fprintf(['They will be saved in the settings sheets when the review window opens.\n' ...
        'Optional: paste the two lines above into SETTINGS (now or after the run)\n' ...
        'so later runs use the same times without clicking.\n']);
else
    title(axTop, 'Tag on/off times from SETTINGS');
    fprintf('\nUsing tag on/off times from SETTINGS.\n');
end

% --- Crop the data to the tag-on period (original times are kept)
keep = data.Time >= tagOn & data.Time <= tagOff;
data = data(keep, :);

fprintf('Cropped to %.3f - %.3f s: %d samples (%.2f h)\n', ...
    tagOn, tagOff, height(data), (tagOff - tagOn) / 3600);







%% ---- FILTERING ------------------------------------------------------------
% Makes a filtered copy of the ECG, used only for beat detection.
% The raw ECG (data.ECG) is never changed.
% Band-pass filter from settings.highPassHz to settings.lowPassHz, run
% forward and then backward (filtfilt) so filtered peaks stay at the same
% times as the raw peaks.


% ----- FILTER SETTINGS -----
% Values used are recorded automatically in <deployment>_Settings.csv and
% HeartRate_Reference_Settings.csv (see the note at the top of the script).
%
%
% High-pass cutoff (Hz): removes slow drift (baseline wander from breathing,
%   body movement, electrode shifts, depth changes). Raising it flattens the
%   baseline more, but too high can shrink wide/slow QRS complexes.
%   Typical: 0.5-5 Hz.
settings.highPassHz = 1;

% Low-pass cutoff (Hz): removes fast jitter. Lowering it smooths more, but
%   too low can blunt sharp R peaks. Must be below half the sampling rate
%   of the tag. 
% Typical: 25-50 Hz.
settings.lowPassHz = 40;

% Filter order: how sharply the filter cuts off around the two cutoffs.
%   Higher = sharper, but can add small ripples ("ringing") next to large
%   peaks. 
% 2-4 is typical; leave at 4 unless there is a reason to change it.
settings.filterOrder = 4;

% Invert ECG: set to true if R waves point DOWNWARD on this tag. The script
%   prints a suggestion each run. Only the filtered copy used for detection
%   is flipped; the raw ECG is never changed.
settings.invertECG = true;

% THIS CAN JUST STAY TRUE
% False just skips the figure pane for this filtering step.
% Show the filter check plot (raw and filtered ECG, below any acceleration
%   and depth strips). Set to false once the values above are settled, to
%   skip it.
settings.showFilterCheck = true;



% --- Report missing values (NaN). The filter cannot run over gaps, so they
% are filled in temporarily, then set back to NaN in the filtered copy.
nanECG = isnan(data.ECG);
nNaN   = sum(nanECG);
fprintf('\nECG missing values (NaN) in tag-on period: %d (%.3f%%)\n', ...
    nNaN, 100 * nNaN / height(data));
ecgForFilter = data.ECG;
if nNaN > 0
    ecgForFilter = fillmissing(ecgForFilter, 'linear');
    fprintf('  Filled temporarily for filtering; they stay NaN in the filtered copy.\n');
end

% --- Check the cutoffs make sense
nyq = fs / 2;                              % highest frequency the data can hold
if settings.highPassHz <= 0 || settings.lowPassHz >= nyq || ...
        settings.highPassHz >= settings.lowPassHz
    error('Check filter cutoffs: need 0 < highPassHz < lowPassHz < %g Hz.', nyq);
end

% --- Design the band-pass filter and run it forward and backward
[z, p, k]  = butter(settings.filterOrder, ...
    [settings.highPassHz settings.lowPassHz] / nyq, 'bandpass');
[sos, g]   = zp2sos(z, p, k);              % numerically stable form of the filter
ecgFilt    = filtfilt(sos, g, ecgForFilter);
ecgFilt(nanECG) = NaN;                     % put missing values back
clear ecgForFilter

% --- Polarity suggestion: do the biggest deflections point up or down?
% Uses the 0.1% most extreme values in each direction.
vals = sort(ecgFilt(~isnan(ecgFilt)));
hi   = vals(max(1, round(0.999 * numel(vals))));
lo   = vals(max(1, round(0.001 * numel(vals))));
clear vals
if abs(lo) > 1.2 * abs(hi)
    polarityNote = 'DOWNWARD - consider settings.invertECG = true';
elseif abs(hi) > 1.2 * abs(lo)
    polarityNote = 'UPWARD - settings.invertECG = false';
else
    polarityNote = 'UNCLEAR - check the plot by eye';
end
fprintf('Polarity check: largest deflections point %s\n', polarityNote);
fprintf('  settings.invertECG is currently: %s\n', mat2str(settings.invertECG));

if settings.invertECG
    ecgFilt = -ecgFilt;                    % flip the filtered copy only
end
data.ECG_filtered = ecgFilt;               % new column, next to the raw ECG
clear ecgFilt

fprintf('Filtered ECG: %g-%g Hz band-pass, order %d, zero-phase.\n', ...
    settings.highPassHz, settings.lowPassHz, settings.filterOrder);

% --- Check plot: acceleration/depth strips, raw ECG and filtered ECG,
% linked in time
if settings.showFilterCheck
    tCrop = data.Time;
    filterFig = figure('Name', 'Filter check: raw and filtered ECG', ...
        'NumberTitle', 'off', 'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);
    [stripPos, mainPos] = panelLayout(nStrips, 2, 0.08, 0.95, 0.12, 0.02);
    [fStripAx, fStripLines, fStripSigs] = addStrips(filterFig, stripPos, accNames, hasDepth, data);
    axR = axes(filterFig, 'Position', mainPos(1, :));   % raw ECG
    axF = axes(filterFig, 'Position', mainPos(2, :));   % filtered ECG

    hR = plot(axR, NaN, NaN, 'Color', [0.8 0 0]);   % raw ECG: red
    hF = plot(axF, NaN, NaN, 'k');                   % filtered ECG: black
    ylabel(axR, 'Raw ECG');
    ylabel(axF, 'Filtered ECG');
    xlabel(axF, 'Time (s)');
    grid(axR, 'on'); grid(axF, 'on');

    fAll = [fStripAx axR axF];              % every panel, top to bottom
    title(fAll(1), sprintf('Filter check: %g-%g Hz band-pass, order %d, inverted: %s', ...
        settings.highPassHz, settings.lowPassHz, settings.filterOrder, ...
        mat2str(settings.invertECG)));
    linkaxes(fAll, 'x');
    axR.XTickLabel = {};                    % time labels only on the bottom panel
    setTimeOnlyNavigation(filterFig, fAll); % zoom/pan change time only
    for s = 1:numel(fStripAx)               % always refit y to the visible traces
        keepYFitted(fStripAx(s), fStripLines([fStripLines.Parent] == fStripAx(s)));
    end
    keepYFitted(axR, hR);
    keepYFitted(axF, hF);
    set(axF, 'XLim', [tCrop(1) tCrop(end)]);

    hFilt = [fStripLines hR hF];            % every plotted line
    sigs  = [fStripSigs, {data.ECG, data.ECG_filtered}];   % the matching data
    addlistener(axF, 'XLim', 'PostSet', ...
        @(~, ~) refreshTraces(axF, hFilt, tCrop, sigs, fs));
    refreshTraces(axF, hFilt, tCrop, sigs, fs);    % first draw
end







%% ---- AUTOMATIC R-WAVE DETECTION -------------------------------------------
% Finds every upward peak in the filtered ECG, measures how much each one
% stands out from the nearby background (size, steepness, width), and keeps
% those that look like R waves. Results are shown as red circles for a quick
% check. Nothing is saved here; beats are locked in during the review step.

% ----- DETECTION SETTINGS (adjust here while tuning) -----
% Stands-out ratio (AMPLITUDE): how many times taller a peak must be than
%   the typical background signal nearby. Raise it if noise bumps get red
%   circles; lower it if small real beats are missed. Typical: 3-8.
settings.minStandOut = 20;

% Steepness ratio (SLOPE): how many times steeper a peak's rise or fall must
%   be than the typical background nearby. R waves are sharp; slower bumps
%   (T waves, movement) are not. Raise it to reject rounded bumps; lower it
%   if real beats are missed. Typical: 3-8.
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
settings.maxHR = 60;


% Oversized-peak filter (removes e.g. surfacing artifacts): a detected beat
%   is removed if its prominence is more than maxRelSize times the median
%   prominence of its neighbouring beats (nNeighbors on each side).
%   Lower maxRelSize to remove more large peaks; raise it if real beats are
%   being removed. Typical: 2-5 times, 3-10 neighbours each side.
settings.maxRelSize = 3;
settings.nNeighbors = 3;

% ---- Detection (no editing needed) ----------------------------------------
fprintf('\nDetecting R waves (this may take a little while)...\n');
t = data.Time;
x = data.ECG_filtered;
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
clear win

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

clear blocked dx x

% --- Summary
fprintf('Candidate peaks: %d | Detected beats: %d\n', height(cand), height(beats));
fprintf('Removed as oversized (> %gx neighbouring beats, likely surfacing artifacts): %d\n', ...
    settings.maxRelSize, nOversized);
if height(beats) > 1
    fprintf('Typical heart rate (median gap between detected beats): %.1f bpm\n', ...
        60 / median(diff(beats.Time)));
end

% --- Detection window: acceleration/depth strips + filtered ECG with red circles
if isempty(beats)
    markerOffset = 0;
else
    markerOffset = 0.15 * median(beats.Prominence);   % circles sit just above each peak
end
beatY = beats.Height + markerOffset;

detectFig = figure('Name', 'Automatic R-wave detection', 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);
[stripPos, mainPos] = panelLayout(nStrips, 1, 0.08, 0.95, 0.11, 0.03);
[dStripAx, dStripLines, dStripSigs] = addStrips(detectFig, stripPos, accNames, hasDepth, data);
detAxECG = axes(detectFig, 'Position', mainPos(1, :));   % filtered ECG

detECG   = plot(detAxECG, NaN, NaN, 'k');
hold(detAxECG, 'on');
detBeats = plot(detAxECG, beats.Time, beatY, 'o', 'LineStyle', 'none', ...
    'MarkerSize', 6, 'MarkerFaceColor', [0.85 0 0], 'MarkerEdgeColor', [0.85 0 0]);
hold(detAxECG, 'off');
ylabel(detAxECG, 'Filtered ECG');
xlabel(detAxECG, 'Time (s)');
grid(detAxECG, 'on');

detAll = [dStripAx detAxECG];              % every panel, top to bottom
title(detAll(1), sprintf(['Automatic detection: %d beats  |  stands-out >= %g, ' ...
    'steepness >= %g, width <= %g ms, max HR %g bpm, oversized > %gx removed'], ...
    height(beats), settings.minStandOut, settings.minSteepness, ...
    settings.maxWidthMs, settings.maxHR, settings.maxRelSize));
linkaxes(detAll, 'x');
setTimeOnlyNavigation(detectFig, detAll);
for s = 1:numel(dStripAx)                  % always refit y to the visible traces
    keepYFitted(dStripAx(s), dStripLines([dStripLines.Parent] == dStripAx(s)));
end
keepYFitted(detAxECG, [detECG detBeats]);  % fit the trace AND the red circles
set(detAxECG, 'XLim', [t(1) t(end)]);

hDet    = [dStripLines detECG];            % strip lines, then the ECG (last)
sigsDet = [dStripSigs, {data.ECG_filtered}];
addlistener(detAxECG, 'XLim', 'PostSet', ...
    @(~, ~) refreshDetection(detAxECG, hDet, detBeats, t, sigsDet, fs));
refreshDetection(detAxECG, hDet, detBeats, t, sigsDet, fs);   % first draw








%% ---- REVIEW: EDIT BEATS AND MARK BREAKS -----------------------------------
% Edits are saved to <deployment>_Heartbeats.csv in the Processed folder
% when you click Save & keep working or Save & finish (bottom right). Save
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
%   Save & finish button        -> save, record progress, and close
%   Closing the window (X)      -> asks to save first if there are unsaved changes
%   New markers snap to the highest point of the filtered ECG near the click.
%   NOTE: MATLAB treats a RIGHT click the same as Ctrl + click (adds a red x)
%   and a MIDDLE click the same as Shift + click (adds a green circle).

% SAVING
%   Save & keep working saves to <deployment>_Heartbeats.csv in the
%   Processed folder, with columns: Time, Certainty, NoPriorBeat,
%   RRInterval, HeartRate, Segment, Comment. The button is orange while
%   there are unsaved changes and green once everything is saved.
%   Save & finish saves, asks for progress details (recorded in
%   HeartRate_Progress.csv in the project folder), and closes the window.

% ---- REVIEW SETTINGS (adjust here as needed) ------------------------------
% PRE-PLACED x's: only used when a review STARTS from the automatic
%   detections. After that, x's are only changed by you. A beat starts as an
%   x if the gap before it is EITHER:
%     - longer than the slowest plausible heart rate allows (minHR), OR
%     - more than breakFactor times the typical gap between nearby beats
%       (median of breakNeighbors gaps on each side). This catches single
%       missed beats.
%
% Minimum heart rate (bpm). This is just an approximation.
% For example, 20 bpm = any gap over 3 s gets an x.
% Lower it if real slow beats (e.g. deep dives) get x's
% Raise it to flag shorter gaps.

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

% Personal settings below here. These just affect the way you interact with
% the window. 

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

% ---- Record the settings used: deployment sheet + reference sheet ---------
% Every setting that can change from deployment to deployment is written to:
%   <deployment>\Data\Processed\<deployment>_Settings.csv   (this deployment)
%   HeartRate_Reference_Settings.csv in the project folder    (all deployments,
%     sorted by Species, then Deployment)
% Tag on/off are the times actually used (typed in SETTINGS or clicked).
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
            'Stop: correct the script first.'], settings.deployment, ...
            strjoin(diffs, '\n')), 'Settings differ from saved sheet', ...
            'Update sheets', 'Continue without updating', 'Stop', 'Stop');
        switch settingsChoice
            case 'Update sheets'
                % recordSettings stays true: both sheets are rewritten below
            case 'Continue without updating'
                recordSettings = false;
                fprintf('Continuing WITHOUT updating the settings sheets.\n');
            otherwise                      % 'Stop', or the popup was closed
                error(['Stopped: settings differ from %s\nCopy the values from that ' ...
                    'sheet into the script (or choose another option) and run again.'], ...
                    settingsFile);
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
    reviewChoice = questdlg(sprintf(['A saved review was found:\n%s\n\n' ...
        'Continue it, view it only, or start over from the automatic detections?'], ...
        reviewFile), 'Saved review found', ...
        'Continue review', 'View only', 'Start over', 'Continue review');
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

% ---- Review window: acceleration/depth strips + filtered ECG with markers --
reviewFig  = figure('Name', ['Review: ' settings.deployment], 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);
[stripPos, mainPos] = panelLayout(nStrips, 1, 0.08, 0.87, 0.11, 0.03);   % room above for instructions
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
R.offset   = markerOffset;                 % markers sit just above the peaks
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
reviewFig.UserData = R;

% --- Connect the mouse, keys and Save buttons
reviewFig.WindowButtonDownFcn   = @(~, ~) reviewMouseDown(reviewFig);
reviewFig.WindowButtonMotionFcn = @(~, ~) reviewMouseMove(reviewFig);   % drag to move in time
reviewFig.WindowButtonUpFcn     = @(~, ~) reviewMouseUp(reviewFig);
reviewFig.WindowScrollWheelFcn  = @(~, evt) reviewScroll(reviewFig, evt);   % scroll to zoom in time
reviewFig.WindowKeyPressFcn = @(~, evt) reviewKey(reviewFig, evt);
R = reviewFig.UserData;
R.hSave = uicontrol(reviewFig, 'Style', 'pushbutton', 'String', 'Save & keep working', ...
    'Units', 'normalized', 'Position', [0.60 0.005 0.22 0.04], 'FontWeight', 'bold', ...
    'Callback', @(~, ~) saveReview(reviewFig));
R.hFinish = uicontrol(reviewFig, 'Style', 'pushbutton', 'String', 'Save & finish', ...
    'Units', 'normalized', 'Position', [0.83 0.005 0.14 0.04], 'FontWeight', 'bold', ...
    'BackgroundColor', [0.2 0.45 0.8], 'ForegroundColor', 'w', ...
    'Callback', @(~, ~) finishReview(reviewFig));
reviewFig.UserData = R;
updateSaveButton(reviewFig);

% --- First draw, starting at the beginning of the tag-on period
hRevTraces = [rStripLines revECG];         % strip lines, then the ECG (last)
sigsRev    = [rStripSigs, {data.ECG_filtered}];
addlistener(revAxECG, 'XLim', 'PostSet', @(~, ~) refreshDetection(revAxECG, ...
    hRevTraces, [revRed revGreen revX], data.Time, sigsRev, fs));
set(revAxECG, 'XLim', [data.Time(1), ...
    min(data.Time(end), data.Time(1) + settings.reviewWindowS)]);
if startFresh && ~viewOnly
    afterEdit(reviewFig);                  % applies first-beat x; marks as unsaved
else
    drawReviewMarkers(reviewFig);
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
% Called by the Set Tag On / Set Tag Off buttons. 'which' is 'On' or 'Off'.
S = overviewFig.UserData;
zoom(overviewFig, 'off');                 % turn off zoom/pan so the click registers
pan(overviewFig, 'off');
title(S.axTop, sprintf('Click on the plot to set TAG %s', upper(which)));
[x, ~] = ginput(1);                       % wait for one click
i = round((x - S.t(1)) * S.fs) + 1;       % snap to the nearest sample
i = min(max(i, 1), numel(S.t));
S.(['tag' which]) = S.t(i);               % stores in S.tagOn or S.tagOff
overviewFig.UserData = S;
drawTagLines(overviewFig);
title(S.axTop, 'Zoom/pan to find tag on/off, then use the buttons below');
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

function finishTags(overviewFig)
% Called by the Done button: checks the times, then asks Accept or Redo.
S = overviewFig.UserData;
if isempty(S.tagOn) || isempty(S.tagOff)
    warndlg('Please set both Tag On and Tag Off before clicking Done.', 'Missing time');
    return
end
if S.tagOff <= S.tagOn
    warndlg('Tag Off must be later than Tag On.', 'Check times');
    return
end
tagChoice = questdlg(sprintf('Tag on:  %.3f s\nTag off: %.3f s\n\nUse these times?', ...
    S.tagOn, S.tagOff), ...
    'Confirm tag times', 'Accept', 'Redo', 'Accept');
if strcmp(tagChoice, 'Accept')
    S.accepted = true;
    overviewFig.UserData = S;
    uiresume(overviewFig);                % let the script continue
end
% Redo (or closing the popup) just returns to the plot to adjust
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
% Runs after every change: the first beat is always an x, the Save button
% turns orange (unsaved changes), and the markers are redrawn.
R = fig.UserData;
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
y   = R.ecg(idx) + R.offset;                            % just above the peak
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
% Save & finish: saves, records progress in HeartRate_Progress.csv, and
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
% After Save & finish: asks who worked on this deployment, how far they got
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

function [stripPos, mainPos] = panelLayout(nStrips, nMain, bottom, top, stripH, gap)
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
left = 0.07;  width = 0.9;
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