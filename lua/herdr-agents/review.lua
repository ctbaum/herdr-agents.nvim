local M = {}

M.ns = vim.api.nvim_create_namespace("herdr-agents-review")

local comments = {}
local next_id = 1
local config = {
  clear_after_submit = true,
  snippet_lines = 5,
}
local transport

vim.api.nvim_set_hl(0, "HerdrAgentsReviewComment", { default = true, link = "DiagnosticWarn" })

local function resolve(id)
  local item = comments[id]
  if not item or not vim.api.nvim_buf_is_valid(item.bufnr) then
    return nil
  end
  local mark = vim.api.nvim_buf_get_extmark_by_id(item.bufnr, M.ns, item.extmark, { details = true })
  if not mark or #mark == 0 then
    return nil
  end
  local first = mark[1] + 1
  local last = mark[3] and mark[3].end_row or first
  return {
    id = id,
    bufnr = item.bufnr,
    extmark = item.extmark,
    file = vim.api.nvim_buf_get_name(item.bufnr),
    first = first,
    last = math.max(first, last),
    text = item.text,
  }
end

local function mark_options(text, last)
  local display = text:gsub("\n", " ")
  return {
    end_row = last,
    end_col = 0,
    right_gravity = false,
    end_right_gravity = true,
    virt_lines = { { { "╰─ review: " .. display, "HerdrAgentsReviewComment" } } },
    virt_lines_above = false,
  }
end

function M.add(bufnr, first, last, text)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  assert(type(text) == "string" and text ~= "", "review comment text is required")
  assert(first >= 1 and last >= first, "review range must use ordered 1-based lines")
  local id = next_id
  next_id = next_id + 1
  local extmark = vim.api.nvim_buf_set_extmark(bufnr, M.ns, first - 1, 0, mark_options(text, last))
  comments[id] = { bufnr = bufnr, extmark = extmark, text = text }
  return id
end

function M.get(id)
  return resolve(id)
end

function M.list()
  local result = {}
  for id in pairs(comments) do
    local item = resolve(id)
    if item then
      result[#result + 1] = item
    end
  end
  table.sort(result, function(left, right)
    if left.file ~= right.file then
      return left.file < right.file
    end
    return left.first < right.first
  end)
  return result
end

function M.edit(id, text)
  local item = resolve(id)
  if not item or type(text) ~= "string" or text == "" then
    return false
  end
  comments[id].text = text
  vim.api.nvim_buf_set_extmark(item.bufnr, M.ns, item.first - 1, 0, vim.tbl_extend("force", {
    id = item.extmark,
  }, mark_options(text, item.last)))
  return true
end

function M.delete(id)
  local item = comments[id]
  if not item then
    return false
  end
  if vim.api.nvim_buf_is_valid(item.bufnr) then
    vim.api.nvim_buf_del_extmark(item.bufnr, M.ns, item.extmark)
  end
  comments[id] = nil
  return true
end

function M.clear()
  local ids = vim.tbl_keys(comments)
  for _, id in ipairs(ids) do
    M.delete(id)
  end
end

function M.prompt()
  local queued = M.list()
  if #queued == 0 then
    return nil
  end
  local lines = { "Queued code review comments from Neovim:", "" }
  for index, item in ipairs(queued) do
    local file = vim.fn.fnamemodify(item.file, ":~:.")
    lines[#lines + 1] = ("%d. %s:%d-%d"):format(index, file, item.first, item.last)
    local snippet = vim.api.nvim_buf_get_lines(item.bufnr, item.first - 1, item.last, false)
    for line = 1, math.min(config.snippet_lines, #snippet) do
      lines[#lines + 1] = "   > " .. snippet[line]
    end
    lines[#lines + 1] = "   Comment: " .. item.text
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = "Please address each comment and summarize what changed for every item."
  return table.concat(lines, "\n")
end

local function choose_agent(requested, callback)
  if requested and requested ~= "" then
    if vim.tbl_contains(transport.agents(), requested) then
      callback(requested)
    else
      vim.notify("Unknown or disabled agent integration: " .. requested, vim.log.levels.WARN)
    end
    return
  end
  local agents = transport.agents()
  if #agents == 0 then
    vim.notify("No enabled Herdr agent integrations", vim.log.levels.WARN)
  elseif #agents == 1 then
    callback(agents[1])
  else
    vim.ui.select(agents, { prompt = "Send review comments to agent" }, function(agent)
      if agent then
        callback(agent)
      end
    end)
  end
end

local function dispatch(method, agent)
  local payload = M.prompt()
  if not payload then
    vim.notify("No queued review comments", vim.log.levels.INFO)
    return
  end
  choose_agent(agent, function(selected)
    local dispatched = transport[method](selected, payload)
    if not dispatched then
      vim.notify("No connected " .. selected .. " pane found", vim.log.levels.WARN)
    elseif method == "submit" and config.clear_after_submit then
      M.clear()
    end
  end)
end

function M.paste(agent)
  dispatch("paste", agent)
end

function M.submit(agent)
  dispatch("submit", agent)
end

function M.statusline()
  local count = #M.list()
  return count == 0 and "" or ("● " .. count)
end

local function add_interactive(first, last)
  vim.ui.input({ prompt = "Review comment: " }, function(text)
    if text and text ~= "" then
      M.add(0, first, last, text)
    end
  end)
end

local function list_interactive()
  local queued = M.list()
  if #queued == 0 then
    vim.notify("No queued review comments", vim.log.levels.INFO)
    return
  end
  vim.ui.select(queued, {
    prompt = "Queued review comments",
    format_item = function(item)
      return ("%s:%d-%d  %s"):format(vim.fn.fnamemodify(item.file, ":t"), item.first, item.last, item.text)
    end,
  }, function(item)
    if not item then
      return
    end
    vim.api.nvim_set_current_buf(item.bufnr)
    vim.api.nvim_win_set_cursor(0, { item.first, 0 })
    vim.cmd("normal! zz")
  end)
end

function M.setup(opts, callbacks)
  config = vim.tbl_deep_extend("force", config, opts or {})
  transport = callbacks

  vim.api.nvim_create_user_command("HerdrReviewComment", function(command)
    local first = command.range > 0 and command.line1 or vim.api.nvim_win_get_cursor(0)[1]
    local last = command.range > 0 and command.line2 or first
    add_interactive(first, last)
  end, { range = true })
  vim.api.nvim_create_user_command("HerdrReviewList", list_interactive, {})
  vim.api.nvim_create_user_command("HerdrReviewPaste", function(command)
    M.paste(command.args)
  end, { nargs = "?", complete = function() return transport.agents() end })
  vim.api.nvim_create_user_command("HerdrReviewSubmit", function(command)
    M.submit(command.args)
  end, { nargs = "?", complete = function() return transport.agents() end })
  vim.api.nvim_create_user_command("HerdrReviewClear", M.clear, {})
end

return M
