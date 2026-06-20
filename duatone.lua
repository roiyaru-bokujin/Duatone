-- duatone v1.2
-- 2-channel tone generator
--
-- by @good.sines
--
--
--
--    ▼ instructions below ▼
--
-- e1 selects preset
-- e2 tunes selected side
-- e3 changes waveform
-- k2 selects side (L/R)
-- k2+e2 coarse tunes side
-- k2+e3 changes volume
-- k3 toggles phase motion
-- k3+e2 manual phase adjust

engine.name = "Duatone"

local controlspec = require "controlspec"
local util = require "util"

local WAVE_NAMES = { "SINE", "SQUARE", "TRI", "SAW" }
local BASE_AMP = 0.14
local FREQ_MIN = 20.0
local FREQ_MAX = 4000.0
local PHASE_MIN = 0
local PHASE_MAX = 359
local MOD_BOUND_MIN = 0
local MOD_BOUND_MAX = 360
local PAN_MIN = -1.0
local PAN_MAX = 1.0
local VOLUME_MIN = 0.0
local VOLUME_MAX = 1.0
local DEFAULT_SWEEP_MODE = 1
local SWEEP_MODE_NAMES = { "WRAP", "PING-PONG" }
local DIM_LEVEL = 2
local VOLUME_ICON_BITS = { 0x08, 0x4c, 0x8f, 0xaf, 0xaf, 0x8f, 0x4c, 0x08 }
local VOLUME_MUTE_ICON_BITS = { 0x08, 0x0c, 0xaf, 0x4f, 0x4f, 0xaf, 0x0c, 0x08 }
local SINGLE_NOTE_BITS = { 0x08, 0x18, 0x28, 0x08, 0x08, 0x0e, 0x0d, 0x0f, 0x06 }
local WAVE_ICON_BITS = {
  { 0x040c, 0x0412, 0x0222, 0x0241, 0x0181 },
  { 0x007c, 0x0044, 0x0044, 0x0044, 0x07c7 },
  { 0x0020, 0x0050, 0x0088, 0x0104, 0x0603 },
  { 0x0100, 0x01c0, 0x0130, 0x010c, 0x0703 },
}

local PRESETS = {
  {
    name = "OVAL",
    channel = {
      { wave = 1, freq = 220.0, phase = 45, phase_rate = 0 },
      { wave = 1, freq = 220.0, phase = 135, phase_rate = 10 },
    }
  },
  {
    name = "FIGURE8",
    channel = {
      { wave = 1, freq = 220.0, phase = 0, phase_rate = 0 },
      { wave = 1, freq = 440.0, phase = 0, phase_rate = 18 },
    }
  },
  {
    name = "TREFOIL",
    channel = {
      { wave = 1, freq = 220.0, phase = 0, phase_rate = 0 },
      { wave = 1, freq = 330.0, phase = 90, phase_rate = 24 },
    }
  },
  {
    name = "TRIKNOT",
    channel = {
      { wave = 1, freq = 330.0, phase = 0, phase_rate = 0 },
      { wave = 1, freq = 220.0, phase = 90, phase_rate = 20 },
    }
  },
  {
    name = "ORBIT",
    channel = {
      { wave = 1, freq = 330.0, phase = 0, phase_rate = 0 },
      { wave = 1, freq = 440.0, phase = 90, phase_rate = 12 },
    }
  },
  {
    name = "DRIFT",
    channel = {
      { wave = 1, freq = 221.0, phase = 0, phase_rate = 0 },
      { wave = 4, freq = 220.0, phase = 180, phase_rate = 8 },
    }
  },
  {
    name = "ROSETTE",
    channel = {
      { wave = 1, freq = 550.0, phase = 0, phase_rate = 0 },
      { wave = 1, freq = 220.0, phase = 72, phase_rate = 16 },
    }
  },
}

local state = {
  selected_side = 1,
  shift = false,
  shift_used = false,
  volume_hold = false,
  phase_hold = false,
  phase_used = false,
  master = 1.0,
  preset_index = 3,
  preset_dirty = false,
  sweep_mode = DEFAULT_SWEEP_MODE,
  channel = {
    { wave = 1, freq = 220.0, phase = 0, phase_rate = 0, default_phase_rate = 0, mod_min = 0, mod_max = 360, pan = -1.0, mod_enabled = false, mod_direction = 1, volume = 1.0 },
    { wave = 2, freq = 220.0, phase = 0, phase_rate = 0, default_phase_rate = 0, mod_min = 0, mod_max = 360, pan = 1.0, mod_enabled = false, mod_direction = 1, volume = 1.0 },
  },
  center_mark_phase = 0,
  phase_clock = nil,
  last_phase_tick = 0,
}

