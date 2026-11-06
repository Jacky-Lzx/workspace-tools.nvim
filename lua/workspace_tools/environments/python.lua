local M = {}
local api, uv = vim.api, vim.uv
local options, records, jobs = {}, {}, {}
local markers =
  { 'pyrightconfig.json', 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile', '.git' }
local defaults = {
  directory = vim.fn.stdpath('state') .. '/workspace-tools/python',
  search_paths = {
    '~/.virtualenvs',
    '~/.cache/pypoetry/virtualenvs',
    '~/Library/Caches/pypoetry/virtualenvs',
    '~/.pyenv/versions',
    '~/.conda/envs',
    '~/miniconda3/envs',
    '~/anaconda3/envs',
  },
  search_depth = 3,
  max_directories = 3000,
}
local function normalize(path, real)
  if path == '~' or path:sub(1, 2) == '~/' then
    path = vim.fn.expand('~') .. path:sub(2)
  end
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ':p'), { expand_env = false }):gsub('/+$', '')
  path = path == '' and '/' or path
  return real and (uv.fs_realpath(path) or path) or path
end
local function config()
  return vim.tbl_extend('force', defaults, options)
end
function M.root(opts)
  opts = opts or {}
  if opts.root then
    return normalize(opts.root, true)
  end
  local buf = opts.buf or api.nvim_get_current_buf()
  local name = api.nvim_buf_is_valid(buf) and api.nvim_buf_get_name(buf) or ''
  local dir = name ~= '' and vim.fs.dirname(name) or vim.fn.getcwd()
  return normalize(vim.fs.root(dir, markers) or dir, true)
end
local function interpreter(path)
  -- Preserve bin/python symlinks: realpath would lose the venv's sys.prefix.
  path = normalize(path)
  if vim.fn.isdirectory(path) == 1 then
    for _, suffix in ipairs({ '/bin/python', '/bin/python3', '/Scripts/python.exe' }) do
      if vim.fn.executable(path .. suffix) == 1 then
        path = path .. suffix
        break
      end
    end
  end
  return vim.fn.executable(path) == 1 and path or nil
end
local function describe(python)
  local parent = vim.fs.dirname(python)
  local root = (vim.fs.basename(parent) == 'bin' or vim.fs.basename(parent) == 'Scripts') and vim.fs.dirname(parent)
    or nil
  local kind = root and uv.fs_stat(root .. '/conda-meta') and 'conda'
    or root and uv.fs_stat(root .. '/pyvenv.cfg') and 'venv'
    or 'interpreter'
  return { python = python, path = root or parent, kind = kind, name = vim.fs.basename(root or python) }
end
local function location(root)
  return normalize(config().directory) .. '/' .. vim.fn.sha256(root) .. '.json'
end
local function load(root)
  if records[root] == nil then
    records[root] = false
    local path = location(root)
    local stat = uv.fs_stat(path)
    if stat and stat.size <= 65536 then
      local ok, value = pcall(function()
        return vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
      end)
      if
        ok
        and type(value) == 'table'
        and value.version == 1
        and value.root == root
        and type(value.python) == 'string'
      then
        records[root] = value.python
      end
    end
  end
  return records[root]
end
local function system_python()
  for _, name in ipairs({ 'python3', 'python' }) do
    local path = vim.fn.exepath(name)
    if path ~= '' then
      return path
    end
  end
end
function M.current(opts)
  local root = M.root(opts)
  local selected = load(root)
  if selected == 'system' then
    return system_python()
  end
  if selected and interpreter(selected) then
    return selected
  end
  for _, name in ipairs({ '.venv', 'venv', 'env' }) do
    local python = interpreter(root .. '/' .. name)
    if python then
      return python
    end
  end
  for _, name in ipairs({ 'VIRTUAL_ENV', 'CONDA_PREFIX' }) do
    if vim.env[name] and vim.env[name] ~= '' then
      local python = interpreter(vim.env[name])
      if python then
        return python
      end
    end
  end
  return nil
