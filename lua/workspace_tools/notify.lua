local M = {}

function M.send(message, level)
  vim.notify(tostring(message), level or vim.log.levels.ERROR, { title = 'workspace-tools', markdown = true })
end

function M.code(value)
  local size = 1
  for ticks in value:gmatch('`+') do
    size = math.max(size, #ticks + 1)
  end
  local fence = string.rep('`', size)
  return fence .. ' ' .. value .. ' ' .. fence
end

return M
