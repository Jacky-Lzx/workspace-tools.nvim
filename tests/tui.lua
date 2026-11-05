local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
vim.cmd('runtime plugin/workspace-tools.lua')
local directory = assert(vim.env.WORKSPACE_TEST_DIR)
local case = assert(vim.env.WORKSPACE_TEST_CASE)
local workspace = require('workspace_tools')
local store = require('workspace_tools.store')
directory = store.normalize(directory)
local a, b = directory .. '/alpha', directory .. '/beta'
vim.fn.mkdir(a, 'p')
vim.fn.mkdir(b, 'p')
vim.fn.writefile({ 'alpha content', 'second' }, a .. '/one.txt')
vim.fn.writefile({ 'beta content', 'second' }, b .. '/two.txt')
if case == 'selection' then
  vim.opt.rtp:append(root .. '/../selection-tools.nvim')
  require('selection_tools').setup({ matcher = { backend = 'native' } })
end
workspace.setup({
  directory = directory .. '/store',
  auto_save = false,
  picker = case == 'selection' and 'auto' or 'builtin',
})
vim.api.nvim_set_current_dir(a)
vim.cmd.edit(vim.fn.fnameescape(a .. '/one.txt'))
local alpha = assert(workspace.save())
vim.api.nvim_set_current_dir(b)
vim.cmd.edit(vim.fn.fnameescape(b .. '/two.txt'))
vim.cmd('tabnew ' .. vim.fn.fnameescape(b .. '/two.txt'))
local beta = assert(workspace.save({ name = 'beta-target-workspace' }))
assert(workspace.restore(alpha))

local phase, picker, ticks, finished = 'open', nil, 0, false
local function mark(stage)
  vim.fn.writefile({ stage }, directory .. '/stage')
end
vim.keymap.set('n', '<F6>', function()
  picker = workspace.search()
end)
mark('open')
local function input()
  return picker and (picker.input or picker.input_buf)
end
local function query()
  if not picker then
    return ''
  end
  if case == 'selection' then
    return picker.query
  end
  return vim.api.nvim_buf_get_lines(input(), 0, 1, false)[1]
end
local function closed()
  return not input() or not vim.api.nvim_buf_is_valid(input())
end
local function no_leaks()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    assert(vim.bo[buf].filetype ~= 'workspace-tools', 'picker buffer leaked')
  end
end
local timer = vim.uv.new_timer()
timer:start(
  25,
  25,
  vim.schedule_wrap(function()
    if finished then
      return
    end
    local ok, err = xpcall(function()
      ticks = ticks + 1
      assert(ticks < 600, 'timeout at ' .. phase)
      if phase == 'open' and input() and vim.api.nvim_get_mode().mode == 'i' then
        phase = 'move'
        mark('move')
      elseif
        phase == 'move'
        and (
          case == 'selection' and picker.index == 2
          or case == 'builtin' and vim.api.nvim_win_get_cursor(picker.results_win)[1] == 2
        )
      then
        phase = 'long'
        mark('long')
      elseif phase == 'long' and #query() == 120 then
        vim.cmd.redraw()
        if case == 'builtin' then
          assert(vim.api.nvim_buf_get_lines(picker.list, 0, 1, false)[1] == 'No matching workspaces')
        else
          assert(#picker.matches == 0)
        end
        assert(store.normalize(vim.fn.getcwd()) == a, 'typing changed the workspace')
        phase = 'filter'
        mark('filter')
      elseif phase == 'filter' and query() == 'bta-trgt-wrkspc' then
        if case == 'builtin' then
          assert(vim.api.nvim_buf_line_count(picker.list) == 1)
          assert(vim.api.nvim_buf_get_lines(picker.list, 0, 1, false)[1]:find('/beta', 1, true))
          vim.cmd.redraw()
          local cfg = vim.api.nvim_win_get_config(picker.results_win)
          local screen = ''
          for column = cfg.col + 2, cfg.col + 8 do
            screen = screen .. vim.fn.screenstring(cfg.row + 2, column)
          end
          assert(screen:find('beta', 1, true), 'matching project is not visible in the terminal')
        else
          assert(#picker.matches == 1)
        end
        phase = 'resize'
        mark('resize')
      elseif phase == 'resize' and vim.o.columns == 42 then
        assert(vim.api.nvim_get_mode().mode == 'i')
        local cfg = vim.api.nvim_win_get_config(picker.input_win)
        assert(cfg.width <= 42, 'picker did not fit resized terminal')
        phase = 'confirm'
        mark('confirm')
      elseif phase == 'confirm' and closed() and workspace.status().active.id == beta.id then
        assert(store.normalize(vim.fn.getcwd()) == b)
        assert(#vim.api.nvim_list_tabpages() == 2)
        assert(vim.api.nvim_buf_get_name(0) == b .. '/two.txt')
        assert(vim.api.nvim_get_mode().mode == 'n', 'restore did not return to Normal mode')
        no_leaks()
        phase = 'reopen'
        mark('reopen')
      elseif phase == 'reopen' and input() and not closed() and vim.api.nvim_get_mode().mode == 'i' then
        phase = 'cancel'
        mark('cancel')
      elseif phase == 'cancel' and closed() then
        assert(workspace.status().active.id == beta.id)
        assert(store.normalize(vim.fn.getcwd()) == b)
        no_leaks()
        -- The Ex command also opens a prefiltered search and Esc cleans it up.
        vim.cmd('WorkspaceSearch alpha')
        phase = 'command'
        mark('command_cancel')
      elseif phase == 'command' and vim.api.nvim_get_mode().mode == 'n' then
        local floats = 0
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_config(win).relative ~= '' then
            floats = floats + 1
          end
        end
        if floats == 0 then
          no_leaks()
          finished = true
          timer:stop()
          timer:close()
          vim.fn.writefile({
            'PASS '
              .. case
              .. ' real TUI: burst input, fuzzy search, resize, restore, cancellation, Ex command, focus/mode cleanup',
          }, directory .. '/result')
          vim.cmd('qa!')
        end
      end
    end, debug.traceback)
    if not ok then
      finished = true
      timer:stop()
      timer:close()
      vim.fn.writefile({ tostring(err) }, directory .. '/result')
      vim.cmd('cquit 1')
    end
  end)
)
