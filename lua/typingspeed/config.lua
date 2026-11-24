local M = {}

M.defaults = {
  unit = 'wpm', -- 'wpm' | 'cpm'
  window = 10, -- sliding window length, seconds
}

--- Merges user options over defaults and validates them.
--- Raises an error naming the invalid option.
function M.resolve(opts)
  local cfg = vim.tbl_extend('force', M.defaults, opts or {})
  vim.validate('unit', cfg.unit, function(v)
    return v == 'wpm' or v == 'cpm'
  end, "'wpm' or 'cpm'")
  vim.validate('window', cfg.window, function(v)
    return type(v) == 'number' and v >= 3
  end, 'number >= 3')
  return cfg
end

return M