end
function M.environment(opts)
  local python = M.current(opts)
  if not python then
    return {}
  end
  local item = describe(python)
  local env = { PATH = vim.fs.dirname(python) .. (vim.fn.has('win32') == 1 and ';' or ':') .. (vim.env.PATH or '') }
  if item.kind == 'venv' then
    env.VIRTUAL_ENV, env.CONDA_PREFIX = item.path, ''
  end
  if item.kind == 'conda' then
    env.CONDA_PREFIX, env.VIRTUAL_ENV = item.path, ''
  end
  return env
end
local function persist(root, value)
  local directory = normalize(config().directory)
  assert(
    vim.fn.mkdir(directory, 'p', 448) == 1 or vim.fn.isdirectory(directory) == 1,
    'cannot create Python environment store'
  )
  local path = location(root)
  if not value then
    if uv.fs_stat(path) then
      assert(uv.fs_unlink(path))
    end
    return
  end
  local temp = path .. '.' .. uv.os_getpid() .. '.' .. tostring(uv.hrtime())
  local fd = assert(uv.fs_open(temp, 'wx', 384))
  local data = vim.json.encode({ version = 1, root = root, python = value })
  local ok, err = pcall(function()
    local written = 0
    while written < #data do
      local size = assert(uv.fs_write(fd, data:sub(written + 1), written))
      assert(size > 0, 'short write')
      written = written + size
    end
    assert(uv.fs_fsync(fd))
  end)
  uv.fs_close(fd)
  if not ok then
    uv.fs_unlink(temp)
    error(err)
  end
  local moved, failure = uv.fs_rename(temp, path)
  if not moved then
    uv.fs_unlink(temp)
    error(failure)
  end
end
function M.set(path, opts)
  opts = opts or {}
  local root = M.root(opts)
  local value = path == 'system' and 'system' or path and interpreter(path) or nil
  assert(not path or value, 'Expected a Python executable or environment directory')
  persist(root, value)
  records[root] = value or false
  local python = M.current({ root = root })
  api.nvim_exec_autocmds('User', {
    pattern = 'WorkspacePythonChanged',
    modeline = false,
    data = { root = root, python = python, environment = M.environment({ root = root }) },
  })
  return python
end

