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
  unit = 'wpm', -- 'wpm' | 'cpm' | { 'wpm', 'cpm' }
  window = 10,  -- sliding window length in seconds, >= 3
})
```

## Statusline

`require('typingspeed').status()` returns `"62 wpm"` (or `"310 cpm"`), or `""` when there is
nothing to show.

To show both units at once, pass a list: `unit = { 'wpm', 'cpm' }` gives `"62 wpm / 310 cpm"`.
The units are shown in the order of the list.

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
| `<BS>`, `<C-H>`, `<Del>` | −1 per press (also when 'softtabstop' removes several spaces at once) |
| `<C-W>`, `<C-U>` | minus the number of deleted characters |
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
- Deleting text that was inserted without typing (completion, snippets, abbreviations) is still subtracted.
- Replace mode is not counted, and the first character typed into a snippet placeholder (Select mode) is not counted.
- Deletions spanning several lines (other than joining two lines) are ignored.

## Development

```sh
make test
```
