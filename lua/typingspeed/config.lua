local M = {}

local UNITS = { wpm = true, cpm = true }

local function valid_unit(v)
  if type(v) == 'string' then
    return UNITS[v] == true
  end
  if type(v) ~= 'table' or not vim.islist(v) or #v == 0 then
    return false
  end
  for _, u in ipairs(v) do
    if not UNITS[u] then
      return false
    end
  end
  return true
end

M.defaults = {
  unit = 'wpm', -- 'wpm' | 'cpm' | list of them, e.g. { 'wpm', 'cpm' }
  window = 10, -- sliding window length, seconds
}

--- Merges user options over defaults and validates them.
--- Raises an error naming the invalid option.
function M.resolve(opts)
  local cfg = vim.tbl_extend('force', M.defaults, opts or {})
  vim.validate('unit', cfg.unit, valid_unit, "'wpm' or 'cpm', or a non-empty list of them")
  vim.validate('window', cfg.window, function(v)
    return type(v) == 'number' and v >= 3
  end, 'number >= 3')
  return cfg
end

return M
