local h = require('helpers')

return {
  { 'resolve() returns defaults for nil', function()
    h.reset()
    h.eq({ unit = 'wpm', window = 10 }, require('typingspeed.config').resolve(nil))
  end },

  { 'resolve() merges user options', function()
    h.reset()
    h.eq({ unit = 'cpm', window = 30 }, require('typingspeed.config').resolve({ unit = 'cpm', window = 30 }))
  end },

  { 'resolve() rejects unknown unit', function()
    h.reset()
    h.raises("unit: expected 'wpm' or 'cpm', got foo", function()
      require('typingspeed.config').resolve({ unit = 'foo' })
    end)
  end },

  { 'resolve() rejects window below 3 seconds', function()
    h.reset()
    h.raises('window: expected number >= 3, got 1', function()
      require('typingspeed.config').resolve({ window = 1 })
    end)
  end },

  { 'resolve() rejects non-number window', function()
    h.reset()
    h.raises('window: expected number >= 3', function()
      require('typingspeed.config').resolve({ window = '10' })
    end)
  end },
}
