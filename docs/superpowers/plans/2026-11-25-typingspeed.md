# typingspeed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Плагин Neovim, показывающий текущую чистую скорость печати (wpm/cpm) в statusline через `require('typingspeed').status()`.

**Architecture:** `meter.lua` — чистый модуль скользящего окна (время передаётся параметром). `tracker.lua` слушает `vim.on_key`, `InsertCharPre`, `InsertLeave` и передаёт в `meter` события «+1 символ» и «−N удалено»; таймер раз в секунду перерисовывает statusline, пока в окне есть события. `config.lua` проверяет опции, `init.lua` даёт публичный API.

**Tech Stack:** Lua (LuaJIT), Neovim 0.12+ API (`vim.on_key`, `vim.uv`, `vim.validate`), тесты без зависимостей через `nvim --headless -l`.

**Спецификация:** `docs/superpowers/specs/2026-11-25-typingspeed-design.md`

---

## Важные факты о Neovim (проверены на 0.12.6)

Эти факты определяют реализацию `tracker.lua`. Не меняйте логику, не проверив их заново.

- `vim.on_key(fn(key, typed), ns)` вызывается **до** обработки каждой клавиши, в том числе
  клавиш из раскрытия маппингов. Буфер в этот момент отражает результат **предыдущей** клавиши.
- `typed` не пустой только у клавиш, нажатых пользователем (и `nvim_feedkeys` с флагом `t`).
  У клавиш из раскрытия маппинга, повтора `.` и макроса `@q` он пустой.
- Возврат `""` из колбэка `on_key` поглощает клавишу; колбэк всегда должен возвращать `nil`.
  Возврат truthy-значения из колбэка autocmd удаляет autocmd.
- `InsertCharPre` срабатывает и для символов из раскрытия маппинга (закрывающая скобка автопары),
  но не для вставок через API (`nvim_put`, `nvim_buf_set_text`). Для `<CR>` не срабатывает;
  для `<Tab>` срабатывает только при `noexpandtab` (`v:char == "\t"`).
- `TextChangedI` не вызывается после каждой клавиши при пакетной обработке typeahead,
  поэтому для измерения удалений не используется.
- Стандартный маппинг Insert mode: `<C-W>` → `<C-G>u<C-W>`.
- `vim.keycode`: `<CR>` = `"\r"`, `<Tab>` = `"\t"`, `<C-H>` = `"\b"`, `<BS>` и `<Del>` — особые
  последовательности `\x80kb`, `\x80kD`.

## Структура файлов

| Файл | Ответственность |
| --- | --- |
| `Makefile` | цель `test` |
| `tests/run.lua` | раннер: загружает `tests/*_spec.lua`, печатает результат, код выхода 1 при ошибках |
| `tests/helpers.lua` | `eq`, `raises`, `reset` (сброс модулей и буфера), `type` (feedkeys `tx`) |
| `lua/typingspeed/config.lua` | значения по умолчанию, слияние, `vim.validate` |
| `lua/typingspeed/meter.lua` | очередь событий, `add`, `rate`, `empty`, `net` |
| `lua/typingspeed/tracker.lua` | обработчики Neovim, снимок удаления, таймер, защита от ошибок |
| `lua/typingspeed/init.lua` | `setup(opts)`, `status()` |
| `README.md` | установка, statusline, что считается, ограничения |

Каждый spec-файл возвращает список пар `{ 'имя теста', function() ... end }`.
Все команды выполняются из корня репозитория.

---

### Task 1: Тестовый раннер

**Files:**
- Create: `Makefile`
- Create: `tests/run.lua`
- Create: `tests/helpers.lua`

- [ ] **Step 1: Создать `Makefile`** (отступ в рецепте — символ табуляции)

```make
.PHONY: test
test:
	nvim --headless --clean --cmd 'set rtp^=.' -l tests/run.lua
```

- [ ] **Step 2: Создать `tests/run.lua`**

