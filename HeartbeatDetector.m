%% HeartbeatDetector.m
% Semi-automated R-wave detection and interactive review for ECG tag data
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
%      The Raw folder should contain the LabChart file (any name; not used by the
%      script) and the text file exported from it (any name). The text file
%      is a LabChart "Export As Text" file with the block header included
%      (time column first, tab-separated, one column per channel), as
%      described in the IMPORT section. 
%
%   3. Edit the SETTINGS section below: enter the deployment folder name and
%      the text file name exactly as they appear in the folders, plus tag
%      on/off (if known), channel names and notes. The FILTERING, AUTOMATIC
%      R-WAVE DETECTION and REVIEW sections each start with their own tuning
%      values.
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
%            before it), RRInterval (s) and HeartRate (bpm). RRInterval and
%            HeartRate are empty (NaN) where NoPriorBeat = 1.
%        Processed\<deployment>_Settings.csv
%            The settings used for this deployment, for reference and review.
%        Raw\<deployment>_imported_time_depth_ecg.mat
%            Time, depth and ECG for the whole recording, copied from the
%            LabChart export so later runs load in seconds. Safe to delete;
%            it is rebuilt automatically.
%        HeartRate_Reference_Settings.csv (in the project folder)
%            A running list of the settings used for every deployment.
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
% Version: 0.9 (import, tag on/off, filtering, detection, review, settings record)

%% ---- SETTINGS (edit this section for each deployment) ---------------
clear; clc; close all;

settings.species    = 'Turtle';          % Species. This is recorded in the settings sheets
settings.deployment = 'SevillaTurtle_06102026';      % Folder name inside project
settings.rawFile    = 'SevillaTurtle_06102026.txt';  % LabChart text export

% Tag on/off times, in seconds from the start of the recording.
% If known, enter them here. If left empty [], you will click them
% on the overview plot.
settings.tagOnTime  = [0.184];
settings.tagOffTime = [23261.64];

% Channel names exactly as they appear in LabChart's ChannelTitle line
% This can be found in the text file that was exported from Labchart
settings.ecgChannel   = 'ecg'; % Raw ECG values
settings.depthChannel = 'depth'; % Depth values

