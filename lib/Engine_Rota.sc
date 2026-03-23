// Engine_Rota.sc
// A Ciat-Lombarde rungler + Motor Synth inertia engine for norns
//
// 8 "motor" voices with physical inertia, multi-timbral oscillators,
// cogging noise, wavefolder, and a JPverb FX bus.
//
// Each voice has 3 oscillator sources:
//   1. VarSaw (optical disc waveform: saw/tri/reverse saw)
//   2. Pulse (PWM: thin buzzy to fat square)
//   3. Sub (sine one octave below for weight)
// Plus self-FM for metallic/bell textures.
//
// Sound philosophy:
//   - Rough like an electric motor vibrating at resonance
//   - Polished like the Meris Mercury7 trailing its decay into silence
//   - Deterministic chaos: the same patch never repeats, never collapses

Engine_Rota : CroneEngine {

  var <synths;
  var <fxSynth;
  var <fxBus;
  var voiceGroup;
  var fxGroup;

  *new { arg context, doneCallback;
    ^super.new(context, doneCallback);
  }

  alloc {
    var s = Server.default;

    fxBus = Bus.audio(s, 2);

    // ---------------------------------------------------------------
    // MOTOR VOICE SynthDef — multi-timbral oscillator bank
    // ---------------------------------------------------------------
    SynthDef(\rota_motor, {
      arg out=0, fxBus=0,
          targetFreq=110, inertia=0.5,
          amp=0.0, ampLag=0.08,
          grind=0.2, phaseNoise=0.01,
          waveshape=0.5,       // VarSaw width (0=saw, 0.5=tri, 1=rev saw)
          pulseWidth=0.5,      // Pulse wave width (0.01=thin, 0.5=square)
          oscMix=0.0,          // 0=all VarSaw, 1=all Pulse
          subLevel=0.0,        // Sub oscillator level (0-1)
          fmAmt=0.0,           // Self-FM amount (0=clean, 1=metallic)
          fxSend=0.4,
          pan=0.0;

      var freq, phaseMod, sigVar, sigPulse, sigSub, sigFM, sig, cogging, env;

      // Physical inertia: pitch slides to target with lag
      freq = Lag.kr(targetFreq, inertia);

      // Electromagnetic phase noise (brush contact irregularity)
      phaseMod = LFNoise2.ar(freq * 0.03) * (freq * phaseNoise * 0.5);

      // --- OSCILLATOR 1: VarSaw (optical disc waveform) ---
      sigVar = VarSaw.ar(freq + phaseMod, 0,
        waveshape + (LFNoise1.kr(0.7) * 0.08));

      // --- OSCILLATOR 2: Pulse (PWM) ---
      // Width modulated by slow LFO for movement
      sigPulse = Pulse.ar(freq + phaseMod,
        (pulseWidth + (LFNoise1.kr(0.5) * 0.06)).clip(0.01, 0.99));

      // --- OSCILLATOR 3: Sub (sine, one octave below) ---
      sigSub = SinOsc.ar(freq * 0.5) * subLevel;

      // --- Self-FM: frequency modulation for metallic/bell textures ---
      sigFM = SinOsc.ar(freq + (SinOsc.ar(freq * 1.414) * freq * fmAmt * 0.5));
      // Blend FM into the mix when fmAmt > 0
      sigVar = sigVar * (1 - (fmAmt * 0.5)) + (sigFM * fmAmt * 0.5);

      // --- MIX oscillators ---
      sig = (sigVar * (1 - oscMix)) + (sigPulse * oscMix) + sigSub;

      // Cogging noise: low-freq amplitude flutter (motor teeth)
      cogging = 1 - (grind * LFNoise0.kr(freq * 0.12).range(0, 1));
      sig = sig * cogging;

      // Soft wavefold: adds upper harmonics without hard clipping
      sig = (sig * (1 + (grind * 2))).fold(-1, 1);
      sig = sig.tanh * 0.7;

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
    // ---------------------------------------------------------------
    SynthDef(\rota_fx, {
      arg in=0, out=0,
          drive=0.15,
          revSize=1.2, revT60=3.0, revDamp=0.5,
          revMix=0.35,
          rolloff=8000;

      var sig, wet;

      sig = In.ar(in, 2);
      sig = (sig * (1 + drive)).tanh;
      sig = LPF.ar(sig, rolloff);

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
    // Instantiate synths
    // ---------------------------------------------------------------
    voiceGroup = Group.new(context.xg);
    fxGroup    = Group.after(voiceGroup);

    fxSynth = Synth(\rota_fx, [
      \in, fxBus.index, \out, context.out_b,
      \drive, 0.15, \revSize, 1.2, \revT60, 3.0,
      \revDamp, 0.5, \revMix, 0.35, \rolloff, 8000
    ], fxGroup);

    synths = Array.new(8);
    8.do { |i|
      var pan = (i / 7.0 * 2) - 1;
      synths.add(
        Synth(\rota_motor, [
          \out, context.out_b, \fxBus, fxBus.index,
          \targetFreq, 55 * (i + 1).sqrt,
          \inertia, 0.3 + (i * 0.08),
          \amp, 0.0, \grind, 0.15, \phaseNoise, 0.01,
          \waveshape, 0.45, \pulseWidth, 0.5,
          \oscMix, 0.0, \subLevel, 0.0, \fmAmt, 0.0,
          \fxSend, 0.4, \pan, pan * 0.7
        ], voiceGroup)
      );
    };

    // ---------------------------------------------------------------
    // ENGINE COMMANDS
    // ---------------------------------------------------------------

    // Per-voice frequency target
    this.addCommand("freq", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\targetFreq, msg[2]);
    });

    // Per-voice amplitude
    this.addCommand("amp", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\amp, msg[2]);
    });

    // Per-voice inertia
    this.addCommand("inertia", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\inertia, msg[2]);
    });

    // Global grind
    this.addCommand("grind", "f", { |msg|
      synths.do { |s| s.set(\grind, msg[1]) };
    });

    // Per-voice grind
    this.addCommand("grind_v", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\grind, msg[2]);
    });

    // Global waveshape
    this.addCommand("waveshape", "f", { |msg|
      synths.do { |s| s.set(\waveshape, msg[1]) };
    });

    // Per-voice waveshape
    this.addCommand("waveshape_v", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\waveshape, msg[2]);
    });

    // Global pulse width
    this.addCommand("pulse_width", "f", { |msg|
      synths.do { |s| s.set(\pulseWidth, msg[1]) };
    });

    // Per-voice pulse width
    this.addCommand("pulse_width_v", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\pulseWidth, msg[2]);
    });

    // Global osc mix (0=VarSaw, 1=Pulse)
    this.addCommand("osc_mix", "f", { |msg|
      synths.do { |s| s.set(\oscMix, msg[1]) };
    });

    // Per-voice osc mix
    this.addCommand("osc_mix_v", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\oscMix, msg[2]);
    });

    // Global sub level
    this.addCommand("sub_level", "f", { |msg|
      synths.do { |s| s.set(\subLevel, msg[1]) };
    });

    // Per-voice sub level
    this.addCommand("sub_level_v", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\subLevel, msg[2]);
    });

    // Global FM amount
    this.addCommand("fm_amt", "f", { |msg|
      synths.do { |s| s.set(\fmAmt, msg[1]) };
    });

    // Per-voice FM amount
    this.addCommand("fm_amt_v", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\fmAmt, msg[2]);
    });

    // Global phase noise
    this.addCommand("phase_noise", "f", { |msg|
      synths.do { |s| s.set(\phaseNoise, msg[1]) };
    });

    // Per-voice phase noise
    this.addCommand("phase_noise_v", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\phaseNoise, msg[2]);
    });

    // FX commands
    this.addCommand("rev_mix", "f", { |msg| fxSynth.set(\revMix, msg[1]) });
    this.addCommand("rev_time", "f", { |msg| fxSynth.set(\revT60, msg[1]) });
    this.addCommand("rev_size", "f", { |msg| fxSynth.set(\revSize, msg[1]) });
    this.addCommand("drive", "f", { |msg| fxSynth.set(\drive, msg[1]) });
    this.addCommand("rolloff", "f", { |msg| fxSynth.set(\rolloff, msg[1]) });

    this.addCommand("fx_send", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\fxSend, msg[2]);
    });
    this.addCommand("fx_send_all", "f", { |msg|
      synths.do { |s| s.set(\fxSend, msg[1]) };
    });

    this.addCommand("amp_lag", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\ampLag, msg[2]);
    });

    this.addCommand("pan", "if", { |msg|
      synths[msg[1].clip(0,7)].set(\pan, msg[2]);
    });

    this.addCommand("all_off", "", { |msg|
      synths.do { |s| s.set(\amp, 0.0) };
    });

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
