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