% Notes for this deployment, saved in the settings sheets (e.g. 'ECG shifted
% 17 s in LabChart to align with CATS depth'). Leave as '' if none.
settings.notes = 'Turtle species unknown (CN 06/10/2026)';

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
% Reads time, ECG, and depth from the LabChart text export.
% The first run reads the text file (slow) and saves a .mat copy of just
% the time, depth and ECG columns in the Raw folder, next to the text file
% (<deployment>_imported_time_depth_ecg.mat). Later runs load that copy
% instead (fast). If the text file has been modified since the copy was
% saved (e.g. a re-export from LabChart), a popup asks whether to re-import
% it. To force a fresh import, delete the .mat file in the Raw folder.
cacheFile = fullfile(fileparts(paths.raw), ...                      % the Raw folder
    [settings.deployment '_imported_time_depth_ecg.mat']);
useCache  = isfile(cacheFile);   % is there a saved copy?

if useCache
    % If the raw text file was modified after the saved copy was made,
    % ask whether to re-import it.
    rawInfo   = dir(paths.raw);
    cacheInfo = dir(cacheFile);
    if rawInfo.datenum > cacheInfo.datenum
        choice = questdlg(['The raw data file has changed since it was last ' ...
            'imported. Re-import it?'], ...
            'Newer raw file found', ...
            'Re-import', 'Use saved copy', 'Re-import');
        if strcmp(choice, 'Re-import')
            useCache = false;
        else
            fprintf('Using saved copy. It may not match the newer raw file.\n');
        end
    end
end

if useCache
    cached = load(cacheFile);
    % Re-read the text file if the saved copy came from a different raw
    % file, or used different channels, than the current settings
    if ~isfield(cached, 'rawFile') || ~strcmp(cached.rawFile, settings.rawFile)
        fprintf('Saved copy came from a different raw file. Re-reading text file.\n');
        useCache = false;
    elseif ~strcmp(cached.channels.ecg, settings.ecgChannel) || ...
            ~strcmp(cached.channels.depth, settings.depthChannel)
        fprintf('Channel settings changed since last import. Re-reading text file.\n');
        useCache = false;
    end
end

if useCache
    data = cached.data;
    fs   = cached.fs;
    fprintf('Loaded saved import: %s\n', cacheFile);
else
    % --- Read the header: everything before the first line starting with a number
    fid = fopen(paths.raw, 'r');
    nHeader = 0; interval = NaN; titles = {};
    while true
        txt = fgetl(fid);
        if ~ischar(txt), break; end
        if ~isempty(regexp(txt, '^\s*-?\d', 'once')), break; end
        nHeader = nHeader + 1;
        if startsWith(txt, 'Interval=')
            tok = regexp(txt, 'Interval=\s*([-+\d\.eE]+)', 'tokens', 'once');
            interval = str2double(tok{1});
        elseif startsWith(txt, 'ChannelTitle=')
            parts  = strtrim(strsplit(txt, char(9)));   % split on tabs
            titles = parts(2:end);
            titles = titles(~cellfun('isempty', titles));
        end
    end
    fclose(fid);

    if isnan(interval) || isempty(titles)
        error('Could not read Interval or ChannelTitle from the file header.');
    end

    % --- Find the requested channels by name
    ecgIdx   = find(strcmp(titles, settings.ecgChannel));
    depthIdx = find(strcmp(titles, settings.depthChannel));
    if isempty(ecgIdx) || isempty(depthIdx)
        error('Channel not found. Channels in this file:\n  %s', strjoin(titles, '\n  '));
    end

    % --- Build a read format that keeps only time, ECG, and depth
    nCols  = numel(titles) + 1;                     % +1 for the time column
    wanted = [1, ecgIdx + 1, depthIdx + 1];
    fmt = repmat({'%*f'}, 1, nCols);                % %*f = skip this column
    fmt(wanted) = {'%f'};                           % %f  = keep this column
    fmt = [strjoin(fmt, '') '%*[^\n]'];             % ignore any trailing text (comments)

    % --- Read the data
    fprintf('Reading %s (this may take a few minutes)...\n', settings.rawFile);
    fid = fopen(paths.raw, 'r');
    C = textscan(fid, fmt, 'Delimiter', '\t', 'HeaderLines', nHeader, ...
        'ReturnOnError', true);
    reachedEnd = feof(fid);
    fclose(fid);

    if ~reachedEnd
        warning(['Reading stopped before the end of the file. The file may ' ...
            'contain more than one LabChart block. Only the first was loaded.']);
    end

    % --- Put the columns into a table (textscan returns them in file order)
    n = min(cellfun(@numel, C));
    sortedCols = sort(wanted);
    getCol = @(col) C{sortedCols == col}(1:n);
    data = table(getCol(1), getCol(ecgIdx + 1), getCol(depthIdx + 1), ...
        'VariableNames', {'Time', 'ECG', 'Depth'});
    fs = 1 / interval;
    clear C

    % --- Save a fast-loading copy, recording where it came from
    channels.ecg   = settings.ecgChannel;
    channels.depth = settings.depthChannel;
    rawFile        = settings.rawFile;
    save(cacheFile, 'data', 'fs', 'channels', 'rawFile', '-v7.3');
    fprintf('Saved import to: %s\n', cacheFile);
end

% --- Basic checks
dt = diff(data.Time);
nIrregular = sum(abs(dt - 1/fs) > 0.5/fs);
fprintf('\nSamples: %d | Sampling rate: %g Hz | Duration: %.2f h\n', ...
    height(data), fs, (data.Time(end) - data.Time(1)) / 3600);
fprintf('Irregular time steps: %d\n', nIrregular);
fprintf('NaN values - ECG: %d, Depth: %d\n', sum(isnan(data.ECG)), sum(isnan(data.Depth)));









%% ---- OVERVIEW PLOT AND TAG ON/OFF -----------------------------------------
% Shows depth (top) and ECG (bottom) for the whole recording, in seconds.
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

% --- Build the figure: depth panel on top, ECG panel below
overviewFig = figure('Name', 'Overview: depth and ECG', 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.05 0.1 0.9 0.8]);
axDepth = axes(overviewFig, 'Position', [0.07 0.80 0.9 0.14]);   % thin depth strip
axECG   = axes(overviewFig, 'Position', [0.07 0.14 0.9 0.63]);   % tall ECG panel

