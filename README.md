# Duatone

![Duatone screenshot](doc/cover.png)

Duatone is a two-voice tone generator for norns made for shaping Lissajous figures and oscilloscope motion. By default the voices are panned left and right, making it easy to view each waveform separately while dialing in phase and frequency relationships.

## Installation

Requires: norns

Install via Maiden or clone/download this repo to:

```sh
/home/we/dust/code/duatone
```

Restart norns after install so SuperCollider picks up `Engine_Duatone.sc`.

## Features

- Two independently shaped voices with per-side frequency, phase, waveform, and volume
- Four waveforms: `sine`, `square`, `triangle`, `saw`
- Per-side phase modulation with adjustable rate and span limits
- Shared sweep modes: `WRAP` and `PING-PONG`
- Seven presets tuned for Lissajous loops, knots, and geometric figures
- A focused screen layout that keeps the active side easy to read while editing

## Controls

- `E1`: step through the preset shapes
- `E2`: fine-tune the selected side's frequency
- `E3`: change the selected side's waveform
- tap `K2`: switch the selected side (`L` / `R`)
- hold `K2` + `E2`: coarse-tune the selected side's frequency
- hold `K2` + `E3`: adjust the selected side's volume
- tap `K3`: toggle phase modulation for the selected side
- hold `K3` + `E2`: disable modulation and set a manual phase

## Parameters

- Levels: `L volume`, `R volume`, `global volume`
- Modulation: `phase sweep`, `L mod rate`, `R mod rate`
- Modulation spans: `L mod span min`, `L mod span max`, `R mod span min`, `R mod span max`
- Stereo placement: `L pan`, `R pan`

By default the voices are hard-panned left and right for oscilloscope viewing and Lissajous shaping. Set both pan controls to `0` for dual-mono output.

## Presets

The presets recall waveform, frequency, and phase relationships for both sides as starting points for different Lissajous knots, loops, and geometric figures. Volume, pan, modulation depth, and sweep settings remain open for performance and refinement.

- `OVAL`
- `FIGURE8`
- `TREFOIL`
- `TRIKNOT`
- `ORBIT`
- `DRIFT`
- `ROSETTE`
