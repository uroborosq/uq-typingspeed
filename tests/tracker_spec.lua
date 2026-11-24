local h = require('helpers')

--- Resets state and starts the tracker with a frozen clock (t = 0).
local function start()
  h.reset()
  local tracker = require('typingspeed.tracker')
  tracker.start({ window_ms = 10000, warmup_ms = 2000, clock = function() return 0 end })
  return tracker
end

return {
  { 'counts typed ASCII characters', function()
    local tracker = start()
    h.type('iabc<Esc>')
    h.eq(3, tracker.net())
  end },

  { 'counts Cyrillic as characters, not bytes', function()
    local tracker = start()
    h.type('iабв<BS><Esc>')
    h.eq(2, tracker.net())
  end },

  { '<BS> subtracts the deleted character', function()
    local tracker = start()
    h.type('iabc<BS><Esc>')
    h.eq(2, tracker.net())
  end },

  { '<C-W> through the default mapping subtracts the word', function()
    local tracker = start()
    h.type('ifoo bar<C-W><Esc>')
    h.eq(4, tracker.net())
  end },

  { '<CR> and <Tab> count once each with expandtab', function()
    local tracker = start()
    vim.bo.expandtab = true
    vim.bo.shiftwidth = 2
    h.type('ia<Tab>b<CR>c<Esc>')
    h.eq(5, tracker.net())
  end },

  { '<CR> and <Tab> count once each with noexpandtab', function()
    local tracker = start()
    vim.bo.expandtab = false
    h.type('ia<Tab>b<CR>c<Esc>')
    h.eq(5, tracker.net())
  end },

  { '<BS> at line start joining lines subtracts one', function()
    local tracker = start()
    h.type('iab<CR>cd<Esc>0i<BS><Esc>')
    h.eq(4, tracker.net())
  end },

  { '<Del> at line end joining lines subtracts one', function()
    local tracker = start()
    h.type('iab<CR>cd<Esc>ggA<Del><Esc>')
    h.eq(4, tracker.net())
  end },

  { 'closing char from an autopair mapping is not counted', function()
    local tracker = start()
    vim.keymap.set('i', '(', '()<Left>', { buffer = true })
    h.type('ia(b<Esc>')
    h.eq(3, tracker.net())
  end },

  { 'text inserted through the API is not counted', function()
    local tracker = start()
    vim.keymap.set('i', '<C-x>', function()
      vim.api.nvim_put({ 'snippet' }, 'c', false, true)
    end, { buffer = true })
    h.type('ia<C-x><Esc>')
    h.eq(1, tracker.net())
  end },

  { 'dot-repeat is not counted', function()
    local tracker = start()
    h.type('iab<Esc>')
    h.type('.')
    h.eq(2, tracker.net())
  end },

  { 'macro replay is not counted', function()
    local tracker = start()
    vim.fn.setreg('q', 'Acd\27')
    h.type('@q')
    h.eq(0, tracker.net())
  end },

  { 'non-file buffers are ignored', function()
    local tracker = start()
    vim.bo.buftype = 'nofile'
    h.type('iabc<Esc>')
    h.eq(0, tracker.net())
  end },

  { 'an error disables the tracker and notifies once', function()
    h.reset()
    local messages = {}
    local orig_notify = vim.notify
    vim.notify = function(msg)
      table.insert(messages, msg)
    end
    local tracker = require('typingspeed.tracker')
    local ok, err = pcall(function()
      tracker.start({ window_ms = 10000, warmup_ms = 2000, clock = function() error('boom') end })
      h.type('iab<Esc>')
      vim.wait(100, function() return #messages > 0 end)
    end)
    vim.notify = orig_notify
    if not ok then
      error(err, 0)
    end
    h.eq(1, #messages)
    h.eq(1, messages[1]:find('typingspeed: disabled after error', 1, true))
    h.eq(nil, tracker.rate())
    h.eq(false, (pcall(vim.api.nvim_get_autocmds, { group = 'typingspeed' })))
  end },

  { '<BS> through softtabstop indentation subtracts one', function()
    local tracker = start()
    vim.bo.expandtab = true
    vim.bo.shiftwidth = 4
    vim.bo.softtabstop = 4
    h.type('i<Tab><BS>x<Esc>')
    h.eq(1, tracker.net())
    h.eq({ 'x' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end },

  { '<C-H> subtracts one', function()
    local tracker = start()
    h.type('iabc<C-H><Esc>')
    h.eq(2, tracker.net())
  end },

  { '<C-U> through the default mapping subtracts the deleted text', function()
    local tracker = start()
    h.type('iab cd<C-U>x<Esc>')
    h.eq(1, tracker.net())
  end },

  { 'keys reach the buffer unchanged', function()
    start()
    h.type('iabc<BS>d<Esc>')
    h.eq({ 'abd' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end },

  { 'restarting does not double count', function()
    local tracker = start()
    tracker.start({ window_ms = 10000, warmup_ms = 2000, clock = function() return 0 end })
    h.type('iabc<BS><Esc>')
    h.eq(2, tracker.net())
  end },

  { 'nothing is counted after stop()', function()
    local tracker = start()
    tracker.stop()
    h.type('iabc<Esc>')
    h.eq(0, tracker.net())
    h.eq(nil, tracker.rate())
    h.eq({ 'abc' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end },

  { 'rate() is nil before start', function()
    h.reset()
    h.eq(nil, require('typingspeed.tracker').rate())
  end },
}
