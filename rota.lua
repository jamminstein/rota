-- rota.lua
-- Ciat-Lombarde Rungler + Motor Synth inertia engine for norns
--
-- A chaotic self-generating synthesizer built from two ideas:
--   1. Peter Blasser's rungler: a shift register that eats its own output
--   2. Motor Synth's physical inertia: pitch as a moving physical object
--
-- 8 "motor" voices with physical mass, each gated rhythmically by the
-- rungler. The system feeds itself: shift register bits determine WHICH
-- voices sound and WHEN. Not every step plays. Silence is musical.
--
-- Controls:
--   ENC1       -> chaos / rungler feedback depth
--   ENC2       -> global inertia (motor mass)
--   ENC3       -> grind (electromechanical roughness)
--   KEY2       -> toggle bandmate (tap) / cycle style (hold)
--   KEY3       -> reseed / reset rungler

engine.name = "Rota"

local musicutil = require "musicutil"
local lattice   = require "lattice"
local util      = require "util"

-- -----------------------------------------------------------------------
-- MIDI OUT
-- -----------------------------------------------------------------------

local midi_out_device = nil
local midi_out_ch_base = 1
local midi_active_notes = {}
for i = 1, 8 do midi_active_notes[i] = nil end

-- -----------------------------------------------------------------------
-- STATE
-- -----------------------------------------------------------------------

local NUM_VOICES = 8

-- Rungler (8-bit shift register)
local rungler = {
  reg      = 180,          -- seed
  value    = 0,            -- current output 0..1
  prev_val = 0,            -- previous value for motion detection
  feedback = 0.4,
  speed    = 1.0,
  step_acc = 0,
  step_count = 0,          -- total steps taken (for per-voice dividers)
}

-- VOICE ROLES — each motor has a musical identity
-- bass voices (1-2): low, slow, foundational
-- mid voices (3-5): melodic, moderate motion
-- high voices (6-8): accents, fast, sparse
local VOICE_ROLES = {
  {name="bass",  base_oct=-1, range=12, div=2, density=0.8,  amp_lo=0.22, amp_hi=0.38, gate_len=6},
  {name="bass",  base_oct=-1, range=14, div=2, density=0.7,  amp_lo=0.20, amp_hi=0.35, gate_len=5},
  {name="mid",   base_oct=0,  range=19, div=1, density=0.65, amp_lo=0.16, amp_hi=0.32, gate_len=4},
  {name="mid",   base_oct=0,  range=17, div=1, density=0.6,  amp_lo=0.15, amp_hi=0.30, gate_len=3},
  {name="mid",   base_oct=0,  range=21, div=1, density=0.55, amp_lo=0.14, amp_hi=0.28, gate_len=3},
  {name="high",  base_oct=1,  range=14, div=1, density=0.45, amp_lo=0.10, amp_hi=0.22, gate_len=2},
  {name="high",  base_oct=1,  range=12, div=1, density=0.4,  amp_lo=0.08, amp_hi=0.20, gate_len=2},
  {name="high",  base_oct=2,  range=10, div=1, density=0.35, amp_lo=0.07, amp_hi=0.18, gate_len=2},
}

-- Motor voice state
local motors = {}
for i = 1, NUM_VOICES do
  local role = VOICE_ROLES[i]
  motors[i] = {
    on            = false,        -- voice enabled (can be gated)
    gated         = false,        -- currently sounding
    freq          = 55,
    target_freq   = 55,
    amp           = 0.0,
    target_amp    = 0.0,
    inertia       = 0.2 + (i * 0.06),
    grind         = 0.15,
    pitch_offset  = 0,
    gate_counter  = 0,            -- counts down to gate-off
    last_note     = 0,            -- for MIDI note-off
    active_bright = 0,
  }
end

-- Scale system
local SCALES = {
  "chromatic", "minor", "major", "dorian",
  "pentatonic minor", "whole tone", "phrygian"
}
local scale_idx   = 2
local scale_root  = 36        -- C2 MIDI
local scale_notes = {}
local quantize    = true

-- Density control: global gate probability multiplier
local density = 0.7  -- 0=silence, 1=full density

-- -----------------------------------------------------------------------
-- BANDMATE SYSTEM
-- -----------------------------------------------------------------------

