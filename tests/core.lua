local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
vim.cmd('runtime plugin/workspace-tools.lua')
local workspace = require('workspace_tools')
local store = require('workspace_tools.store')
local temp = store.normalize(assert(vim.env.WORKSPACE_TEST_DIR))
local a, b = temp .. '/project A 中文', temp .. '/project-B'
vim.fn.mkdir(a, 'p')
vim.fn.mkdir(b, 'p')
vim.fn.writefile({ 'one', 'two', 'three', 'four', 'five' }, a .. '/one.txt')
vim.fn.writefile({ 'other' }, a .. '/two.txt')
vim.fn.writefile({ 'foreign' }, b .. '/other.txt')
vim.api.nvim_set_current_dir(a)
local calls = {}
workspace.setup({
  directory = temp .. '/state with spaces',
  auto_save = false,
  picker = 'builtin',
  hooks = {
    pre_save = {
      function(entry)
        assert(entry.id and entry.cwd and entry.files)
        calls[#calls + 1] = 'pre_save'
      end,
    },
    post_restore = {
      function(entry)
        calls[#calls + 1] = 'post_restore'
        assert(store.normalize(vim.fn.getcwd()) == entry.cwd)
      end,
    },
    post_delete = {
      function()
        calls[#calls + 1] = 'post_delete'
      end,
    },
  },
})
local function must(entry, err)
  assert(entry, err)
  return entry
end
local function notification(command)
  local notifications, notify = {}, vim.notify
  vim.notify = function(message, level, opts)
    notifications[#notifications + 1] = { message = message, level = level, opts = opts }
  end
  local ok, err = pcall(vim.cmd, command)
  vim.notify = notify
  assert(ok, err)
  assert(#notifications == 1, 'expected one notification for ' .. command)
  return notifications[1]
end

-- Missing records are actionable warnings without Lua source paths or line numbers.
for _, command in ipairs({
  'WorkspaceRestore',
  'WorkspaceRestore missing name',
  'WorkspaceDelete',
  'WorkspaceDelete! missing name',
  'WorkspaceLast',
}) do
  local result = notification(command)
  assert(result.level == vim.log.levels.WARN, command .. ' should warn')
  assert(result.opts.title == 'workspace-tools' and result.opts.markdown == true)
  assert(not result.message:find('workspace-tools:', 1, true), 'plugin name repeated in body')
  assert(result.message:find('No saved workspace', 1, true))
  assert(result.message:find(':Workspace', 1, true), 'missing action hint')
  assert(not result.message:find('.lua:', 1, true), 'Lua source location leaked')
  if command ~= 'WorkspaceLast' then
    assert(result.message:find(require('workspace_tools.notify').code(a), 1, true), 'missing highlighted directory')
  end
  if command:find('missing name', 1, true) then
    assert(result.message:find('missing name', 1, true), 'missing workspace name')
  end
end
assert(notification('WorkspaceRestore').message:find('`:WorkspaceSave`', 1, true), 'command should use Markdown code')
local absent, message, level = workspace.restore({ id = store.id(a, 'deleted') })
assert(not absent and level == vim.log.levels.WARN and message:find('with ID', 1, true))

vim.cmd.edit(vim.fn.fnameescape(a .. '/one.txt'))
vim.wo.foldmethod = 'manual'
vim.cmd('2,4fold')
vim.api.nvim_win_set_cursor(0, { 5, 0 })
vim.cmd.vsplit(vim.fn.fnameescape(a .. '/two.txt'))
vim.cmd('tabnew ' .. vim.fn.fnameescape(a .. '/one.txt'))
local options = vim.o.sessionoptions
local saved = must(workspace.save())
assert(saved.name == '' and #saved.files == 2 and not saved.session)
assert(vim.o.sessionoptions == options, 'save mutated global sessionoptions')
assert(store.read(saved.id).session:find('tabnew', 1, true))
assert(vim.fn.getfperm(store.path(saved.id)) == 'rw-------', 'bundle is not private')
assert(#calls == 1 and calls[1] == 'pre_save')

-- Clean workspace switch restores real split/tab/view state and removes old hidden files.
vim.cmd('tabonly | only')
vim.api.nvim_set_current_dir(b)
vim.cmd.edit(vim.fn.fnameescape(b .. '/other.txt'))
local foreign = vim.api.nvim_get_current_buf()
must(workspace.restore(saved))
assert(store.normalize(vim.fn.getcwd()) == store.normalize(a))
assert(#vim.api.nvim_list_tabpages() == 2)
assert(#vim.api.nvim_tabpage_list_wins(vim.api.nvim_list_tabpages()[1]) == 2)
assert(not vim.api.nvim_buf_is_valid(foreign), 'old workspace file leaked')
local found_view = false
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_list_tabpages()[1])) do
  if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == a .. '/one.txt' then
    vim.api.nvim_win_call(win, function()
      assert(vim.fn.foldclosed(2) == 2, 'manual fold not restored')
      assert(vim.api.nvim_win_get_cursor(win)[1] == 5, 'cursor not restored')
      found_view = true
    end)
  end
end
assert(found_view)
assert(calls[#calls] == 'post_restore')

-- Refusal leaves modified text, cwd and tabs untouched, and prevents exit overwrite.
vim.api.nvim_buf_set_lines(0, 0, 1, false, { 'unsaved' })
local before_tabs, before_cwd = #vim.api.nvim_list_tabpages(), vim.fn.getcwd()
local entry, err = workspace.restore(saved)
assert(not entry and err:find('modified buffers', 1, true))
assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'unsaved')
assert(#vim.api.nvim_list_tabpages() == before_tabs and vim.fn.getcwd() == before_cwd)
assert(workspace.status().blocked)
vim.cmd('edit!')
must(workspace.restore(saved.id))
assert(not workspace.status().blocked)

local named = must(workspace.save({ name = 'Review / 中文 | tab' }))
assert(named.id ~= saved.id and #workspace.list() == 2)
assert(must(workspace.save()).id == named.id, 'active named workspace not retained')
assert(workspace.list({ query = 'Rv中文' })[1].id == named.id, 'fuzzy search failed')
assert(#workspace.list({ query = 'does-not-exist' }) == 0)
assert(#workspace.list({ limit = 1 }) == 1)
assert(must(workspace.restore('Review / 中文 | tab')).id == named.id)
assert(workspace.list()[1].id == named.id, 'sub-second recency ordering is incorrect')
assert(must(workspace.last()).id == named.id)

-- Canonical symlink identity and arbitrary path/name characters never become commands.
local link = temp .. '/alias'
assert(vim.uv.fs_symlink(a, link, { dir = true }))
vim.api.nvim_set_current_dir(link)
assert(must(workspace.save({ name = '' })).id == saved.id)
assert(store.normalize(a .. '/') == store.normalize(a))
assert(store.normalize(temp .. '/literal$HOME') == temp .. '/literal$HOME')

-- Disposable task/checkhealth UI is excluded as in the user's current config.
vim.cmd('new')
local transient = vim.api.nvim_get_current_buf()
vim.bo[transient].filetype = 'tasktoolsoutput'
vim.bo[transient].buftype = 'nofile'
must(workspace.save())
assert(not vim.api.nvim_buf_is_valid(transient))

-- Hook cancellation never replaces the last known-good bundle.
local original = store.read(saved.id).session
workspace.setup({
  directory = temp .. '/state with spaces',
  auto_save = false,
  hooks = {
    pre_save = {
      function()
        return false
      end,
    },
  },
})
entry, err = workspace.save()
assert(not entry and err:find('cancelled', 1, true))
assert(store.read(saved.id).session == original)
workspace.setup({ directory = temp .. '/state with spaces', auto_save = false })

-- A capture failure and an interrupted replacement preserve the previous record.
workspace.setup({ directory = temp .. '/state with spaces', auto_save = false, sessionoptions = 'invalid' })
entry, err = workspace.save({ name = '' })
assert(not entry and err)
assert(vim.o.sessionoptions == options)
assert(store.read(saved.id).session == original)
workspace.setup({ directory = temp .. '/state with spaces', auto_save = false })
local rename = vim.uv.fs_rename
vim.uv.fs_rename = function()
  return nil, 'simulated rename failure'
end
entry, err = workspace.save({ name = '' })
vim.uv.fs_rename = rename
assert(not entry and err:find('simulated rename failure', 1, true))
assert(store.read(saved.id).session == original)

-- One malformed record must not hide valid history; failed loads block auto-save.
local broken = {
  version = 1,
  id = store.id(a, 'broken'),
  cwd = a,
  name = 'broken',
  created_at = 1,
  updated_at = 1,
  accessed_at = 1,
  files = {},
  session = 'this is invalid vimscript\n',
}
store.write(broken)
assert(notification('WorkspaceRestore broken').level == vim.log.levels.ERROR, 'invalid sessions must still error')
entry, err = workspace.restore(broken.id)
assert(not entry and err and workspace.status().blocked)
assert(vim.g.SessionLoad == nil)
local bad_id = string.rep('a', 64)
store.write_file(store.path(bad_id), '{broken')
local list, errors = workspace.list()
assert(#list == 3 and #errors == 1)
must(workspace.restore(saved))

local missing = {
  version = 1,
  id = store.id(b, 'gone'),
  cwd = b,
  name = 'gone',
  created_at = 1,
  updated_at = 1,
  accessed_at = 1,
  files = {},
  session = '',
}
store.write(missing)
vim.fn.delete(b, 'rf')
entry, err = workspace.restore(missing.id)
assert(not entry and err:find('no longer exists', 1, true))
assert(workspace.list({ query = 'gone' })[1].missing)

-- Commands use whole names with spaces; explicit deletion cannot recreate on exit.
vim.cmd('WorkspaceSave command name')
assert(store.read(store.id(store.normalize(a), 'command name')))
vim.cmd('WorkspaceDelete! command name')
assert(not store.read(store.id(store.normalize(a), 'command name')))
assert(workspace.status().stopped)
vim.cmd('WorkspaceStart')
assert(not workspace.status().stopped)
vim.cmd('WorkspaceStop')
assert(workspace.status().stopped)
must(workspace.delete(named.id))
assert(not store.read(named.id))
assert(#vim.fn.glob(store.directory() .. '/.tmp-*', false, true) == 0, 'temporary file leaked')

-- Window and tab local directories survive, without changing the caller's global options.
vim.cmd('tabonly | only')
vim.api.nvim_set_current_dir(a)
vim.cmd.edit(vim.fn.fnameescape(a .. '/one.txt'))
vim.fn.mkdir(a .. '/window-local', 'p')
vim.fn.mkdir(a .. '/tab-local', 'p')
vim.cmd.vsplit(vim.fn.fnameescape(a .. '/two.txt'))
vim.cmd('lcd ' .. vim.fn.fnameescape(a .. '/window-local'))
vim.cmd('tabnew ' .. vim.fn.fnameescape(a .. '/one.txt'))
vim.cmd('tcd ' .. vim.fn.fnameescape(a .. '/tab-local'))
local scoped = must(workspace.save({ name = 'scopes' }))
vim.cmd('tabonly | only')
vim.api.nvim_set_current_dir(a)
must(workspace.restore(scoped))
assert(vim.fn.getcwd() == a .. '/tab-local' and vim.fn.haslocaldir(-1, 0) == 1)
local local_window = false
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_list_tabpages()[1])) do
  if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == a .. '/two.txt' then
    assert(vim.fn.haslocaldir(win, 1) == 1)
    assert(vim.fn.getcwd(win, 1) == a .. '/window-local', vim.fn.getcwd(win, 1))
    local_window = true
  end
end
assert(local_window, 'window local directory not restored')

print(
  'PASS native sessions, splits/tabs/cursor/folds, dirty guard, names, fuzzy history, symlinks, hooks, corrupt/missing records, commands'
)
vim.cmd('qa!')
