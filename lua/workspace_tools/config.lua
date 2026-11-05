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

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  -- Empty lists replace defaults rather than retaining their trailing entries.
  for _, key in ipairs({ 'suppressed_dirs', 'close_filetypes_on_save' }) do
    if opts and opts[key] then
      M.options[key] = vim.deepcopy(opts[key])
    end
  end
  assert(type(M.options.directory) == 'string' and M.options.directory ~= '', 'directory must be a path')
  assert(
    type(M.options.picker) == 'function' or vim.tbl_contains({ 'auto', 'builtin', 'selection' }, M.options.picker),
    'invalid picker'
  )
  return M.options
end

return M
