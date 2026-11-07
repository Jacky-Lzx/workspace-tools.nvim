vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.getcwd() .. '/../selection-tools.nvim')
vim.o.columns, vim.o.lines = 220, 60
local api = vim.api
local selection = require('selection_tools')
selection.setup({
  layout = { width = 0.95 },
  select = { layout = { width = 0.95, min_width = 200, max_width = 220 } },
  matcher = { backend = 'native' },
  component_defaults = { path = { hl = 'Special' }, time = { hl = 'String' } },
})
local function ready(p)
  assert(
    vim.wait(5000, function()
      return not p.loading and not p.matching
    end, 5),
    'picker did not settle'
  )
  assert(not p.error, p.error)
end
local function spans(p, group)
  local result = {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(p.list_buf, -1, 0, -1, { details = true })) do
    if mark[4].hl_group == group then
      local line = api.nvim_buf_get_lines(p.list_buf, mark[2], mark[2] + 1, false)[1]
      result[#result + 1] = line:sub(mark[3] + 1, mark[4].end_col)
    end
  end
  return table.concat(result)
end
local workspace = require('workspace_tools')
local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/中文 project', 'p')
directory = assert(vim.uv.fs_realpath(directory))
vim.fn.writefile({ 'original' }, directory .. '/中文 project/file.txt')
workspace.setup({ directory = directory .. '/store', auto_save = false, picker = 'selection' })
api.nvim_set_current_dir(directory .. '/中文 project')
vim.cmd.edit(vim.fn.fnameescape(directory .. '/中文 project/file.txt'))
local saved = assert(workspace.save({ name = 'needle workspace' }))
local p = workspace.search()
ready(p)
assert(spans(p, 'Special'):find('中文 project', 1, true))
local date = os.date('%Y-%m-%d %H:%M', p:current().updated_at)
assert(spans(p, 'String') == date)
p:set_query(date)
assert(#p.matches == 1 and spans(p, 'SelectionToolsMatch') == date)
p:set_query('needle')
assert(#p.matches == 1 and spans(p, 'SelectionToolsMatch') == 'needle')
p:confirm()
assert(workspace.status().active.id == saved.id)
local python = require('workspace_tools.environments.python')
vim.fn.mkdir(directory .. '/中文 project/.venv/bin', 'p')
local executable = directory .. '/中文 project/.venv/bin/python'
vim.fn.writefile({ '#!/bin/sh', 'exit 0' }, executable)
assert(vim.uv.fs_chmod(executable, 448))
vim.fn.writefile({ '' }, directory .. '/中文 project/.venv/pyvenv.cfg')
python.setup({ directory = directory .. '/python-store', search_paths = {} })
local original = selection.open
selection.open = function(opts)
  p = original(opts)
  return p
end
local done
python.select({
  on_done = function(value)
    done = value
  end,
})
assert(vim.wait(5000, function()
  return p and not p.closed
end, 5))
ready(p)
p:set_query('.venv')
assert(
  #p.matches == 1 and p:current().python == executable,
  vim.inspect({ executable = executable, matches = p.matches })
)
assert(spans(p, 'Special'):find('python', 1, true))
p:confirm()
assert(done == executable)
selection.open = original
vim.cmd('enew!')
api.nvim_set_current_dir(vim.fn.fnamemodify(directory, ':h'))
vim.fn.delete(directory, 'rf')
print('Workspace components: shared path/time styles, date/path search, restore and interpreter identity passed')