local BANDMATE_STYLES = {
  {
    name = "DRIFT",
    chaos_lo = 0.15, chaos_hi = 0.45,
    mass_lo  = 0.4,  mass_hi  = 0.9,
    rough_lo = 0.05, rough_hi = 0.2,
    density_lo = 0.3, density_hi = 0.6,
    evolution_speed   = 0.025,
    scale_change_prob = 0.015,
    reverb_mix_target = 0.6,
    reverb_time_target = 7.0,
    reseed_prob       = 0.008,
    topology_mutate_prob = 0.015,
    voice_toggle_prob = 0.015,
  },
  {
    name = "SURGE",
    chaos_lo = 0.1,  chaos_hi = 0.8,
    mass_lo  = 0.2,  mass_hi  = 0.9,
    rough_lo = 0.05, rough_hi = 0.5,
    density_lo = 0.25, density_hi = 0.9,
    evolution_speed   = 0.06,
    scale_change_prob = 0.03,
    reverb_mix_target = 0.4,
    reverb_time_target = 4.0,
    reseed_prob       = 0.015,
    topology_mutate_prob = 0.025,
    voice_toggle_prob = 0.025,
  },
  {
    name = "SWARM",
    chaos_lo = 0.3,  chaos_hi = 0.55,
    mass_lo  = 0.08, mass_hi  = 0.4,
    rough_lo = 0.1,  rough_hi = 0.35,
    density_lo = 0.6, density_hi = 0.95,
    evolution_speed   = 0.1,
    scale_change_prob = 0.025,
    reverb_mix_target = 0.25,
    reverb_time_target = 2.0,
    reseed_prob       = 0.025,
    topology_mutate_prob = 0.04,
    voice_toggle_prob = 0.1,
  },
  {
    name = "BLASSER",
    chaos_lo = 0.55, chaos_hi = 0.9,
    mass_lo  = 0.15, mass_hi  = 0.6,
    rough_lo = 0.2,  rough_hi = 0.55,
    density_lo = 0.35, density_hi = 0.75,
    evolution_speed   = 0.08,
    scale_change_prob = 0.05,
    reverb_mix_target = 0.35,
    reverb_time_target = 3.5,
    reseed_prob       = 0.08,
    topology_mutate_prob = 0.12,
    voice_toggle_prob = 0.05,
  },
  {
    name = "GLACIAL",
    chaos_lo = 0.08, chaos_hi = 0.25,
    mass_lo  = 0.9,  mass_hi  = 1.4,
    rough_lo = 0.0,  rough_hi = 0.1,
    density_lo = 0.15, density_hi = 0.35,
    evolution_speed   = 0.012,
    scale_change_prob = 0.02,
    reverb_mix_target = 0.75,
    reverb_time_target = 10.0,
    reseed_prob       = 0.003,
    topology_mutate_prob = 0.008,
    voice_toggle_prob = 0.008,
  },
  {
    name = "RUPTURE",
    chaos_lo = 0.25, chaos_hi = 0.95,
    mass_lo  = 0.05, mass_hi  = 0.4,
    rough_lo = 0.1,  rough_hi = 0.9,
    density_lo = 0.2, density_hi = 0.85,
    evolution_speed   = 0.15,
    scale_change_prob = 0.04,
    reverb_mix_target = 0.2,
    reverb_time_target = 1.5,
    reseed_prob       = 0.1,
    topology_mutate_prob = 0.08,
    voice_toggle_prob = 0.1,
  },
}

local bandmate_on    = false
local bandmate_style = 1
local bandmate_phase = 0

local surge_direction = 1
local surge_progress  = 0

local key2_down_time = nil

-- Grid
local g         = grid.connect()
local grid_page = 1
local held_grid = {}

-- Screen
local screen_dirty = true
local frame        = 0

-- Global params
local chaos     = 0.4
local mass      = 0.5
local roughness = 0.2

-- Topology
local topology = {true, true, false, false, false, false, false, false}

-- Metro/lattice refs
local auto_lattice = nil
local screen_metro = nil
local grid_metro   = nil

-- -----------------------------------------------------------------------
-- SCALE UTILITIES
-- -----------------------------------------------------------------------

local function rebuild_scale()
  scale_notes = musicutil.generate_scale(scale_root, SCALES[scale_idx], 6)
end

local function quantize_midi(midi_note)
  if not quantize then return midi_note end
  return musicutil.snap_note_to_array(midi_note, scale_notes)
end

local function midi_to_hz(n)
  return musicutil.note_num_to_freq(n)
end

-- -----------------------------------------------------------------------
-- MIDI OUT UTILITIES
-- -----------------------------------------------------------------------

local function midi_note_on(voice, midi_note, vel)
  if midi_out_device == nil then return end
  local ch = midi_out_ch_base + voice - 1
  if ch > 16 then return end
  if midi_active_notes[voice] then
    pcall(function()
      midi_out_device:note_off(midi_active_notes[voice].note, 0, midi_active_notes[voice].ch)
    end)
  end
  pcall(function()
    midi_out_device:note_on(midi_note, vel, ch)
  end)
  midi_active_notes[voice] = {note = midi_note, ch = ch}
end

local function midi_note_off(voice)
  if midi_out_device == nil then return end
  if midi_active_notes[voice] then
    pcall(function()
      midi_out_device:note_off(midi_active_notes[voice].note, 0, midi_active_notes[voice].ch)
    end)
    midi_active_notes[voice] = nil
  end
end

local function midi_all_notes_off()
  for i = 1, NUM_VOICES do midi_note_off(i) end
end

