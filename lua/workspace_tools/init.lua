local M = {}
local config = require('workspace_tools.config')
local store = require('workspace_tools.store')
local session = require('workspace_tools.session')
local state = { initialized = false, busy = false, blocked = false, stopped = false, active = nil, explicit = false }

local function now()
  local seconds, microseconds = vim.uv.gettimeofday()
  return seconds + microseconds / 1000000
end

local function hooks(event, entry)
  for _, callback in ipairs(config.options.hooks[event] or {}) do
    assert(type(callback) == 'function', 'workspace hooks must be functions')
    if callback(store.metadata(entry)) == false then
      error(event .. ' hook cancelled operation')
    end
  end
end

local function operation(callback, restoring)
  if not state.initialized then
    M.setup()
  end
  if state.busy then
    return nil, 'workspace operation already in progress'
  end
  state.busy = true
  local ok, value = pcall(callback)
  state.busy = false
  if not ok then
    if restoring then
      state.blocked = true
    end
    return nil, tostring(value)
  end
  return value
end

local function current(name)
  local cwd = store.normalize(vim.fn.getcwd())
  if name == nil and state.active and state.active.cwd == cwd then
    name = state.active.name
  end
  name = name or ''
  assert(type(name) == 'string' and not name:find('[\r\n%z]'), 'invalid workspace name')
  return cwd, name
end

local function resolve(target)
  if type(target) == 'table' then
    return assert(store.read(target.id), 'workspace not found')
  end
  if type(target) == 'string' and #target == 64 and target:match('^[a-f0-9]+$') then
    local entry = store.read(target)
    if entry then
      return entry
    end
  end
  local cwd, name = current(target)
  return assert(store.read(store.id(cwd, name)), 'workspace not found for ' .. cwd)
end

---Save the effective current directory, or a named workspace within it.
---@param opts? {name?:string}
---@return table? workspace, string? error
function M.save(opts)
  return operation(function()
    local cwd, name = current(opts and opts.name)
    local id, timestamp = store.id(cwd, name), now()
    local entry = store.read(id) or { version = 1, id = id, cwd = cwd, name = name, created_at = timestamp }
    entry.updated_at, entry.accessed_at = timestamp, timestamp
    entry.files = session.files()
    hooks('pre_save', entry)
    entry.session = session.capture()
    entry.files = session.files()
    store.write(entry)
    state.active, state.blocked, state.explicit = store.metadata(entry), false, true
    hooks('post_save', entry)
    return store.metadata(entry)
  end)
end

---Restore by metadata, ID, name in the current directory, or current workspace.
function M.restore(target)
  return operation(function()
    local entry = resolve(target)
    assert(vim.fn.isdirectory(entry.cwd) == 1, 'workspace directory no longer exists: ' .. entry.cwd)
    session.check_modified()
    hooks('pre_restore', entry)
    session.restore(entry)
    entry.accessed_at = now()
    store.write(entry)
    state.active, state.explicit = store.metadata(entry), true
    hooks('post_restore', entry)
    state.blocked = false
    return store.metadata(entry)
  end, true)
end

---List metadata in most-recently-used order; query uses native fuzzy matching.
function M.list(opts)
  local items, errors = store.list()
  opts = opts or {}
  if opts.query and opts.query ~= '' then
    items = vim.fn.matchfuzzy(items, opts.query, { key = 'search' })
  end
  if opts.limit then
    items = vim.list_slice(items, 1, opts.limit)
  end
  return items, errors
end

function M.last()
  local items = M.list({ limit = 1 })
  if not items[1] then
    return nil, 'no saved workspaces'
  end
  return M.restore(items[1])
end

function M.delete(target)
  return operation(function()
    local entry = resolve(target)
    assert(vim.uv.fs_unlink(store.path(entry.id)))
    if state.active and state.active.id == entry.id then
      state.active = nil
      state.stopped = true -- do not recreate a deliberately deleted workspace on exit
    elseif store.normalize(vim.fn.getcwd()) == entry.cwd and entry.name == '' then
      state.stopped = true
    end
    hooks('post_delete', entry)
    return store.metadata(entry)
  end)
end

function M.stop()
  state.stopped = true
end

function M.start()
  state.stopped = false
end

function M.status()
  return vim.deepcopy(state)
end

function M.search(opts)
  if not state.initialized then
    M.setup()
  end
  return require('workspace_tools.picker').open(opts or {})
end

local function automatic_allowed(target_cwd)
  if state.busy or state.blocked or state.stopped or #vim.api.nvim_list_uis() == 0 or state.stdin then
    return false
  end
  if not state.explicit and #state.argv > 0 then
    if #state.argv ~= 1 or vim.fn.isdirectory(state.argv[1]) ~= 1 then
      return false
    end
  end
  local cwd = target_cwd or store.normalize(vim.fn.getcwd())
  for _, path in ipairs(config.options.suppressed_dirs) do
    if cwd == store.normalize(path) then
      return false
    end
  end
  return true
end

local function report_error(err)
  vim.notify('workspace-tools: ' .. err, vim.log.levels.ERROR)
end

function M.setup(opts)
  config.setup(opts)
  state.initialized = true
  state.argv = state.argv or vim.tbl_map(store.normalize, vim.fn.argv())
  state.stdin = state.stdin or vim.tbl_contains(vim.v.argv, '-')
  local group = vim.api.nvim_create_augroup('WorkspaceTools', { clear = true })
  vim.api.nvim_create_autocmd('StdinReadPre', {
    group = group,
    callback = function()
      state.stdin = true
    end,
  })
  local function startup()
    if state.startup_done then
      return
    end
    state.startup_done = true
    if not config.options.auto_restore then
      return
    end
    local cwd = store.normalize(vim.fn.getcwd())
    local target = #state.argv == 1 and store.normalize(state.argv[1]) or cwd
    if not automatic_allowed(target) then
      return
    end
    local id = store.id(target, '')
    if vim.fn.filereadable(store.path(id)) == 1 then
      local _, err = M.restore({ id = id })
      if err then
        report_error(err)
      end
    end
  end
  if vim.v.vim_did_enter == 1 then
    vim.schedule(startup)
  else
    vim.api.nvim_create_autocmd('VimEnter', { group = group, once = true, callback = startup })
  end
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      if config.options.auto_save and automatic_allowed() and #session.files() > 0 then
        local _, err = M.save()
        if err then
          report_error(err)
        end
      end
    end,
  })
  return M
end

return M
