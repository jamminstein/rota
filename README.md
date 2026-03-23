# ROTA

*a chaotic motor instrument for monome norns + grid*

---

## Concept

Two ideas that shouldn't fit together, but do completely:

**Ciat-Lombarde / Benjolin rungler** -- a shift register that eats its own output. Clocked by two oscillators that are themselves modulated by the shift register. The system feeds back on itself, creating deterministic chaos: patterns that repeat but never quite the same way twice.

**Motor Synth MKII** -- eight DC motors spinning as oscillators. Pitch isn't a number -- it's a target that a physical object has to *arrive at*. Inertia is real. Acceleration and braking are real.

ROTA runs 8 motor voices -- each with its own mass, its own cogging friction -- and gives them targets determined by a self-modifying shift register. You're not sequencing notes. You're releasing a physical system into a harmonic space and watching it find its own equilibria.

---

## Sound Character

- **Multi-timbral oscillator**: each voice blends VarSaw and Pulse waveforms (osc mix), with variable pulse width, sub-oscillator one octave below, and FM for metallic/bell textures. Per-note timbre is driven by the rungler bits -- every note has a unique waveform character.
- **Rough but polished**: the wavefolder adds harmonics without aliasing; JPverb reverb trails everything into silk.
- **Radical and pleasing**: dissonances arise naturally from the rungler and resolve as motors arrive at new targets.
- **Organic**: amplitude cogging, phase noise, and per-voice inertia variation make every voice sound slightly alive.

---

## Controls

5 pages, navigated with E1.

### Page 1: MOTORS

| Control | Function |
|---------|----------|
| E2 | Density -- gate probability (how many voices sound per step) |
| E3 | Aggression -- brutality scaling (drive, grind, amp, dryness) |
| K2 | Short press: play/stop. Long press (>0.5s): cycle bandmate style |
| K3 | Randomize which voices are active |

### Page 2: RUNGLER

| Control | Function |
|---------|----------|
| E2 | Chaos -- rungler feedback depth. Low = orderly, high = volatile |
| E3 | Rungler speed -- clock rate multiplier (0.125x to 8x) |
| K2 | Short press: play/stop. Long press: cycle bandmate style |
| K3 | Reseed -- inject new random state into shift register + pitch offsets |

### Page 3: SPACE

| Control | Function |
|---------|----------|
| E2 | Reverb macro -- controls mix, time, and size together |
| E3 | Distortion macro -- controls drive, waveshape, and roughness together |
| K2 | Short press: play/stop. Long press: cycle bandmate style |
| K3 | Randomize timbre (waveshape, drive, roughness) |

Display shows reverb (mix/time/size), distortion (drive/shape/grind), FX send level, and oscillator mode (SAW/MIX/PLS).

### Page 4: CHAOS

| Control | Function |
|---------|----------|
| E2 | Chaos -- rungler feedback depth |
| E3 | Mass -- global motor inertia. Low = instant pitch snap, high = glacial slides |
| K2 | Short press: play/stop. Long press: cycle bandmate style |
| K3 | Toggle octave shift (-2 to +2) |

### Page 5: RHYTHM

| Control | Function |
|---------|----------|
| E2 | Cycle gate mode (FREE / PATTERN / EUCLID) |
| E3 | Mode-specific: FREE = density, PATTERN = rotate patterns, EUCLID = change hit count |
| K2 | Short press: play/stop. Long press: cycle bandmate style |
| K3 | Randomize gate patterns / euclidean parameters |

---

## Gate Modes

| Mode | Behavior |
|------|----------|
| **FREE** | Rungler bits determine which voices gate on each step. Density scales probability. This is the default chaos mode. |
| **PATTERN** | 8-step gate patterns per voice. Deterministic rhythms that interact with the rungler's note choices. |
| **EUCLID** | Euclidean rhythms per voice with adjustable hit count and rotation. Mathematical rhythmic structures. |

---

## Bandmate System

10 distinct performance styles that shape how the system evolves over time. Each style controls chaos sweeps, voice density, reverb breathing, topology mutations, timbre evolution, and reseed probability.

