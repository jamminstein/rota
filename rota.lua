-- rota.lua
-- Ciat-Lombarde Rungler + Motor Synth inertia engine for norns
--
-- A chaotic self-generating synthesizer built from two ideas:
--   1. Peter Blasser's rungler: a shift register that eats its own output
--   2. Motor Synth's physical inertia: pitch as a moving physical object
--
-- 8 "motor" voices whose target frequencies are driven by a Lua-side
-- rungler. The system feeds itself: oscillator output states clock the
-- shift register, which votes on frequency destinations.
--
-- Controls (norns only, no grid needed for fun):
--   ENC1       -> chaos / rungler feedback depth
--   ENC2       -> global inertia (motor mass)
--   ENC3       -> grind (electromechanical roughness)
--   KEY2       -> toggle bandmate (tap) / cycle style (hold)
--   KEY3       -> reseed / reset rungler to new state
--
-- Grid (profound + fun):
--   Cols 1-8   -> 8 motors, rows = parameter layers
--   Row 1      -> motor on/off (tap to toggle)
--   Row 2      -> motor pitch offset from rungler (+/- octave)
--   Row 3      -> motor inertia (per-voice)
--   Row 4      -> motor grind (per-voice)
--   Rows 5-6   -> rungler feedback topology (which motors feed which)
--   Row 7      -> scale lock (quantize or free chaos)
--   Row 8      -> page / function row

engine.name = "Rota"

local musicutil = require "musicutil"
local lattice   = require "lattice"
local util      = require "util"

-- -----------------------------------------------------------------------
-- MIDI OUT
-- -----------------------------------------------------------------------

local midi_out_device = nil
local midi_out_ch_base = 1
local midi_active_notes = {}  -- [voice] = {note, channel}
for i = 1, 8 do midi_active_notes[i] = nil end

-- -----------------------------------------------------------------------
-- STATE
-- -----------------------------------------------------------------------

local NUM_VOICES = 8

-- Rungler state (8-bit shift register, mirroring the SC engine concept)
local rungler = {
  reg        = 180,           -- initial seed (0b10110100)
  freq1      = 40,           -- data oscillator
  freq2      = 7,            -- clock oscillator
  phase1     = 0,
  phase2     = 0,
  value      = 0,            -- current output 0..1
  feedback   = 0.4,          -- how much rungler feeds back into itself
  speed      = 1.0,          -- clock rate for rungler steps
  step_acc   = 0,            -- accumulator for sub-beat stepping
}

-- Motor voice state
local motors = {}
for i = 1, NUM_VOICES do
  motors[i] = {
    on          = (i <= 4),     -- first 4 on by default
    freq        = 55 + (i * 40),
    target_freq = 55 + (i * 40),
    amp         = 0.0,
    inertia     = 0.2 + (i * 0.06),
    grind       = 0.15,
    pitch_offset = 0,           -- semitone offset from rungler target (-12..12)
    active_bright = 0,          -- for grid animation
  }
end

-- Scale system
local SCALES = {
  "chromatic", "minor", "major", "dorian",
  "pentatonic minor", "whole tone", "phrygian"
}
local scale_idx    = 2         -- minor default
local scale_root   = 36        -- C2 MIDI
local scale_notes  = {}
local quantize     = true

-- -----------------------------------------------------------------------
-- BANDMATE SYSTEM
-- 6 performance styles that replace the old simple auto_mode.
-- Each style defines a character: how chaos/mass/roughness evolve,
-- voice density patterns, scale/reverb preferences, and mutation rates.
-- -----------------------------------------------------------------------

