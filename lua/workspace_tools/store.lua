local M = {}

function M.normalize(path)
  if path == '~' or path:sub(1, 2) == '~/' then
    path = vim.fn.expand('~') .. path:sub(2)
  end
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ':p'), { expand_env = false })
  path = vim.uv.fs_realpath(path) or path
  return path == '/' and path or path:gsub('/+$', '')
end

function M.directory()
  return M.normalize(require('workspace_tools.config').options.directory)
end

function M.id(cwd, name)
  return vim.fn.sha256(cwd .. '\n' .. name)
end

function M.path(id)
  assert(type(id) == 'string' and id:match('^[a-f0-9]+$') and #id == 64, 'invalid workspace id')
  return M.directory() .. '/' .. id .. '.json'
end

function M.prepare()
  assert(vim.fn.mkdir(M.directory(), 'p', 448) == 1 or vim.fn.isdirectory(M.directory()) == 1, 'cannot create store')
end

function M.temporary(suffix)
  M.prepare()
  return M.directory() .. '/.tmp-' .. vim.fn.getpid() .. '-' .. tostring(vim.uv.hrtime()) .. suffix
end

-- Exclusive, private temporary files; rename commits a complete bundle in one step.
function M.write_file(path, data)
  local fd, err = vim.uv.fs_open(path, 'wx', 384)
  assert(fd, err)
  local ok, failure = pcall(function()
    local offset = 0
    while offset < #data do
      local count, write_err = vim.uv.fs_write(fd, data:sub(offset + 1), offset)
      assert(count and count > 0, write_err or 'short write')
      offset = offset + count
    end
    assert(vim.uv.fs_fsync(fd))
  end)
  local closed, close_err = vim.uv.fs_close(fd)
  if not ok or not closed then
    vim.uv.fs_unlink(path)
    error(failure or close_err)
  end
end

function M.write(entry)
  local temp = M.temporary('.json')
  local ok, err = pcall(function()
    local bundle = vim.deepcopy(entry)
    -- mksession's bytewise quoting of UTF-8 option values is not itself valid UTF-8.
    bundle.session = vim.base64.encode(entry.session)
    bundle.session_encoding = 'base64'
    M.write_file(temp, vim.json.encode(bundle))
    assert(vim.uv.fs_rename(temp, M.path(entry.id)))
  end)
  if not ok then
    vim.uv.fs_unlink(temp)
    error(err)
  end
end

function M.read(id)
  local path = M.path(id)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  local entry = vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
  assert(
    type(entry) == 'table'
      and entry.version == 1
      and entry.id == id
      and type(entry.cwd) == 'string'
      and type(entry.name) == 'string'
      and M.id(entry.cwd, entry.name) == id
      and type(entry.session) == 'string'
      and entry.session_encoding == 'base64'
      and type(entry.files) == 'table'
      and type(entry.updated_at) == 'number'
      and type(entry.created_at) == 'number'
      and type(entry.accessed_at) == 'number',
    'invalid workspace bundle: ' .. path
  )
  for _, path_ in ipairs(entry.files) do
    assert(type(path_) == 'string', 'invalid workspace file list')
  end
  entry.session = vim.base64.decode(entry.session)
  entry.session_encoding = nil
  return entry
end

function M.metadata(entry)
  local result = vim.deepcopy(entry)
  result.session = nil
  result.missing = vim.fn.isdirectory(entry.cwd) == 0
  result.search = (entry.name == '' and '' or entry.name .. ' ') .. entry.cwd
  return result
end

function M.list()
  local items, errors = {}, {}
  if vim.fn.isdirectory(M.directory()) == 0 then
    return items, errors
  end
  for name, kind in vim.fs.dir(M.directory()) do
    local id = name:match('^([a-f0-9]+)%.json$')
    if kind == 'file' and id and #id == 64 then
      local ok, entry = pcall(M.read, id)
      if ok and entry then
        items[#items + 1] = M.metadata(entry)
      elseif not ok then
        errors[#errors + 1] = tostring(entry)
      end
    end
  end
  table.sort(items, function(a, b)
    local at, bt = math.max(a.accessed_at, a.updated_at), math.max(b.accessed_at, b.updated_at)
    if at == bt then
      return a.id < b.id
    end
    return at > bt
  end)
  return items, errors
end

return M