-- -----------------------------------------------------------------------
-- RUNGLER LOGIC
-- -----------------------------------------------------------------------

local function rungler_step()
  local reg = rungler.reg

  -- XOR feedback: bits 0, 1, 3 (Blasser topology)
  local b0 = reg & 1
  local b1 = (reg >> 1) & 1
  local b3 = (reg >> 3) & 1
  local new_bit = (b0 ~ b1 ~ b3) & 1

  -- Shift + insert
  reg = ((reg >> 1) | (new_bit << 7)) & 0xFF

  -- Chaos injection
  if math.random() < (rungler.feedback * 0.18) then
    local flip_pos = math.floor(math.random() * 8)
    reg = reg ~ (1 << flip_pos)
  end

  rungler.reg = reg
  rungler.step_count = rungler.step_count + 1

  -- DAC: use bits 5,6,7 for pitch value (top 3 bits = more variation)
  local val = (((reg >> 5) & 0x07)) / 7.0

  -- Less smoothing = more motion, more life
  rungler.prev_val = rungler.value
  rungler.value = rungler.value + (val - rungler.value) * 0.6

  return rungler.value
end

-- Per-voice gate decision: uses different rungler bits per voice
-- This is what creates RHYTHM from chaos
local function should_voice_gate(v_idx, rung_val)
  local role = VOICE_ROLES[v_idx]

  -- Each voice uses a different bit of the register for gating
  local gate_bit = (rungler.reg >> ((v_idx - 1) % 8)) & 1

  -- Combine with density and per-role density
  local prob = density * role.density

  -- Gate bit provides rhythmic structure
  -- When gate_bit = 1: high probability of sounding
  -- When gate_bit = 0: still possible (ghost notes / fills)
  if gate_bit == 1 then
    return math.random() < prob
  else
    return math.random() < (prob * 0.25)  -- ghost notes
  end
end

-- Map rungler value to a MIDI note for a given voice
-- Each voice has its own register, range, and character
local function rungler_to_midi(v_idx, rung_val)
  local role = VOICE_ROLES[v_idx]
  local base = scale_root + (role.base_oct * 12)
  local range = role.range

  -- Each voice reads the register differently for independence
  -- Voice gets a shifted view of the rungler
  local shifted_reg = ((rungler.reg >> (v_idx - 1)) | (rungler.reg << (8 - (v_idx - 1)))) & 0xFF
  local voice_val = (shifted_reg & 0x1F) / 31.0  -- 5-bit DAC per voice

  -- Blend with global rungler for some coherence
  local blended = voice_val * 0.7 + rung_val * 0.3

  local raw = base + math.floor(blended * range)
  raw = raw + motors[v_idx].pitch_offset
  return quantize_midi(math.floor(raw))
end

-- -----------------------------------------------------------------------
-- ENGINE COMMANDS
-- -----------------------------------------------------------------------

local function send_voice(i)
  local m = motors[i]
  local amp = (m.on and m.gated) and m.amp or 0.0
  pcall(function() engine.freq(i - 1, midi_to_hz(m.target_freq)) end)
  pcall(function() engine.amp(i - 1, amp) end)
  pcall(function() engine.inertia(i - 1, m.inertia) end)
  pcall(function() engine.grind_v(i - 1, m.grind) end)
end

local function update_globals()
  pcall(function() engine.grind(roughness) end)
  pcall(function() engine.phase_noise(roughness * 0.04) end)
  pcall(function() engine.drive(0.1 + roughness * 0.3) end)
  pcall(function() engine.rolloff(12000 - (roughness * 5000)) end)
end

-- Silence a voice (gate off) — motor spins down with lag
local function gate_off(i)
  motors[i].gated = false
  motors[i].gate_counter = 0
  pcall(function() engine.amp_lag(i - 1, 0.3) end)  -- slow spin-down
  pcall(function() engine.amp(i - 1, 0.0) end)
  midi_note_off(i)
end

-- Gate on — motor spins up
local function gate_on_lag(i)
  pcall(function() engine.amp_lag(i - 1, 0.08) end)  -- fast spin-up
end

-- -----------------------------------------------------------------------
-- BANDMATE BEHAVIORS
-- -----------------------------------------------------------------------

local function get_style()
  return BANDMATE_STYLES[bandmate_style]
end