local BANDMATE_STYLES = {
  -- 1. DRIFT: the meditator
  {
    name = "DRIFT",
    chaos_lo = 0.2,  chaos_hi = 0.5,
    mass_lo  = 0.3,  mass_hi  = 0.8,
    rough_lo = 0.05, rough_hi = 0.25,
    voice_density     = 0.35,   -- few voices
    evolution_speed   = 0.03,   -- very slow
    scale_change_prob = 0.02,   -- rare scale shifts
    reverb_mix_target = 0.65,   -- high reverb
    reverb_time_target = 6.0,
    reseed_prob       = 0.01,
    topology_mutate_prob = 0.02,
    voice_toggle_prob = 0.02,   -- slow voice changes
  },
  -- 2. SURGE: the crescendo builder
  {
    name = "SURGE",
    chaos_lo = 0.15, chaos_hi = 0.85,
    mass_lo  = 0.3,  mass_hi  = 1.0,
    rough_lo = 0.1,  rough_hi = 0.5,
    voice_density     = 0.55,
    evolution_speed   = 0.08,   -- moderate
    scale_change_prob = 0.04,
    reverb_mix_target = 0.45,
    reverb_time_target = 4.0,
    reseed_prob       = 0.02,
    topology_mutate_prob = 0.03,
    voice_toggle_prob = 0.03,
  },
  -- 3. SWARM: the density player
  {
    name = "SWARM",
    chaos_lo = 0.3,  chaos_hi = 0.6,
    mass_lo  = 0.1,  mass_hi  = 0.6,
    rough_lo = 0.1,  rough_hi = 0.4,
    voice_density     = 0.85,   -- lots of voices
    evolution_speed   = 0.12,   -- fast toggling
    scale_change_prob = 0.03,
    reverb_mix_target = 0.3,
    reverb_time_target = 2.5,
    reseed_prob       = 0.03,
    topology_mutate_prob = 0.05,
    voice_toggle_prob = 0.15,   -- rapid voice toggling
  },
  -- 4. BLASSER: channels the Ciat-Lombarde spirit
  {
    name = "BLASSER",
    chaos_lo = 0.6,  chaos_hi = 0.9,
    mass_lo  = 0.2,  mass_hi  = 0.7,
    rough_lo = 0.2,  rough_hi = 0.6,
    voice_density     = 0.6,
    evolution_speed   = 0.1,
    scale_change_prob = 0.06,
    reverb_mix_target = 0.4,
    reverb_time_target = 3.5,
    reseed_prob       = 0.1,    -- frequent reseeds
    topology_mutate_prob = 0.15, -- frequent topology mutations
    voice_toggle_prob = 0.06,
  },
  -- 5. GLACIAL: the deep listener
  {
    name = "GLACIAL",
    chaos_lo = 0.1,  chaos_hi = 0.3,
    mass_lo  = 0.8,  mass_hi  = 1.4,
    rough_lo = 0.0,  rough_hi = 0.15,
    voice_density     = 0.25,   -- 2-3 voices
    evolution_speed   = 0.015,  -- extremely slow
    scale_change_prob = 0.03,
    reverb_mix_target = 0.8,    -- maxed reverb
    reverb_time_target = 9.0,
    reseed_prob       = 0.005,
    topology_mutate_prob = 0.01,
    voice_toggle_prob = 0.01,
  },
  -- 6. RUPTURE: the disruptor
  {
    name = "RUPTURE",
    chaos_lo = 0.3,  chaos_hi = 0.95,
    mass_lo  = 0.1,  mass_hi  = 0.5,
    rough_lo = 0.1,  rough_hi = 1.0,
    voice_density     = 0.5,
    evolution_speed   = 0.2,    -- fast
    scale_change_prob = 0.05,
    reverb_mix_target = 0.25,
    reverb_time_target = 2.0,
    reseed_prob       = 0.12,   -- frequent reseeds
    topology_mutate_prob = 0.1,
    voice_toggle_prob = 0.12,   -- voices slam on/off
  },
}

local bandmate_on    = false
local bandmate_style = 1
local bandmate_phase = 0   -- slowly evolving phase for bandmate behaviors

-- Surge-specific state
local surge_direction = 1  -- 1 = building up, -1 = pulling back
local surge_progress  = 0  -- 0..1 progress through a surge cycle

-- Key2 hold detection
local key2_down_time = nil

-- Grid
local g            = grid.connect()
local grid_page    = 1         -- 1=motors, 2=topology
local held_grid    = {}        -- held grid keys for gestures

-- Screen
local screen_dirty = true
local frame        = 0

-- Global params (mapped to encoders)
local chaos        = 0.4       -- ENC1: rungler feedback
local mass         = 0.5       -- ENC2: global inertia
local roughness    = 0.2       -- ENC3: global grind

-- Topology matrix: which motors feed the rungler clock
-- topology[i] = true means motor i participates in shift register feedback
local topology = {true, true, false, false, false, false, false, false}

-- Lattice + metro references for cleanup
local auto_lattice  = nil
local screen_metro  = nil
local grid_metro    = nil

-- -----------------------------------------------------------------------
-- SCALE UTILITIES
-- -----------------------------------------------------------------------

local function rebuild_scale()
  scale_notes = musicutil.generate_scale(scale_root, SCALES[scale_idx], 5)
end

local function quantize_midi(midi_note)
  if not quantize then return midi_note end
  return musicutil.snap_note_to_scale(midi_note, scale_notes)
end

local function midi_to_hz(n)
  return musicutil.midi_to_hz(n)
end

-- -----------------------------------------------------------------------
-- MIDI OUT UTILITIES
-- -----------------------------------------------------------------------

local function midi_note_on(voice, midi_note)
  if midi_out_device == nil then return end
  local ch = midi_out_ch_base + voice - 1
  if ch > 16 then return end

  -- note-off previous note on this voice
  if midi_active_notes[voice] then
    pcall(function()
      midi_out_device:note_off(midi_active_notes[voice].note, 0, midi_active_notes[voice].ch)
    end)
  end

  local vel = math.floor(util.clamp(motors[voice].amp * 127 / 0.4, 1, 127))
  pcall(function()
    midi_out_device:note_on(midi_note, vel, ch)
  end)
  midi_active_notes[voice] = {note = midi_note, ch = ch}
end

local function midi_all_notes_off()
  if midi_out_device == nil then return end
  for i = 1, NUM_VOICES do
    if midi_active_notes[i] then
      pcall(function()
        midi_out_device:note_off(midi_active_notes[i].note, 0, midi_active_notes[i].ch)
      end)
      midi_active_notes[i] = nil
    end
  end
end

-- -----------------------------------------------------------------------
-- RUNGLER LOGIC (Lua-side, mirrors SC topology)
-- Clocked from lattice; outputs a 0..1 value that drives voice targets
-- -----------------------------------------------------------------------