```lua
-- Minimal test runner.
-- Usage: nvim --headless --clean --cmd 'set rtp^=.' -l tests/run.lua [tests/x_spec.lua ...]
-- Each spec file returns a list of { name, fn } pairs.
package.path = './tests/?.lua;' .. package.path

local files = (#arg > 0) and arg or vim.fn.glob('tests/*_spec.lua', false, true)
local passed, failed = 0, 0

for _, file in ipairs(files) do
  for _, test in ipairs(dofile(file)) do
    local ok, err = pcall(test[2])
    if ok then
      passed = passed + 1
      io.write('ok   ', file, ': ', test[1], '\n')
    else
      failed = failed + 1
      io.write('FAIL ', file, ': ', test[1], '\n     ', tostring(err), '\n')
    end
  end
end

io.write(string.format('\n%d passed, %d failed\n', passed, failed))
os.exit(failed > 0 and 1 or 0)
```

- [ ] **Step 3: Создать `tests/helpers.lua`**

`reset()` нужен для изоляции тестов: он останавливает трекер (снимает `on_key` и закрывает таймер),
выгружает модули плагина и открывает новый пустой буфер, поэтому буферные маппинги и опции
предыдущего теста не влияют на следующий.

```lua
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
```

- [ ] **Step 4: Проверить раннер без тестов**

Run: `make test`
Expected: последняя строка `0 passed, 0 failed`, код выхода 0.

- [ ] **Step 5: Commit**

```bash
git add Makefile tests/run.lua tests/helpers.lua
git commit -m "test: add dependency-free test runner

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: config.lua

**Files:**
- Create: `lua/typingspeed/config.lua`
- Test: `tests/config_spec.lua`

- [ ] **Step 1: Написать тесты**

```lua
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
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `make test`
Expected: 5 строк `FAIL tests/config_spec.lua: ...` с ошибкой `module 'typingspeed.config' not found`, итог `0 passed, 5 failed`.

- [ ] **Step 3: Реализовать `lua/typingspeed/config.lua`**

```lua
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
```

- [ ] **Step 4: Убедиться, что тесты проходят**

Run: `make test`
Expected: `5 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add lua/typingspeed/config.lua tests/config_spec.lua
git commit -m "feat: add config resolution and validation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: meter.lua

**Files:**
- Create: `lua/typingspeed/meter.lua`
- Test: `tests/meter_spec.lua`

Формула (из спецификации): события старше `now − window_ms` удаляются; `streak_start` — время
первого события, добавленного в пустую очередь; `elapsed = min(window_ms, now − streak_start)`;
при `elapsed < warmup_ms` результат `nil`; иначе `max(0, Σdelta) / elapsed × 60000` (cpm).
`add()` сначала удаляет устаревшие события, чтобы после паузы длиннее окна серия началась заново.

- [ ] **Step 1: Написать тесты**

```lua
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
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `make test`
Expected: 7 строк `FAIL tests/meter_spec.lua: ...` с `module 'typingspeed.meter' not found`; тесты config проходят.

- [ ] **Step 3: Реализовать `lua/typingspeed/meter.lua`**

```lua
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
```

- [ ] **Step 4: Убедиться, что тесты проходят**

Run: `make test`
Expected: `12 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add lua/typingspeed/meter.lua tests/meter_spec.lua
git commit -m "feat: add sliding-window speed meter

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: tracker.lua

**Files:**
- Create: `lua/typingspeed/tracker.lua`
- Test: `tests/tracker_spec.lua`

Логика (см. «Важные факты о Neovim»):

- `user_insert` — наследуемый признак: обновляется только на клавишах с непустым `typed`
  (`= в Insert mode ли мы`); клавиши раскрытия маппинга, `.` и макросов его наследуют.
  Используется для удалений и `<CR>`/`<Tab>`: так учитываются `<C-W>` из стандартного маппинга
  и `<CR>`/`<Tab>`, переданные плагинами автодополнения через fallback; повтор `.` и макросы
  (запущенные из Normal mode) — нет.
- `key_typed` — признак только текущей клавиши (`typed` не пустой и Insert mode). Используется в
  `InsertCharPre`, чтобы не считать закрывающую скобку автопары из раскрытия маппинга.
- Удаляющая клавиша сохраняет снимок `{buf, row, chars, lines, t}`; `flush()` в начале следующего
  `on_key`, на тике таймера и на `InsertLeave` сравнивает его с текущим состоянием.
- `guard()` оборачивает все колбэки: при первой ошибке трекер отключается и выводится одно
  сообщение через `vim.notify`.

- [ ] **Step 1: Написать тесты**

Тесты запускают трекер с замороженными часами (`clock = 0`), поэтому окно не истекает, и проверяют
`tracker.net()` — сумму событий в окне.

```lua
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
    tracker.start({ window_ms = 10000, warmup_ms = 2000, clock = function() error('boom') end })
    h.type('iab<Esc>')
    vim.wait(100, function() return #messages > 0 end)
    vim.notify = orig_notify
    h.eq(1, #messages)
    h.eq(1, messages[1]:find('typingspeed: disabled after error', 1, true))
    h.eq(nil, tracker.rate())
  end },

  { 'rate() is nil before start', function()
    h.reset()
    h.eq(nil, require('typingspeed.tracker').rate())
  end },
}
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `make test`
Expected: 15 строк `FAIL tests/tracker_spec.lua: ...` с `module 'typingspeed.tracker' not found`; итог `12 passed, 15 failed`.

