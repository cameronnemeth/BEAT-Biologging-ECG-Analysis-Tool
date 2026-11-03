# **Heartbeat Detector Script**
A private repository for HeartbeatDetector.m and associated files.  

This script was designed to process ECG data from animal-borne tags: detecting
heartbeats (R waves) semi-automatically, reviewing and correcting them manually, and
producing a table of beat times, RR intervals and instantaneous heart rates. It was built so that
data are easy both to process and to review and edit afterwards, whether by the original processor
or by someone else.

The script is free to use but runs in MATLAB, which requires a license, plus MATLAB’s
Signal Processing Toolbox. It was tested in MATLAB R2026a (Update 5). At a minimum, the
script needs a plain-text data file (e.g. .txt or .csv) containing a column of ECG values, plus
either a time column (in seconds) or a known sampling rate. Depth and acceleration can also be
included and are displayed alongside the ECG.

In brief, the script: (1) imports the data; (2) crops it to the period the tag was on the
animal; (3) filters the ECG; (4) automatically detects candidate heartbeats; and (5) opens an
interactive window to review and edit them, saving the results and the settings used.

# Usage
To begin using the program, download the script and protocol and place them inside of a folder where you will host all of your ECG tag deployments. 
The protocol PDF in this repository is designed to take you through the script, step by step. 
To make sure your folder structure is correctly set up for the script to run, see the example folder tree below with three example tag deployments (e.g., gm240124-C1).
If those pieces are in place, you should be ready to click "Run" in MATLAB and move through the program! 

```text
HeartRate/
│
├── BEAT.m
├── BEAT_Protocol.pdf
│
├── bb260613-A2/
│   └── Data/
│       └── Raw/
│           └── bb260613-A2.txt
│
├── gm240124-C1/
│   └── Data/
│       └── Raw/
│           └── gm240124-C1.txt
│
└── mn250303-H4/
    └── Data/
        └── Raw/
            └── mn250303-H4.txt
```