local function rungler_step()
  local reg = rungler.reg

  -- XOR feedback: bits 0, 1, 3 (Blasser topology)
  local b0 = reg & 1
  local b1 = (reg >> 1) & 1
  local b3 = (reg >> 3) & 1
  local new_bit = (b0 ~ b1 ~ b3) & 1

  -- Shift right, insert new bit at top
  reg = ((reg >> 1) | (new_bit << 7)) & 0xFF

  -- Inject chaos: occasionally flip a bit based on feedback depth
  if math.random() < (rungler.feedback * 0.15) then
    local flip_pos = math.floor(math.random() * 8)
    reg = reg ~ (1 << flip_pos)
  end

  rungler.reg = reg

  -- DAC: weight the top 3 bits into 0..7 range, normalize
  local val = ((reg & 0x07)) / 7.0

  -- Smooth with feedback
  rungler.value = rungler.value + (val - rungler.value) * 0.35
  return rungler.value
end

-- Map rungler value (0..1) to a MIDI note for a given voice
local function rungler_to_midi(v_idx, rung_val)
  -- Each voice has its own offset and range mapping
  local base  = scale_root + (v_idx - 1) * 7  -- stack in 5ths
  local range = 24  -- 2 octave range
  local raw   = base + math.floor(rung_val * range)
        raw   = raw + motors[v_idx].pitch_offset
  return quantize_midi(math.floor(raw))
end

-- -----------------------------------------------------------------------
-- ENGINE COMMANDS -- translate state to SuperCollider
-- All engine calls wrapped in pcall for safety in lattice sprockets
-- -----------------------------------------------------------------------

local function send_voice(i)
  local m = motors[i]
  local amp = m.on and m.amp or 0.0
  pcall(function() engine.freq(i - 1, midi_to_hz(m.target_freq)) end)
  pcall(function() engine.amp(i - 1, amp) end)
  pcall(function() engine.inertia(i - 1, m.inertia) end)
  pcall(function() engine.grind_v(i - 1, m.grind) end)
end

local function send_all()
  for i = 1, NUM_VOICES do
    send_voice(i)
  end
end

local function update_globals()
  pcall(function() engine.grind(roughness) end)
  pcall(function() engine.phase_noise(roughness * 0.04) end)
  pcall(function() engine.drive(0.1 + roughness * 0.3) end)
  pcall(function() engine.rolloff(12000 - (roughness * 5000)) end)
end

-- -----------------------------------------------------------------------
-- BANDMATE: style-aware musical behaviors
-- Each style shapes how chaos/mass/roughness evolve, how voices
-- toggle, how often the rungler reseeds, and how reverb breathes.
-- The motors need TIME to arrive at their targets -- never rush.
-- -----------------------------------------------------------------------

local function get_style()
  return BANDMATE_STYLES[bandmate_style]
end

-- Smoothly move a value toward a target by a fraction
local function drift_toward(current, target, rate)
  return current + (target - rate) * rate + (target - current) * rate
end

-- Evolve chaos, mass, roughness according to the current style
local function bandmate_evolve_params()
  local s = get_style()
  local speed = s.evolution_speed

  if bandmate_style == 2 then
    -- SURGE: build up then pull back
    surge_progress = surge_progress + speed * 0.5
    if surge_progress >= 1.0 then
      surge_progress = 0
      surge_direction = -surge_direction
    end
    local t = surge_progress
    if surge_direction == 1 then
      -- building: chaos rises from low to high
      chaos = s.chaos_lo + (s.chaos_hi - s.chaos_lo) * t
      mass  = s.mass_lo + (s.mass_hi - s.mass_lo) * t * 0.7
      roughness = s.rough_lo + (s.rough_hi - s.rough_lo) * t * 0.5
    else
      -- pulling back: sudden drop then settle
      chaos = s.chaos_hi - (s.chaos_hi - s.chaos_lo) * t * 1.5
      chaos = math.max(chaos, s.chaos_lo)
      mass  = s.mass_hi - (s.mass_hi - s.mass_lo) * t
      roughness = s.rough_hi - (s.rough_hi - s.rough_lo) * t
    end
  elseif bandmate_style == 6 then
    -- RUPTURE: sudden jumps, not smooth evolution
    if math.random() < speed then
      chaos = s.chaos_lo + math.random() * (s.chaos_hi - s.chaos_lo)
    end
    if math.random() < speed * 0.7 then
      mass = s.mass_lo + math.random() * (s.mass_hi - s.mass_lo)
    end
    -- roughness spikes then drops
    if math.random() < 0.08 then
      roughness = s.rough_hi
    elseif roughness > s.rough_lo + 0.1 then
      roughness = roughness - 0.04
    end
  else
    -- All other styles: smooth sine-based evolution
    local chaos_center = (s.chaos_lo + s.chaos_hi) / 2
    local chaos_range  = (s.chaos_hi - s.chaos_lo) / 2
    chaos = chaos_center + math.sin(bandmate_phase * 0.7) * chaos_range

    local mass_center = (s.mass_lo + s.mass_hi) / 2
    local mass_range  = (s.mass_hi - s.mass_lo) / 2
    mass = mass_center + math.sin(bandmate_phase * 0.3) * mass_range

    local rough_center = (s.rough_lo + s.rough_hi) / 2
    local rough_range  = (s.rough_hi - s.rough_lo) / 2
    roughness = rough_center + math.sin(bandmate_phase * 0.5) * rough_range
  end

  -- Clamp everything
  chaos     = util.clamp(chaos, 0.0, 1.0)
  mass      = util.clamp(mass, 0.0, 1.5)
  roughness = util.clamp(roughness, 0.0, 1.0)

  -- Apply to rungler and engine
  rungler.feedback = chaos
  update_globals()

  -- Update param displays
  params:set("chaos", chaos, true)
  params:set("mass", mass, true)
  params:set("roughness", roughness, true)