local params_ready = false
local syncing_param = false
local saved_dry_mix = nil

local DRY_PARAM_CANDIDATES = {
  { id = "monitor_rev", value = 0 },
  { id = "cut_rev", value = 0 },
  { id = "ext_rev", value = 0 },
  { id = "adc_rev", value = 0 },
  { id = "tape_rev", value = 0 },
  { id = "rev_level", value = 0 },
  { id = "output_monitor_rev", value = 0 },
  { id = "output_cut_rev", value = 0 },
  { id = "output_ext_rev", value = 0 },
  { id = "output_adc_rev", value = 0 },
  { id = "output_tape_rev", value = 0 },
}

local function wrap_index(index, count)
  while index < 1 do
    index = index + count
  end
  while index > count do
    index = index - count
  end
  return index
end

local function round_step(value, step)
  return math.floor((value / step) + 0.5) * step
end

local function engine_call(name, ...)
  local fn = engine and engine[name]
  if type(fn) ~= "function" then
    return false
  end
  local ok = pcall(fn, ...)
  return ok
end

local function effective_amp(channel)
  local voice = state.channel[channel]
  return BASE_AMP * state.master * voice.volume
end

local function centered_text(text, x, y, level)
  screen.level(level)
  screen.move(x, y)
  screen.text_center(text)
end

local function sync_param(id, value)
  if not params_ready or syncing_param then
    return
  end
  syncing_param = true
  params:set(id, value)
  syncing_param = false
end

local function fmt_freq(value)
  if value >= 1000 then
    return string.format("%.1fk", value / 1000.0)
  end
  if value >= 100 then
    return string.format("%d", math.floor(value + 0.5))
  end
  return string.format("%.1f", value)
end

local function fmt_phase(value)
  return string.format("%03d", math.floor(value + 0.5))
end

local function wrap_phase(value)
  value = value % 360
  if value < 0 then
    value = value + 360
  end
  return value
end

local function clamp_mod_bound(value)
  return util.clamp(math.floor(value + 0.5), MOD_BOUND_MIN, MOD_BOUND_MAX)
end

local function clamp_pan(value)
  return util.clamp(round_step(value, 0.01), PAN_MIN, PAN_MAX)
end

local function fmt_volume(value)
  return string.format("%d", math.floor(value * 100 + 0.5))
end

local function mark_custom()
  state.preset_dirty = true
end

local apply_channel

local function reset_mod_direction(channel)
  local voice = state.channel[channel]
  voice.mod_direction = 1
end

local function phase_in_mod_bounds(voice)
  return voice.phase >= voice.mod_min and voice.phase <= voice.mod_max
end

local function move_phase_to_mod_min(channel)
  local voice = state.channel[channel]
  voice.phase = voice.mod_min
  voice.mod_direction = 1
end

local function sync_mod_bounds(channel)
  if channel == 1 then
    sync_param("l_mod_span_min", state.channel[channel].mod_min)
    sync_param("l_mod_span_max", state.channel[channel].mod_max)
  else
    sync_param("r_mod_span_min", state.channel[channel].mod_min)
    sync_param("r_mod_span_max", state.channel[channel].mod_max)
  end
end

local function normalize_mod_bounds(channel, edited_bound)
  local voice = state.channel[channel]
  if edited_bound == "min" and voice.mod_min > voice.mod_max then
    voice.mod_max = voice.mod_min
  elseif edited_bound == "max" and voice.mod_max < voice.mod_min then
    voice.mod_min = voice.mod_max
  end

  if voice.mod_enabled and not phase_in_mod_bounds(voice) then
    move_phase_to_mod_min(channel)
    apply_channel(channel)
  end

  sync_mod_bounds(channel)
end

apply_channel = function(channel)
  local voice = state.channel[channel]
  engine_call("wave", channel, voice.wave - 1)
  engine_call("hz", channel, voice.freq)
  engine_call("phase", channel, voice.phase)
  engine_call("amp", channel, effective_amp(channel))
  engine_call("pan", channel, voice.pan)
end

local function apply_state()
  apply_channel(1)
  apply_channel(2)
end