hDepth = plot(axDepth, NaN, NaN, 'b');      % empty lines, filled in below
hECG   = plot(axECG,   NaN, NaN, 'k');      % raw ECG: black, so the tag lines stand out
set(axDepth, 'YDir', 'reverse');            % deeper = lower on the plot
ylabel(axDepth, 'Depth (m)');
ylabel(axECG, 'ECG');
xlabel(axECG, 'Time (s)');
grid(axDepth, 'on'); grid(axECG, 'on');

linkaxes([axDepth axECG], 'x');             % zoom/pan both panels together
axDepth.XTickLabel = {};                    % time labels only on the bottom panel
setTimeOnlyNavigation(overviewFig, [axDepth axECG]);   % zoom/pan change time only
keepYFitted(axDepth, hDepth);               % always refit y to the visible trace
keepYFitted(axECG,   hECG);
set([axDepth axECG], 'XLim', [t(1) t(end)]);

% --- Redraw the traces whenever the visible time range changes
depthVec = data.Depth;
ecgVec   = data.ECG;
sigsOverview = {depthVec, ecgVec};          % one data column per panel
addlistener(axECG, 'XLim', 'PostSet', ...
    @(~, ~) refreshTraces(axECG, [hDepth hECG], t, sigsOverview, fs));
refreshTraces(axECG, [hDepth hECG], t, sigsOverview, fs);   % first draw

% --- Store what the buttons need, inside the figure
S.axDepth  = axDepth;
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
    title(axDepth, 'Zoom/pan to find tag on/off, then use the buttons below');

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

    fprintf('\nTag times accepted. To reuse them, paste these into SETTINGS:\n');
    fprintf('settings.tagOnTime  = %.3f;\n', tagOn);
    fprintf('settings.tagOffTime = %.3f;\n', tagOff);
else
    title(axDepth, 'Tag on/off times from SETTINGS');
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
%   of the tag. Typical: 25-50 Hz.
settings.lowPassHz = 40;

% Filter order: how sharply the filter cuts off around the two cutoffs.
%   Higher = sharper, but can add small ripples ("ringing") next to large
%   peaks. 2-4 is typical; leave at 4 unless there is a reason to change it.
settings.filterOrder = 4;

% Invert ECG: set to true if R waves point DOWNWARD on this tag. The script
%   prints a suggestion each run. Only the filtered copy used for detection
%   is flipped; the raw ECG is never changed.
settings.invertECG = true;

% Show the filter check plot (depth, raw ECG, filtered ECG). Set to false
%   once the values above are settled, to skip it.
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