local function bandmate_evolve_params()
  local s = get_style()
  local speed = s.evolution_speed

  if bandmate_style == 2 then
    -- SURGE: build up then pull back
    surge_progress = surge_progress + speed * 0.4
    if surge_progress >= 1.0 then
      surge_progress = 0
      surge_direction = -surge_direction
    end
    local t = surge_progress
    if surge_direction == 1 then
      chaos = s.chaos_lo + (s.chaos_hi - s.chaos_lo) * t
      mass  = s.mass_lo + (s.mass_hi - s.mass_lo) * t * 0.6
      roughness = s.rough_lo + (s.rough_hi - s.rough_lo) * t * 0.4
      density = s.density_lo + (s.density_hi - s.density_lo) * t
    else
      chaos = s.chaos_hi - (s.chaos_hi - s.chaos_lo) * math.min(t * 1.8, 1)
      mass  = s.mass_hi - (s.mass_hi - s.mass_lo) * t
      roughness = s.rough_hi - (s.rough_hi - s.rough_lo) * t
      density = s.density_hi - (s.density_hi - s.density_lo) * math.min(t * 1.5, 1)
    end
  elseif bandmate_style == 6 then
    -- RUPTURE: sudden jumps
    if math.random() < speed then
      chaos = s.chaos_lo + math.random() * (s.chaos_hi - s.chaos_lo)
      density = s.density_lo + math.random() * (s.density_hi - s.density_lo)
    end
    if math.random() < speed * 0.6 then
      mass = s.mass_lo + math.random() * (s.mass_hi - s.mass_lo)
    end
    if math.random() < 0.06 then
      roughness = s.rough_hi
    elseif roughness > s.rough_lo + 0.05 then
      roughness = roughness - 0.03
    end
  else
    -- Sine-based evolution
    local t = bandmate_phase
    chaos = (s.chaos_lo + s.chaos_hi) / 2 + math.sin(t * 0.7) * (s.chaos_hi - s.chaos_lo) / 2
    mass = (s.mass_lo + s.mass_hi) / 2 + math.sin(t * 0.3) * (s.mass_hi - s.mass_lo) / 2
    roughness = (s.rough_lo + s.rough_hi) / 2 + math.sin(t * 0.5) * (s.rough_hi - s.rough_lo) / 2
    density = (s.density_lo + s.density_hi) / 2 + math.sin(t * 0.4) * (s.density_hi - s.density_lo) / 2
  end

  chaos     = util.clamp(chaos, 0.0, 1.0)
  mass      = util.clamp(mass, 0.0, 1.5)
  roughness = util.clamp(roughness, 0.0, 1.0)
  density   = util.clamp(density, 0.0, 1.0)

  rungler.feedback = chaos
  update_globals()
  params:set("chaos", chaos, true)
  params:set("mass", mass, true)
  params:set("roughness", roughness, true)
end

local function bandmate_pick_voices()
  local s = get_style()
  for i = 1, NUM_VOICES do
    if math.random() < s.voice_toggle_prob then
      if bandmate_style == 5 then
        -- GLACIAL: max 3 voices
        local count = 0
        for j = 1, NUM_VOICES do if motors[j].on then count = count + 1 end end
        if count < 3 and not motors[i].on then
          motors[i].on = math.random() < 0.25
        elseif count > 3 then
          motors[i].on = false
        end
      elseif bandmate_style == 6 then
        -- RUPTURE: group slams
        if math.random() < 0.25 then
          local on = math.random() < 0.5
          local start = math.random(1, 4)
          for j = start, math.min(start + 2, NUM_VOICES) do
            motors[j].on = on
          end
        end
      else
        motors[i].on = math.random() < s.density_lo + (s.density_hi - s.density_lo) * 0.5
      end
    end
  end
  -- Always ensure at least 1 voice is on
  local any_on = false
  for i = 1, NUM_VOICES do if motors[i].on then any_on = true end end
  if not any_on then motors[math.random(1, NUM_VOICES)].on = true end
end

