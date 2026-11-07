local M = {}

function M.check()
  vim.health.start('workspace-tools.nvim')
  if vim.fn.has('nvim-0.11') == 0 then
    vim.health.error('Neovim 0.11+ is required', { 'Upgrade Neovim' })
    return
  end
  local issues = {}
  local function problem(level, message, advice)
    issues[#issues + 1] = { level = level, message = message, advice = advice }
  end
  local plugin = package.loaded.workspace_tools
  local state = plugin and plugin.status()
  if not state or not state.initialized then
    vim.health.info('Not configured; workspace checks skipped.')
    return
  end
  local store = require('workspace_tools.store')
  local _, errors = store.list()
  for _, err in ipairs(errors) do
    problem('warn', tostring(err), { 'Inspect :WorkspaceInfo and repair the affected workspace record' })
  end
  if state.blocked then
    problem(
      'warn',
      'Auto-save blocked after a restore failure; automatic saves are suspended.',
      { 'Save manually or successfully restore a workspace to resume' }
    )
  end

  table.sort(issues, function(a, b)
    if a.level ~= b.level then
      return a.level == 'error'
    end
    return a.message < b.message
  end)
  for _, issue in ipairs(issues) do
    vim.health[issue.level](issue.message, issue.advice)
  end
  if #issues == 0 then
    vim.health.ok('Workspace records and automatic-save state are valid.')
  end
  vim.health.info('Details: :WorkspaceInfo')
end

return M
