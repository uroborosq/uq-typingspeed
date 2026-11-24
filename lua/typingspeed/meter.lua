--- Sliding-window speed meter. Pure Lua, no Neovim API; time is passed in milliseconds.
local Meter = {}
Meter.__index = Meter

--- @param opts { window_ms: number, warmup_ms: number }
function Meter.new(opts)
  return setmetatable({
    window_ms = opts.window_ms,
    warmup_ms = opts.warmup_ms,
    events = {}, -- { t = ms, delta = chars }, ordered by t
    sum = 0, -- sum of delta over events
    streak_start = nil, -- t of the first event added to an empty queue
  }, Meter)
end

--- Drops events older than the window.
function Meter:prune(now)
  local cutoff = now - self.window_ms
  while self.events[1] and self.events[1].t < cutoff do
    self.sum = self.sum - table.remove(self.events, 1).delta
  end
end

--- Records `delta` characters (+1 typed, -N deleted) at time `t`.
function Meter:add(t, delta)
  self:prune(t)
  if #self.events == 0 then
    self.streak_start = t
  end
  table.insert(self.events, { t = t, delta = delta })
  self.sum = self.sum + delta
end

--- True when no events remain in the window.
function Meter:empty(now)
  self:prune(now)
  return #self.events == 0
end

--- Net characters currently in the window (may be negative).
function Meter:net()
  return self.sum
end

--- Characters per minute, or nil when there is no data or the streak is still warming up.
function Meter:rate(now)
  if self:empty(now) then
    return nil
  end
  local elapsed = math.min(self.window_ms, now - self.streak_start)
  if elapsed < self.warmup_ms then
    return nil
  end
  return math.max(0, self.sum) / elapsed * 60000
end

return Meter