- [ ] **Step 3: Реализовать `lua/typingspeed/tracker.lua`**

```lua
--- Glue between Neovim events and the meter.
local Meter = require('typingspeed.meter')

local M = {}

local NS = vim.api.nvim_create_namespace('typingspeed')
local GROUP = 'typingspeed'

local DELETE_KEYS = {}
for _, k in ipairs({ '<BS>', '<C-H>', '<C-W>', '<C-U>', '<Del>' }) do
  DELETE_KEYS[vim.keycode(k)] = true
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

local function snapshot()
  return {
    buf = vim.api.nvim_get_current_buf(),
    row = vim.api.nvim_win_get_cursor(0)[1],
    chars = vim.fn.strchars(vim.api.nvim_get_current_line()),
    lines = vim.api.nvim_buf_line_count(0),
    t = state.clock(),
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
    deleted = math.max(0, p.chars - vim.fn.strchars(vim.api.nvim_get_current_line()))
  else
    return
  end
  if deleted > 0 then
    add(p.t, -deleted)
  end
end

tick = vim.schedule_wrap(guard(function()
  flush()
  vim.cmd.redrawstatus()
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
  if DELETE_KEYS[key] then
    state.pending = snapshot()
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
```

- [ ] **Step 4: Убедиться, что тесты проходят**

Run: `make test`
Expected: `27 passed, 0 failed`. В выводе могут встречаться сообщения о режиме вставки
(`-- INSERT --` или локализованные) — это вывод Neovim в headless-режиме, на результат не влияет.

- [ ] **Step 5: Commit**

```bash
git add lua/typingspeed/tracker.lua tests/tracker_spec.lua
git commit -m "feat: track net typed characters in Insert mode

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: init.lua (публичный API)

**Files:**
- Create: `lua/typingspeed/init.lua`
- Test: `tests/init_spec.lua`

`setup()` передаёт в трекер скрытую опцию `_clock` — она нужна только тестам и в README не
документируется. Прогрев фиксирован: 2000 мс.

- [ ] **Step 1: Написать тесты**

Проверка расчёта: 55 символов за 10 с → 330 cpm → 66 wpm.

```lua
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
  end },
}
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `make test`
Expected: 6 строк `FAIL tests/init_spec.lua: ...` с `module 'typingspeed' not found`; итог `27 passed, 6 failed`.

- [ ] **Step 3: Реализовать `lua/typingspeed/init.lua`**

```lua
local config = require('typingspeed.config')
local tracker = require('typingspeed.tracker')

local M = {}

local WARMUP_MS = 2000

local cfg = nil

--- @param opts? { unit?: 'wpm'|'cpm', window?: number }
function M.setup(opts)
  cfg = config.resolve(opts)
  tracker.start({
    window_ms = cfg.window * 1000,
    warmup_ms = WARMUP_MS,
    clock = cfg._clock, -- private hook for tests
  })
end

--- Statusline string: "62 wpm" / "310 cpm", or "" when there is no data.
function M.status()
  if not cfg then
    return ''
  end
  local cpm = tracker.rate()
  if not cpm then
    return ''
  end
  local value = cfg.unit == 'wpm' and cpm / 5 or cpm
  return string.format('%d %s', math.floor(value + 0.5), cfg.unit)
end

return M
```