local function capture_and_set_dry_mix()
  saved_dry_mix = {}
  for _, entry in ipairs(DRY_PARAM_CANDIDATES) do
    local ok_get, current = pcall(function()
      return params:get(entry.id)
    end)
    if ok_get and current ~= nil then
      saved_dry_mix[entry.id] = current
      pcall(function()
        params:set(entry.id, entry.value)
      end)
    end
  end
end

local function restore_dry_mix()
  if saved_dry_mix == nil then
    return
  end
  for id, value in pairs(saved_dry_mix) do
    pcall(function()
      params:set(id, value)
    end)
  end
  saved_dry_mix = nil
end

local function wave_level(selected)
  return selected and 13 or 5
end

local function text_level(selected, strong)
  if selected then
    return strong and 15 or 12
  end
  return strong and 9 or DIM_LEVEL
end

local function draw_text(x, y, text, align_right)
  screen.move(x, y)
  if align_right then
    screen.text_right(text)
  else
    screen.text(text)
  end
end

local draw_bitmap_rows

local function draw_wave_icon(wave, x, y, w, h, level)
  local rows = WAVE_ICON_BITS[wave]
  if rows == nil then
    return
  end
  draw_bitmap_rows(x, y, rows, 11, level, nil)
end

local function draw_preset_dots(index, count, x, y, spacing)
  local start_x = x - (((count - 1) * spacing) / 2)
  for i = 1, count do
    screen.level(i == index and 15 or DIM_LEVEL)
    screen.rect(start_x + ((i - 1) * spacing), y, 2, 2)
    screen.fill()
  end
end

draw_bitmap_rows = function(x, y, rows, width, bright_level, dim_level)
  for row = 1, #rows do
    local bits = rows[row]
    for col = 0, width - 1 do
      local bit_on = math.floor(bits / (2 ^ col)) % 2 == 1
      if bit_on then
        screen.level(bright_level or 15)
        screen.pixel(x + col, y + row - 1)
        screen.fill()
      elseif dim_level ~= nil then
        screen.level(dim_level)
        screen.pixel(x + col, y + row - 1)
        screen.fill()
      end
    end
  end
end

local function draw_volume_rail(channel, x, icon_x)
  local rail_top = 11
  local rail_bottom = 51
  local rail_h = rail_bottom - rail_top
  local volume = state.channel[channel].volume
  local filled_h = math.floor(rail_h * volume + 0.5)
  local y0 = rail_bottom - filled_h
  local icon_bits = volume <= VOLUME_MIN and VOLUME_MUTE_ICON_BITS or VOLUME_ICON_BITS

  screen.level(DIM_LEVEL)
  screen.move(x, rail_top)
  screen.line(x, rail_bottom)
  screen.stroke()

  screen.level(15)
  screen.move(x, y0)
  screen.line(x, rail_bottom)
  screen.stroke()
  draw_bitmap_rows(icon_x, 55, icon_bits, 8, 15, nil)
end

local function draw_phase_label(channel, x, align_right)
  local text = "P" .. fmt_phase(state.channel[channel].phase)
  screen.level(text_level(state.selected_side == channel, false))
  draw_text(x, 7, text, align_right)
end

local function draw_channel_disc(channel, cx, cy, active)
  local selected = state.selected_side == channel
  local voice = state.channel[channel]
  local radius = 22

  screen.level(active and 15 or 13)
  screen.circle(cx, cy, radius)
  screen.fill()

  screen.level(active and 15 or DIM_LEVEL)
  screen.circle(cx, cy, 25)
  screen.stroke()

  screen.level(15)
  screen.circle(cx, cy, radius)
  screen.stroke()

  centered_text(WAVE_NAMES[voice.wave], cx - 1, cy - 11, 0)

  screen.font_size(18)
  centered_text(fmt_freq(voice.freq), cx, cy + 5, 0)

  screen.font_size(8)
  draw_wave_icon(voice.wave, cx - 5, cy + 10, 11, 5, 0)
end