function M.discover(opts, callback)
  opts = opts or {}
  assert(type(callback) == 'function', 'discover requires a callback')
  local settings, root = config(), M.root(opts)
  local job = { cancelled = false }
  function job.cancel()
    job.cancelled = true
    jobs[job] = nil
  end
  jobs[job] = true
  local items, seen, queue, visited = {}, {}, {}, {}
  local function add(path)
    local python = path and interpreter(path)
    if python and not seen[python] then
      seen[python], items[#items + 1] = true, describe(python)
      return true
    end
  end
  add(M.current({ root = root }))
  for _, name in ipairs({ '.venv', 'venv', 'env' }) do
    add(root .. '/' .. name)
  end
  for _, name in ipairs({ 'VIRTUAL_ENV', 'CONDA_PREFIX' }) do
    if vim.env[name] and vim.env[name] ~= '' then
      add(vim.env[name])
    end
  end
  local paths = vim.deepcopy(settings.search_paths)
  for _, value in ipairs({
    vim.env.WORKON_HOME or '',
    vim.env.PYENV_ROOT and (vim.env.PYENV_ROOT .. '/versions') or '',
    vim.env.POETRY_CACHE_DIR and (vim.env.POETRY_CACHE_DIR .. '/virtualenvs') or '',
  }) do
    if value ~= '' then
      paths[#paths + 1] = value
    end
  end
  for _, path in ipairs(paths) do
    queue[#queue + 1] = { path = normalize(path, true), depth = 0 }
  end
  local conda = vim.fn.expand('~/.conda/environments.txt')
  if vim.fn.filereadable(conda) == 1 then
    for _, path in ipairs(vim.fn.readfile(conda, '', 1000)) do
      if path ~= '' then
        add(path)
      end
    end
  end
  local cursor, scanned, truncated = 1, 0, false
  local excluded = {
    ['.git'] = true,
    node_modules = true,
    __pycache__ = true,
    lib = true,
    include = true,
    share = true,
    pkgs = true,
    bin = true,
    Scripts = true,
  }
  local function step()
    if job.cancelled then
      return
    end
    for _ = 1, 16 do
      local entry = queue[cursor]
      if not entry or scanned >= settings.max_directories then
        truncated = entry ~= nil
        table.sort(items, function(a, b)
          return a.python < b.python
        end)
        jobs[job] = nil
        callback(items, { root = root, truncated = truncated })
        return
      end
      cursor = cursor + 1
      if not visited[entry.path] then
        visited[entry.path], scanned = true, scanned + 1
        local found = add(entry.path)
        if not found and entry.depth < settings.search_depth then
          local scan = uv.fs_scandir(entry.path)
          if scan then
            for _ = 1, 10000 do
              local name, kind = uv.fs_scandir_next(scan)
              if not name then
                break
              end
              if not excluded[name] then
                local child = entry.path .. '/' .. name
                if kind == 'directory' then
                  queue[#queue + 1] = { path = child, depth = entry.depth + 1 }
                elseif kind == 'link' then
                  add(child)
                end
              end
            end
          end
        end
      end
    end
    vim.schedule(step)
  end
  vim.schedule(step)
  return job
end
function M.select(opts)
  opts = opts or {}
  local root = M.root(opts)
  return M.discover({ root = root }, function(items, info)
    local choices = {
      { name = 'Automatic (project environment)', automatic = true },
      { name = 'System (PATH)', system = true },
      { name = 'Enter Python or environment path…', manual = true },
    }
    vim.list_extend(choices, items)
    local picker = opts.picker or config().picker
    if not picker then
      local ok, selection = pcall(require, 'selection_tools')
      picker = ok and selection.select or vim.ui.select
    end
    local function choose(path)
      local ok, result = pcall(M.set, path, { root = root })
      vim.notify(
        ok and ('Python: ' .. (result or 'PATH fallback')) or tostring(result),
        ok and vim.log.levels.INFO or vim.log.levels.ERROR,
        { title = 'workspace-tools' }
      )
      if opts.on_done then
        opts.on_done(ok and result or nil)
      end
    end
    picker(choices, {
      prompt = 'Python environment' .. (info.truncated and ' (search limit reached)' or ''),
      format_item = function(item)
        return item.python and (item.kind .. ' · ' .. item.python) or item.name
      end,
    }, function(item)
      if not item then
        return
      end
      if item.manual then
        vim.ui.input({ prompt = 'Python executable or environment: ', completion = 'file' }, function(path)
          if path and path ~= '' then
            choose(path)
          end
        end)
      else
        choose(item.system and 'system' or item.python)
      end
    end)
  end)
end
function M.disable()
  for job in pairs(jobs) do
    job.cancel()
  end
  pcall(require('workspace_tools.user_command').delete, 'WorkspacePython')
end
function M.setup(opts)
  opts = opts or {}
  assert(type(opts) == 'table', 'Python environment options must be a table')
  for _, key in ipairs({ 'max_directories', 'search_depth' }) do
    assert(
      opts[key] == nil or type(opts[key]) == 'number' and opts[key] >= 0 and opts[key] % 1 == 0,
      key .. ' must be a nonnegative integer'
    )
  end
  assert(opts.directory == nil or type(opts.directory) == 'string' and opts.directory ~= '', 'directory must be a path')
  if opts.search_paths then
    assert(vim.islist(opts.search_paths), 'search_paths must be a list')
    for _, path in ipairs(opts.search_paths) do
      assert(type(path) == 'string' and path ~= '', 'search_paths must contain paths')
    end
  end
  M.disable()
  options, records = vim.deepcopy(opts), {}
  require('workspace_tools.user_command').create('WorkspacePython', function(args)
    if args.bang or args.args ~= '' then
      local path
      if not args.bang then
        path = args.args
      end
      local ok, err = pcall(M.set, path)
      if not ok then
        vim.notify(tostring(err), vim.log.levels.ERROR)
      end
    else
      M.select()
    end
  end, {
    nargs = '?',
    bang = true,
    complete = 'file',
    desc = 'Select a project Python environment; ! restores automatic selection',
  })
end
return M