end

-- Toggle voices on/off based on style density + randomness
local function bandmate_pick_voices()
  local s = get_style()
  local density = s.voice_density

  for i = 1, NUM_VOICES do
    if math.random() < s.voice_toggle_prob then
      if bandmate_style == 3 then
        -- SWARM: rapid toggling, patterned
        local pattern_on = ((i + math.floor(bandmate_phase * 3)) % 3) ~= 0
        motors[i].on = pattern_on and (math.random() < density + 0.2)
      elseif bandmate_style == 5 then
        -- GLACIAL: only 2-3 voices, chosen carefully
        local active_count = 0
        for j = 1, NUM_VOICES do
          if motors[j].on then active_count = active_count + 1 end
        end
        if active_count < 3 and not motors[i].on then
          motors[i].on = math.random() < 0.3
        elseif active_count > 3 and motors[i].on then
          motors[i].on = false
        end
      elseif bandmate_style == 6 then
        -- RUPTURE: voices slam on/off in groups
        if math.random() < 0.3 then
          local group_on = math.random() < 0.5
          local start = math.random(1, 4)
          for j = start, math.min(start + 3, NUM_VOICES) do
            motors[j].on = group_on
          end
        end
      else
        -- Generic density-based toggling
        motors[i].on = math.random() < density
      end
      send_voice(i)
    end
  end
end

