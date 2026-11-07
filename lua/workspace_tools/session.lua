local M = {}

function M.files()
  local files, seen = {}, {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and vim.bo[buf].buftype == '' then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= '' then
        name = require('workspace_tools.store').normalize(name)
        if not seen[name] then
          files[#files + 1], seen[name] = name, true
        end
      end
    end
  end
  table.sort(files)
  return files
end

function M.check_modified()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].modified then
      error('save or discard modified buffers before restoring: ' .. vim.api.nvim_buf_get_name(buf))
    end
  end
end

local function close_transient()
  local excluded = require('workspace_tools.config').options.close_filetypes_on_save
  -- Match the existing configuration: close disposable UI buffers before saving.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.tbl_contains(excluded, vim.bo[buf].filetype) then
      assert(not vim.bo[buf].modified, 'excluded buffer contains unsaved changes')
      vim.api.nvim_buf_delete(buf, { force = false })
    end
  end
end

function M.capture()
  local store = require('workspace_tools.store')
  local temp = store.temporary('.vim')
  local sessionoptions, current_session = vim.o.sessionoptions, vim.v.this_session
  local ok, result = pcall(function()
    close_transient()
    vim.o.sessionoptions = require('workspace_tools.config').options.sessionoptions
    -- mksession otherwise creates its output with the process umask.
    store.write_file(temp, '')
    vim.cmd('silent mksession! ' .. vim.fn.fnameescape(temp))
    -- readfile() strips mapping <CR> bytes at line endings and translates NULs.
    -- Keep the native script byte-for-byte, including escaped control characters.
    local file = assert(io.open(temp, 'rb'))
    local data, read_err = file:read('*a')
    local closed, close_err = file:close()
    assert(data, read_err)
    assert(closed, close_err)
    return data
  end)
  vim.o.sessionoptions, vim.v.this_session = sessionoptions, current_session
  vim.uv.fs_unlink(temp)
  if not ok then
    error(result)
  end
  return result
end

function M.restore(entry)
  local store = require('workspace_tools.store')
  local temp = store.temporary('.vim')
  local previous, keep = {}, {}
  for _, path in ipairs(entry.files) do
    keep[path] = true
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == '' and vim.api.nvim_buf_get_name(buf) ~= '' then
      previous[#previous + 1] = buf
    end
  end
  local hidden, current_session = vim.o.hidden, vim.v.this_session
  local ok, err = pcall(function()
    store.write_file(temp, entry.session)
    vim.o.hidden = true
    vim.api.nvim_set_current_dir(entry.cwd)
    vim.cmd('source ' .. vim.fn.fnameescape(temp))
  end)
  vim.o.hidden = hidden
  -- The bundle, rather than a permanent executable .vim file, owns the session.
  vim.v.this_session = current_session
  vim.uv.fs_unlink(temp)
  vim.g.SessionLoad = nil -- native sessions can leave this set after a source error
  if not ok then
    error(err)
  end
  -- Native sessions retain old hidden buffers; remove those belonging to the old workspace.
  for _, buf in ipairs(previous) do
    if vim.api.nvim_buf_is_valid(buf) and not vim.bo[buf].modified then
      local path = store.normalize(vim.api.nvim_buf_get_name(buf))
      if not keep[path] and #vim.fn.win_findbuf(buf) == 0 then
        vim.api.nvim_buf_delete(buf, { force = false })
      end
    end
  end
end

return M
