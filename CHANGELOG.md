# Changelog

All notable changes to BEAT (Biologging ECG Analysis Tool) are listed here,
newest first. Dates are day-month-year.

## [4.1] – 03-11-2026

### Changed
- Renamed from `HeartbeatDetector.m` to `BEAT.m` (Biologging ECG Analysis
  Tool). Output file names (`_Heartbeats.csv`, `_Settings.csv`, the
  `HeartRate_*.csv` sheets) are unchanged, so existing deployments still work.

## [4.0] – 01-11-2026

### Changed
- Press Run (F5) and the script guides you through every step; each window
  waits for you (Continue / Apply & continue). Running section by section
  still works but is no longer needed.
- Nothing needs to be typed into the script: a setup window replaces the
  typed SETTINGS block.

### Added
- Start popup: **New deployment** or **Existing deployment**
  (`run.mode = 'ask'`; set `'new'` or `'existing'` to skip the popup).
- **Setup window** (new deployments): choose the deployment folder, raw data
  file (listed from the Raw folder), species (existing spellings reused) and
  columns (dropdowns with best guesses), with a preview of 20 rows at each of
  20 points through the file. Pre-filled from the settings sheet if the
  folder was processed before.
- **Existing-deployment mode** (continue a first pass, or review): pick the
  folder; every setting is read from its settings sheet; the overview,
  tuning windows and detection are skipped; the review opens with Continue
  review or View only (no Start over, so saved work can't be overwritten by
  accident).
- Overview: tag on/off can be typed or clicked on the plot.
- **Filter tuning window** (replaces the filter check plot): live re-filtering
  of the whole deployment, a short description, typical range and
  species range for each value, polarity check, Reset, Apply & continue.
- **Detection tuning window** (replaces the detection window): the same, for
  the detection values, with beat counts and heart rate shown.
- Starting values for new deployments come from the deployment's own
  settings sheet, otherwise the most recently processed deployment of the
  same species, otherwise the script defaults (the windows say which).
- Review: **Change filter…** button to view the data with a different filter
  (beats stay put; unsaved edits are kept), with the option to record the
  new filter in the settings sheets.
- Review: settings panel on the right with **Breaks** (Min heart rate,
  recorded in the settings sheets) and **Preferences** (snap distance, click
  tolerance, marker gap, window length; saved per user on that computer,
  never in the shared sheets).
- Review: any beat after a gap longer than the Min heart rate allows becomes
  an x after every edit and when a saved review reopens (only adds x's,
  never removes them).
- Review: **checkpoint popup** when a saved review opens, showing where an
  unfinished first pass or review was left off (by whom, when, and at what
  time), with a Go button to jump there.

### Changed (review)
- Marker placement is now a "Marker gap": a percentage of the on-screen plot
  height, so markers look the same at any zoom level.
- "Save & finish" button renamed "Save & finish session".
- Wider typical ranges: stands-out 3–30, steepness 3–20.

### Internal
- Filtering and detection moved into functions (results checked identical to
  version 3.3); reading the top of the raw file is shared by the setup
  window and the import.

## [3.3] – 31-10-2026

### Fixed
- `HeartRate_Progress.csv` lost the ProcessedDate / ReviewDate of other
  deployments whenever a new session was recorded. Dates are now kept as
  text, so existing dates are preserved.

### Added
- New sheet `HeartRate_Deployment_Information.csv` in the project folder:
  one row per deployment, refreshed after every save. Includes completion
  status, tag on/off and duration, numbers of beats (all / certain /
  possible), segments and RR intervals, segment duration and beats per
  segment, PercentCleanECG, heart rate (mean, median, SD), last updated and
  comments. Summary values are written with two decimal places.

### Changed
- Clearer Command Window message after clicking tag on/off.

## [3.1] – 28-10-2026

Tested in MATLAB R2026a. Version described in the first user protocol.

- Accepts three kinds of raw text file: LabChart "Export As Text", a file
  with one row of column names, or numbers only; tab, comma or space
  separated.
- Columns for time, ECG, depth and acceleration chosen by name or number;
  depth and acceleration optional; sampling rate entered if there is no
  time column.
- Optional acceleration strip (display only) above the depth strip.
- Fast-loading `.mat` copy of the import, rebuilt automatically if the raw
  file or column settings change.
- Settings used are recorded in `<deployment>_Settings.csv` and
  `HeartRate_Reference_Settings.csv`; a popup lists any differences when a
  deployment is rerun.
- Review window: add/remove certain (red), possible (green) and no-prior-beat
  (x) markers; Shift+drag to select and delete a span; undo (Z); per-beat
  comments (C); colour-coded Save button; Save & finish records progress in
  `HeartRate_Progress.csv`.
- Output `<deployment>_Heartbeats.csv`: Time, Certainty, NoPriorBeat,
  RRInterval, HeartRate, Segment, Comment.

## Earlier versions – September–October 2026

Initial development on a pilot whale deployment (LabChart export): portable
project-folder paths, import, overview plot with tag on/off, band-pass
filtering, automatic R-wave detection, and the interactive review window.