| Style | Character |
|-------|-----------|
| **DRIFT** | The meditator. Very slow evolution. Chaos 0.15-0.45. Voices turn on/off one at a time with long gaps. High reverb. The gentlest explorer. |
| **SURGE** | The crescendo builder. Gradually increases chaos from low to high, then pulls back suddenly. Creates natural swell-and-release forms. |
| **SWARM** | The density player. Rapidly toggles voices on/off in patterns. All 8 voices in play. Per-voice inertia varies wildly. Creates buzzing cloud textures. |
| **BLASSER** | Channels the Ciat-Lombarde spirit. High chaos (0.55-0.95). Topology mutations. Frequent reseeds. Quantize toggles on/off. True Benjolin behavior. |
| **GLACIAL** | The deep listener. Very high mass/inertia. Low chaos. Only 2-3 voices. Each note takes seconds to arrive. Reverb maxed. Time feels suspended. |
| **RUPTURE** | The disruptor. Sudden parameter jumps. Roughness spikes to max then drops. Voices slam on/off in groups. Controlled chaos bursts with silence between. |
| **STEREO** | The spatial architect. Voices move through stereo field in 5 phases: SPLIT, ARPEGGIO, CONVERGE, DIALOGUE, SWIRL. Moderate chaos, high density. |
| **CLOCKWORK** | The machine. Low mass for snappy attacks, high density, dry reverb. Precise rhythmic patterns. The most percussive style. |
| **FREERUN** | The drifter. Unquantized chaos with heavy mass. Notes float unmoored in reverb wash. No hurry. Scale changes more frequent. |
| **CONDUCTOR** | The orchestrator. Borrows behavior from other styles in planned multi-movement structures (exposition, development, transition, recapitulation, coda). Macro-level compositional form. |

---

## ARC Engine

An always-on progression intelligence that runs on top of any bandmate style. Creates macro-level song form with 8 phases:

INTRO -- BUILD -- DROP -- SUSTAIN -- BREAKDOWN -- TENSION -- CLIMAX -- EXHALE

Each phase has a target intensity and duration. Intensity modulates density, aggression, voice count, and reverb. The arc engine creates deliberate curves -- not random parameter changes, but planned journeys. On each new cycle, it may change scale and root for freshness. CLIMAX can shift octave up; BREAKDOWN brings it back down.

Toggle via PARAMS > ARC > arc engine.

---

## Presets

4 snapshot slots that save and recall all performance parameters (chaos, mass, roughness, density, aggression, reverb, drive, waveshape, fx send, osc mix, pulse width, sub level, FM amount, scale, root, rungler speed, octave shift).

Access via PARAMS > PRESETS.

---

## Grid Interface (16x8)

### Page 1: Motor Control

```
Row 1  [*][*][*][*][o][o][o][o]  Motor on/off (tap to toggle)
Row 2  [.][.][.][.][.][.][.][.]  Pitch offset from rungler (-12 to +12 semitones)
Row 3  [.][.][.][.][.][.][.][.]  Inertia per voice (6 levels, cycle with tap)
Row 4  [.][.][.][.][.][.][.][.]  Grind per voice (6 levels, cycle with tap)
Row 5  [~][~][~][~][~][~][~][~]  Rungler activity meter (animated, read-only)
Row 6  [~][~][~][~][~][~][~][~]  Rungler activity meter level 2
Row 7  [1][2][3][4][5][6][7]      Scale selection (minor/major/dorian/etc)
Row 8  [B][Q][1][2][3][4][5][6]  B=bandmate Q=quantize 1-6=style select
```

**Two-finger gesture on row 2**: hold one motor column and tap another to set a precise harmonic interval between them (in semitones).

### Page 2: Topology

```
Row 1  [.][.][.][.][.][.][.][.]  Rungler topology: which motors feed the shift register
Row 2  [.][.][.][.][.][.][.][.]  Current shift register bits (animated)
Row 3  [.][.][.][.][.][.][.][.]  Rungler output value meter
Row 4  [.][.][.][.][.][.][.][.]  Rungler clock speed (0.25x to 8x)
Row 7  [C][C#][D][D#][E][F]...    Scale root selection (chromatic)
Row 8  [<-]                       Back to page 1
```

**Topology** is the deepest control: toggle which motor voices contribute their state to the rungler's shift register clock. With all 8 feeding in, maximum chaotic interaction. With only 1-2, the system settles into loops and slow cycles.

---

## MIDI Out

ROTA doubles as a chaotic MIDI sequencer. When a motor voice gets a new target frequency, it sends MIDI note-on on the corresponding channel (voice 1 = channel 1, etc).

Configure via PARAMS > MIDI OUT:
- **midi out device**: select your MIDI output
- **midi base channel**: starting channel (voices map to consecutive channels)

---

## OP-XY MIDI Out

Dedicated OP-XY output with CC mapping:

| CC | Parameter |
|----|-----------|
| CC 74 | Filter cutoff (from chaos) |
| CC 11 | Expression (from density) |
| CC 91 | Reverb send (from rev_mix) |
| CC 1 | Mod wheel (from waveshape) |
| CC 71 | Resonance (from roughness) |

