local M = {}
local active

local function label(item)
  local name = (item.name ~= '' and item.name or vim.fs.basename(item.cwd)) .. ' — '
  return name
    .. vim.fn.fnamemodify(item.cwd, ':~')
    .. ('  [%d files · %s]'):format(#item.files, os.date('%Y-%m-%d %H:%M', item.updated_at))
    .. (item.missing and ' [missing]' or '')
end

local function choose(item)
  if item then
    local _, err = require('workspace_tools').restore(item)
    if err then
      vim.notify('workspace-tools: ' .. err, vim.log.levels.ERROR)
    end
  end
end

local function builtin(items, opts)
  if active then
    active.close()
  end
  local origin = vim.api.nvim_get_current_win()
  local input = vim.api.nvim_create_buf(false, true)
  local list = vim.api.nvim_create_buf(false, true)
  for _, buf in ipairs({ input, list }) do
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'workspace-tools'
  end
  local function geometry()
    local width = math.max(1, math.min(100, vim.o.columns - 4))
    local height = math.max(1, math.min(14, vim.o.lines - 8))
    return width,
      height,
      math.max(0, math.floor((vim.o.lines - height - 6) / 2)),
      math.max(0, math.floor((vim.o.columns - width - 2) / 2))
  end
  local width, height, row, col = geometry()
  local results_win = vim.api.nvim_open_win(list, false, {
    relative = 'editor',
    row = row + 3,
    col = col,
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
  })
  local input_win = vim.api.nvim_open_win(input, true, {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = 1,
    style = 'minimal',
    border = 'rounded',
    title = ' Workspaces · type to search ',
    title_pos = 'center',
  })
  vim.wo[results_win].cursorline = true
  vim.wo[results_win].wrap = false
  vim.wo[input_win].wrap = false
  local filtered, selected, closed = {}, 1, false
  local group = vim.api.nvim_create_augroup('WorkspaceToolsPicker', { clear = true })
  local handle = { input = input, list = list, input_win = input_win, results_win = results_win }
  local function close()
    if closed then
      return
    end
    closed = true
    vim.api.nvim_del_augroup_by_id(group)
    vim.cmd('stopinsert')
    for _, win in ipairs({ input_win, results_win }) do
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
    for _, buf in ipairs({ input, list }) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    if vim.api.nvim_win_is_valid(origin) then
      vim.api.nvim_set_current_win(origin)
    end
    if active == handle then
      active = nil
    end
  end
  handle.close = close
  active = handle
  local function render()
    local query = vim.api.nvim_buf_get_lines(input, 0, 1, false)[1] or ''
    filtered = query == '' and items or vim.fn.matchfuzzy(items, query, { key = 'search' })
    selected = math.max(1, math.min(selected, #filtered))
    local lines = {}
    for _, item in ipairs(filtered) do
      lines[#lines + 1] = label(item)
    end
    if #lines == 0 then
      lines = { 'No matching workspaces' }
    end
    vim.bo[list].modifiable = true
    vim.api.nvim_buf_set_lines(list, 0, -1, false, lines)
    vim.bo[list].modifiable = false
    vim.api.nvim_win_set_cursor(results_win, { selected, 0 })
  end
  local function move(delta)
    if #filtered > 0 then
      selected = ((selected - 1 + delta) % #filtered) + 1
      vim.api.nvim_win_set_cursor(results_win, { selected, 0 })
    end
  end
  local function confirm()
    local item = filtered[selected]
    if not item then
      return
    end
    close()
    vim.schedule(function()
      choose(item)
    end)
  end
  for _, key in ipairs({ '<CR>' }) do
    vim.keymap.set({ 'i', 'n' }, key, confirm, { buffer = input, nowait = true })
  end
  for _, key in ipairs({ '<Esc>', '<C-c>' }) do
    vim.keymap.set({ 'i', 'n' }, key, close, { buffer = input, nowait = true })
  end
  for _, key in ipairs({ '<C-n>', '<Down>' }) do
    vim.keymap.set({ 'i', 'n' }, key, function()
      move(1)
    end, { buffer = input })
  end
  for _, key in ipairs({ '<C-p>', '<Up>' }) do
    vim.keymap.set({ 'i', 'n' }, key, function()
      move(-1)
    end, { buffer = input })
  end
  vim.api.nvim_create_autocmd({ 'TextChangedI', 'TextChanged' }, { group = group, buffer = input, callback = render })
  vim.api.nvim_create_autocmd('VimResized', {
    group = group,
    callback = function()
      local w, h, r, c = geometry()
      vim.api.nvim_win_set_config(input_win, { relative = 'editor', row = r, col = c, width = w, height = 1 })
      vim.api.nvim_win_set_config(results_win, { relative = 'editor', row = r + 3, col = c, width = w, height = h })
    end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(args)
      if tonumber(args.match) == input_win or tonumber(args.match) == results_win then
        vim.schedule(close)
      end
    end,
  })
  vim.api.nvim_buf_set_lines(input, 0, -1, false, { opts.query or '' })
  render()
  vim.api.nvim_win_set_cursor(input_win, { 1, #(opts.query or '') })
  vim.cmd('startinsert!')
  return handle
end

function M.open(opts)
  local items, errors = require('workspace_tools').list()
  if #errors > 0 then
    vim.notify(
      ('workspace-tools: skipped %d invalid bundle(s); see :checkhealth workspace_tools'):format(#errors),
      vim.log.levels.WARN
    )
  end
  if #items == 0 then
    vim.notify('workspace-tools: no saved workspaces', vim.log.levels.INFO)
    return
  end
  local picker = opts.picker or require('workspace_tools.config').options.picker
  if type(picker) == 'function' then
    if opts.query and opts.query ~= '' then
      items = vim.fn.matchfuzzy(items, opts.query, { key = 'search' })
    end
    return picker(items, { prompt = 'Workspaces', format_item = label }, choose)
  end
  if picker == 'auto' or picker == 'selection' then
    local ok, selection = pcall(require, 'selection_tools')
    if ok then
      if opts.query and opts.query ~= '' then
        items = vim.fn.matchfuzzy(items, opts.query, { key = 'search' })
      end
      return selection.select(items, { prompt = 'Workspaces', format_item = label }, choose)
    end
    assert(picker ~= 'selection', 'selection-tools.nvim is unavailable')
  end
  return builtin(items, opts)
end

return M
