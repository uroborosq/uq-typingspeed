local h = require('helpers')

--- Sets up the plugin with a controllable clock; returns a setter for the current time.
local function setup(opts)
  h.reset()
  local now = 0
  opts._clock = function()
    return now
  end
  require('typingspeed').setup(opts)
  return function(t)
    now = t
  end
end

return {
  { 'status() is empty before setup()', function()
    h.reset()
    h.eq('', require('typingspeed').status())
  end },

  { 'status() is empty without typing', function()
    setup({})
    h.eq('', require('typingspeed').status())
  end },

  { 'status() reports wpm by default', function()
    local set_time = setup({})
    h.type('i' .. string.rep('a', 55) .. '<Esc>')
    set_time(10000)
    h.eq('66 wpm', require('typingspeed').status())
  end },

  { 'status() reports cpm when configured', function()
    local set_time = setup({ unit = 'cpm' })
    h.type('i' .. string.rep('a', 55) .. '<Esc>')
    set_time(10000)
    h.eq('330 cpm', require('typingspeed').status())
  end },

  { 'status() reports several units in the configured order', function()
    local set_time = setup({ unit = { 'wpm', 'cpm' } })
    h.type('i' .. string.rep('a', 55) .. '<Esc>')
    set_time(10000)
    h.eq('66 wpm / 330 cpm', require('typingspeed').status())
  end },

  { 'status() with a single-element list matches the string form', function()
    local set_time = setup({ unit = { 'cpm' } })
    h.type('i' .. string.rep('a', 55) .. '<Esc>')
    set_time(10000)
    h.eq('330 cpm', require('typingspeed').status())
  end },

  { 'status() uses the configured window', function()
    local set_time = setup({ window = 3 })
    h.type('iabc<Esc>')
    set_time(3001)
    h.eq('', require('typingspeed').status())
  end },

  { 'setup() rejects invalid options', function()
    h.reset()
    h.raises('unit:', function()
      require('typingspeed').setup({ unit = 'foo' })
    end)
    h.raises('window:', function()
      require('typingspeed').setup({ window = 1 })
    end)
  end },
}
