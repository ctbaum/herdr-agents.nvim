local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local review = require("herdr-agents.review")
local buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buffer, "/tmp/herdr-review.lua")
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "zero", "one", "two", "three" })
vim.api.nvim_set_current_buf(buffer)

local calls = {}
review.setup({ clear_after_submit = true, snippet_lines = 2 }, {
  agents = function() return { "claude", "codex" } end,
  paste = function(agent, payload)
    calls[#calls + 1] = { method = "paste", agent = agent, payload = payload }
    return true
  end,
  submit = function(agent, payload)
    calls[#calls + 1] = { method = "submit", agent = agent, payload = payload }
    return true
  end,
})

local first = review.add(buffer, 2, 3, "Handle this range")
local current = review.add(0, 1, 1, "Track the current buffer")
assert(review.get(current).bufnr == buffer)
assert(review.edit(current, "Updated comment"))
assert(review.get(current).text == "Updated comment")
review.delete(current)
vim.api.nvim_buf_set_lines(buffer, 0, 0, false, { "inserted" })
local tracked = assert(review.get(first))
assert(tracked.first == 3 and tracked.last == 4, vim.inspect(tracked))

local prompt = assert(review.prompt())
assert(prompt:find("herdr%-review.lua:3%-4"), prompt)
assert(prompt:find("> one", 1, true), prompt)
assert(prompt:find("> two", 1, true), prompt)
assert(not prompt:find("> three", 1, true), prompt)

assert(review.paste("claude") == nil)
assert(#review.list() == 1, "paste should retain queued comments")
assert(calls[1].method == "paste" and calls[1].agent == "claude")

assert(review.submit("codex") == nil)
assert(#review.list() == 0, "successful submit should clear queued comments")
assert(calls[2].method == "submit" and calls[2].agent == "codex")

local select_callback
local original_select = vim.ui.select
vim.ui.select = function(_, _, callback) select_callback = callback end
review.add(buffer, 1, 1, "Choose asynchronously")
assert(review.submit() == nil)
assert(#calls == 2, "dispatch ran before the asynchronous agent choice")
assert(select_callback, "agent picker callback was not registered")
review.add(buffer, 2, 2, "Added while picker was open")
select_callback("claude")
assert(#calls == 3 and calls[3].method == "submit" and calls[3].agent == "claude")
assert(calls[3].payload:find("Added while picker was open", 1, true))
assert(#review.list() == 0)

local modified = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(modified)
vim.api.nvim_buf_set_lines(modified, 0, -1, false, { "unsaved" })
local listed = review.add(buffer, 1, 1, "Navigate without abandoning edits")
vim.ui.select = function(_, _, callback) callback(review.get(listed)) end
vim.cmd("HerdrReviewList")
assert(vim.api.nvim_get_current_buf() == buffer)
assert(vim.api.nvim_buf_is_valid(modified) and vim.bo[modified].modified)
vim.ui.select = original_select

assert(vim.fn.exists(":HerdrReviewComment") == 2)
assert(vim.fn.exists(":HerdrReviewPaste") == 2)
assert(vim.fn.exists(":HerdrReviewSubmit") == 2)

print("herdr-agents review test passed")
