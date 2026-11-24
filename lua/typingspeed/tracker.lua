--- Glue between Neovim events and the meter.
local Meter = require('typingspeed.meter')

local M = {}

local NS = vim.api.nvim_create_namespace('typingspeed')
local GROUP = 'typingspeed'

-- Deletion key -> maximum characters subtracted per press. Single-character keys are capped
-- at 1, as in a typing trainer: one <BS> through 'softtabstop'/'smarttab' indentation
-- removes several spaces that were typed with a single <Tab> or inserted by autoindent.
local DELETE_KEYS = {}
for _, k in ipairs({ '<BS>', '<C-H>', '<Del>' }) do
  DELETE_KEYS[vim.keycode(k)] = 1
end
for _, k in ipairs({ '<C-W>', '<C-U>' }) do
  DELETE_KEYS[vim.keycode(k)] = math.huge
end

local ADD_KEYS = {}
for _, k in ipairs({ '<CR>', '<Tab>' }) do
  ADD_KEYS[vim.keycode(k)] = true
end

--- nil when stopped; otherwise:
--- { meter, clock, timer, user_insert: boolean, key_typed: boolean, pending: snapshot|nil }
local state = nil

local function in_insert()
  return vim.api.nvim_get_mode().mode:sub(1, 1) == 'i'
end

local function eligible()
  return vim.bo.buftype == ''
end

local function teardown(s)
  vim.on_key(nil, NS)
  pcall(vim.api.nvim_del_augroup_by_name, GROUP)
  if s and not s.timer:is_closing() then
    s.timer:stop()
    s.timer:close()
  end
end

--- Wraps a callback: on the first error the tracker is disabled and one message is shown.
--- Always returns nil (a truthy return would delete an autocmd, "" would swallow a key in on_key).
local function guard(fn)
  return function(...)
    if not state then
      return
    end
    local ok, err = pcall(fn, ...)
    if not ok then
      local s = state
      state = nil
      s.timer:stop()
      vim.schedule(function()
        if not state then
          teardown(s)
        elseif not s.timer:is_closing() then
          s.timer:close()
        end
        vim.notify('typingspeed: disabled after error: ' .. tostring(err), vim.log.levels.ERROR)
      end)
    end
  end
end

local tick

local function add(t, delta)
  state.meter:add(t, delta)
  if not state.timer:is_active() then
    state.timer:start(1000, 1000, tick)
  end
end

local function snapshot(limit)
  return {
    buf = vim.api.nvim_get_current_buf(),
    row = vim.api.nvim_win_get_cursor(0)[1],
    chars = vim.fn.strchars(vim.api.nvim_get_current_line()),
    lines = vim.api.nvim_buf_line_count(0),
    t = state.clock(),
    limit = limit,
  }
end

--- Applies the pending deletion snapshot, if any, by comparing it with the current line.
local function flush()
  local p = state.pending
  if not p then
    return
  end
  state.pending = nil
  if vim.api.nvim_get_current_buf() ~= p.buf then
    return
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local joined = p.lines - vim.api.nvim_buf_line_count(0)
  local deleted
  if joined > 0 and (row == p.row - joined or row == p.row) then
    deleted = joined -- removed line breaks: <BS> at line start or <Del> at line end
  elseif joined == 0 and row == p.row then
    deleted = math.min(p.limit, math.max(0, p.chars - vim.fn.strchars(vim.api.nvim_get_current_line())))
  else
    return
  end
  if deleted > 0 then
    add(p.t, -deleted)
  end
end

tick = vim.schedule_wrap(guard(function()
  flush()
  vim.cmd.redrawstatus({ bang = true })
  if state.meter:empty(state.clock()) then
    state.timer:stop()
  end
end))

--- Called before every key is processed; the buffer reflects the previous key.
local function on_key(key, typed)
  flush()
  local from_user = typed ~= nil and typed ~= ''
  if from_user then
    -- Keys with empty `typed` (mapping expansion, `.`, macros) inherit this flag
    -- from the user key that produced them.
    state.user_insert = in_insert()
  end
  -- Only the user's own key may produce a counted character in InsertCharPre;
  -- characters inserted by a mapping expansion (e.g. an autopair) are not counted.
  state.key_typed = from_user and state.user_insert
  if not (state.user_insert and in_insert() and eligible()) then
    return
  end
  local limit = DELETE_KEYS[key]
  if limit then
    state.pending = snapshot(limit)
  elseif ADD_KEYS[key] then
    add(state.clock(), 1)
  end
end

local function on_insert_char()
  -- <Tab> is counted in on_key: InsertCharPre fires for it only with 'noexpandtab'.
  if state.key_typed and eligible() and vim.v.char ~= '\t' then
    add(state.clock(), 1)
  end
end

--- Starts (or restarts) tracking.
--- @param opts { window_ms: number, warmup_ms: number, clock?: fun(): number }
function M.start(opts)
  M.stop()
  state = {
    meter = Meter.new({ window_ms = opts.window_ms, warmup_ms = opts.warmup_ms }),
    clock = opts.clock or function()
      return vim.uv.hrtime() / 1e6
    end,
    timer = assert(vim.uv.new_timer()),
    user_insert = false,
    key_typed = false,
    pending = nil,
  }
  local group = vim.api.nvim_create_augroup(GROUP, { clear = true })
  vim.api.nvim_create_autocmd('InsertCharPre', { group = group, callback = guard(on_insert_char) })
  vim.api.nvim_create_autocmd('InsertLeave', { group = group, callback = guard(flush) })
  vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = M.stop })
  vim.on_key(guard(on_key), NS)
end

--- Stops tracking and releases the timer. Safe to call when not started.
function M.stop()
  local s = state
  state = nil
  teardown(s)
end

--- Characters per minute, or nil (not started, no data, or warming up).
function M.rate()
  if not state then
    return nil
  end
  return state.meter:rate(state.clock())
end

--- Net characters in the current window; for tests.
function M.net()
  return state and state.meter:net() or 0
end

return M
