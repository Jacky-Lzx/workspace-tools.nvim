if vim.g.loaded_workspace_tools then
  return
end
vim.g.loaded_workspace_tools = true
local notify = require('workspace_tools.notify')
if vim.fn.has('nvim-0.11') == 0 then
  notify.send('Requires Neovim 0.11+', vim.log.levels.ERROR)
  return
end

local function api()
  return require('workspace_tools')
end
local function notify_result(entry, err, level)
  if not entry then
    notify.send(err, level)
  end
end
local function complete(prefix)
  local names = {}
  for _, entry in ipairs(api().list()) do
    if entry.cwd == require('workspace_tools.store').normalize(vim.fn.getcwd()) and entry.name ~= '' then
      if vim.startswith(entry.name, prefix) then
        names[#names + 1] = entry.name
      end
    end
  end
  return names
end

require('workspace_tools.user_command').create('WorkspaceSave', function(args)
  notify_result(api().save({ name = args.args ~= '' and args.args or nil }))
end, { nargs = '*', complete = complete, desc = 'Save current workspace (optional name)' })
require('workspace_tools.user_command').create('WorkspaceRestore', function(args)
  notify_result(api().restore(args.args ~= '' and args.args or nil))
end, { nargs = '*', complete = complete, desc = 'Restore current workspace (optional name or ID)' })
require('workspace_tools.user_command').create('WorkspaceSearch', function(args)
  api().search({ query = args.args })
end, { nargs = '*', desc = 'Search workspace history' })
require('workspace_tools.user_command').create('WorkspaceLast', function()
  notify_result(api().last())
end, { desc = 'Restore most recently used workspace' })
require('workspace_tools.user_command').create('WorkspaceDelete', function(args)
  local target = args.args ~= '' and args.args or nil
  if args.bang then
    notify_result(api().delete(target))
    return
  end
  -- Resolve the exact ID before displaying an asynchronous confirmation.
  local store = require('workspace_tools.store')
  local cwd = store.normalize(vim.fn.getcwd())
  local active = api().status().active
  local name = target or (active and active.cwd == cwd and active.name) or ''
  local id = #name == 64 and name:match('^[a-f0-9]+$') and name or store.id(cwd, name)
  local ok, entry = pcall(store.read, id)
  if ok and not entry and id == name then
    ok, entry = pcall(store.read, store.id(cwd, name))
  end
  if not ok or not entry then
    if not ok then
      notify_result(nil, tostring(entry))
    else
      notify_result(
        nil,
        ('No saved workspace %sfor %s. Use `:WorkspaceSearch` to browse saved workspaces.'):format(
          name ~= '' and ('named ' .. notify.code(name) .. ' ') or '',
          notify.code(cwd)
        ),
        vim.log.levels.WARN
      )
    end
    return
  end
  vim.ui.select({ 'Cancel', 'Delete' }, {
    prompt = 'Delete workspace ' .. (entry.name ~= '' and entry.name or entry.cwd) .. '?',
  }, function(choice)
    if choice == 'Delete' then
      notify_result(api().delete({ id = entry.id }))
    end
  end)
end, { nargs = '*', bang = true, complete = complete, desc = 'Delete saved workspace; ! skips confirmation' })
require('workspace_tools.user_command').create('WorkspaceStop', function()
  api().stop()
end, { desc = 'Pause automatic workspace saving' })
require('workspace_tools.user_command').create('WorkspaceStart', function()
  api().start()
end, { desc = 'Resume automatic workspace saving' })