local function draw_footer()
  draw_preset_dots(state.preset_index, #PRESETS, 62, 61, 4)
end

local function draw_center_mark(cx, y)
  local x = cx - 3
  local icon_y = y + 2 + state.center_mark_phase
  draw_bitmap_rows(x, icon_y, SINGLE_NOTE_BITS, 6, 15, nil)
end

local function set_channel_volume(channel, value, update_param)
  state.channel[channel].volume = util.clamp(value, VOLUME_MIN, VOLUME_MAX)
  apply_channel(channel)
  if update_param then
    sync_param(channel == 1 and "l_volume" or "r_volume", state.channel[channel].volume * 100)
  end
end

local function set_master_volume(value, update_param)
  state.master = util.clamp(value, VOLUME_MIN, VOLUME_MAX)
  apply_channel(1)
  apply_channel(2)
  if update_param then
    sync_param("global_volume", state.master * 100)
  end
end

local function install_params()
  params:add_separator("duatone_levels", "duatone levels")
  params:add_control(
    "l_volume",
    "L volume",
    controlspec.new(0, 100, "lin", 1, state.channel[1].volume * 100, "%")
  )
  params:set_action("l_volume", function(value)
    set_channel_volume(1, value / 100, false)
    redraw()
  end)

  params:add_control(
    "r_volume",
    "R volume",
    controlspec.new(0, 100, "lin", 1, state.channel[2].volume * 100, "%")
  )
  params:set_action("r_volume", function(value)
    set_channel_volume(2, value / 100, false)
    redraw()
  end)

  params:add_control(
    "global_volume",
    "global volume",
    controlspec.new(0, 100, "lin", 1, state.master * 100, "%")
  )
  params:set_action("global_volume", function(value)
    set_master_volume(value / 100, false)
    redraw()
  end)

  params:add_separator("duatone_mod", "duatone modulation")

  params:add_option("phase_sweep", "phase sweep", SWEEP_MODE_NAMES, state.sweep_mode)
  params:set_action("phase_sweep", function(value)
    state.sweep_mode = value
    if state.channel[1].mod_enabled and not phase_in_mod_bounds(state.channel[1]) then
      move_phase_to_mod_min(1)
      apply_channel(1)
    end
    if state.channel[2].mod_enabled and not phase_in_mod_bounds(state.channel[2]) then
      move_phase_to_mod_min(2)
      apply_channel(2)
    end
    redraw()
  end)

  params:add_control(
    "l_mod_rate",
    "L mod rate",
    controlspec.new(0, 60, "lin", 0.5, state.channel[1].phase_rate, "")
  )
  params:set_action("l_mod_rate", function(value)
    state.channel[1].phase_rate = round_step(value, 0.5)
    if state.channel[1].phase_rate > 0 then
      state.channel[1].default_phase_rate = state.channel[1].phase_rate
    end
    redraw()
  end)

  params:add_control(
    "r_mod_rate",
    "R mod rate",
    controlspec.new(0, 60, "lin", 0.5, state.channel[2].phase_rate, "")
  )
  params:set_action("r_mod_rate", function(value)
    state.channel[2].phase_rate = round_step(value, 0.5)
    if state.channel[2].phase_rate > 0 then
      state.channel[2].default_phase_rate = state.channel[2].phase_rate
    end
    redraw()
  end)

  params:add_control(
    "l_mod_span_min",
    "L mod span min",
    controlspec.new(0, 360, "lin", 1, state.channel[1].mod_min, "")
  )
  params:set_action("l_mod_span_min", function(value)
    state.channel[1].mod_min = clamp_mod_bound(value)
    normalize_mod_bounds(1, "min")
    redraw()
  end)

  params:add_control(
    "l_mod_span_max",
    "L mod span max",
    controlspec.new(0, 360, "lin", 1, state.channel[1].mod_max, "")
  )
  params:set_action("l_mod_span_max", function(value)
    state.channel[1].mod_max = clamp_mod_bound(value)
    normalize_mod_bounds(1, "max")
    redraw()
  end)

  params:add_control(
    "r_mod_span_min",
    "R mod span min",
    controlspec.new(0, 360, "lin", 1, state.channel[2].mod_min, "")
  )
  params:set_action("r_mod_span_min", function(value)
    state.channel[2].mod_min = clamp_mod_bound(value)
    normalize_mod_bounds(2, "min")
    redraw()
  end)

  params:add_control(
    "r_mod_span_max",
    "R mod span max",
    controlspec.new(0, 360, "lin", 1, state.channel[2].mod_max, "")
  )
  params:set_action("r_mod_span_max", function(value)
    state.channel[2].mod_max = clamp_mod_bound(value)
    normalize_mod_bounds(2, "max")
    redraw()
  end)

  params:add_control(
    "l_pan",
    "L pan",
    controlspec.new(-1, 1, "lin", 0.01, state.channel[1].pan, "")
  )
  params:set_action("l_pan", function(value)
    state.channel[1].pan = clamp_pan(value)
    apply_channel(1)
    redraw()
  end)

  params:add_control(
    "r_pan",
    "R pan",
    controlspec.new(-1, 1, "lin", 0.01, state.channel[2].pan, "")
  )
  params:set_action("r_pan", function(value)
    state.channel[2].pan = clamp_pan(value)
    apply_channel(2)
    redraw()
  end)

  params_ready = true
  sync_param("l_volume", state.channel[1].volume * 100)
  sync_param("r_volume", state.channel[2].volume * 100)
  sync_param("global_volume", state.master * 100)
  sync_param("phase_sweep", state.sweep_mode)
  sync_param("l_mod_rate", state.channel[1].phase_rate)
  sync_param("r_mod_rate", state.channel[2].phase_rate)
  sync_mod_bounds(1)
  sync_mod_bounds(2)
  sync_param("l_pan", state.channel[1].pan)
  sync_param("r_pan", state.channel[2].pan)
end

local function recall_preset(index)
  local preset = PRESETS[index]
  for channel = 1, 2 do
    local source = preset.channel[channel]
    local target = state.channel[channel]
    target.wave = source.wave
    target.freq = source.freq
    target.phase = source.phase
    target.phase_rate = source.phase_rate or 0
    target.default_phase_rate = source.phase_rate == 0 and 12 or source.phase_rate
    target.mod_enabled = target.phase_rate ~= 0
    reset_mod_direction(channel)
    if target.mod_enabled and not phase_in_mod_bounds(target) then
      move_phase_to_mod_min(channel)
    end
  end
  state.preset_index = index
  state.preset_dirty = false
  sync_param("l_mod_rate", state.channel[1].phase_rate)
  sync_param("r_mod_rate", state.channel[2].phase_rate)
  apply_state()
end

local function step_preset(delta)
  if delta == 0 then
    return
  end
  local next_index = wrap_index(state.preset_index + delta, #PRESETS)
  recall_preset(next_index)
end

local function select_side(delta)
  if delta == 0 then
    state.selected_side = wrap_index(state.selected_side + 1, 2)
  else
    state.selected_side = wrap_index(state.selected_side + delta, 2)
  end
end

local function adjust_wave(channel, delta)
  if delta == 0 then
    return
  end
  state.channel[channel].wave = wrap_index(state.channel[channel].wave + delta, #WAVE_NAMES)
  mark_custom()
  apply_channel(channel)
end

local function adjust_freq(channel, delta, fine)
  if delta == 0 then
    return
  end
  local freq = state.channel[channel].freq
  if fine then
    freq = freq + (delta * 0.25)
  else
    freq = freq * math.pow(2, delta / 36)
  end
  state.channel[channel].freq = util.clamp(round_step(freq, 0.1), FREQ_MIN, FREQ_MAX)
  mark_custom()
  apply_channel(channel)
end

local function adjust_volume(channel, delta)
  if delta == 0 then
    return
  end
  local step = 0.02
  set_channel_volume(channel, round_step(state.channel[channel].volume + (delta * step), 0.01), true)
end

local function adjust_phase(channel, delta)
  if delta == 0 then
    return
  end
  local step = 3
  local phase = state.channel[channel].phase + (delta * step)
  local voice = state.channel[channel]
  voice.phase = wrap_phase(phase)
  voice.mod_enabled = false
  reset_mod_direction(channel)
  mark_custom()
  apply_channel(channel)
end

local function toggle_phase_mod(channel)
  local voice = state.channel[channel]
  if voice.phase_rate == 0 then
    voice.phase_rate = voice.default_phase_rate
    sync_param(channel == 1 and "l_mod_rate" or "r_mod_rate", voice.phase_rate)
  end
  if voice.phase_rate == 0 then
    voice.phase_rate = 12
    voice.default_phase_rate = 12
    sync_param(channel == 1 and "l_mod_rate" or "r_mod_rate", voice.phase_rate)
  end
  if not voice.mod_enabled and not phase_in_mod_bounds(voice) then
    move_phase_to_mod_min(channel)
    apply_channel(channel)
  end
  voice.mod_enabled = not voice.mod_enabled
end

local function update_phase_wrap(voice, delta_phase)
  local span = voice.mod_max - voice.mod_min
  if span <= 0 then
    voice.phase = voice.mod_min
    return false
  end

  local phase = voice.phase
  if phase < voice.mod_min or phase > voice.mod_max then
    phase = voice.mod_min
  end
  voice.phase = voice.mod_min + (((phase - voice.mod_min) + delta_phase) % span)
  return true
end

local function update_phase_ping_pong(voice, delta_phase)
  if voice.mod_max <= voice.mod_min then
    voice.phase = voice.mod_min
    return false
  end

  local next_phase = (phase_in_mod_bounds(voice) and voice.phase or voice.mod_min) + (delta_phase * voice.mod_direction)
  while next_phase > voice.mod_max or next_phase < voice.mod_min do
    if next_phase > voice.mod_max then
      next_phase = voice.mod_max - (next_phase - voice.mod_max)
      voice.mod_direction = -1
    elseif next_phase < voice.mod_min then
      next_phase = voice.mod_min + (voice.mod_min - next_phase)
      voice.mod_direction = 1
    end
  end

  voice.phase = next_phase
  return true
end

function redraw()
  screen.clear()
  screen.aa(0)
  screen.font_size(8)

  screen.level(state.selected_side == 1 and 15 or DIM_LEVEL)
  draw_text(0, 7, "L", false)
  screen.level(state.selected_side == 2 and 15 or DIM_LEVEL)
  draw_text(127, 7, "R", true)
  draw_phase_label(1, 14, false)
  draw_phase_label(2, 114, true)

  centered_text("DUATONE", 64, 7, 15)
  draw_center_mark(64, 11)

  draw_volume_rail(1, 1, 0)
  draw_volume_rail(2, 126, 120)
  draw_channel_disc(1, 33, 37, state.selected_side == 1)
  draw_channel_disc(2, 93, 37, state.selected_side == 2)
  draw_footer()

  screen.update()
end

local function phase_tick()
  local now = util.time()
  if state.last_phase_tick == 0 then
    state.last_phase_tick = now
    return
  end

  local dt = now - state.last_phase_tick
  state.last_phase_tick = now
  local changed = false
  local center_mark_phase = math.floor(now) % 2

  if center_mark_phase ~= state.center_mark_phase then
    state.center_mark_phase = center_mark_phase
    changed = true
  end

  for channel = 1, 2 do
    local voice = state.channel[channel]
    if voice.mod_enabled and voice.phase_rate ~= 0 then
      local delta_phase = voice.phase_rate * dt
      local moved = false
      if state.sweep_mode == 1 then
        moved = update_phase_wrap(voice, delta_phase)
      else
        moved = update_phase_ping_pong(voice, delta_phase)
      end
      if moved then
        apply_channel(channel)
        changed = true
      end
    end
  end

  if changed then
    redraw()
  end
end

function init()
  capture_and_set_dry_mix()
  install_params()
  recall_preset(3)
  state.last_phase_tick = util.time()
  state.center_mark_phase = math.floor(state.last_phase_tick) % 2
  state.phase_clock = metro.init(phase_tick, 1 / 20, -1)
  state.phase_clock:start()
  redraw()
end

function enc(n, delta)
  if n == 1 then
    step_preset(delta)
  elseif n == 2 then
    if state.phase_hold then
      state.phase_used = true
      adjust_phase(state.selected_side, delta)
    elseif state.shift then
      state.shift_used = true
      adjust_freq(state.selected_side, delta, false)
    else
      adjust_freq(state.selected_side, delta, true)
    end
  elseif n == 3 then
    if state.shift then
      state.shift_used = true
      state.volume_hold = true
      adjust_volume(state.selected_side, delta)
    else
      adjust_wave(state.selected_side, delta)
    end
  end

  redraw()
end

function key(n, z)
  if n == 2 then
    if z == 1 then
      state.shift = true
      state.shift_used = false
      state.volume_hold = false
    else
      state.shift = false
      state.volume_hold = false
      if not state.shift_used then
        select_side(0)
      end
      state.shift_used = false
    end
  elseif n == 3 and z == 1 then
    if state.shift then
      state.shift_used = true
    end
    state.phase_hold = true
    state.phase_used = false
  elseif n == 3 and z == 0 then
    if state.phase_hold and not state.phase_used then
      toggle_phase_mod(state.selected_side)
    end
    state.phase_hold = false
    state.phase_used = false
  end

  redraw()
end

function cleanup()
  if state.phase_clock ~= nil then
    state.phase_clock:stop()
    state.phase_clock = nil
  end
  engine_call("amp", 1, 0)
  engine_call("amp", 2, 0)
  restore_dry_mix()
end