local function bandmate_evolve_harmony()
  local s = get_style()
  if math.random() < s.scale_change_prob then
    if bandmate_style == 5 then
      scale_idx = ({6, 7})[math.random(2)]
    elseif bandmate_style == 4 then
      if math.random() < 0.3 then
        quantize = not quantize
        params:set("quantize", quantize and 1 or 0, true)
      end
      scale_idx = math.random(1, #SCALES)
    else
      scale_idx = ({2, 2, 4, 4, 5, 5, 3})[math.random(7)]
    end
    params:set("scale", scale_idx, true)
    rebuild_scale()
  end
  if math.random() < s.scale_change_prob * 0.5 then
    scale_root = 24 + ({0, 2, 3, 5, 7, 8, 10})[math.random(7)]
    params:set("root", scale_root, true)
    rebuild_scale()
  end
end

local function bandmate_update_inertia()
  for i = 1, NUM_VOICES do
    local base = mass * 0.8
    local variation
    if bandmate_style == 3 then
      variation = math.sin(bandmate_phase * 2.0 + i * 1.7) * 0.35
    elseif bandmate_style == 5 then
      base = mass * 1.0
      variation = math.sin(bandmate_phase * 0.1 + i) * 0.08
    else
      variation = math.sin(bandmate_phase * 0.2 + i * 1.3) * 0.2
    end
    motors[i].inertia = math.max(0.05, base + variation)
    pcall(function() engine.inertia(i - 1, motors[i].inertia) end)
  end
end

local function bandmate_mutate_topology()
  local s = get_style()
  if math.random() < s.topology_mutate_prob then
    topology[math.random(1, NUM_VOICES)] = not topology[math.random(1, NUM_VOICES)]
  end
end

local function bandmate_maybe_reseed()
  local s = get_style()
  if math.random() < s.reseed_prob then
    rungler.reg = math.random(1, 255)
    for i = 1, NUM_VOICES do
      motors[i].pitch_offset = math.random(-4, 4)
    end
  end
end

local function bandmate_evolve_reverb()
  local s = get_style()
  local cur_mix = params:get("rev_mix")
  local cur_time = params:get("rev_time")
  params:set("rev_mix", cur_mix + (s.reverb_mix_target - cur_mix) * 0.04, true)
  params:set("rev_time", cur_time + (s.reverb_time_target - cur_time) * 0.025, true)
  pcall(function() engine.rev_mix(params:get("rev_mix")) end)
  pcall(function() engine.rev_time(params:get("rev_time")) end)
end

-- -----------------------------------------------------------------------
-- CORE CLOCK
-- The musical heart: rungler drives rhythm AND pitch.
-- Per-voice step dividers create polyrhythmic independence.
-- Gate lengths create articulation (staccato vs legato).
-- -----------------------------------------------------------------------

local function setup_lattice()
  if auto_lattice then auto_lattice:destroy() end
  auto_lattice = lattice:new()

  -- MAIN CLOCK: rungler step + voice gating (1/8 = 16th notes)
  auto_lattice:new_sprocket({
    action = function(t)
      local ok, err = pcall(function()
        -- Speed accumulator
        rungler.step_acc = rungler.step_acc + rungler.speed
        if rungler.step_acc < 1.0 then
          -- Even when rungler doesn't step, count down gates
          for i = 1, NUM_VOICES do
            if motors[i].gate_counter > 0 then
              motors[i].gate_counter = motors[i].gate_counter - 1
              if motors[i].gate_counter <= 0 then
                gate_off(i)
              end
            end
          end
          screen_dirty = true
          return
        end
        rungler.step_acc = rungler.step_acc - 1.0

        local rung = rungler_step()
        local step = rungler.step_count

        -- Process each voice independently
        for i = 1, NUM_VOICES do
          local role = VOICE_ROLES[i]
          local m = motors[i]

          -- Count down active gates
          if m.gate_counter > 0 then
            m.gate_counter = m.gate_counter - 1
            if m.gate_counter <= 0 then
              gate_off(i)
            end
          end

          -- Check if this voice should step (per-voice clock divider)
          if step % role.div == 0 and m.on then
            -- Should this voice gate on this step?
            if should_voice_gate(i, rung) then
              -- New note!
              local midi_note = rungler_to_midi(i, rung)

              -- Velocity from rungler + role range
              local vel_raw = role.amp_lo + rung * (role.amp_hi - role.amp_lo)
              -- Add accent: occasional louder hits
              if math.random() < 0.15 then
                vel_raw = vel_raw * 1.4
              end
              m.amp = util.clamp(vel_raw, 0.0, 0.45)

              -- Set target and gate
              m.target_freq = midi_note
              m.gated = true
              m.gate_counter = role.gate_len

              -- Send to engine: fast spin-up, then freq+amp
              gate_on_lag(i)
              local hz = midi_to_hz(midi_note)
              engine.freq(i - 1, hz)
              engine.amp(i - 1, m.amp)

              -- MIDI out
              local midi_vel = math.floor(util.clamp(m.amp * 320, 1, 127))
              midi_note_on(i, midi_note, midi_vel)

              m.active_bright = 12
            end
          end

          -- Decay the visual brightness
          if m.active_bright > 0 then
            m.active_bright = m.active_bright - 1
          end
        end

        screen_dirty = true
      end)
      if not ok then print("[rota] clock error: " .. tostring(err)) end
    end,
    division = 1 / 8,
    enabled  = true
  })

  -- BANDMATE CLOCK 1: harmony + voices (7/4 beats)
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

  -- BANDMATE CLOCK 2: params + inertia (11/4 beats)
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

  -- BANDMATE CLOCK 3: reverb (13/4 beats)
  auto_lattice:new_sprocket({
    action = function(t)
      pcall(function()
        if bandmate_on then bandmate_evolve_reverb() end
      end)
    end,
    division = 13 / 4,
    enabled  = true
  })

  -- SCREEN ANIMATION (1/16)
  auto_lattice:new_sprocket({
    action = function(t)
      frame = frame + 1
      screen_dirty = true
    end,
    division = 1 / 16,
    enabled  = true
  })

  auto_lattice:start()
  print("[rota] lattice started OK")
end

-- -----------------------------------------------------------------------
-- GRID INTERFACE
-- -----------------------------------------------------------------------

local BRIGHT = {
  OFF = 0, GHOST = 2, DIM = 4, MID = 8, BRIGHT = 12, FULL = 15
}

local function grid_redraw()
  if g == nil then return end
  g:all(0)

  if grid_page == 1 then
    for i = 1, NUM_VOICES do
      local m = motors[i]
      -- Row 1: on/off + gated flash
      local r1_bright = BRIGHT.DIM
      if m.on and m.gated then r1_bright = BRIGHT.FULL
      elseif m.on then r1_bright = BRIGHT.MID end
      g:led(i, 1, r1_bright)

      -- Row 2: pitch offset
      local offset_norm = (m.pitch_offset + 12) / 24.0
      g:led(i, 2, math.floor(offset_norm * 11) + 2)

      -- Row 3: inertia
      g:led(i, 3, math.floor(m.inertia / 1.5 * 11) + 2)

      -- Row 4: grind
      g:led(i, 4, math.floor(m.grind * 11) + 2)

      -- Rows 5-6: activity meter
      local ab = m.active_bright or 0
      g:led(i, 5, ab > 4 and BRIGHT.BRIGHT or BRIGHT.GHOST)
      g:led(i, 6, ab > 8 and BRIGHT.FULL or BRIGHT.GHOST)

      -- Row 7: scale
      if i <= #SCALES then
        g:led(i, 7, (i == scale_idx) and BRIGHT.FULL or BRIGHT.DIM)
      end
    end

    -- Row 8: controls
    g:led(1, 8, bandmate_on and BRIGHT.FULL or BRIGHT.DIM)
    g:led(2, 8, quantize and BRIGHT.BRIGHT or BRIGHT.DIM)
    if bandmate_on then
      for i = 3, 2 + bandmate_style do
        if i <= 8 then g:led(i, 8, BRIGHT.MID) end
      end
    end
    -- Density indicator: cols 10-16
    local dens_leds = math.floor(density * 7)
    for i = 1, 7 do
      g:led(9 + i, 8, i <= dens_leds and BRIGHT.MID or BRIGHT.GHOST)
    end
    g:led(16, 8, BRIGHT.MID)

  elseif grid_page == 2 then
    for i = 1, NUM_VOICES do
      g:led(i, 1, topology[i] and BRIGHT.FULL or BRIGHT.DIM)
    end
    for bit = 0, 7 do
      g:led(bit + 1, 2, ((rungler.reg >> bit) & 1) == 1 and BRIGHT.BRIGHT or BRIGHT.GHOST)
      g:led(bit + 1, 3, bit < math.floor(rungler.value * 8) and BRIGHT.MID or BRIGHT.DIM)
    end
    local speed_steps = {0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 8.0}
    for i = 1, 8 do
      g:led(i, 4, math.abs(speed_steps[i] - rungler.speed) < 0.01 and BRIGHT.FULL or BRIGHT.DIM)
    end
    local root_oct = scale_root % 12
    for i = 1, 12 do
      g:led(i, 7, (i - 1 == root_oct) and BRIGHT.FULL or BRIGHT.DIM)
    end
    g:led(1, 8, BRIGHT.MID)
  end

  g:refresh()
end

local function grid_key(x, y, z)
  local kid = x .. "," .. y
  if z == 1 then held_grid[kid] = {x = x, y = y, t = util.time()}
  else held_grid[kid] = nil end
  if z == 0 then return end

  if grid_page == 1 then
    if y == 1 and x <= NUM_VOICES then
      motors[x].on = not motors[x].on
      if not motors[x].on then gate_off(x) end

    elseif y == 2 and x <= NUM_VOICES then
      local offsets = {-12, -7, -5, 0, 5, 7, 12}
      local cur = motors[x].pitch_offset
      local ni = 1
      for i, v in ipairs(offsets) do
        if v == cur then ni = (i % #offsets) + 1; break end
      end
      motors[x].pitch_offset = offsets[ni]

    elseif y == 3 and x <= NUM_VOICES then
      local lvls = {0.05, 0.15, 0.3, 0.5, 0.8, 1.2}
      local cur = motors[x].inertia
      local ni = 1
      for i, v in ipairs(lvls) do
        if math.abs(v - cur) < 0.05 then ni = (i % #lvls) + 1; break end
      end
      motors[x].inertia = lvls[ni]
      pcall(function() engine.inertia(x - 1, motors[x].inertia) end)

    elseif y == 4 and x <= NUM_VOICES then
      local lvls = {0.0, 0.1, 0.25, 0.45, 0.7, 1.0}
      local cur = motors[x].grind
      local ni = 1
      for i, v in ipairs(lvls) do
        if math.abs(v - cur) < 0.05 then ni = (i % #lvls) + 1; break end
      end
      motors[x].grind = lvls[ni]
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
          -- Turn on a few voices, not all
          for i = 1, NUM_VOICES do
            motors[i].on = (i <= 3) or (math.random() < 0.3)
          end
        end
      elseif x == 2 then
        quantize = not quantize
        params:set("quantize", quantize and 1 or 0, true)
      elseif x >= 3 and x <= 8 then
        local sn = x - 2
        if sn <= #BANDMATE_STYLES then
          bandmate_style = sn
          params:set("bandmate_style", bandmate_style, true)
        end
      elseif x == 16 then
        grid_page = 2
      end
    end

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
    elseif y == 8 and x == 1 then
      grid_page = 1
    end
  end

  grid_redraw()
  screen_dirty = true
end

-- -----------------------------------------------------------------------
-- NORNS CONTROLS
-- -----------------------------------------------------------------------

function enc(n, d)
  if n == 1 then
    chaos = util.clamp(chaos + d * 0.02, 0.0, 1.0)
    rungler.feedback = chaos
    params:set("chaos", chaos, true)
    update_globals()
  elseif n == 2 then
    mass = util.clamp(mass + d * 0.02, 0.0, 1.5)
    params:set("mass", mass, true)
    for i = 1, NUM_VOICES do
      motors[i].inertia = mass * (0.4 + i * 0.1)
      pcall(function() engine.inertia(i - 1, motors[i].inertia) end)
    end
  elseif n == 3 then
    roughness = util.clamp(roughness + d * 0.02, 0.0, 1.0)
    params:set("roughness", roughness, true)
    update_globals()
  end
  screen_dirty = true
end

function key(n, z)
  if n == 2 then
    if z == 1 then
      key2_down_time = util.time()
    else
      if key2_down_time then
        local dur = util.time() - key2_down_time
        if dur > 0.5 then
          bandmate_style = (bandmate_style % #BANDMATE_STYLES) + 1
          params:set("bandmate_style", bandmate_style, true)
        else
          bandmate_on = not bandmate_on
          params:set("bandmate_on", bandmate_on and 2 or 1, true)
          if bandmate_on then
            for i = 1, NUM_VOICES do
              motors[i].on = (i <= 3) or (math.random() < 0.3)
            end
          end
        end
        key2_down_time = nil
      end
    end
  elseif n == 3 and z == 1 then
    rungler.reg = math.random(1, 255)
    rungler.value = 0
    for i = 1, NUM_VOICES do
      motors[i].pitch_offset = math.random(-4, 4)
    end
  end
  screen_dirty = true
end

-- -----------------------------------------------------------------------
-- SCREEN
-- -----------------------------------------------------------------------

local function draw_motor_bars()
  local bar_w = 11
  local bar_h = 18
  local y_base = 63
  local x_start = 2
  local gap = 2

  for i = 1, NUM_VOICES do
    local x = x_start + (i - 1) * (bar_w + gap)
    local m = motors[i]

    -- Role indicator: thin line at top shows voice type
    local role = VOICE_ROLES[i]
    if role.name == "bass" then
      screen.level(m.on and 6 or 2)
      screen.rect(x, y_base - bar_h - 2, bar_w, 1)
      screen.fill()
    elseif role.name == "high" then
      screen.level(m.on and 4 or 1)
      screen.pixel(x + 2, y_base - bar_h - 2)
      screen.pixel(x + 5, y_base - bar_h - 2)
      screen.pixel(x + 8, y_base - bar_h - 2)
      screen.fill()
    end

    -- Border: brighter when gated
    screen.level(m.gated and 10 or (m.on and 4 or 1))
    screen.rect(x, y_base - bar_h, bar_w, bar_h)
    screen.stroke()

    -- Fill: amplitude
    local level = (m.on and m.gated) and m.amp or 0
    local h = math.floor(level / 0.45 * bar_h)
    if h > 0 then
      screen.level(m.gated and 15 or 3)
      screen.rect(x + 1, y_base - h, bar_w - 2, h)
      screen.fill()
    end

    -- Frequency dot
    if m.on and m.target_freq and m.target_freq > 0 then
      local note_norm = util.clamp((m.target_freq - 24) / 60, 0, 1)
      local dot_y = y_base - 2 - math.floor(note_norm * (bar_h - 4))
      screen.level(m.gated and 15 or 6)
      screen.rect(x + math.floor(bar_w/2) - 1, dot_y, 3, 1)
      screen.fill()
    end
  end
end

local function draw_rungler_arc()
  local cx = 108
  local cy = 20
  local r = 8 + math.floor(chaos * 6)
  screen.level(3)
  screen.circle(cx, cy, r)
  screen.stroke()

  for bit = 0, 7 do
    local angle = (bit / 8.0) * 2 * math.pi - (math.pi / 2)
    local bval = (rungler.reg >> bit) & 1
    local bx = cx + math.cos(angle) * r
    local by = cy + math.sin(angle) * r
    screen.level(bval == 1 and 15 or 2)
    screen.circle(bx, by, 1.5)
    screen.fill()
  end

  -- Center: rungler value
  screen.level(math.floor(rungler.value * 12) + 2)
  screen.circle(cx, cy, 2.5)
  screen.fill()
end

local function draw_param_bar(label, value, x, y, w)
  screen.level(6)
  screen.move(x, y)
  screen.font_size(8)
  screen.text(label)
  screen.level(2)
  screen.rect(x + 10, y - 5, w, 3)
  screen.fill()
  screen.level(12)
  screen.rect(x + 10, y - 5, math.floor(util.clamp(value, 0, 1) * w), 3)
  screen.fill()
end

function redraw()
  if not screen_dirty then return end
  screen_dirty = false
  screen.clear()
  screen.font_face(1)
  screen.aa(0)

  -- Title
  screen.level(10)
  screen.move(2, 7)
  screen.font_size(8)
  screen.text("ROTA")

  -- Bandmate style / MANUAL
  if bandmate_on then
    screen.level(12)
    screen.move(88, 7)
    screen.font_size(8)
    screen.text_right(BANDMATE_STYLES[bandmate_style].name)
    local pulse = math.floor((math.sin(frame * 0.25) * 0.5 + 0.5) * 13) + 2
    screen.level(pulse)
    screen.circle(92, 4, 1.5)
    screen.fill()
  else
    screen.level(4)
    screen.move(92, 7)
    screen.font_size(8)
    screen.text_right("MANUAL")
  end

  -- Param bars
  draw_param_bar("C", chaos, 2, 16, 26)
  draw_param_bar("M", mass / 1.5, 2, 23, 26)
  draw_param_bar("R", roughness, 2, 30, 26)

  -- Density bar
  draw_param_bar("D", density, 2, 37, 26)

  -- Scale
  screen.level(5)
  screen.move(44, 37)
  screen.font_size(7)
  screen.text(SCALES[scale_idx])

  -- Rungler arc
  draw_rungler_arc()

  -- Motor bars
  draw_motor_bars()

  screen.update()
end

-- -----------------------------------------------------------------------
-- INIT
-- -----------------------------------------------------------------------

function init()
  rebuild_scale()

  params:add_separator("ROTA")

  params:add_control("chaos", "chaos",
    controlspec.new(0, 1, "lin", 0.01, 0.4, ""))
  params:set_action("chaos", function(v)
    chaos = v; rungler.feedback = v; update_globals(); screen_dirty = true
  end)

  params:add_control("mass", "mass",
    controlspec.new(0, 1.5, "lin", 0.01, 0.5, ""))
  params:set_action("mass", function(v)
    mass = v; screen_dirty = true
  end)

  params:add_control("roughness", "roughness",
    controlspec.new(0, 1, "lin", 0.01, 0.2, ""))
  params:set_action("roughness", function(v)
    roughness = v; update_globals(); screen_dirty = true
  end)

  params:add_control("density", "density",
    controlspec.new(0, 1, "lin", 0.01, 0.7, ""))
  params:set_action("density", function(v)
    density = v; screen_dirty = true
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
    scale_idx = v; rebuild_scale(); screen_dirty = true
  end)

  params:add_number("root", "root (MIDI)", 24, 48, scale_root)
  params:set_action("root", function(v)
    scale_root = v; rebuild_scale()
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

  -- BANDMATE
  params:add_separator("BANDMATE")

  local style_names = {}
  for i, s in ipairs(BANDMATE_STYLES) do style_names[i] = s.name end

  params:add_option("bandmate_style", "bandmate style", style_names, 1)
  params:set_action("bandmate_style", function(v)
    bandmate_style = v; screen_dirty = true
  end)

  params:add_binary("bandmate_on", "bandmate", "toggle", 0)
  params:set_action("bandmate_on", function(v)
    bandmate_on = v == 1
    if bandmate_on then
      for i = 1, NUM_VOICES do
        motors[i].on = (i <= 3) or (math.random() < 0.3)
      end
    end
    screen_dirty = true
  end)

  -- MIDI OUT
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

  -- Grid
  g.key = grid_key

  -- Start lattice
  setup_lattice()

  -- Init engine
  update_globals()
  pcall(function() engine.rev_mix(0.35) end)
  pcall(function() engine.rev_time(3.0) end)

  -- Start with bass + mid voices on (3 voices)
  for i = 1, NUM_VOICES do
    motors[i].on = (i <= 3)
    motors[i].amp = 0.0
    motors[i].gated = false
  end

  -- Send initial state to engine
  for i = 1, NUM_VOICES do
    send_voice(i)
  end

  -- Screen timer
  screen_metro = metro.init()
  screen_metro.time = 1 / 15
  screen_metro.event = function()
    if screen_dirty then redraw() end
  end
  screen_metro:start()

  -- Grid timer
  grid_metro = metro.init()
  grid_metro.time = 1 / 20
  grid_metro.event = function() grid_redraw() end
  grid_metro:start()
end

function cleanup()
  midi_all_notes_off()
  if screen_metro then screen_metro:stop() end
  if grid_metro then grid_metro:stop() end
  if auto_lattice then auto_lattice:destroy() end
end
