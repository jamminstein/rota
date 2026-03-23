// Engine_Rota.sc
// A Ciat-Lombarde rungler + Motor Synth inertia engine for norns
// Two oscillators cross-modulate a shift register (the Rungler).
// The Rungler output drives up to 8 "motor" voices — oscillators
// with physical inertia (Lag), electromagnetic cogging noise,
// and an optical waveshaper that imposes asymmetric distortion.
//
// Sound philosophy:
//   - Rough like an electric motor vibrating at resonance
//   - Polished like the Meris Mercury7 trailing its decay into silence
//   - Deterministic chaos: the same patch never repeats, never collapses
//
// NOTE: The \rota_rungler SynthDef has been removed.
// All rungler logic is implemented Lua-side for maximum control
// and visibility (lattice-driven shift register, topology mutation,
// bandmate style integration). The SC engine is purely a sound
// generator: 8 motor voices + FX bus. The Lua rungler feeds target
// frequencies to the motors via the engine.freq() command.

Engine_Rota : CroneEngine {

  var <synths;          // array of 8 motor voice synths
  var <fxSynth;         // reverb + saturation bus synth
  var <fxBus;           // audio bus for FX chain
  var voiceGroup;
  var fxGroup;

  *new { arg context, doneCallback;
    ^super.new(context, doneCallback);
  }

  alloc {
    var s = Server.default;

    fxBus = Bus.audio(s, 2);

    // ---------------------------------------------------------------
    // MOTOR VOICE SynthDef
    // Each voice is an oscillator whose pitch chases a target with
    // physical inertia (Lag). Timbre comes from:
    //   - VarSaw (the optical waveform: imperfect, slightly triangular)
    //   - Cogging noise: LFNoise0 at low freq multiplies amplitude
    //   - Electromagnetic roughness: phase noise via LFNoise2
    //   - A soft wavefolder that adds harmonic grit without aliasing
    // ---------------------------------------------------------------
    SynthDef(\rota_motor, {
      arg out=0, fxBus=0,
          targetFreq=110, inertia=0.5,
          amp=0.0, ampLag=0.08,
          grind=0.2, phaseNoise=0.01,
          waveshape=0.5,
          fxSend=0.4,
          pan=0.0;

      var freq, phaseMod, sig, cogging, env;

      // Physical inertia: pitch slides to target with lag
      // inertia 0.0 = instant snap, 1.5 = very heavy/slow
      freq = Lag.kr(targetFreq, inertia);

      // Electromagnetic phase noise (brush contact irregularity)
      phaseMod = LFNoise2.ar(freq * 0.03) * (freq * phaseNoise * 0.5);

      // VarSaw: width modulated slowly = optical disc imperfection
      // waveshape 0=saw, 0.5=triangle-ish, 1=reverse saw
      sig = VarSaw.ar(freq + phaseMod, 0,
        waveshape + (LFNoise1.kr(0.7) * 0.08));

      // Cogging noise: low-freq amplitude flutter (motor teeth)
      // Creates the characteristic "roughness" at low RPM
      cogging = 1 - (grind * LFNoise0.kr(freq * 0.12).range(0, 1));
      sig = sig * cogging;

      // Soft wavefold: adds upper harmonics without hard clipping
      // This is the "polished grit" — warm distortion, not digital
      sig = (sig * (1 + (grind * 2))).fold(-1, 1);
      sig = sig.tanh * 0.7; // final soft saturation

      // Amplitude with lag (smooth on/off like a motor spinning up)
      env = Lag.kr(amp, ampLag);
      sig = sig * env;

      // Stereo width via panning per voice
      sig = Pan2.ar(sig, pan);

      // Send to dry output and FX bus
      Out.ar(out, sig * (1 - fxSend));
      Out.ar(fxBus, sig * fxSend);

    }).add;

    // ---------------------------------------------------------------
    // FX BUS SynthDef
    // The output of all voices passes through:
    //   1. Gentle drive/saturation (the motor amp stage)
    //   2. JPverb reverb (the mercury7 space)
    //   3. Subtle tape roll-off (anti-alias warmth)
    // ---------------------------------------------------------------
    SynthDef(\rota_fx, {
      arg in=0, out=0,
          drive=0.15,
          revSize=1.2, revT60=3.0, revDamp=0.5,
          revMix=0.35,
          rolloff=8000;

      var sig, wet;

      sig = In.ar(in, 2);

      // Drive stage: warms up the motor voices collectively
      sig = (sig * (1 + drive)).tanh;

      // High-frequency rolloff (tape machine warmth)
      sig = LPF.ar(sig, rolloff);

      // JPverb: the reverb of choice for norns (sc3-plugins)
      wet = JPverb.ar(sig,
        t60: revT60,
        damp: revDamp,
        size: revSize,
        earlyDiff: 0.72,
        modDepth: 0.05,
        modFreq: 0.5
      );

      Out.ar(out, XFade2.ar(sig, wet, revMix * 2 - 1));

    }).add;

    s.sync;

    // ---------------------------------------------------------------
    // Instantiate the synths in proper group order
    // ---------------------------------------------------------------
    voiceGroup = Group.new(context.xg);
    fxGroup    = Group.after(voiceGroup);

    fxSynth = Synth(\rota_fx, [
      \in,      fxBus.index,
      \out,     context.out_b,
      \drive,   0.15,
      \revSize, 1.2,
      \revT60,  3.0,
      \revDamp, 0.5,
      \revMix,  0.35,
      \rolloff, 8000
    ], fxGroup);

    // Create 8 motor voices, initially silent
    synths = Array.new(8);
    8.do { |i|
      var pan = (i / 7.0 * 2) - 1; // spread -1 to +1
      synths.add(
        Synth(\rota_motor, [
          \out,        context.out_b,
          \fxBus,      fxBus.index,
          \targetFreq, 55 * (i + 1).sqrt, // harmonic-ish spacing
          \inertia,    0.3 + (i * 0.08),  // each motor has own physics
          \amp,        0.0,
          \grind,      0.15,
          \phaseNoise, 0.01,
          \waveshape,  0.45,
          \fxSend,     0.4,
          \pan,        pan * 0.7
        ], voiceGroup)
      );
    };

    // ---------------------------------------------------------------
    // ENGINE COMMANDS — all parameters accessible from Lua
    // ---------------------------------------------------------------

    // Per-voice frequency target (inertia engine will chase it)
    this.addCommand("freq", "if", { |msg|
      var idx = msg[1].clip(0, 7);
      synths[idx].set(\targetFreq, msg[2]);
    });

    // Per-voice amplitude
    this.addCommand("amp", "if", { |msg|
      var idx = msg[1].clip(0, 7);
      synths[idx].set(\amp, msg[2]);
    });

    // Per-voice inertia (0=instant, 1.5=very slow)
    this.addCommand("inertia", "if", { |msg|
      var idx = msg[1].clip(0, 7);
      synths[idx].set(\inertia, msg[2]);
    });

    // Global grind (electromechanical roughness 0..1)
    this.addCommand("grind", "f", { |msg|
      synths.do { |s| s.set(\grind, msg[1]) };
    });

    // Per-voice grind
    this.addCommand("grind_v", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\grind, msg[2]);
    });

    // Global waveshape (0=saw, 0.5=tri-ish, 1=inv saw)
    this.addCommand("waveshape", "f", { |msg|
      synths.do { |s| s.set(\waveshape, msg[1]) };
    });

    // Global phase noise (electromagnetic texture)
    this.addCommand("phase_noise", "f", { |msg|
      synths.do { |s| s.set(\phaseNoise, msg[1]) };
    });

    // FX: reverb mix
    this.addCommand("rev_mix", "f", { |msg|
      fxSynth.set(\revMix, msg[1]);
    });

    // FX: reverb time
    this.addCommand("rev_time", "f", { |msg|
      fxSynth.set(\revT60, msg[1]);
    });

    // FX: reverb size
    this.addCommand("rev_size", "f", { |msg|
      fxSynth.set(\revSize, msg[1]);
    });

    // FX: drive (global saturation)
    this.addCommand("drive", "f", { |msg|
      fxSynth.set(\drive, msg[1]);
    });

    // FX: high frequency rolloff
    this.addCommand("rolloff", "f", { |msg|
      fxSynth.set(\rolloff, msg[1]);
    });

    // FX send per voice
    this.addCommand("fx_send", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\fxSend, msg[2]);
    });

    // Global FX send
    this.addCommand("fx_send_all", "f", { |msg|
      synths.do { |s| s.set(\fxSend, msg[1]) };
    });

    // Per-voice amp lag (spin-up speed)
    this.addCommand("amp_lag", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\ampLag, msg[2]);
    });

    // Per-voice pan (-1 left, 0 center, +1 right)
    this.addCommand("pan", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\pan, msg[2]);
    });

    // All voices off
    this.addCommand("all_off", "", { |msg|
      synths.do { |s| s.set(\amp, 0.0) };
    });

    // Set all amplitudes at once (8 floats packed as one param)
    // Uses 8 separate commands for simplicity
    8.do { |i|
      this.addCommand("amp" ++ i, "f", { |msg|
        synths[i].set(\amp, msg[1]);
      });
    };

  }

  free {
    synths.do { |s| s.free };
    fxSynth.free;
    fxBus.free;
    voiceGroup.free;
    fxGroup.free;
  }

}
