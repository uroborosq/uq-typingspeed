local h = require('helpers')

local function new_meter()
  return require('typingspeed.meter').new({ window_ms = 10000, warmup_ms = 2000 })
end

return {
  { 'rate() is nil without events', function()
    h.reset()
    h.eq(nil, new_meter():rate(0))
  end },

  { 'rate() is nil during warm-up and a number after it', function()
    h.reset()
    local m = new_meter()
    m:add(0, 1)
    h.eq(nil, m:rate(1500))
    h.eq(30, m:rate(2000)) -- 1 char / 2 s = 30 cpm
  end },

  { 'rate() counts net characters', function()
    h.reset()
    local m = new_meter()
    for _ = 1, 60 do
      m:add(0, 1)
    end
    m:add(0, -5)
    h.eq(55, m:net())
    h.eq(330, m:rate(10000))
  end },

  { 'events older than the window are dropped', function()
    h.reset()
    local m = new_meter()
    m:add(0, 1)
    h.eq(false, m:empty(10000))
    h.eq(nil, m:rate(10001))
    h.eq(true, m:empty(10001))
    h.eq(0, m:net())
  end },

  { 'rate() never goes below zero', function()
    h.reset()
    local m = new_meter()
    m:add(0, 1)
    m:add(0, -3)
    h.eq(0, m:rate(5000))
  end },

  { 'elapsed time is capped by the window', function()
    h.reset()
    local m = new_meter()
    m:add(0, 1)
    m:add(9000, 1)
    h.eq(6, m:rate(15000)) -- one event left, divided by the full 10 s window
  end },

  { 'a pause longer than the window starts a new streak', function()
    h.reset()
    local m = new_meter()
    m:add(0, 1)
    m:add(20000, 1)
    h.eq(20, m:rate(23000)) -- 1 char / 3 s since the new streak started
  end },
}
