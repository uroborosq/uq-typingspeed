local config = require('typingspeed.config')
local tracker = require('typingspeed.tracker')

local M = {}

local WARMUP_MS = 2000

local cfg = nil

--- @param opts? { unit?: 'wpm'|'cpm', window?: number }
function M.setup(opts)
  cfg = config.resolve(opts)
  tracker.start({
    window_ms = cfg.window * 1000,
    warmup_ms = WARMUP_MS,
    clock = cfg._clock, -- private hook for tests
  })
end

--- Statusline string: "62 wpm" / "310 cpm", or "" when there is no data.
function M.status()
  if not cfg then
    return ''
  end
  local cpm = tracker.rate()
  if not cpm then
    return ''
  end
  local value = cfg.unit == 'wpm' and cpm / 5 or cpm
  return string.format('%d %s', math.floor(value + 0.5), cfg.unit)
end

return M
