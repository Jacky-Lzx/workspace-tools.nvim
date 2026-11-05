local root = vim.fn.getcwd()
if vim.fn.isdirectory(root .. '/../task-tools.nvim') == 0 then
  print('SKIP optional sibling task-tools integration')
  vim.cmd('qa!')
end
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(root .. '/../task-tools.nvim')
local directory = assert(vim.env.WORKSPACE_TEST_DIR) .. '/tasks'
vim.fn.mkdir(directory, 'p')
directory = vim.uv.fs_realpath(directory)
vim.fn.writefile({ 'fixture' }, directory .. '/one.txt')
vim.api.nvim_set_current_dir(directory)
vim.cmd.edit(vim.fn.fnameescape(directory .. '/one.txt'))
local tasks = require('task_tools')
tasks.setup({ open = false })
local workspace = require('workspace_tools')
local function sidecar(entry)
  return directory .. '/' .. entry.id .. '.tasks.json'
end
workspace.setup({
  directory = directory .. '/store',
  auto_save = false,
  hooks = {
    pre_save = {
      function(entry)
        tasks.save(sidecar(entry))
      end,
    },
    post_restore = {
      function(entry)
        tasks.load(sidecar(entry))
      end,
    },
    post_delete = {
      function(entry)
        vim.fn.delete(sidecar(entry))
      end,
    },
  },
})
local id = assert(tasks.run({ name = 'build fixture', cmd = { 'sh', '-c', 'printf task-done' }, cwd = directory }))
assert(vim.wait(2000, function()
  return tasks.get(id).status == 'success'
end))
local entry, err = workspace.save({ name = 'tasks fixture' })
assert(entry, err)
assert(vim.fn.filereadable(sidecar(entry)) == 1)
assert(tasks.remove(id))
assert(#tasks.list() == 0)
local restored, failure = workspace.restore(entry)
assert(restored, failure)
assert(#tasks.list() == 0, 'restoring workspace started a task')
local definitions = require('task_tools.session').definitions()
assert(#definitions == 1 and definitions[1].name == 'build fixture')
assert(workspace.delete(entry))
assert(vim.fn.filereadable(sidecar(entry)) == 0)
assert(not package.loaded['features.tasks'], 'workspace-tools loaded a personal config module')
print('PASS real task-tools hooks: save definitions, restore without spawning, delete sidecar')
vim.cmd('qa!')