-- Evolve harmony: root note and scale changes
local function bandmate_evolve_harmony()
  local s = get_style()

  if math.random() < s.scale_change_prob then
    if bandmate_style == 5 then
      -- GLACIAL prefers whole tone or phrygian
      local glacial_scales = {6, 7}  -- whole tone, phrygian
      scale_idx = glacial_scales[math.random(#glacial_scales)]
    elseif bandmate_style == 4 then
      -- BLASSER: quantize toggles on/off
      if math.random() < 0.3 then
        quantize = not quantize
        params:set("quantize", quantize and 1 or 0, true)
      end
      scale_idx = math.random(1, #SCALES)
    else
      -- Other styles: weighted toward minor/dorian/pentatonic
      local weighted = {2, 2, 4, 4, 5, 5, 3, 6, 7}
      scale_idx = weighted[math.random(#weighted)]
    end
    params:set("scale", scale_idx, true)
    rebuild_scale()
  end

  -- Root note drift
  if math.random() < s.scale_change_prob * 0.6 then
    local intervals = {0, 2, 3, 5, 7, 8, 10}
    scale_root = 24 + intervals[math.random(#intervals)]
    params:set("root", scale_root, true)
    rebuild_scale()
  end
end

-- Update per-voice inertia based on style and breathing phase
local function bandmate_update_inertia()
  for i = 1, NUM_VOICES do
    local base = mass * 0.8
    local variation

    if bandmate_style == 3 then
      -- SWARM: wild per-voice inertia variation
      variation = math.sin(bandmate_phase * 2.0 + i * 1.7) * 0.4
    elseif bandmate_style == 5 then
      -- GLACIAL: uniformly high inertia
      base = mass * 1.0
      variation = math.sin(bandmate_phase * 0.1 + i) * 0.1
    else
      -- Default: gentle sine breathing
      variation = math.sin(bandmate_phase * 0.2 + i * 1.3) * 0.2
    end

    motors[i].inertia = math.max(0.05, base + variation)
    pcall(function() engine.inertia(i - 1, motors[i].inertia) end)
  end
end

-- Topology mutation: which motors feed the rungler
local function bandmate_mutate_topology()
  local s = get_style()
  if math.random() < s.topology_mutate_prob then
    local idx = math.random(1, NUM_VOICES)
    topology[idx] = not topology[idx]
  end
end

-- Reseed the rungler
local function bandmate_maybe_reseed()
  local s = get_style()
  if math.random() < s.reseed_prob then
    rungler.reg = math.random(1, 255)
    rungler.value = 0
    -- Randomize pitch offsets slightly
    for i = 1, NUM_VOICES do
      motors[i].pitch_offset = math.random(-5, 5)
    end
  end
end

-- Reverb evolution: styles have target reverb settings
local function bandmate_evolve_reverb()
  local s = get_style()
  local current_mix = params:get("rev_mix")
  local current_time = params:get("rev_time")

  -- Slowly drift toward style targets
  local new_mix  = current_mix + (s.reverb_mix_target - current_mix) * 0.05
  local new_time = current_time + (s.reverb_time_target - current_time) * 0.03

  params:set("rev_mix", new_mix, true)
  params:set("rev_time", new_time, true)
  pcall(function() engine.rev_mix(new_mix) end)
  pcall(function() engine.rev_time(new_time) end)
end

-- -----------------------------------------------------------------------
-- CORE CLOCK: lattice-based, multiple sprockets at prime ratios
-- -----------------------------------------------------------------------

local function setup_lattice()
  if auto_lattice then
    auto_lattice:destroy()
  end
  auto_lattice = lattice:new()

  -- Sprocket 1: rungler step + voice frequency update (every 1/8)
  -- rungler_speed acts as a step accumulator: each tick adds speed,
  -- only steps the rungler when accumulator >= 1
  auto_lattice:new_sprocket({
    action = function(t)
      pcall(function()
        -- Accumulate speed; only step when we've built up enough
        rungler.step_acc = rungler.step_acc + rungler.speed
        if rungler.step_acc >= 1.0 then
          rungler.step_acc = rungler.step_acc - 1.0

          local rung = rungler_step()

          -- Update target frequencies from rungler
          for i = 1, NUM_VOICES do
            if motors[i].on then
              local midi_note = rungler_to_midi(i, rung)
              -- Check if target changed for MIDI out
              local old_target = motors[i].target_freq
              motors[i].target_freq = midi_note
              motors[i].amp = 0.18 + (rung * 0.22)
              engine.freq(i - 1, midi_to_hz(midi_note))
              engine.amp(i - 1, motors[i].on and motors[i].amp or 0.0)

              -- MIDI out: send note when target changes
              if midi_note ~= old_target then
                midi_note_on(i, midi_note)
              end
            end
            motors[i].active_bright = math.floor(rung * 10)
          end
        end

        screen_dirty = true
      end)
    end,
    division = 1 / 8,
    enabled  = true
  })

  -- Sprocket 2: harmony/density evolution (every 7 beats, prime)
  auto_lattice:new_sprocket({
    action = function(t)
      pcall(function()
        if bandmate_on then
          bandmate_phase = bandmate_phase + get_style().evolution_speed
          bandmate_evolve_harmony()
          bandmate_pick_voices()
          bandmate_mutate_topology()
          bandmate_maybe_reseed()
        end
      end)
    end,
    division = 7 / 4,
    enabled  = true
  })

  -- Sprocket 3: inertia + param breathing (every 11 beats, prime)
  auto_lattice:new_sprocket({
    action = function(t)
      pcall(function()
        if bandmate_on then
          bandmate_update_inertia()
          bandmate_evolve_params()
        end
      end)
    end,
    division = 11 / 4,
    enabled  = true
  })

  -- Sprocket 4: reverb evolution (every 13 beats, prime)
  auto_lattice:new_sprocket({
    action = function(t)
      pcall(function()
        if bandmate_on then
          bandmate_evolve_reverb()
        end
      end)
    end,
    division = 13 / 4,
    enabled  = true
  })

  -- Sprocket 5: screen animation frame (every 1/32, visual only)
  auto_lattice:new_sprocket({
    action = function(t)
      frame = frame + 1
      if frame % 2 == 0 then
        screen_dirty = true
      end
    end,
    division = 1 / 32,
    enabled  = true
  })

  auto_lattice:start()
end

-- -----------------------------------------------------------------------
-- GRID INTERFACE
-- -----------------------------------------------------------------------

local BRIGHT = {
  OFF    = 0,
  GHOST  = 2,
  DIM    = 4,
  MID    = 8,
  BRIGHT = 12,
  FULL   = 15
}

local function grid_redraw()
  if g == nil then return end
  g:all(0)

  if grid_page == 1 then
    -- ---- PAGE 1: MOTOR CONTROL ----
    for i = 1, NUM_VOICES do
      local m = motors[i]

      -- Row 1: on/off
      g:led(i, 1, m.on and BRIGHT.FULL or BRIGHT.DIM)

      -- Row 2: pitch offset visualization
      local offset_norm = (m.pitch_offset + 12) / 24.0
      g:led(i, 2, math.floor(offset_norm * 11) + 2)

      -- Row 3: inertia
      g:led(i, 3, math.floor(m.inertia / 1.5 * 11) + 2)

      -- Row 4: grind
      g:led(i, 4, math.floor(m.grind * 11) + 2)

      -- Rows 5-6: rungler meter (animated)
      local rung_bright = motors[i].active_bright or 0
      g:led(i, 5, rung_bright > 5 and BRIGHT.BRIGHT or BRIGHT.DIM)
      g:led(i, 6, rung_bright > 8 and BRIGHT.FULL or BRIGHT.GHOST)

      -- Row 7: scale selection (highlight current)
      if i <= #SCALES then
        g:led(i, 7, (i == scale_idx) and BRIGHT.FULL or BRIGHT.DIM)
      end
    end

    -- Row 8: navigation and mode buttons
    g:led(1, 8, bandmate_on and BRIGHT.FULL or BRIGHT.DIM)   -- bandmate
    g:led(2, 8, quantize and BRIGHT.BRIGHT or BRIGHT.DIM)    -- quantize
    -- Style indicator: light up col 3-8 for style number
    if bandmate_on then
      for i = 3, 3 + bandmate_style - 1 do
        if i <= 8 then g:led(i, 8, BRIGHT.MID) end
      end
    end
    g:led(16, 8, BRIGHT.MID)  -- page 2 arrow

  elseif grid_page == 2 then
    -- ---- PAGE 2: TOPOLOGY ----
    -- Topology row (row 1)
    for i = 1, NUM_VOICES do
      g:led(i, 1, topology[i] and BRIGHT.FULL or BRIGHT.DIM)
    end

    -- Rungler register visualization (rows 2-3)
    for bit = 0, 7 do
      local b = (rungler.reg >> bit) & 1
      g:led(bit + 1, 2, b == 1 and BRIGHT.BRIGHT or BRIGHT.GHOST)
      local meter = math.floor(rungler.value * 8)
      g:led(bit + 1, 3, bit < meter and BRIGHT.MID or BRIGHT.DIM)
    end

    -- Rungler speed (row 4)
    local speed_steps = {0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 8.0}
    for i = 1, 8 do
      local active = math.abs(speed_steps[i] - rungler.speed) < 0.01
      g:led(i, 4, active and BRIGHT.FULL or BRIGHT.DIM)
    end

    -- Row 7: scale root (C..B = cols 1..12)
    local root_in_octave = scale_root % 12
    for i = 1, 12 do
      g:led(i, 7, (i-1 == root_in_octave) and BRIGHT.FULL or BRIGHT.DIM)
    end

    -- Row 8: page control
    g:led(1, 8, BRIGHT.MID)   -- back arrow
    g:led(16, 8, BRIGHT.DIM)
  end

  g:refresh()
end

local function grid_key(x, y, z)
  local key_id = x .. "," .. y
  if z == 1 then
    held_grid[key_id] = {x = x, y = y, t = util.time()}
  else
    held_grid[key_id] = nil
  end

  if z == 0 then return end  -- only act on press

  -- ---- PAGE 1 ----
  if grid_page == 1 then
    if y == 1 and x <= NUM_VOICES then
      motors[x].on = not motors[x].on
      send_voice(x)

    elseif y == 2 and x <= NUM_VOICES then
      local held_count = 0
      local held_x = nil
      for k, v in pairs(held_grid) do
        if v.y == 2 and v.x ~= x then
          held_count = held_count + 1
          held_x = v.x
        end
      end
      if held_count > 0 and held_x then
        local diff = x - held_x
        motors[math.max(x, held_x)].pitch_offset =
          util.clamp(diff * 2, -12, 12)
      else
        local offsets = {-12, -7, -5, 0, 5, 7, 12}
        local cur = motors[x].pitch_offset
        local next_idx = 1
        for i, v in ipairs(offsets) do
          if v == cur then next_idx = (i % #offsets) + 1; break end
        end
        motors[x].pitch_offset = offsets[next_idx]
      end

    elseif y == 3 and x <= NUM_VOICES then
      local levels = {0.05, 0.15, 0.3, 0.5, 0.8, 1.2}
      local cur = motors[x].inertia
      local next_idx = 1
      for i, v in ipairs(levels) do
        if math.abs(v - cur) < 0.05 then
          next_idx = (i % #levels) + 1; break
        end
      end
      motors[x].inertia = levels[next_idx]
      pcall(function() engine.inertia(x - 1, motors[x].inertia) end)

    elseif y == 4 and x <= NUM_VOICES then
      local glevels = {0.0, 0.1, 0.25, 0.45, 0.7, 1.0}
      local cur = motors[x].grind
      local next_idx = 1
      for i, v in ipairs(glevels) do
        if math.abs(v - cur) < 0.05 then
          next_idx = (i % #glevels) + 1; break
        end
      end
      motors[x].grind = glevels[next_idx]
      pcall(function() engine.grind_v(x - 1, motors[x].grind) end)

    elseif y == 7 and x <= #SCALES then
      scale_idx = x
      params:set("scale", scale_idx, true)
      rebuild_scale()

    elseif y == 8 then
      if x == 1 then
        bandmate_on = not bandmate_on
        params:set("bandmate_on", bandmate_on and 2 or 1, true)
        if bandmate_on then
          for i = 1, NUM_VOICES do
            motors[i].on = true
            motors[i].amp = 0.15 + math.random() * 0.15
            send_voice(i)
          end
        end
      elseif x == 2 then
        quantize = not quantize
        params:set("quantize", quantize and 1 or 0, true)
      elseif x >= 3 and x <= 8 then
        -- Tap cols 3-8 to select bandmate style directly
        local style_num = x - 2
        if style_num <= #BANDMATE_STYLES then
          bandmate_style = style_num
          params:set("bandmate_style", bandmate_style, true)
        end
      elseif x == 16 then
        grid_page = 2
      end
    end

  -- ---- PAGE 2 ----
  elseif grid_page == 2 then
    if y == 1 and x <= NUM_VOICES then
      topology[x] = not topology[x]

    elseif y == 4 then
      local speeds = {0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 8.0}
      if x <= #speeds then
        rungler.speed = speeds[x]
        params:set("rungler_speed", speeds[x], true)
      end

    elseif y == 7 and x <= 12 then
      scale_root = 24 + (x - 1)
      params:set("root", scale_root, true)
      rebuild_scale()

    elseif y == 8 then
      if x == 1 then
        grid_page = 1
      end
    end
  end

  grid_redraw()
  screen_dirty = true
end

-- -----------------------------------------------------------------------
-- NORNS HARDWARE CONTROLS
-- -----------------------------------------------------------------------

function enc(n, d)
  if n == 1 then
    -- ENC1: chaos (rungler feedback depth)
    chaos = util.clamp(chaos + d * 0.02, 0.0, 1.0)
    rungler.feedback = chaos
    params:set("chaos", chaos, true)
    update_globals()
  elseif n == 2 then
    -- ENC2: mass (global inertia)
    mass = util.clamp(mass + d * 0.02, 0.0, 1.5)
    params:set("mass", mass, true)
    for i = 1, NUM_VOICES do
      motors[i].inertia = mass * (0.5 + i * 0.08)
      pcall(function() engine.inertia(i - 1, motors[i].inertia) end)
    end
  elseif n == 3 then
    -- ENC3: roughness (global grind)
    roughness = util.clamp(roughness + d * 0.02, 0.0, 1.0)
    params:set("roughness", roughness, true)
    update_globals()
  end
  screen_dirty = true
end

function key(n, z)
  if n == 2 then
    if z == 1 then
      -- KEY2 pressed: record time
      key2_down_time = util.time()
    else
      -- KEY2 released: check hold duration
      if key2_down_time then
        local hold_dur = util.time() - key2_down_time
        if hold_dur > 0.5 then
          -- Long press: cycle bandmate style
          bandmate_style = (bandmate_style % #BANDMATE_STYLES) + 1
          params:set("bandmate_style", bandmate_style, true)
        else
          -- Short press: toggle bandmate on/off
          bandmate_on = not bandmate_on
          params:set("bandmate_on", bandmate_on and 2 or 1, true)
          if bandmate_on then
            -- Spin up all motors gradually
            for i = 1, NUM_VOICES do
              motors[i].on = true
              motors[i].amp = 0.15 + math.random() * 0.15
              send_voice(i)
            end
          end
        end
        key2_down_time = nil
      end
    end
  elseif n == 3 and z == 1 then
    -- KEY3: reseed rungler with new random state
    rungler.reg = math.random(1, 255)
    rungler.value = 0
    for i = 1, NUM_VOICES do
      motors[i].pitch_offset = math.random(-5, 5)
    end
  end

  screen_dirty = true
end

-- -----------------------------------------------------------------------
-- SCREEN DRAWING
-- 128x64 OLED — informative, elegant, non-overlapping
-- -----------------------------------------------------------------------

local function draw_motor_bars()
  -- 8 motor bars across the bottom, with frequency dot and voice number
  local bar_w = 11
  local bar_h = 16
  local y_base = 62
  local x_start = 2
  local gap = 2

  for i = 1, NUM_VOICES do
    local x = x_start + (i - 1) * (bar_w + gap)
    local m = motors[i]
    local level = m.on and (m.amp or 0) or 0
    local h = math.floor(level * bar_h)

    -- Outer border
    screen.level(m.on and 5 or 2)
    screen.rect(x, y_base - bar_h, bar_w, bar_h)
    screen.stroke()

    -- Filled level
    if h > 0 then
      screen.level(m.on and 12 or 3)
      screen.rect(x + 1, y_base - h, bar_w - 2, h)
      screen.fill()
    end

    -- Frequency indicator dot: position within bar based on MIDI note
    if m.on and m.target_freq then
      local note_norm = util.clamp((m.target_freq - 24) / 60, 0, 1)
      local dot_y = y_base - 1 - math.floor(note_norm * (bar_h - 2))
      screen.level(15)
      screen.pixel(x + math.floor(bar_w / 2), dot_y)
      screen.fill()
    end

    -- Active flash
    if (motors[i].active_bright or 0) > 7 then
      screen.level(15)
      screen.rect(x + 3, y_base - bar_h - 2, 5, 1)
      screen.fill()
    end

    -- Voice number below
    screen.level(m.on and 8 or 3)
    screen.move(x + 3, y_base + 6)
    screen.font_size(6)
    screen.text(tostring(i))
  end
end

local function draw_rungler_arc()
  -- Rungler shift register as a circle, radius scales with chaos
  local cx = 106
  local cy = 20
  local base_r = 8
  local r  = base_r + math.floor(chaos * 6)  -- 8-14 radius, scales with chaos
  screen.level(4)
  screen.circle(cx, cy, r)
  screen.stroke()

  for bit = 0, 7 do
    local angle = (bit / 8.0) * 2 * math.pi - (math.pi / 2)
    local bval  = (rungler.reg >> bit) & 1
    local bx    = cx + math.cos(angle) * r
    local by    = cy + math.sin(angle) * r
    screen.level(bval == 1 and 15 or 2)
    screen.circle(bx, by, 1.5)
    screen.fill()
  end

  -- Center: rungler value as brightness
  screen.level(math.floor(rungler.value * 12) + 2)
  screen.circle(cx, cy, 2.5)
  screen.fill()
end

local function draw_param_bar(label, value, x, y, w)
  screen.level(6)
  screen.move(x, y)
  screen.font_size(8)
  screen.text(label)
  -- Background
  screen.level(2)
  screen.rect(x + 10, y - 5, w, 4)
  screen.fill()
  -- Fill
  screen.level(12)
  screen.rect(x + 10, y - 5, math.floor(util.clamp(value, 0, 1) * w), 4)
  screen.fill()
end

function redraw()
  if not screen_dirty then return end
  screen_dirty = false

  screen.clear()
  screen.font_face(1)
  screen.aa(0)

  -- Top left: title
  screen.level(10)
  screen.move(2, 7)
  screen.font_size(8)
  screen.text("ROTA")

  -- Top right: bandmate style or MANUAL
  if bandmate_on then
    screen.level(12)
    screen.move(86, 7)
    screen.font_size(8)
    local style_name = BANDMATE_STYLES[bandmate_style].name
    screen.text_right(style_name)
    -- Pulsing dot
    local pulse = math.floor((math.sin(frame * 0.3) * 0.5 + 0.5) * 13) + 2
    screen.level(pulse)
    screen.circle(90, 4, 2)
    screen.fill()
  else
    screen.level(5)
    screen.move(90, 7)
    screen.font_size(8)
    screen.text_right("MANUAL")
  end

  -- Three encoder param bars (left column, below title)
  draw_param_bar("C", chaos, 2, 17, 28)
  draw_param_bar("M", mass / 1.5, 2, 25, 28)
  draw_param_bar("R", roughness, 2, 33, 28)

  -- Scale name below param bars
  screen.level(5)
  screen.move(2, 42)
  screen.font_size(7)
  screen.text(SCALES[scale_idx])

  -- Rungler arc visualization (right side, middle)
  draw_rungler_arc()

  -- Motor bars (bottom)
  draw_motor_bars()

  screen.update()
end

-- -----------------------------------------------------------------------
-- INIT
-- -----------------------------------------------------------------------

function init()
  rebuild_scale()

  -- ---- PARAMS ----
  params:add_separator("ROTA")

  params:add_control("chaos", "chaos",
    controlspec.new(0, 1, "lin", 0.01, 0.4, ""))
  params:set_action("chaos", function(v)
    chaos = v
    rungler.feedback = v
    update_globals()
    screen_dirty = true
  end)

  params:add_control("mass", "mass",
    controlspec.new(0, 1.5, "lin", 0.01, 0.5, ""))
  params:set_action("mass", function(v)
    mass = v
    screen_dirty = true
  end)

  params:add_control("roughness", "roughness",
    controlspec.new(0, 1, "lin", 0.01, 0.2, ""))
  params:set_action("roughness", function(v)
    roughness = v
    update_globals()
    screen_dirty = true
  end)

  params:add_control("rev_time", "reverb time",
    controlspec.new(0.5, 12, "exp", 0.1, 3.0, "s"))
  params:set_action("rev_time", function(v)
    pcall(function() engine.rev_time(v) end)
  end)

  params:add_control("rev_mix", "reverb mix",
    controlspec.new(0, 1, "lin", 0.01, 0.35, ""))
  params:set_action("rev_mix", function(v)
    pcall(function() engine.rev_mix(v) end)
  end)

  params:add_control("rev_size", "reverb size",
    controlspec.new(0.5, 5, "lin", 0.1, 1.2, ""))
  params:set_action("rev_size", function(v)
    pcall(function() engine.rev_size(v) end)
  end)

  params:add_number("scale", "scale", 1, #SCALES, scale_idx)
  params:set_action("scale", function(v)
    scale_idx = v
    rebuild_scale()
    screen_dirty = true
  end)

  params:add_number("root", "root (MIDI)", 24, 48, scale_root)
  params:set_action("root", function(v)
    scale_root = v
    rebuild_scale()
  end)

  params:add_binary("quantize", "quantize", "toggle", 1)
  params:set_action("quantize", function(v)
    quantize = v == 1
  end)

  params:add_control("rungler_speed", "rungler speed",
    controlspec.new(0.125, 8, "exp", 0.01, 1.0, "x"))
  params:set_action("rungler_speed", function(v)
    rungler.speed = v
  end)

  -- ---- BANDMATE PARAMS ----
  params:add_separator("BANDMATE")

  local style_names = {}
  for i, s in ipairs(BANDMATE_STYLES) do
    style_names[i] = s.name
  end

  params:add_option("bandmate_style", "bandmate style", style_names, 1)
  params:set_action("bandmate_style", function(v)
    bandmate_style = v
    screen_dirty = true
  end)

  params:add_binary("bandmate_on", "bandmate", "toggle", 0)
  params:set_action("bandmate_on", function(v)
    bandmate_on = v == 1
    if bandmate_on then
      for i = 1, NUM_VOICES do
        motors[i].on = true
        motors[i].amp = 0.15 + math.random() * 0.15
        send_voice(i)
      end
    end
    screen_dirty = true
  end)

  -- ---- MIDI OUT PARAMS ----
  params:add_separator("MIDI OUT")

  params:add_number("midi_out_dev", "midi out device", 1, 16, 1)
  params:set_action("midi_out_dev", function(v)
    midi_all_notes_off()
    midi_out_device = midi.connect(v)
  end)

  params:add_number("midi_out_ch_base", "midi base channel", 1, 16, 1)
  params:set_action("midi_out_ch_base", function(v)
    midi_all_notes_off()
    midi_out_ch_base = v
  end)

  params:bang()

  -- Grid setup
  g.key = grid_key

  -- Start the lattice
  setup_lattice()

  -- Initial engine state
  update_globals()
  pcall(function() engine.rev_mix(0.35) end)
  pcall(function() engine.rev_time(3.0) end)

  -- Spin up first 4 voices quietly
  for i = 1, 4 do
    motors[i].on  = true
    motors[i].amp = 0.12
    send_voice(i)
  end

  -- Screen refresh timer (store reference for cleanup)
  screen_metro = metro.init()
  screen_metro.time = 1 / 15  -- 15 fps
  screen_metro.event = function()
    if screen_dirty then redraw() end
  end
  screen_metro:start()

  -- Grid refresh timer
  grid_metro = metro.init()
  grid_metro.time = 1 / 20
  grid_metro.event = function()
    grid_redraw()
  end
  grid_metro:start()
end

function cleanup()
  -- Stop all MIDI notes
  midi_all_notes_off()

  -- Stop metros
  if screen_metro then screen_metro:stop() end
  if grid_metro then grid_metro:stop() end

  -- Destroy lattice
  if auto_lattice then
    auto_lattice:destroy()
  end
end
