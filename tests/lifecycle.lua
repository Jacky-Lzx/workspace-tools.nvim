local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
local directory = assert(vim.env.WORKSPACE_TEST_DIR)
local case = assert(vim.env.WORKSPACE_TEST_CASE)
local workspace = require('workspace_tools')
local store = require('workspace_tools.store')
directory = store.normalize(directory)
local project = directory .. '/project'
vim.fn.mkdir(project, 'p')
vim.fn.writefile({ 'persistent content' }, project .. '/one.txt')
local original = store.normalize(vim.fn.getcwd())
vim.api.nvim_set_current_dir(project)
local options = { directory = directory .. '/store', auto_save = true }
local id = store.id(project, '')
if case == 'seed' then
  workspace.setup(options)
  vim.cmd.edit(vim.fn.fnameescape(project .. '/one.txt'))
elseif case == 'restore' or case == 'directory_arg' then
  options.auto_restore = true
  if case == 'directory_arg' then
    -- Suppression applies to the target project, rather than the launch directory.
    vim.api.nvim_set_current_dir(directory)
    options.suppressed_dirs = { directory }
  end
  workspace.setup(options)
  vim.defer_fn(function()
    local ok, err = pcall(function()
      assert(workspace.status().active.id == id, 'startup did not restore')
      assert(vim.api.nvim_buf_get_name(0) == project .. '/one.txt')
    end)
    vim.fn.writefile({ ok and ('PASS startup auto-restore (' .. case .. ')') or tostring(err) }, directory .. '/result')
    vim.cmd(ok and 'qa!' or 'cquit 1')
  end, 150)
  return
elseif case == 'suppressed' then
  options.suppressed_dirs = { project }
  workspace.setup(options)
  vim.cmd.edit(vim.fn.fnameescape(project .. '/one.txt'))
elseif case == 'stopped' then
  workspace.setup(options)
  vim.cmd.edit(vim.fn.fnameescape(project .. '/one.txt'))
  workspace.stop()
elseif case == 'file_arg' then
  workspace.setup(options)
  vim.cmd.edit(vim.fn.fnameescape(project .. '/one.txt'))
elseif case == 'late' then
  -- A lazy-loaded setup after VimEnter must still get one startup attempt.
  options.auto_restore = true
  vim.defer_fn(function()
    workspace.setup(options)
    vim.defer_fn(function()
      local active = workspace.status().active
      vim.fn.writefile(
        { active and active.id == id and 'PASS late startup restore' or 'FAIL late startup restore' },
        directory .. '/result'
      )
      vim.cmd(active and 'qa!' or 'cquit 1')
    end, 100)
  end, 50)
  return
elseif case == 'delete' then
  workspace.setup(options)
  vim.cmd.edit(vim.fn.fnameescape(project .. '/one.txt'))
  assert(workspace.restore({ id = id }))
  assert(workspace.delete())
elseif case == 'blocked' then
  workspace.setup(options)
  vim.cmd.edit(vim.fn.fnameescape(project .. '/one.txt'))
  local entry = store.read(id)
  entry.session = 'invalid session command\n'
  store.write(entry)
  assert(not workspace.restore(entry))
elseif case == 'default' then
  workspace.setup(options)
  vim.defer_fn(function()
    vim.fn.writefile(
      { not workspace.status().active and 'PASS default startup does not restore' or 'FAIL unexpected restore' },
      directory .. '/result'
    )
    vim.cmd('qa!')
  end, 100)
  return
else
  error('unknown case: ' .. case .. ' in ' .. original)
end
vim.defer_fn(function()
  vim.cmd('qa!')
end, 100)
