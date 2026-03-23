# ROTA

*a chaotic motor instrument for monome norns + grid*

---

## Concept

Two ideas that shouldn't fit together, but do completely:

**Ciat-Lombarde / Benjolin rungler** -- a shift register that eats its own output. Clocked by two oscillators that are themselves modulated by the shift register. The system feeds back on itself, creating deterministic chaos: patterns that repeat but never quite the same way twice.

**Motor Synth MKII** -- eight DC motors spinning as oscillators. Pitch isn't a number -- it's a target that a physical object has to *arrive at*. Inertia is real. Acceleration and braking are real. The electromagnetic pickup produces a waveform that no digitally designed oscillator has ever made.

ROTA is what happens when you run 8 motor voices -- each with its own mass, each with its own cogging friction -- and give them targets determined by a self-modifying shift register. You're not sequencing notes. You're releasing a physical system into a harmonic space and watching it find its own equilibria.

---

## Sound Character

- **Rough but polished**: the wavefolder adds harmonics without aliasing; the JPverb reverb trails everything into silk
- **Radical and pleasing**: dissonances arise naturally from the rungler and resolve as motors arrive at new targets
- **Organic**: amplitude cogging, phase noise, and per-voice inertia variation make every voice sound slightly alive

---

## Controls

| Control | Function |
|---------|----------|
| **ENC1** | Chaos -- rungler feedback depth. Low = orderly patterns, high = volatile chaos |
| **ENC2** | Mass -- global motor inertia. Low = instant pitch snap, high = slow glacial movement |
| **ENC3** | Roughness -- electromechanical grit. Low = clean, high = cogged and industrial |
| **KEY2** | Tap: toggle bandmate on/off. Hold (>0.5s): cycle bandmate style |
| **KEY3** | Reseed -- inject new random state into the rungler + randomize pitch offsets |

---

## Bandmate System

ROTA's bandmate replaces the old auto mode with 6 distinct performance styles. Each style shapes how the system evolves over time -- chaos sweeps, voice density, reverb breathing, topology mutations, and reseed probability.

| Style | Character |
|-------|-----------|
| **DRIFT** | The meditator. Very slow evolution. Chaos 0.2-0.5. Voices turn on/off one at a time with long gaps. High reverb. The gentlest explorer. |
| **SURGE** | The crescendo builder. Gradually increases chaos from low to high over ~30-60 seconds, then pulls back suddenly. Creates natural swell-and-release forms. |
| **SWARM** | The density player. Rapidly toggles voices on/off in patterns. All 8 voices in play. Per-voice inertia varies wildly. Creates buzzing cloud textures. |
| **BLASSER** | Channels the Ciat-Lombarde spirit. High chaos (0.6-0.9). Topology mutations. Frequent reseeds. Quantize toggles on/off. True Benjolin behavior. |
| **GLACIAL** | The deep listener. Very high mass/inertia. Low chaos. Only 2-3 voices. Each note takes seconds to arrive. Reverb maxed. Time feels suspended. |
| **RUPTURE** | The disruptor. Sudden parameter jumps. Roughness spikes to max then drops. Voices slam on/off in groups. Controlled chaos bursts with silence between. |

---

## MIDI Out

ROTA doubles as a chaotic MIDI sequencer. When a motor voice gets a new target frequency, it sends MIDI note-on on the corresponding channel (voice 1 = channel 1, etc).

Configure via PARAMS > MIDI OUT:
- **midi out device**: select your MIDI output
- **midi base channel**: starting channel (voices map to consecutive channels)

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

## PARAMS Menu

| Param | Range | Default |
|-------|-------|---------|
| chaos | 0-1 | 0.4 |
| mass | 0-1.5 | 0.5 |
| roughness | 0-1 | 0.2 |
| reverb time | 0.5-12s | 3.0s |
| reverb mix | 0-1 | 0.35 |
| reverb size | 0.5-5 | 1.2 |
| scale | chromatic-phrygian | minor |
| root | C2-C4 | C2 |
| quantize | on/off | on |
| rungler speed | 0.125-8x | 1x |
| bandmate style | DRIFT-RUPTURE | DRIFT |
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

**Robot mod**: Copy the profile from `lib/profiles/rota.lua` to `~/dust/code/robot/lib/profiles/rota.lua` for bandmate integration.

---

## Technical Architecture

```
Lua layer:
  Rungler (8-bit shift register, Lua-side simulation)
  | generates target frequencies (0..1 normalized)
  | maps to MIDI via scale quantization (musicutil)
  | sends to engine via engine.freq(voice, hz)
  | sends MIDI out on note change

  Lattice (5 sprockets, prime-ratio divisions):
    1/8    -> rungler step + voice update (speed-accumulated)
    7/4    -> harmony/density/topology/reseed (bandmate)
    11/4   -> inertia breathing + param evolution (bandmate)
    13/4   -> reverb evolution (bandmate)
    1/32   -> screen animation

  Bandmate (6 styles):
    DRIFT / SURGE / SWARM / BLASSER / GLACIAL / RUPTURE
    Each defines: chaos/mass/roughness ranges, voice density,
    evolution speed, scale preference, reverb targets,
    reseed probability, topology mutation probability

SuperCollider engine (lib/Engine_Rota.sc):
  8x rota_motor SynthDefs:
    Lag.kr(targetFreq, inertia)      -> physical pitch inertia
    VarSaw.ar + phaseNoise           -> optical waveform imperfection
    LFNoise0.kr cogging              -> electromechanical amplitude texture
    .fold(-1,1).tanh                 -> wavefold + soft saturation

  rota_fx SynthDef:
    .tanh drive                      -> collective motor amp stage
    LPF rolloff                      -> tape warmth
    JPverb                           -> the reverb space
```

---

## Aesthetic Notes

The reverb is intentionally long. ROTA is not a percussive instrument -- it's a drone system that breathes. The motors spin up, find frequency, beat against each other in natural unison drift, and tail off into JPverb's wash.

The chaos parameter is musical, not random. At 0.2-0.4, the rungler settles into long cycles that feel composed. At 0.7+, it becomes genuinely unpredictable. The sweet spot for "radical and pleasing" is 0.35-0.55 with moderate mass (0.4-0.6) and low roughness (0.1-0.25).

---

*ROTA is where the rungler and the motor meet.*
