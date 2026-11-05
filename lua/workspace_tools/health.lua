local M = {}

function M.check()
  vim.health.start('workspace-tools.nvim')
  if vim.fn.has('nvim-0.11') == 1 then
    vim.health.ok('Neovim 0.11+')
  else
    vim.health.error('Neovim 0.11+ required')
  end
  local store = require('workspace_tools.store')
  vim.health.info('Store: ' .. store.directory())
  local items, errors = store.list()
  vim.health.ok(('%d saved workspace(s)'):format(#items))
  for _, err in ipairs(errors) do
    vim.health.warn(err)
  end
  for _, entry in ipairs(items) do
    if entry.missing then
      vim.health.warn('Missing directory: ' .. entry.cwd)
    end
  end
  local state = require('workspace_tools').status()
  if state.blocked then
    vim.health.warn('Auto-save blocked by a restore failure; manually save or successfully restore to recover')
  end
  if state.stopped then
    vim.health.info('Auto-save paused; :WorkspaceStart resumes it')
  end
end

return M
