vim.opt.rtp:prepend(vim.fn.getcwd())
local api, uv = vim.api, vim.uv
local directory = assert(vim.env.WORKSPACE_TEST_DIR) .. '/python'
vim.fn.mkdir(directory, 'p')
directory = assert(uv.fs_realpath(directory))
local P = require('workspace_tools.environments.python')
local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  vim.fn.writefile(lines or { '' }, path)
end
local function venv(path, conda)
  write(path .. '/bin/python', { '#!/bin/sh', 'printf fixture' })
  assert(uv.fs_chmod(path .. '/bin/python', 448))
  if conda then
    vim.fn.mkdir(path .. '/conda-meta', 'p')
  else
    write(path .. '/pyvenv.cfg')
  end
  return path .. '/bin/python'
end
local a, b = directory .. '/project a', directory .. '/project b'
write(a .. '/pyproject.toml')
write(b .. '/pyproject.toml')
write(a .. '/src/main.py')
write(b .. '/src/main.py')
local auto = venv(a .. '/.venv')
local other = venv(b .. '/.venv')
local selected = venv(directory .. '/envs/selected % $() 中')
local conda = venv(directory .. '/envs/conda', true)
local settings = { directory = directory .. '/store', search_paths = { directory .. '/envs' } }
P.setup(settings)
assert(
  not package.loaded.workspace_tools and not package.loaded.selection_tools,
  'environment setup is independent of sessions/picker'
)
local function buffer(name)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(buf, name)
  return buf
end
local one, two = buffer(a .. '/src/main.py'), buffer(b .. '/src/main.py')
assert(P.root({ buf = one }) == a and P.root({ buf = two }) == b)
assert(P.current({ buf = one }) == auto and P.current({ buf = two }) == other)
local snapshot = P.info({ buf = one })
assert(snapshot.root == a and snapshot.python == auto and snapshot.source == 'project:.venv')
assert(vim.fn.isdirectory(settings.directory) == 0, 'inspection must not create the selection store')
assert(not package.loaded.selection_tools, 'inspection must not load a picker')
snapshot.python = 'changed'
assert(P.info({ buf = one }).python == auto, 'inspection shares mutable state')
local inherited = vim.env.VIRTUAL_ENV
local events = {}
local event = api.nvim_create_autocmd('User', {
  pattern = 'WorkspacePythonChanged',
  callback = function(ev)
    events[#events + 1] = ev.data
  end,
})
assert(P.set(selected, { buf = one }) == selected)
assert(P.current({ buf = two }) == other)
assert(P.info({ buf = one }).source == 'selection')
assert(events[1].root == a and events[1].python == selected)
assert(vim.env.VIRTUAL_ENV == inherited, 'selection must not mutate process-wide environment')
assert(P.environment({ buf = one }).VIRTUAL_ENV == vim.fs.dirname(vim.fs.dirname(selected)))
P.setup(settings)
assert(P.current({ buf = one }) == selected, 'selection survives a fresh setup/cache')
local store = settings.directory .. '/' .. vim.fn.sha256(a) .. '.json'
assert(vim.fn.getfperm(store) == 'rw-------')
assert(not pcall(P.set, directory .. '/missing', { buf = one }))
assert(P.current({ buf = one }) == selected, 'invalid selection does not replace a good selection')
P.set(conda, { buf = one })
assert(P.environment({ buf = one }).CONDA_PREFIX == directory .. '/envs/conda')
P.set(nil, { buf = one })
assert(P.current({ buf = one }) == auto and vim.fn.filereadable(store) == 0)
api.nvim_set_current_buf(one)
P.set(selected)
vim.cmd('WorkspacePython!')
assert(P.current() == auto, 'bang clears an explicit override')
local done, choices
P.discover({ buf = one }, function(items)
  choices, done = items, true
end)
assert(vim.wait(3000, function()
  return done
end, 10))
local found = {}
for _, item in ipairs(choices) do
  found[item.python] = item.kind
end
assert(found[selected] == 'venv' and found[conda] == 'conda' and found[auto] == 'venv')
local called = false
local job = P.discover({ buf = one }, function()
  called = true
end)
job.cancel()
vim.wait(20, function()
  return false
end, 5)
assert(not called, 'cancelled discovery never opens a picker')
local chosen
P.select({
  buf = one,
  picker = function(items, _, callback)
    api.nvim_set_current_buf(two)
    for _, item in ipairs(items) do
      if item.python == selected then
        callback(item)
        chosen = true
        break
      end
    end
  end,
})
assert(vim.wait(3000, function()
  return chosen
end, 10))
assert(
  P.current({ buf = one }) == selected and P.current({ buf = two }) == other,
  'picker choice retains its originating project'
)
uv.fs_unlink(selected)
assert(P.current({ buf = one }) == auto, 'deleted cached interpreters fall back to project discovery')
write(store, { '{ broken json' })
P.setup(settings)
assert(P.current({ buf = one }) == auto, 'corrupt state does not break interpreter discovery')
-- A Python symlink must retain the venv path rather than resolve to base Python.
local actual = vim.fn.exepath('python3')
vim.fn.mkdir(directory .. '/envs/symlink/bin', 'p')
assert(uv.fs_symlink(actual, directory .. '/envs/symlink/bin/python'))
write(directory .. '/envs/symlink/pyvenv.cfg')
P.set(directory .. '/envs/symlink', { buf = two })
assert(P.current({ buf = two }) == directory .. '/envs/symlink/bin/python')
local bare = directory .. '/bare'
vim.fn.mkdir(bare, 'p')
local virtual_env, conda_prefix = vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX
vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX = nil, nil
assert(P.info({ root = bare }).source == 'none' and P.info({ root = bare }).python == nil)
vim.env.VIRTUAL_ENV = b .. '/.venv'
assert(P.info({ root = bare }).source == 'env:VIRTUAL_ENV' and P.info({ root = bare }).python == other)
vim.env.VIRTUAL_ENV = nil
P.set('system', { root = bare })
assert(P.info({ root = bare }).source == 'system' and P.info({ root = bare }).python == actual)
vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX = virtual_env, conda_prefix
P.disable()
api.nvim_del_autocmd(event)
assert(vim.fn.exists(':WorkspacePython') == 0)
print(
  'Python environments: projects, discovery, private persistence, selection/cancellation, stale state, child environments and symlink identity passed'
)
