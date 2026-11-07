vim.opt.rtp:prepend(vim.fn.getcwd())
local workspace = require('workspace_tools')
local store = require('workspace_tools.store')
local directory = assert(vim.env.WORKSPACE_TEST_DIR) .. '/session-bytes'
vim.fn.mkdir(directory, 'p')
vim.api.nvim_set_current_dir(directory)
vim.fn.writefile({ 'session control characters' }, directory .. '/file.txt')
vim.cmd.edit(directory .. '/file.txt')
workspace.setup({ directory = directory .. '/store', auto_save = false })

local mappings = {
  { 'x', ' Wx', ':<C-u>echo "visual"<CR>' },
  { 'n', ' Wn', ':echo "中文"<CR>' },
  { 'n', '|', ':echo "bar"<CR>' },
  { 'n', '<F10>', ':echo "newline"<NL>' },
  { 'n', '<F11>', ':echo "quote"<C-v><CR>' },
}
for _, mapping in ipairs(mappings) do
  vim.keymap.set(mapping[1], mapping[2], mapping[3], { buffer = true, silent = true })
  mapping.rhs = vim.fn.maparg(mapping[2], mapping[1])
end

-- Compare against mksession's exact bytes, before any workspace serialization.
local options, current_session = vim.o.sessionoptions, vim.v.this_session
vim.o.sessionoptions = require('workspace_tools.config').options.sessionoptions
vim.cmd('mksession! ' .. vim.fn.fnameescape(directory .. '/native.vim'))
vim.o.sessionoptions, vim.v.this_session = options, current_session
local file = assert(io.open(directory .. '/native.vim', 'rb'))
local native = assert(file:read('*a'))
assert(file:close())
assert(native:find('\022\r\n', 1, true), 'fixture must contain escaped CR at a mapping line ending')
local saved, err = workspace.save()
assert(saved, err)
assert(store.read(saved.id).session == native, 'capture changed native session bytes')
assert(vim.o.sessionoptions == options and vim.v.this_session == current_session)

-- A successful source must preserve each mapping's meaning, not just avoid errors.
for _, mapping in ipairs(mappings) do
  vim.keymap.del(mapping[1], mapping[2], { buffer = true })
end
local restored, restore_err = workspace.restore(saved)
assert(restored, restore_err)
for _, mapping in ipairs(mappings) do
  assert(vim.fn.maparg(mapping[2], mapping[1]) == mapping.rhs, 'mapping changed: ' .. mapping[2])
end
assert(vim.o.sessionoptions == options and vim.v.this_session == current_session)
assert(#vim.fn.glob(store.directory() .. '/.tmp-*', false, true) == 0)
print('PASS byte-exact session capture and restored CR/LF, quoting, bar and UTF-8 mappings')
vim.cmd('qa!')