Per-voice notes on separate channels for polyphonic motor control.

---

## Robot Mod

ROTA includes a robot profile for the robot bandmate system. The profile maps all performance parameters with appropriate weights and sensitivities.

Primary levers: chaos (0.95), density (0.85), mass (0.8). Timbral controls: waveshape, osc mix, roughness, pulse width, sub level, FM amount, drive, fx send, reverb. Structural events (scale, bandmate style, arc engine, gate mode) are weighted low for rare dramatic shifts.

Copy the profile: `lib/profiles/rota.lua` to `~/dust/code/robot/lib/profiles/rota.lua`

---

## Params

| Param | Range | Default |
|-------|-------|---------|
| chaos | 0-1 | 0.4 |
| mass | 0-1.5 | 0.5 |
| roughness | 0-1 | 0.2 |
| density | 0-1 | 0.7 |
| aggression | 0-1 | 0.0 |
| osc mix | 0-1 | 0.0 (VarSaw) |
| pulse width | 0.01-0.99 | 0.5 |
| sub osc level | 0-1 | 0.0 |
| FM amount | 0-1 | 0.0 |
| waveshape | 0-1 | 0.45 |
| drive | 0-1 | 0.1 |
| fx send | 0-1 | 0.4 |
| reverb time | 0.5-12s | 3.0s |
| reverb mix | 0-1 | 0.35 |
| reverb size | 0.5-5 | 1.2 |
| scale | chromatic-phrygian | minor |
| root | C2-C4 | C2 (MIDI 36) |
| quantize | on/off | on |
| rungler speed | 0.125-8x | 1x |
| octave shift | -2 to +2 | 0 |
| gate mode | FREE/PATTERN/EUCLID | FREE |
| arc engine | on/off | off |
| bandmate style | DRIFT-CONDUCTOR | DRIFT |
| bandmate | on/off | off |
| midi out device | - | - |
| midi base channel | 1-16 | 1 |

---

## Installation

```
;install https://github.com/jamminstein/rota
```

Or manually:
1. Copy `rota/` folder to `~/dust/code/rota/`
2. The `lib/Engine_Rota.sc` file must be in `rota/lib/`
3. `SYSTEM > RESTART` on norns to compile the SuperCollider engine
4. Load `rota` from the SELECT menu

**Dependencies**: sc3-plugins must be installed on your norns (JPverb is in sc3-plugins/DEINDUGens). Most norns installations include sc3-plugins by default.

---

## Technical Architecture

```
Lua layer:
  Rungler (8-bit shift register, Lua-side simulation)
  | generates target frequencies (0..1 normalized)
  | maps to MIDI via scale quantization (musicutil)
  | sends to engine via engine.freq(voice, hz)
  | sends MIDI out on note change

  Per-note timbre (from rungler bits):
  | waveshape, inertia, grind, fx_send, phase_noise, amp_lag
  | osc_mix (saw vs pulse), pulse_width, sub_level, fm_amt
  | Each voice reads different register bits for independence

  Lattice (5 sprockets, prime-ratio divisions):
    1/8    -> rungler step + voice update (speed-accumulated)
    7/4    -> harmony/density/topology/reseed (bandmate)
    11/4   -> inertia breathing + param evolution (bandmate)
    13/4   -> reverb evolution (bandmate)
    1/32   -> screen animation

  Bandmate (10 styles):
    DRIFT / SURGE / SWARM / BLASSER / GLACIAL / RUPTURE
    STEREO / CLOCKWORK / FREERUN / CONDUCTOR
    Each defines: chaos/mass/roughness ranges, voice density,
    evolution speed, scale preference, reverb targets,
    reseed probability, topology mutation probability

  ARC engine (8-phase intensity curve):
    INTRO / BUILD / DROP / SUSTAIN / BREAKDOWN
    TENSION / CLIMAX / EXHALE
    Runs on top of bandmate style for macro-level form

SuperCollider engine (lib/Engine_Rota.sc):
  8x rota_motor SynthDefs:
    VarSaw + Pulse oscillator blend (osc_mix)
    Sub oscillator (one octave below)
    FM modulation (sine ratio)
    Lag.kr(targetFreq, inertia)      -> physical pitch inertia
    phaseNoise                       -> optical waveform imperfection
    LFNoise0.kr cogging              -> electromechanical amplitude texture
    .fold(-1,1).tanh                 -> wavefold + soft saturation

  rota_fx SynthDef:
    .tanh drive                      -> collective motor amp stage
    LPF rolloff                      -> tape warmth
    JPverb                           -> the reverb space
```

---

*ROTA is where the rungler and the motor meet.*
