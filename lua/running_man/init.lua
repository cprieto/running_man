local M = {}
local api = vim.api
local namespace = api.nvim_create_namespace('running_man')
local options = { sign_text = '▶', sign_hl_group = 'RunningManSign', priority = 10, debounce_ms = 200 }
local generation = 0
local active_buffer
local pending

local function invalidate()
  generation = generation + 1
  if pending then
    pending.client:cancel_request(pending.id)
    pending = nil
  end
end

local function clear()
  invalidate()
  if active_buffer and api.nvim_buf_is_valid(active_buffer) then
    api.nvim_buf_clear_namespace(active_buffer, namespace, 0, -1)
  end
  active_buffer = nil
end

local function rust_client(bufnr)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    local experimental = client.server_capabilities.experimental or {}
    if client.name == 'rust_analyzer' or client.name == 'rust-analyzer' or experimental.runnables then
      return client
    end
  end
end

---Refresh runnable signs for the current buffer only.
function M.refresh()
  local bufnr = api.nvim_get_current_buf()
  if active_buffer and active_buffer ~= bufnr then
    clear()
  else
    invalidate()
  end
  if vim.bo[bufnr].filetype ~= 'rust' then
    clear()
    return
  end
  local client = rust_client(bufnr)
  if not client then
    clear()
    return
  end
  active_buffer = bufnr
  local token = generation
  local tick = api.nvim_buf_get_changedtick(bufnr)
  local uri = vim.uri_from_bufnr(bufnr)
  local accepted, id = client:request('experimental/runnables', {
    textDocument = { uri = uri },
  }, function(err, result)
    vim.schedule(function()
      if token ~= generation then
        return
      end
      pending = nil
      if err or not api.nvim_buf_is_valid(bufnr) or api.nvim_get_current_buf() ~= bufnr
        or api.nvim_buf_get_changedtick(bufnr) ~= tick
        or not vim.lsp.buf_is_attached(bufnr, client.id) then
        return
      end
      api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
      local seen = {}
      for _, runnable in ipairs(result or {}) do
        local args = runnable.args or {}
        local location = runnable.location
        -- Cargo run targets are binary entry points; tests/checks have other subcommands.
        if runnable.kind == 'cargo' and args.cargoArgs and args.cargoArgs[1] == 'run'
          and location and location.targetUri == uri then
          local range = location.targetSelectionRange or location.targetRange
          local row = range and range.start and range.start.line
          if type(row) == 'number' and row >= 0 and row < api.nvim_buf_line_count(bufnr) and not seen[row] then
            seen[row] = true
            api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
              sign_text = options.sign_text,
              sign_hl_group = options.sign_hl_group,
              priority = options.priority,
            })
          end
        end
      end
    end)
  end, bufnr)
  if accepted then
    pending = { client = client, id = id }
  end
end

local function queue_refresh()
  invalidate()
  local token = generation
  vim.defer_fn(function()
    if generation == token then
      M.refresh()
    end
  end, options.debounce_ms)
end

---Configure Running Man. Safe to call again.
---@param opts? table
function M.setup(opts)
  options = vim.tbl_extend('force', options, opts or {})
  clear()
  api.nvim_set_hl(0, 'RunningManSign', { default = true, link = 'DiagnosticOk' })
  local group = api.nvim_create_augroup('RunningMan', { clear = true })
  api.nvim_create_autocmd({ 'BufEnter', 'FileType', 'LspAttach', 'BufWritePost', 'TextChanged', 'TextChangedI' }, {
    group = group,
    callback = function(event)
      if event.buf == api.nvim_get_current_buf() then
        queue_refresh()
      end
    end,
  })
  api.nvim_create_autocmd({ 'BufLeave', 'BufWipeout' }, {
    group = group,
    callback = function(event)
      if event.buf == active_buffer then
        clear()
      end
    end,
  })
  api.nvim_create_autocmd('LspDetach', {
    group = group,
    callback = function(event)
      -- Detachment completes after this event; query clients on the next loop.
      if event.buf == api.nvim_get_current_buf() then
        queue_refresh()
      end
    end,
  })
  api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      api.nvim_set_hl(0, 'RunningManSign', { default = true, link = 'DiagnosticOk' })
    end,
  })
  M.refresh()
end

return M
