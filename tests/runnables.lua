vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local callbacks = {}
local attached = true
local cancelled = 0
local client = {
  id = 1,
  name = 'rust_analyzer',
  server_capabilities = {},
  stop = function() end,
  request = function(_, method, params, callback, bufnr)
    assert(method == 'experimental/runnables')
    assert(params.position == nil)
    assert(params.textDocument.uri == vim.uri_from_bufnr(bufnr))
    callbacks[#callbacks + 1] = callback
    return true, #callbacks
  end,
  cancel_request = function()
    cancelled = cancelled + 1
  end,
}
vim.lsp.get_clients = function()
  return attached and { client } or {}
end
vim.lsp.buf_is_attached = function()
  return attached
end
local buf = api.nvim_get_current_buf()
api.nvim_buf_set_name(buf, '/tmp/running-man-main.rs')
api.nvim_buf_set_lines(buf, 0, -1, false, { '// comment', 'fn main() {}', '#[test]', 'fn test() {}' })
vim.bo.filetype = 'rust'
local uri = vim.uri_from_bufnr(buf)
local ns = api.nvim_create_namespace('running_man')
local function marks()
  return api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
end
local function runnable(command, row, target)
  return {
    kind = 'cargo', args = { cargoArgs = { command } },
    location = {
      targetUri = target or uri,
      targetRange = { start = { line = 0, character = 0 } },
      targetSelectionRange = { start = { line = row, character = 3 } },
    },
  }
end
local function reply(result, index, err)
  callbacks[index or #callbacks](err, result)
  vim.wait(20, function() return false end)
end
local plugin = require('running_man')
plugin.setup({ debounce_ms = 1 })
reply({ runnable('run', 1), runnable('run', 1), runnable('test', 3), runnable('check', 0),
  runnable('bench', 3), runnable('run', 1, 'file:///other.rs'), runnable('run', 100),
  { kind = 'cargo', args = { cargoArgs = { 'run' } } } })
assert(#marks() == 1, 'only one current-file binary sign expected')
assert(marks()[1][2] == 1, 'selection range should place the sign on main')
assert(vim.trim(marks()[1][4].sign_text) == '▶')
plugin.refresh()
local old = #callbacks
plugin.refresh()
assert(cancelled > 0, 'superseded requests should be cancelled')
reply({ runnable('run', 1) }, old)
assert(#marks() == 1, 'superseded responses must preserve the existing sign')
reply({ runnable('run', 1) })
assert(#marks() == 1)
plugin.refresh()
api.nvim_buf_set_lines(buf, 0, 1, false, { '// edited' })
reply({ runnable('run', 1) })
assert(#marks() == 1, 'responses for old buffer contents must preserve the existing sign')
api.nvim_exec_autocmds('BufWritePost', { buffer = buf })
assert(#marks() == 1, 'saving must not clear signs while waiting for the server')
vim.wait(20, function() return false end)
reply(nil, nil, { message = 'request cancelled' })
assert(#marks() == 1, 'transient errors must preserve the existing sign')
local background = api.nvim_create_buf(true, false)
api.nvim_exec_autocmds('BufWipeout', { buffer = background })
assert(#marks() == 1, 'unrelated buffer cleanup must not clear the active sign')
plugin.refresh()
reply({})
assert(#marks() == 0, 'a successful empty response removes obsolete signs')
plugin.refresh()
local before_switch = #callbacks
local other = api.nvim_create_buf(true, false)
api.nvim_set_current_buf(other)
reply({ runnable('run', 1) }, before_switch)
assert(#marks() == 0, 'leaving a buffer clears signs and rejects late replies')
api.nvim_set_current_buf(buf)
vim.wait(20, function() return false end)
reply({ runnable('run', 1) })
assert(#marks() == 1, 're-entering a buffer refreshes signs')
attached = false
plugin.refresh()
assert(#marks() == 0, 'missing server clears signs')
attached = true
plugin.refresh()
reply(nil, nil, { message = 'request failed' })
assert(#marks() == 0, 'request errors must not create signs')
plugin.setup()
plugin.setup()
assert(#api.nvim_get_autocmds({ group = 'RunningMan', event = 'BufEnter' }) == 1)
print('Running Man checks passed')
vim.cmd('qa!')
