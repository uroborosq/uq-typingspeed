local M = {}

--- Fails the current test when `actual` differs from `expected`.
function M.eq(expected, actual, msg)
  if not vim.deep_equal(expected, actual) then
    error(
      string.format('%sexpected %s, got %s', msg and (msg .. ': ') or '', vim.inspect(expected), vim.inspect(actual)),
      2
    )
  end
end

--- Fails the current test unless `fn` raises an error containing `pattern` (plain match).
function M.raises(pattern, fn)
  local ok, err = pcall(fn)
  if ok then
    error('expected an error containing ' .. vim.inspect(pattern), 2)
  end
  if not tostring(err):find(pattern, 1, true) then
    error(string.format('expected error containing %s, got %s', vim.inspect(pattern), vim.inspect(err)), 2)
  end
end

--- Stops the tracker, unloads all plugin modules and opens a fresh empty buffer.
function M.reset()
  local tracker = package.loaded['typingspeed.tracker']
  if tracker then
    tracker.stop()
  end
  for name in pairs(package.loaded) do
    if name == 'typingspeed' or name:match('^typingspeed%.') then
      package.loaded[name] = nil
    end
  end
  vim.cmd('enew!')
end

--- Sends keys as if typed by the user and processes them synchronously.
function M.type(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), 'tx', false)
end

return M
