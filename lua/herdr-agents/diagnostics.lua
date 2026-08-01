local M = {}

local severity_names = {
  [vim.diagnostic.severity.ERROR] = "ERROR",
  [vim.diagnostic.severity.WARN] = "WARN",
  [vim.diagnostic.severity.INFO] = "INFO",
  [vim.diagnostic.severity.HINT] = "HINT",
}

function M.payload(bufnr)
  bufnr = bufnr or 0
  local diagnostics = vim.diagnostic.get(bufnr)
  if #diagnostics == 0 then
    return nil
  end

  local file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":~:.")
  local lines = { "LSP diagnostics for " .. file .. ":" }
  for _, item in ipairs(diagnostics) do
    lines[#lines + 1] = ("  [%s] %d:%d  %s%s"):format(
      severity_names[item.severity] or "?",
      item.lnum + 1,
      item.col + 1,
      item.message:gsub("\n", " "),
      item.source and (" (" .. item.source .. ")") or ""
    )
  end
  return table.concat(lines, "\n")
end

function M.register(command, provider, agent)
  vim.api.nvim_create_user_command(command, function()
    local payload = M.payload(0)
    if not payload then
      vim.notify("No diagnostics in current buffer", vim.log.levels.INFO)
      return
    end
    if not provider.paste("\27[200~" .. payload .. "\27[201~") then
      vim.notify("No " .. agent .. " pane found", vim.log.levels.WARN)
    end
  end, {})
end

return M
