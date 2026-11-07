-- Explicit inspection does not configure or start the plugin.
require('workspace_tools.user_command').create('WorkspaceInfo', function()
  vim.notify(
    vim.inspect({
      state = require('workspace_tools').status(),
      directory = require('workspace_tools.store').directory(),
      records = { require('workspace_tools.store').list() },
    }),
    vim.log.levels.INFO,
    { title = 'workspace-tools.nvim', filetype = 'lua' }
  )
end, { desc = 'Inspect configuration and current runtime state' })
