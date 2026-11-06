local M = {}

M.defaults = {
  directory = vim.fn.stdpath('state') .. '/workspace-tools',
  auto_save = true,
  auto_restore = false,
  suppressed_dirs = { '~/', '~/Projects', '~/Downloads', '/' },
  close_filetypes_on_save = { 'checkhealth', 'tasktools', 'tasktoolsoutput' },
  sessionoptions = 'buffers,curdir,folds,tabpages,winsize,winpos,localoptions',
  picker = 'auto', -- auto, builtin, selection, or a vim.ui.select-compatible function
  hooks = { pre_save = {}, post_save = {}, pre_restore = {}, post_restore = {}, post_delete = {} },
}
M.options = vim.deepcopy(M.defaults)

-- Resolve and validate without publishing a partially invalid configuration.
function M.resolve(opts)
  assert(opts == nil or type(opts) == 'table', 'workspace-tools: setup expects a table')
  local options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), vim.deepcopy(opts or {}))
  assert(type(options.directory) == 'string' and options.directory ~= '', 'directory must be a path')
  assert(type(options.auto_save) == 'boolean', 'auto_save must be boolean')
  assert(type(options.auto_restore) == 'boolean', 'auto_restore must be boolean')
  assert(type(options.sessionoptions) == 'string', 'sessionoptions must be a string')
  assert(
    type(options.picker) == 'function' or vim.tbl_contains({ 'auto', 'builtin', 'selection' }, options.picker),
    'invalid picker'
  )
  for _, key in ipairs({ 'suppressed_dirs', 'close_filetypes_on_save' }) do
    assert(type(options[key]) == 'table' and vim.islist(options[key]), key .. ' must be a list')
    for _, value in ipairs(options[key]) do
      assert(type(value) == 'string', key .. ' entries must be strings')
    end
  end
  assert(type(options.hooks) == 'table', 'hooks must be a table')
  for name in pairs(M.defaults.hooks) do
    local callbacks = options.hooks[name]
    assert(type(callbacks) == 'table' and vim.islist(callbacks), 'hooks.' .. name .. ' must be a list')
    for _, callback in ipairs(callbacks) do
      assert(type(callback) == 'function', 'workspace hooks must be functions')
    end
  end
  return options
end

function M.setup(opts)
  local options = M.resolve(opts)
  M.options = options
  return options
end

return M
