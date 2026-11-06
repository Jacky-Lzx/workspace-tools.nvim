vim.opt.rtp:prepend(vim.fn.getcwd())
local workspace = require('workspace_tools')
local config = require('workspace_tools.config')
local opts = {
  directory = vim.fn.tempname(),
  auto_save = false,
  auto_restore = false,
  suppressed_dirs = {},
  hooks = { pre_save = { function() end } },
}
local before = vim.deepcopy(opts)
workspace.setup(opts)
assert(vim.deep_equal(opts, before))
opts.hooks.pre_save[1] = function()
  error('caller mutated its input')
end
assert(config.options.hooks.pre_save[1] == before.hooks.pre_save[1])
local configured = vim.deepcopy(config.options)
local handlers = vim.api.nvim_get_autocmds({ group = 'WorkspaceTools' })
for _, invalid in ipairs({ false, { directory = false }, { hooks = { pre_save = { 'bad' } } } }) do
  assert(not pcall(workspace.setup, invalid))
  assert(vim.deep_equal(configured, config.options), 'Invalid setup replaced configuration')
  assert(
    vim.deep_equal(handlers, vim.api.nvim_get_autocmds({ group = 'WorkspaceTools' })),
    'Invalid setup removed handlers'
  )
end
workspace.setup(before)
assert(#handlers == #vim.api.nvim_get_autocmds({ group = 'WorkspaceTools' }))
workspace.disable()
workspace.disable()
assert(vim.fn.exists('#WorkspaceTools') == 0)
workspace.enable()
assert(vim.deep_equal(config.options, configured))
workspace.dispose()
workspace.dispose()
assert(vim.fn.exists('#WorkspaceTools') == 0)
assert(vim.deep_equal(config.options, config.defaults))
workspace.setup()
assert(vim.deep_equal(config.options, config.defaults))
workspace.dispose()
print('Workspace lifecycle: configuration isolation, invalid setup, repeat setup, disable/enable and disposal passed')