- [ ] **Step 4: Убедиться, что тесты проходят**

Run: `make test`
Expected: `33 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add lua/typingspeed/init.lua tests/init_spec.lua
git commit -m "feat: add setup() and status() API

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Проверка таймера на реальных часах

Тесты используют замороженные часы и не проверяют таймер перерисовки. Этот шаг проверяет его
на реальном времени.

**Files:**
- Create (временный, не коммитится): `/tmp/typingspeed-smoke.lua`

- [ ] **Step 1: Создать скрипт проверки**

```lua
local ts = require('typingspeed')
ts.setup({ window = 3 })
vim.o.statusline = "%{v:lua.require'typingspeed'.status()}"
local errs = {}
local orig = vim.notify
vim.notify = function(m) table.insert(errs, m) end
for _ = 1, 10 do vim.api.nvim_feedkeys('ihello <Esc>', 'tx', false) vim.wait(250) end
print('after typing:', vim.inspect(ts.status()))
vim.wait(1500)
print('after 1.5s pause:', vim.inspect(ts.status()))
vim.wait(3000)
print('after 4.5s pause:', vim.inspect(ts.status()))
print('errors:', vim.inspect(errs))
```

- [ ] **Step 2: Запустить**

Run: `nvim --headless --clean --cmd 'set rtp^=.' -l /tmp/typingspeed-smoke.lua`
Expected (числа зависят от машины; feedkeys вводит мгновенно, поэтому значения завышены):

```
after typing: "<N> wpm"            -- непустое значение
after 1.5s pause: "<M> wpm"        -- M < N: значение снижается во время паузы
after 4.5s pause: ""               -- окно 3 с истекло
errors: {}
```

- [ ] **Step 3: Удалить скрипт**

Run: `rm /tmp/typingspeed-smoke.lua`

---

### Task 7: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Создать `README.md`**

````markdown
# typingspeed

Neovim plugin that shows your current typing speed in the statusline.

The value is comparable with typing trainers (monkeytype and similar): it counts **net**
characters — characters you typed minus characters you deleted in Insert mode — over a
sliding time window. 1 word = 5 characters.

Requires Neovim 0.12+.

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  dir = '/path/to/uq-typingspeed',
  main = 'typingspeed',
  opts = {},
}
```

Or call `setup()` yourself:

```lua
require('typingspeed').setup({
  unit = 'wpm', -- 'wpm' | 'cpm'
  window = 10,  -- sliding window length in seconds, >= 3
})
```

## Statusline

`require('typingspeed').status()` returns `"62 wpm"` (or `"310 cpm"`), or `""` when there is
nothing to show.

lualine:

```lua
require('lualine').setup({
  sections = {
    lualine_x = { require('typingspeed').status, 'encoding', 'filetype' },
  },
})
```

Plain statusline:

```lua
vim.o.statusline = "%f %= %{v:lua.require'typingspeed'.status()} "
```

## What is counted

| Action | Effect |
| --- | --- |
| A character you type in Insert mode | +1 |
| `<CR>`, `<Tab>` | +1 each |
| `<BS>`, `<C-H>`, `<C-W>`, `<C-U>`, `<Del>` | minus the number of deleted characters |
| Text inserted by completion, snippets, autopair closing chars | not counted |
| `.` repeat, macros | not counted |
| Buffers with a non-empty `buftype` (prompts, terminals, scratch) | not counted |

The speed is shown after 2 seconds of typing. During a pause it decreases, and after
`window` seconds without typing the status becomes empty.

## Limitations

- Uncorrected typos are counted as correct characters: unlike a trainer, there is no
  reference text to compare against.
- Deleting an autopair with `<BS>` removes two characters while only one was counted, so
  the value is slightly lower in that case.

## Development

```sh
make test
```
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Ручная проверка в обычном Neovim (после Task 7)

1. Подключить плагин по README и добавить `status()` в statusline.
2. Открыть любой файл, набрать текст 5–10 секунд: через 2 с в statusline появится `N wpm`.
3. Остановиться: значение снижается и через 10 с исчезает.
4. Открыть Telescope или `:term`: набор там не меняет значение.