% --- Check plot: depth, raw ECG, and filtered ECG, linked in time
if settings.showFilterCheck
    tCrop = data.Time;
    filterFig = figure('Name', 'Filter check: depth, raw ECG, filtered ECG', ...
        'NumberTitle', 'off', 'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);
    axD = axes(filterFig, 'Position', [0.07 0.83 0.9 0.12]);     % thin depth strip
    axR = axes(filterFig, 'Position', [0.07 0.455 0.9 0.355]);   % raw ECG
    axF = axes(filterFig, 'Position', [0.07 0.08 0.9 0.355]);    % filtered ECG

    hD = plot(axD, NaN, NaN, 'b');
    hR = plot(axR, NaN, NaN, 'Color', [0.8 0 0]);   % raw ECG: red
    hF = plot(axF, NaN, NaN, 'k');                   % filtered ECG: black
    set(axD, 'YDir', 'reverse');
    ylabel(axD, 'Depth (m)');
    ylabel(axR, 'Raw ECG');
    ylabel(axF, 'Filtered ECG');
    xlabel(axF, 'Time (s)');
    grid(axD, 'on'); grid(axR, 'on'); grid(axF, 'on');
    title(axD, sprintf('Filter check: %g-%g Hz band-pass, order %d, inverted: %s', ...
        settings.highPassHz, settings.lowPassHz, settings.filterOrder, ...
        mat2str(settings.invertECG)));

    linkaxes([axD axR axF], 'x');
    axD.XTickLabel = {};                    % time labels only on the bottom panel
    axR.XTickLabel = {};
    setTimeOnlyNavigation(filterFig, [axD axR axF]);   % zoom/pan change time only
    keepYFitted(axD, hD);                   % always refit y to the visible trace
    keepYFitted(axR, hR);
    keepYFitted(axF, hF);
    set(axF, 'XLim', [tCrop(1) tCrop(end)]);
    sigs = {data.Depth, data.ECG, data.ECG_filtered};
    addlistener(axF, 'XLim', 'PostSet', ...
        @(~, ~) refreshTraces(axF, [hD hR hF], tCrop, sigs, fs));
    refreshTraces(axF, [hD hR hF], tCrop, sigs, fs);    % first draw
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

% --- Detection window: thin depth strip + filtered ECG with red circles
if isempty(beats)
    markerOffset = 0;
else
    markerOffset = 0.15 * median(beats.Prominence);   % circles sit just above each peak
end
beatY = beats.Height + markerOffset;

detectFig = figure('Name', 'Automatic R-wave detection', 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);
detAxDepth = axes(detectFig, 'Position', [0.07 0.84 0.9 0.11]);   % thin depth strip
detAxECG   = axes(detectFig, 'Position', [0.07 0.08 0.9 0.73]);   % filtered ECG

detDepth = plot(detAxDepth, NaN, NaN, 'b');
detECG   = plot(detAxECG,   NaN, NaN, 'k');
hold(detAxECG, 'on');
detBeats = plot(detAxECG, beats.Time, beatY, 'o', 'LineStyle', 'none', ...
    'MarkerSize', 6, 'MarkerFaceColor', [0.85 0 0], 'MarkerEdgeColor', [0.85 0 0]);
hold(detAxECG, 'off');

set(detAxDepth, 'YDir', 'reverse');
ylabel(detAxDepth, 'Depth (m)');
ylabel(detAxECG, 'Filtered ECG');
xlabel(detAxECG, 'Time (s)');
grid(detAxDepth, 'on'); grid(detAxECG, 'on');
title(detAxDepth, sprintf(['Automatic detection: %d beats  |  stands-out >= %g, ' ...
    'steepness >= %g, width <= %g ms, max HR %g bpm, oversized > %gx removed'], ...
    height(beats), settings.minStandOut, settings.minSteepness, ...
    settings.maxWidthMs, settings.maxHR, settings.maxRelSize));

linkaxes([detAxDepth detAxECG], 'x');
detAxDepth.XTickLabel = {};                % time labels only on the bottom panel
setTimeOnlyNavigation(detectFig, [detAxDepth detAxECG]);
keepYFitted(detAxDepth, detDepth);
keepYFitted(detAxECG, [detECG detBeats]);  % fit the trace AND the red circles
set(detAxECG, 'XLim', [t(1) t(end)]);
sigsDet = {data.Depth, data.ECG_filtered};
addlistener(detAxECG, 'XLim', 'PostSet', ...
    @(~, ~) refreshDetection(detAxECG, [detDepth detECG], detBeats, t, sigsDet, fs));
refreshDetection(detAxECG, [detDepth detECG], detBeats, t, sigsDet, fs);   % first draw









%% ---- REVIEW: EDIT BEATS AND MARK BREAKS -----------------------------------
% Interactive review of the detected beats. This is where beats are locked in.
% Every edit is saved automatically to <deployment>_Heartbeats.csv in the
% Processed folder. If that file is open in Excel, the save is blocked and
% a warning appears: close it in Excel, and your edits are saved with the
% next edit (or when the review window closes).
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
%   Done button (or close)      -> finish the review (saves one last time)
%   New markers snap to the highest point of the filtered ECG near the click.
%   NOTE: MATLAB treats a RIGHT click the same as Ctrl + click (adds a red x)
%   and a MIDDLE click the same as Shift + click (adds a green circle).

% SAVING
%   Every edit is saved immediately to <deployment>_Heartbeats.csv in the
%   Processed folder, with columns: Time, Certainty, NoPriorBeat,
%   RRInterval, HeartRate. Nothing is lost if MATLAB closes unexpectedly.
%   If that file already exists when the script runs, a popup offers:
%     Continue review - reopen the saved beats and keep editing
%     View only       - reopen the saved beats with editing switched off
%     Start over      - replace them with the automatic detections
%                       (asks to confirm first; the file is overwritten)

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
    'settings.tagOffTime', 'settings.ecgChannel', 'settings.depthChannel', ...
    'settings.highPassHz', 'settings.lowPassHz', 'settings.filterOrder', ...
    'settings.invertECG', 'settings.minStandOut', 'settings.minSteepness', ...
    'settings.maxWidthMs', 'settings.noiseWindowS', 'settings.maxHR', ...
    'settings.maxRelSize', 'settings.nNeighbors', 'settings.minHR', ...
    'settings.breakFactor', 'settings.breakNeighbors', 'Notes'};
