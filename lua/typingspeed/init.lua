local config = require('typingspeed.config')
local tracker = require('typingspeed.tracker')

local M = {}

local WARMUP_MS = 2000

local SEPARATOR = ' / '

local cfg = nil
local units = nil -- cfg.unit normalized to a list

--- @param opts? { unit?: 'wpm'|'cpm'|('wpm'|'cpm')[], window?: number }
function M.setup(opts)
  cfg = config.resolve(opts)
  units = type(cfg.unit) == 'string' and { cfg.unit } or cfg.unit
  tracker.start({
    window_ms = cfg.window * 1000,
    warmup_ms = WARMUP_MS,
    clock = cfg._clock, -- private hook for tests
  })
end

--- Statusline string: "62 wpm", "310 cpm" or "62 wpm / 310 cpm" (in the order of
--- `unit`), or "" when there is no data.
function M.status()
  if not cfg then
    return ''
  end
  local cpm = tracker.rate()
  if not cpm then
    return ''
  end
  local parts = {}
  for _, unit in ipairs(units) do
    local value = unit == 'wpm' and cpm / 5 or cpm
    parts[#parts + 1] = string.format('%d %s', math.floor(value + 0.5), unit)
  end
  return table.concat(parts, SEPARATOR)
end

return M