recVals  = {settings.species, settings.deployment, settings.rawFile, tagOn, ...
    tagOff, settings.ecgChannel, settings.depthChannel, ...
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
    old       = readcell(settingsFile, 'Delimiter', ',');
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
        ref       = readcell(referenceFile, 'Delimiter', ',');
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
    fprintf('Starting review from %d automatic detections (%d pre-placed x''s).\n', ...
        numel(bTime), sum(bNoPrior));
else
    saved    = readtable(reviewFile);
    bTime    = saved.Time;
    bCert    = saved.Certainty;
    bNoPrior = saved.NoPriorBeat == 1;
    fprintf('Loaded saved review (%d beats): %s\n', numel(bTime), reviewFile);
end

% ---- Review window: thin depth strip + filtered ECG with markers ----------
reviewFig  = figure('Name', ['Review: ' settings.deployment], 'NumberTitle', 'off', ...
    'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);
revAxDepth = axes(reviewFig, 'Position', [0.07 0.76 0.9 0.11]);   % room above for instructions
revAxECG   = axes(reviewFig, 'Position', [0.07 0.08 0.9 0.65]);

revDepth = plot(revAxDepth, NaN, NaN, 'b');
revECG   = plot(revAxECG,   NaN, NaN, 'k');
hold(revAxECG, 'on');
revRed   = plot(revAxECG, NaN, NaN, 'o', 'LineStyle', 'none', 'MarkerSize', 7, ...
    'MarkerFaceColor', [0.85 0 0], 'MarkerEdgeColor', [0.85 0 0]);
revGreen = plot(revAxECG, NaN, NaN, 'o', 'LineStyle', 'none', 'MarkerSize', 7, ...
    'MarkerFaceColor', [0 0.6 0], 'MarkerEdgeColor', [0 0.6 0]);
revX     = plot(revAxECG, NaN, NaN, 'x', 'LineStyle', 'none', 'MarkerSize', 11, ...
    'LineWidth', 2, 'Color', [0.85 0 0]);
hold(revAxECG, 'off');
set([revECG revRed revGreen revX], 'PickableParts', 'none');   % clicks go to the panel itself
revSel = patch(revAxECG, NaN(4, 1), NaN(4, 1), [0.3 0.5 1], ...   % selection band, hidden until used
    'FaceAlpha', 0.2, 'EdgeColor', 'none', 'PickableParts', 'none');

set(revAxDepth, 'YDir', 'reverse');
ylabel(revAxDepth, 'Depth (m)');
ylabel(revAxECG, 'Filtered ECG');
xlabel(revAxECG, 'Time (s)');
grid(revAxDepth, 'on'); grid(revAxECG, 'on');
linkaxes([revAxDepth revAxECG], 'x');
revAxDepth.XTickLabel = {};
setTimeOnlyNavigation(reviewFig, [revAxDepth revAxECG]);
revAxDepth.Interactions = [];               % MATLAB's own mouse tools are off here;
revAxECG.Interactions   = [];               % dragging and scrolling are handled below
keepYFitted(revAxDepth, revDepth);
keepYFitted(revAxECG, [revECG revRed revGreen revX]);

% --- Everything the mouse/key functions need, stored inside the figure
R.axDepth  = revAxDepth;
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
R.undo     = {};                           % previous states, for Z (undo)
R.viewOnly = viewOnly;
R.file     = reviewFile;
R.snapN    = round(settings.snapMs / 1000 * fs);    % snap distance in samples
R.tolPx    = settings.clickTolerancePx;
R.downPos  = [];
R.downType = '';
R.downXLim = [];
R.downX    = [];                           % time under the pointer when pressed
R.hSel     = revSel;                       % the selection band
R.selRange = [];                           % selected time span [start end], empty if none
reviewFig.UserData = R;

% --- Connect the mouse, keys and Done button
reviewFig.WindowButtonDownFcn   = @(~, ~) reviewMouseDown(reviewFig);
reviewFig.WindowButtonMotionFcn = @(~, ~) reviewMouseMove(reviewFig);   % drag to move in time
reviewFig.WindowButtonUpFcn     = @(~, ~) reviewMouseUp(reviewFig);
reviewFig.WindowScrollWheelFcn  = @(~, evt) reviewScroll(reviewFig, evt);   % scroll to zoom in time
reviewFig.WindowKeyPressFcn = @(~, evt) reviewKey(reviewFig, evt);
uicontrol(reviewFig, 'Style', 'pushbutton', 'String', 'Done', ...
    'Units', 'normalized', 'Position', [0.89 0.005 0.08 0.04], ...
    'Callback', @(~, ~) uiresume(reviewFig));

% --- First draw, starting at the beginning of the tag-on period
sigsRev = {data.Depth, data.ECG_filtered};
addlistener(revAxECG, 'XLim', 'PostSet', @(~, ~) refreshDetection(revAxECG, ...
    [revDepth revECG], [revRed revGreen revX], data.Time, sigsRev, fs));
set(revAxECG, 'XLim', [data.Time(1), ...
    min(data.Time(end), data.Time(1) + settings.reviewWindowS)]);
if startFresh && ~viewOnly
    afterEdit(reviewFig);                  % applies first-beat x and saves the CSV
else
    drawReviewMarkers(reviewFig);
end

reviewFig.CloseRequestFcn = @(~, ~) closeReview(reviewFig);   % closing with X saves first
uiwait(reviewFig);                         % wait here until Done (or window closed)
if isvalid(reviewFig), closeReview(reviewFig); end            % Done: save, then close
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
title(S.axDepth, sprintf('Click on the plot to set TAG %s', upper(which)));
[x, ~] = ginput(1);                       % wait for one click
i = round((x - S.t(1)) * S.fs) + 1;       % snap to the nearest sample
i = min(max(i, 1), numel(S.t));
S.(['tag' which]) = S.t(i);               % stores in S.tagOn or S.tagOff
overviewFig.UserData = S;
drawTagLines(overviewFig);
title(S.axDepth, 'Zoom/pan to find tag on/off, then use the buttons below');
end

function drawTagLines(overviewFig)
% Draws green (tag on) and red (tag off) vertical lines on both panels.
S = overviewFig.UserData;
delete(findobj(overviewFig, 'Tag', 'tagLine'));   % remove old lines
for ax = [S.axDepth, S.axECG]
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
    fitYAxis(hLines(k).Parent, yy);       % fit this panel to what is visible
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

R.undo{end + 1} = {R.time, R.cert, R.noPrior};          % remember state for undo
if numel(R.undo) > 200, R.undo(1) = []; end

pos = getpixelposition(ax);
tol = R.tolPx * diff(ax.XLim) / pos(3);                 % click tolerance in seconds
[dist, k] = min(abs(R.time - xc));                      % nearest marker
if ~isempty(dist) && dist <= tol
    % --- Clicked ON a marker: remove it
    R.time(k) = [];  R.cert(k) = [];  R.noPrior(k) = [];
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
    [R.time, order] = sort(R.time);                     % keep beats in time order
    R.cert    = R.cert(order);
    R.noPrior = R.noPrior(order);
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
        [R.time, R.cert, R.noPrior] = deal(R.undo{end}{:});   % restore previous state
        R.undo(end) = [];
        fig.UserData = R;
        afterEdit(fig);
        return
    case {'delete', 'backspace'}
        if R.viewOnly || isempty(R.selRange), return; end
        inSel = R.time >= R.selRange(1) & R.time <= R.selRange(2);   % markers in the span
        if any(inSel)
            R.undo{end + 1} = {R.time, R.cert, R.noPrior};           % one undo step
            if numel(R.undo) > 200, R.undo(1) = []; end
            R.time(inSel) = [];  R.cert(inSel) = [];  R.noPrior(inSel) = [];
            nextBeat = find(R.time > R.selRange(2), 1);              % first beat after the span
            if ~isempty(nextBeat), R.noPrior(nextBeat) = true; end   % becomes an x
        end
        R.selRange = [];
        fig.UserData = R;
        afterEdit(fig);                                              % save and redraw
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
% Runs after every change: first beat is always an x, then save and redraw.
R = fig.UserData;
if ~isempty(R.noPrior), R.noPrior(1) = true; end
fig.UserData = R;
saveReview(fig);
drawReviewMarkers(fig);
end

function saveReview(fig)
% Writes the heartbeat datasheet (CSV) unless in view-only mode. If the file
% cannot be written (usually because it is open in Excel), a warning is shown
% and the edits are kept in the window; they are saved with the next edit,
% or when the window is closed.
R = fig.UserData;
if R.viewOnly, return; end
try
    writetable(buildHeartbeatTable(R.time, R.cert, R.noPrior), R.file);
catch
    msg = sprintf(['Could not save:\n%s\n\nIs it open in Excel? Close it there.\n' ...
        'Your edits are kept and will be saved with your next edit.'], R.file);
    fprintf(2, '%s\n', msg);               % red text in the Command Window
    warndlg(msg, 'Could not save', 'modal');
end
end

function T = buildHeartbeatTable(time, cert, noPrior)
% The final datasheet: one row per beat.
%   RRInterval = time since the previous beat (s); NaN for x's
%   HeartRate  = 60 / RRInterval (bpm);          NaN for x's
if isempty(time)
    rr = zeros(0, 1);
else
    rr = [NaN; diff(time)];
    rr(noPrior) = NaN;
end
T = table(time, cert, double(noPrior), rr, 60 ./ rr, ...
    'VariableNames', {'Time', 'Certainty', 'NoPriorBeat', 'RRInterval', 'HeartRate'});
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
    line1 = 'VIEW ONLY - editing is switched off';
    line2 = 'Drag / scroll: move / zoom in time   |   Left / right arrows: move';
else
    line1 = ['Click: add red beat   |   Shift+click: add green (possible)   |   ' ...
        'Ctrl+click: add red x (no prior beat)   |   Click a marker: remove'];
    line2 = ['Drag / scroll: move / zoom   |   Shift+drag: select a span   |   ' ...
        'Arrows: move   |   Z: undo   |   Edits save automatically'];
end
counts = sprintf('Beats: %d   (red %d   |   green %d   |   x %d)', ...
    numel(R.time), sum(isRed), sum(isGreen), sum(isX));
if ~isempty(R.selRange)
    nSel   = sum(R.time >= R.selRange(1) & R.time <= R.selRange(2));
    counts = [counts sprintf('      >>  %d selected: Delete to remove, Esc to cancel', nSel)];
end
title(R.axDepth, {line1, line2, counts}, 'FontWeight', 'normal');
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
elseif ischar(v)
    txt = v;
else
    txt = '';                              % e.g. an empty cell read from a CSV
end
txt = strrep(strtrim(txt), ',', ';');
end


function closeReview(fig)
% Saves one last time (in case an earlier save failed), then closes the
% review window.
saveReview(fig);
delete(fig);
end