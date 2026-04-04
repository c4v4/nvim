-- ============================================================================
-- BASIC SETTINGS
-- ============================================================================
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Disable netrw (conflicts with fugitive)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Make $EDITOR open files in this Neovim instance (e.g. Claude Code's "open in editor" shortcut).
-- scripts/nvim-editor uses --remote-expr to call _nvim_editor_open, which opens the file in a
-- centered floating window. q/<Esc> saves and closes the float; the script unblocks via sentinel.
local _editor_script = vim.fn.stdpath("config") .. "/scripts/nvim-editor"
if vim.fn.executable(_editor_script) == 1 then
	vim.env.EDITOR = _editor_script
	vim.env.VISUAL = _editor_script
end

-- Called by scripts/nvim-editor. Opens the file in a centered floating window so the
-- existing layout is untouched. q/<Esc> writes the buffer to disk and signals the sentinel,
-- unblocking the shell script so Claude Code reads the result.
_G._nvim_editor_open = function(file, sentinel)
	local abs_file = vim.fn.fnamemodify(file, ":p")

	-- Load the buffer without touching any existing window.
	-- buftype=nofile: excludes it from auto-save (prevents premature file writes
	-- that could confuse Claude Code's file watcher before the user is done).
	local bufnr = vim.fn.bufadd(abs_file)
	vim.fn.bufload(bufnr)
	vim.bo[bufnr].buftype = "nofile"

	-- Float dimensions: 80% wide, 70% tall, centered
	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.7)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local win = vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " Claude Prompt -- q/<Esc> to send ",
		title_pos = "center",
	})

	-- Disable nvim-cmp in this buffer (completions are irrelevant here and
	-- confirming one was triggering Claude Code's file-watcher prematurely)
	local cmp_ok, cmp = pcall(require, "cmp")
	if cmp_ok then
		cmp.setup.buffer({ enabled = false })
	end

	-- Define sentinel helpers before any autocmd references them
	local sentinel_written = false
	local function write_sentinel()
		if not sentinel_written then
			sentinel_written = true
			vim.fn.writefile({}, sentinel)
		end
	end

	-- Fallback: if buffer is deleted externally (e.g. :bwipeout from cmdline), write sentinel
	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		buffer = bufnr,
		once = true,
		callback = write_sentinel,
	})

	local function close()
		-- Write buffer content directly to disk -- bypass :write and modified-flag checks
		if vim.api.nvim_buf_is_valid(bufnr) then
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			vim.fn.writefile(lines, abs_file)
		end
		write_sentinel()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		if vim.api.nvim_buf_is_valid(bufnr) then
			pcall(vim.cmd, "bdelete! " .. bufnr)
		end
	end

	vim.keymap.set("n", "q", close, { buffer = bufnr, desc = "Send to Claude" })
	vim.keymap.set("n", "<Esc>", close, { buffer = bufnr, desc = "Send to Claude" })
end

-- UI
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.termguicolors = true
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8

-- Splits
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true

-- Indentation
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Editing
vim.opt.wrap = true
vim.opt.undofile = true
vim.opt.swapfile = false
vim.opt.backup = false

-- Performance
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300

-- Enhanced ShaDa for persistent history
vim.opt.shada = { "!", "'1000", "<50", "s10", "h" }
vim.opt.clipboard = "unnamedplus"

-- Spell checking
vim.opt.spell = true
vim.opt.spelllang = { "en_us" }

-- ============================================================================
-- CONTEXT RESOLVER (Core of Buffer-Centric Philosophy)
-- ============================================================================

-- Returns context for current buffer, falling back to last real buffer if in special buffer
-- (terminal, quickfix, etc). Returns git root if available, otherwise buffer directory.
local function get_buffer_context()
	local bufnr = vim.api.nvim_get_current_buf()

	-- Fallback to last real buffer if in special buffer
	if vim.bo[bufnr].buftype ~= "" then
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" then
				bufnr = buf
				break
			end
		end
	end

	local bufpath = vim.api.nvim_buf_get_name(bufnr)
	local dir = bufpath ~= "" and vim.fn.fnamemodify(bufpath, ":h") or vim.fn.getcwd()

	-- Find git root from buffer directory
	local git_root =
		vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null")[1]

	return {
		path = bufpath ~= "" and bufpath or vim.fn.getcwd(),
		dir = dir,
		git_root = (git_root and git_root ~= "") and git_root or nil,
		is_real_file = bufpath ~= "",
	}
end

-- Returns git root if in repo, otherwise buffer/cwd directory
local function get_smart_cwd()
	local ctx = get_buffer_context()
	return ctx.git_root or ctx.dir
end

-- ============================================================================
-- KEY MAPPINGS
-- ============================================================================

-- Better window navigation
vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })

-- Terminal mode mappings
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
vim.keymap.set("t", "<C-h>", "<C-\\><C-n><C-w>h", { desc = "Go to left window from terminal" })
vim.keymap.set("t", "<C-j>", "<C-\\><C-n><C-w>j", { desc = "Go to lower window from terminal" })
vim.keymap.set("t", "<C-k>", "<C-\\><C-n><C-w>k", { desc = "Go to upper window from terminal" })
vim.keymap.set("t", "<C-l>", "<C-\\><C-n><C-w>l", { desc = "Go to right window from terminal" })

-- Resize windows
vim.keymap.set("n", "<C-Up>", ":resize -2<CR>", { desc = "Decrease window height" })
vim.keymap.set("n", "<C-Down>", ":resize +2<CR>", { desc = "Increase window height" })
vim.keymap.set("n", "<C-Left>", ":vertical resize -2<CR>", { desc = "Decrease window width" })
vim.keymap.set("n", "<C-Right>", ":vertical resize +2<CR>", { desc = "Increase window width" })

-- Better indenting
vim.keymap.set("v", "<", "<gv")
vim.keymap.set("v", ">", ">gv")

-- Keep cursor centered
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- Paste without yanking
vim.keymap.set({ "n", "x" }, "<leader>p", '"_dP', { desc = "Paste without yanking" })

-- Delete without yanking
vim.keymap.set({ "n", "x" }, "<leader>d", '"_d', { desc = "Delete without yanking" })

-- Clear search highlight
vim.keymap.set("n", "<Esc>", ":nohlsearch<CR>", { desc = "Clear search highlight" })

-- Buffers
vim.keymap.set("n", "<S-l>", ":bnext<CR>", { desc = "Next buffer" })
vim.keymap.set("n", "<S-h>", ":bprevious<CR>", { desc = "Previous buffer" })
vim.keymap.set("n", "<leader>x", ":bdelete!<CR>", { desc = "Close buffer" })

-- ============================================================================
-- AUTOCMDS
-- ============================================================================

-- Create parent directories on save
vim.api.nvim_create_autocmd("BufWritePre", {
	callback = function(event)
		local dir = vim.fn.fnamemodify(event.match, ":h")
		if vim.fn.isdirectory(dir) == 0 then
			vim.fn.mkdir(dir, "p")
		end
	end,
})

-- Restore cursor position on file open
vim.api.nvim_create_autocmd("BufReadPost", {
	callback = function()
		local mark = vim.api.nvim_buf_get_mark(0, '"')
		local line_count = vim.api.nvim_buf_line_count(0)
		if mark[1] > 0 and mark[1] <= line_count then
			vim.api.nvim_win_set_cursor(0, mark)
		end
	end,
})

-- Quickfix: <CR> to jump+close, q/<Esc> to close
vim.api.nvim_create_autocmd("FileType", {
	pattern = "qf",
	callback = function(event)
		local opts = { buffer = event.buf, silent = true }
		vim.keymap.set("n", "<CR>", "<CR>:cclose<CR>", opts)
		vim.keymap.set("n", "q", ":cclose<CR>", opts)
		vim.keymap.set("n", "<Esc>", ":cclose<CR>", opts)
	end,
})

-- Terminal: gf opens file in editor window (not terminal)
vim.api.nvim_create_autocmd("TermOpen", {
	callback = function(event)
		-- Disable spellcheck in terminal
		vim.opt_local.spell = false

		vim.keymap.set("n", "gf", function()
			local file = vim.fn.expand("<cfile>")
			if file == "" then
				vim.notify("No file under cursor", vim.log.levels.WARN)
				return
			end

			-- Find first non-terminal window
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				local buf = vim.api.nvim_win_get_buf(win)
				if vim.bo[buf].buftype ~= "terminal" then
					vim.api.nvim_set_current_win(win)
					vim.cmd.edit(vim.fn.fnameescape(file))
					return
				end
			end

			-- No editor window found, create split
			vim.cmd("aboveleft split " .. vim.fn.fnameescape(file))
		end, { buffer = event.buf })
	end,
})

-- Diagnostic configuration
vim.diagnostic.config({
	virtual_text = false,
	signs = true,
	underline = true,
	update_in_insert = false,
	severity_sort = true,
	float = {
		border = "rounded",
		source = "if_many",
		focusable = true,
		wrap = true,
		max_width = math.floor(vim.o.columns * 0.8),
		max_height = math.floor(vim.o.lines * 0.6),
	},
})

-- Show diagnostics on hover (since virtual_text is off)
vim.api.nvim_create_autocmd("CursorHold", {
	callback = function()
		vim.diagnostic.open_float(nil, { focus = false, scope = "cursor" })
	end,
})

-- ============================================================================
-- CLAUDE CODE DIFF VIEW WINBAR
-- ============================================================================

-- Helper to safely read winbar (option may not exist on older nvim)
local function get_winbar(win)
	local ok, val = pcall(vim.api.nvim_get_option_value, "winbar", { win = win })
	return ok and val or nil
end

-- Shows [ORIGINAL]/[PROPOSED] + file path in winbar of both diff windows.
-- Fires on window/option events; clears when diff is no longer active.
local function update_claudecode_diff_winbars()
	-- First pass: find proposed windows (identified by buffer variable set by claudecode.nvim)
	local proposed_wins = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_is_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			local tab_name = vim.b[buf].claudecode_diff_tab_name
			if tab_name then
				table.insert(proposed_wins, { win = win, tab_name = tab_name })
			end
		end
	end

	-- No claudecode diff in this tab: clear any winbars we previously set
	if #proposed_wins == 0 then
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if vim.api.nvim_win_is_valid(win) then
				local wb = get_winbar(win)
				if wb and (wb:match("^%[ PROPOSED %]") or wb:match("^%[ ORIGINAL %]")) then
					pcall(vim.api.nvim_set_option_value, "winbar", "", { win = win })
				end
			end
		end
		return
	end

	-- Set winbar on proposed windows
	for _, info in ipairs(proposed_wins) do
		local rel = vim.fn.fnamemodify(info.tab_name, ":~:.")
		pcall(vim.api.nvim_set_option_value, "winbar", "[ PROPOSED ]  " .. rel, { win = info.win })
	end

	-- Set winbar on original windows (diff mode on, no claudecode marker)
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if not vim.api.nvim_win_is_valid(win) then
			goto continue
		end
		local buf = vim.api.nvim_win_get_buf(win)
		if not vim.b[buf].claudecode_diff_tab_name and vim.wo[win].diff then
			local path = vim.api.nvim_buf_get_name(buf)
			local rel = path ~= "" and vim.fn.fnamemodify(path, ":~:.") or "[No Name]"
			pcall(vim.api.nvim_set_option_value, "winbar", "[ ORIGINAL ]  " .. rel, { win = win })
		end
		::continue::
	end
end

vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
	desc = "Update winbar for Claude Code diff view",
	callback = function()
		vim.schedule(update_claudecode_diff_winbars)
	end,
})

vim.api.nvim_create_autocmd("OptionSet", {
	pattern = "diff",
	desc = "Update winbar when diff mode changes",
	callback = function()
		vim.schedule(update_claudecode_diff_winbars)
	end,
})

-- ============================================================================
-- FILE GIT HISTORY NAVIGATOR IN SPLIT VIEW
-- ============================================================================
local git_history_state = {
	commits = {},
	index = 0,
	original_win = nil,
	diff_buf = nil,
	diff_win = nil,
	info_buf = nil,
	info_win = nil,
}
local git_history_ns = vim.api.nvim_create_namespace("git_history_info")

local function load_file_history()
	local file = vim.fn.expand("%:p")
	local output = vim.fn.systemlist("git log --format=%H -- " .. vim.fn.shellescape(file))
	return output
end

local function update_info_win(commit_hash)
	if not git_history_state.info_buf
	   or not vim.api.nvim_buf_is_valid(git_history_state.info_buf) then
		return
	end

	local raw = vim.fn.system(
		'git show --no-patch --format="%h%x01%s%x01%an%x01%ar%x01%b" ' .. commit_hash
	)
	local parts = vim.split(raw, "\1", { plain = true })
	local hash    = vim.trim(parts[1] or "")
	local subject = vim.trim(parts[2] or "")
	local author  = vim.trim(parts[3] or "")
	local date    = vim.trim(parts[4] or "")
	local body    = parts[5] or ""

	local idx   = git_history_state.index
	local total = #git_history_state.commits

	local lines = {
		string.format(
			"  Git History [ %d / %d ]     [g older   ]g newer   <leader>gq close",
			idx, total
		),
		string.format("  %s  %s  --  %s", hash, author, date),
		string.format("  %s", subject),
	}
	for _, bl in ipairs(vim.split(body, "\n", { plain = true })) do
		table.insert(lines, "  " .. bl)
	end

	local buf = git_history_state.info_buf
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	-- Apply highlights
	vim.api.nvim_buf_clear_namespace(buf, git_history_ns, 0, -1)

	-- Line 0: "  Git History [ N / M ]     [g older   ]g newer   <leader>gq close"
	local l0 = lines[1]
	local ht_s, ht_e = l0:find("Git History")
	if ht_s then
		vim.api.nvim_buf_add_highlight(buf, git_history_ns, "Title", 0, ht_s - 1, ht_e)
	end
	local cnt_s, cnt_e = l0:find("%[%s*%d[^%]]*%]")
	if cnt_s then
		vim.api.nvim_buf_add_highlight(buf, git_history_ns, "Number", 0, cnt_s - 1, cnt_e)
	end
	for _, pat in ipairs({ "%[g older", "%]g newer", "<leader>gq close" }) do
		local ps, pe = l0:find(pat)
		if ps then
			vim.api.nvim_buf_add_highlight(buf, git_history_ns, "Keyword", 0, ps - 1, pe)
		end
	end

	-- Line 1: "  hash  author  --  date"
	if #hash > 0 then
		vim.api.nvim_buf_add_highlight(buf, git_history_ns, "Constant", 1, 2, 2 + #hash)
	end
	local author_start = 2 + #hash + 2
	if #author > 0 then
		vim.api.nvim_buf_add_highlight(buf, git_history_ns, "Identifier", 1, author_start, author_start + #author)
	end
	local sep_s = lines[2]:find("  %-%-  ")
	if sep_s then
		vim.api.nvim_buf_add_highlight(buf, git_history_ns, "Comment", 1, sep_s - 1, -1)
	end

	-- Line 2: subject
	if #subject > 0 then
		vim.api.nvim_buf_add_highlight(buf, git_history_ns, "String", 2, 2, -1)
	end
end

local function show_commit_diff(commit_hash)
	local file = vim.fn.expand("%:p")
	local content = vim.fn.systemlist(
		"git show " .. commit_hash .. ":" .. vim.fn.shellescape(file:gsub(vim.fn.getcwd() .. "/", ""))
	)

	-- Capture filetype and cursor from original window before any window switching
	local orig_filetype = vim.bo[vim.api.nvim_win_get_buf(git_history_state.original_win)].filetype
	local cursor_pos = vim.api.nvim_win_get_cursor(git_history_state.original_win)

	-- Create or reuse windows
	if not git_history_state.diff_buf
	   or not vim.api.nvim_buf_is_valid(git_history_state.diff_buf)
	   or not git_history_state.info_buf
	   or not vim.api.nvim_buf_is_valid(git_history_state.info_buf) then

		-- Create info window at top of tabpage (full width)
		vim.api.nvim_set_current_win(git_history_state.original_win)
		vim.cmd("topleft split")
		git_history_state.info_win = vim.api.nvim_get_current_win()
		git_history_state.info_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_win_set_buf(git_history_state.info_win, git_history_state.info_buf)
		vim.api.nvim_win_set_height(git_history_state.info_win, 4)
		vim.wo[git_history_state.info_win].winfixheight = true
		vim.wo[git_history_state.info_win].number = false
		vim.wo[git_history_state.info_win].relativenumber = false
		vim.wo[git_history_state.info_win].signcolumn = "no"
		vim.wo[git_history_state.info_win].statusline = " "
		vim.wo[git_history_state.info_win].wrap = false
		vim.wo[git_history_state.info_win].foldenable = false
		vim.bo[git_history_state.info_buf].buftype = "nofile"
		vim.bo[git_history_state.info_buf].modifiable = false

		-- Create diff window (vsplit from original)
		vim.api.nvim_set_current_win(git_history_state.original_win)
		vim.cmd("vsplit")
		git_history_state.diff_win = vim.api.nvim_get_current_win()
		git_history_state.diff_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_win_set_buf(git_history_state.diff_win, git_history_state.diff_buf)
	end

	-- Load commit content
	vim.api.nvim_buf_set_lines(git_history_state.diff_buf, 0, -1, false, content)
	vim.bo[git_history_state.diff_buf].filetype = orig_filetype
	vim.bo[git_history_state.diff_buf].buftype = "nofile"

	-- Disable folding in diff buffer
	vim.api.nvim_set_current_win(git_history_state.diff_win)
	vim.wo[git_history_state.diff_win].foldenable = false
	vim.wo[git_history_state.diff_win].foldmethod = "manual"

	-- Set cursor to same position
	pcall(vim.api.nvim_win_set_cursor, git_history_state.diff_win, cursor_pos)

	-- Enable diff mode (targeted -- avoids enabling diff on info_win)
	vim.api.nvim_set_current_win(git_history_state.original_win)
	vim.cmd("diffthis")
	vim.api.nvim_set_current_win(git_history_state.diff_win)
	vim.cmd("diffthis")

	-- Disable folding in both windows after diff is enabled
	vim.api.nvim_set_current_win(git_history_state.original_win)
	vim.wo[git_history_state.original_win].foldenable = false
	vim.api.nvim_set_current_win(git_history_state.diff_win)
	vim.wo[git_history_state.diff_win].foldenable = false

	-- Minimal winbars (full context is in info_win)
	local idx   = git_history_state.index
	local total = #git_history_state.commits
	pcall(vim.api.nvim_set_option_value, "winbar",
		string.format("%%#Comment#[ %d / %d ]%%*", idx, total),
		{ win = git_history_state.diff_win })
	local file_name = vim.fn.fnamemodify(file, ":~:.")
	pcall(vim.api.nvim_set_option_value, "winbar",
		"[ CURRENT ]  " .. file_name,
		{ win = git_history_state.original_win })

	-- Update info window content
	update_info_win(commit_hash)

	-- Return to original window
	vim.api.nvim_set_current_win(git_history_state.original_win)
end

vim.keymap.set("n", "<leader>gH", function()
	git_history_state.commits = load_file_history()
	if #git_history_state.commits == 0 then
		vim.notify("No git history for this file", vim.log.levels.WARN)
		return
	end

	git_history_state.index = 1
	git_history_state.original_win = vim.api.nvim_get_current_win()
	show_commit_diff(git_history_state.commits[1])
end, { desc = "Start git history browser" })

vim.keymap.set("n", "[g", function()
	if git_history_state.index < #git_history_state.commits then
		git_history_state.index = git_history_state.index + 1
		show_commit_diff(git_history_state.commits[git_history_state.index])
	else
		vim.notify("Already at oldest commit", vim.log.levels.WARN)
	end
end, { desc = "Older commit" })

vim.keymap.set("n", "]g", function()
	if git_history_state.index > 1 then
		git_history_state.index = git_history_state.index - 1
		show_commit_diff(git_history_state.commits[git_history_state.index])
	else
		vim.notify("Already at newest commit", vim.log.levels.WARN)
	end
end, { desc = "Newer commit" })

vim.keymap.set("n", "<leader>gq", function()
	if git_history_state.original_win and vim.api.nvim_win_is_valid(git_history_state.original_win) then
		vim.api.nvim_set_current_win(git_history_state.original_win)
		vim.cmd("diffoff")
		pcall(vim.api.nvim_set_option_value, "winbar", "", { win = git_history_state.original_win })
	end
	if git_history_state.diff_win and vim.api.nvim_win_is_valid(git_history_state.diff_win) then
		vim.api.nvim_set_current_win(git_history_state.diff_win)
		vim.cmd("diffoff")
		vim.api.nvim_win_close(git_history_state.diff_win, true)
	end
	if git_history_state.info_win and vim.api.nvim_win_is_valid(git_history_state.info_win) then
		vim.api.nvim_win_close(git_history_state.info_win, true)
	end
	if git_history_state.info_buf and vim.api.nvim_buf_is_valid(git_history_state.info_buf) then
		vim.api.nvim_buf_delete(git_history_state.info_buf, { force = true })
	end
	if git_history_state.original_win and vim.api.nvim_win_is_valid(git_history_state.original_win) then
		vim.api.nvim_set_current_win(git_history_state.original_win)
	end
	git_history_state = {
		commits = {}, index = 0,
		original_win = nil, diff_buf = nil, diff_win = nil,
		info_buf = nil, info_win = nil,
	}
end, { desc = "Close git history" })

-- ============================================================================
-- PLUGIN MANAGER
-- ============================================================================

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

-- ============================================================================
-- PLUGINS
-- ============================================================================

require("lazy").setup({
	-- Theme
	{
		"navarasu/onedark.nvim",
		lazy = false,
		priority = 1000,
		config = function()
			require("onedark").setup({
				style = "dark",
				transparent = false,
				term_colors = true,
				colors = {
					black = "#000000",
					bg0 = "#000000",
					bg1 = "#0f0f0f",
					bg2 = "#0a0a0a",
				},
				highlights = {
					Normal = { bg = "#000000" },
					NormalFloat = { bg = "#0a0a0a" },
				},
			})
			require("onedark").load()
		end,
	},

	-- Treesitter (syntax highlighting, smart selection)
	-- main branch (0.12+): setup() only accepts install_dir.
	-- Highlighting is native Neovim (vim.treesitter.start via FileType autocmd).
	-- Indent uses nvim-treesitter's indentexpr per-buffer.
	-- Parsers are installed explicitly via require('nvim-treesitter').install{}.
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false, -- plugin does not support lazy-loading
		-- No build step: parsers are installed in config via require('nvim-treesitter').install{}.
		-- Run :TSUpdate manually after plugin updates to refresh parsers.
		config = function()
			-- Install parsers for languages we care about
			require("nvim-treesitter").install({
				"c",
				"cpp",
				"python",
				"lua",
				"vim",
				"bash",
				"cmake",
				"json",
				"yaml",
				"make",
				"markdown",
				"markdown_inline",
			})

			-- Enable treesitter highlighting and indentation for all filetypes
			-- where a parser is available.
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("ts_highlight", { clear = true }),
				callback = function(ev)
					if pcall(vim.treesitter.start, ev.buf) then
						vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
					end
				end,
			})
		end,
	},

	-- Fuzzy Finder
	{
		"nvim-telescope/telescope.nvim",
		branch = "master", -- 0.1.x dropped; master has Neovim 0.12 treesitter fixes
		dependencies = {
			"nvim-lua/plenary.nvim",
			{
				"nvim-telescope/telescope-fzf-native.nvim",
				build = "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release",
			},
			"nvim-telescope/telescope-file-browser.nvim",
		},
		config = function()
			local telescope = require("telescope")
			local actions = require("telescope.actions")
			local action_state = require("telescope.actions.state")
			local builtin = require("telescope.builtin")
			local fb_actions = require("telescope").extensions.file_browser.actions

			-- Forward declaration (defined below, used by smart_find_files/smart_live_grep)
			local directory_picker_for_mode

			-- Cache fd command
			local fd_command = vim.fn.executable("fd") == 1
					and { "fd", "--type", "f", "--hidden", "--no-ignore-vcs", "--exclude", ".git" }
				or nil

			-- State for directory picker workflow
			local picker_state = {
				mode = nil, -- "find_files" or "live_grep"
				original_cwd = nil,
				grep_filters = { include = {}, exclude = {} },
			}

			-- Smart file finder
			local function smart_find_files(opts)
				opts = opts or {}
				local path = opts.cwd or get_smart_cwd()

				builtin.find_files({
					cwd = path,
					find_command = fd_command,
					prompt_title = "📁" .. vim.fn.fnamemodify(path, ":~"),
					attach_mappings = function(prompt_bufnr, map)
						-- <C-b>: Open directory picker
						map("i", "<C-b>", function()
							picker_state.mode = "find_files"
							picker_state.original_cwd = path
							actions.close(prompt_bufnr)
							vim.schedule(function()
								directory_picker_for_mode(path)
							end)
						end)

						map("n", "<C-b>", function()
							picker_state.mode = "find_files"
							picker_state.original_cwd = path
							actions.close(prompt_bufnr)
							vim.schedule(function()
								directory_picker_for_mode(path)
							end)
						end)

						return true
					end,
				})
			end

			-- Smart live grep with filtering
			local function format_filter_display()
				local parts = {}
				for _, p in ipairs(picker_state.grep_filters.include) do
					table.insert(parts, "+" .. p)
				end
				for _, p in ipairs(picker_state.grep_filters.exclude) do
					table.insert(parts, "-" .. p)
				end
				return #parts > 0 and " [" .. table.concat(parts, " ") .. "]" or ""
			end

			local function build_glob_args()
				local args = {}
				for _, pattern in ipairs(picker_state.grep_filters.include) do
					table.insert(args, "--glob")
					table.insert(args, pattern)
				end
				for _, pattern in ipairs(picker_state.grep_filters.exclude) do
					table.insert(args, "--glob")
					table.insert(args, "!" .. pattern)
				end
				return args
			end

			local function smart_live_grep(opts)
				opts = opts or {}
				local path = opts.cwd or get_smart_cwd()
				local additional_args = build_glob_args()
				local filter_display = format_filter_display()

				builtin.live_grep({
					cwd = path,
					prompt_title = "🔍 " .. vim.fn.fnamemodify(path, ":~") .. filter_display,
					additional_args = function()
						return additional_args
					end,
					attach_mappings = function(prompt_bufnr, map)
						-- <C-b>: Open directory picker
						map("i", "<C-b>", function()
							picker_state.mode = "live_grep"
							picker_state.original_cwd = path
							actions.close(prompt_bufnr)
							vim.schedule(function()
								directory_picker_for_mode(path)
							end)
						end)

						map("n", "<C-b>", function()
							picker_state.mode = "live_grep"
							picker_state.original_cwd = path
							actions.close(prompt_bufnr)
							vim.schedule(function()
								directory_picker_for_mode(path)
							end)
						end)

						-- <C-f>: Add filters
						map("i", "<C-f>", function()
							local filter_input = vim.fn.input("Filter (+include -exclude): ")
							if filter_input == "" then
								return
							end

							picker_state.grep_filters = { include = {}, exclude = {} }
							for token in filter_input:gmatch("%S+") do
								if token:sub(1, 1) == "+" then
									table.insert(picker_state.grep_filters.include, token:sub(2))
								elseif token:sub(1, 1) == "-" then
									table.insert(picker_state.grep_filters.exclude, token:sub(2))
								else
									table.insert(picker_state.grep_filters.include, token)
								end
							end

							actions.close(prompt_bufnr)
							vim.schedule(smart_live_grep)
						end)

						-- <C-x>: Clear filters
						map("i", "<C-x>", function()
							picker_state.grep_filters = { include = {}, exclude = {} }
							actions.close(prompt_bufnr)
							vim.schedule(smart_live_grep)
						end)

						return true
					end,
				})
			end

			-- Directory picker for mode switching
			directory_picker_for_mode = function(start_path)
				telescope.extensions.file_browser.file_browser({
					path = start_path,
					cwd = start_path,
					respect_gitignore = false,
					hidden = true,
					grouped = true,
					depth = 1, -- Don't recurse into subdirectories
					prompt_title = "📁" .. vim.fn.fnamemodify(start_path, ":~"),
					results_title = "Setting CWD to: " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":~"),
					attach_mappings = function(prompt_bufnr, map)
						-- <C-b>: Select current directory and return to previous mode
						local function select_and_return()
							local current_picker = action_state.get_current_picker(prompt_bufnr)
							local finder = current_picker.finder
							local selected_dir = finder.path

							actions.close(prompt_bufnr)

							vim.schedule(function()
								if picker_state.mode == "find_files" then
									smart_find_files({ cwd = selected_dir })
								elseif picker_state.mode == "live_grep" then
									smart_live_grep({ cwd = selected_dir })
								end

								-- Reset state
								picker_state.mode = nil
								picker_state.original_cwd = nil
							end)
						end

						map("i", "<C-b>", select_and_return)
						map("n", "<C-b>", select_and_return)

						-- Override default selection: directories -> navigate, files -> open
						actions.select_default:replace(function(pb)
							local entry = action_state.get_selected_entry()
							if entry and entry.Path then
								local path = entry.Path:absolute()
								if vim.fn.isdirectory(path) == 1 then
									fb_actions.change_cwd(pb)
									local picker = action_state.get_current_picker(pb)
									picker.results_border:change_title("cwd: " .. vim.fn.fnamemodify(path, ":~"))
								else
									actions.close(pb)
									vim.cmd("edit " .. vim.fn.fnameescape(path))
								end
							end
						end)

						return true
					end,
				})
			end

			-- File browser (standalone mode)
			local function file_browser_mode()
				local ctx = get_buffer_context()
				local start_path = ctx.is_real_file and ctx.dir or get_smart_cwd()

				telescope.extensions.file_browser.file_browser({
					path = start_path,
					cwd = start_path,
					respect_gitignore = false,
				})
			end

			-- Telescope setup
			telescope.setup({
				defaults = {
					mappings = {
						i = {
							["<esc>"] = function()
								vim.cmd("stopinsert")
							end,
							["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
						},
						n = {
							["<esc>"] = actions.close,
							["q"] = actions.close,
							["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
						},
					},
					path_display = { shorten = { len = 3, exclude = { -1, -2, -3 } } },
					dynamic_preview_title = true,
					file_ignore_patterns = {
						"%.git/",
						"node_modules/",
						"%.o$",
						"%.a$",
						"%.so$",
					},
				},
				pickers = {
					buffers = {
						sort_mru = true,
						mappings = {
							i = { ["<C-d>"] = actions.delete_buffer },
							n = { ["dd"] = actions.delete_buffer },
						},
					},
				},
				extensions = {
					file_browser = {
						hijack_netrw = false,
						respect_gitignore = false,
						depth = 1,
						mappings = {
							i = {
								["<esc>"] = function()
									vim.cmd("stopinsert")
								end,
							},
							n = {
								["<esc>"] = actions.close,
								["q"] = actions.close,
							},
						},
					},
				},
			})

			pcall(telescope.load_extension, "fzf")
			pcall(telescope.load_extension, "file_browser")

			-- PRIMARY KEYMAPS
			vim.keymap.set("n", "<C-p>", function()
				local ctx = get_buffer_context()
				local start_path = ctx.is_real_file and ctx.dir or get_smart_cwd()
				picker_state.mode = "find_files"
				picker_state.original_cwd = start_path
				directory_picker_for_mode(start_path)
			end, { desc = "Find files" })

			-- SEARCH NAMESPACE (leader-s)
			vim.keymap.set("n", "<leader>sr", builtin.resume, { desc = "Resume search" })
			vim.keymap.set("n", "<leader>sf", file_browser_mode, { desc = "File browser" })
			vim.keymap.set("n", "<leader>sg", smart_live_grep, { desc = "Search grep" })
			vim.keymap.set("n", "<leader>sb", builtin.buffers, { desc = "Search buffers" })
			vim.keymap.set("n", "<leader>ss", builtin.lsp_document_symbols, { desc = "Search symbols (file)" })
			vim.keymap.set(
				"n",
				"<leader>sS",
				builtin.lsp_dynamic_workspace_symbols,
				{ desc = "Search symbols (project)" }
			)
			vim.keymap.set("n", "<leader>sh", builtin.help_tags, { desc = "Search help" })
			vim.keymap.set("n", "<leader>sc", builtin.commands, { desc = "Search commands" })
			vim.keymap.set("n", "<leader>sk", builtin.keymaps, { desc = "Search keymaps" })
		end,
	},

	-- Terminal
	{
		"akinsho/toggleterm.nvim",
		version = "*",
		opts = {
			size = function(term)
				if term.direction == "horizontal" then
					return vim.o.lines * 0.4
				end
				if term.direction == "vertical" then
					return vim.o.columns * 0.4
				end
			end,
			open_mapping = [[<c-\>]],
			hide_numbers = true,
			shade_terminals = false,
			start_in_insert = true,
			direction = "horizontal",
			close_on_exit = true,
			shell = vim.o.shell,
		},
		config = function(_, opts)
			require("toggleterm").setup(opts)

			-- Regular terminal instance (ID: 1)
			local term = nil

			vim.keymap.set({ "n", "t" }, "<C-\\>", function()
				if not term then
					local cwd = get_smart_cwd()
					-- Validate directory exists
					if vim.fn.isdirectory(cwd) == 0 then
						cwd = vim.fn.getcwd()
					end

					term = require("toggleterm.terminal").Terminal:new({
						id = 1, -- Explicit ID
						direction = "horizontal",
						dir = cwd,
					})
				end
				term:toggle()
			end, { desc = "Toggle terminal" })
		end,
	},

	-- Claude Code Integration (via MCP WebSocket protocol)
	{
		"coder/claudecode.nvim",
		dependencies = {
			"folke/snacks.nvim",
		},
		config = function()
			require("claudecode").setup({
				terminal = {
					split_side = "right",
					split_width_percentage = 0.5,
					provider = "snacks",
				},
				diff_opts = {
					open_in_new_tab = true,
					hide_terminal_in_new_tab = true,
				},
				focus_after_send = true,
			})

			-- Keybindings (keeping <leader>c prefix)
			vim.keymap.set({ "n", "t" }, "<leader>cc", "<cmd>ClaudeCode<cr>", { desc = "Toggle Claude Code" })
			vim.keymap.set("v", "<leader>cs", function()
				vim.cmd("ClaudeCodeSend")
				vim.schedule(function()
					vim.cmd("startinsert")
				end)
			end, { desc = "Send selection to Claude" })
			vim.keymap.set("n", "<leader>cda", "<cmd>ClaudeCodeDiffAccept<cr>", { desc = "Accept Claude diff" })
			vim.keymap.set("n", "<leader>cdd", "<cmd>ClaudeCodeDiffDeny<cr>", { desc = "Deny Claude diff" })
		end,
	},

	-- Git integration
	{
		"tpope/vim-fugitive",
		config = function()
			-- Git status opens in buffer's git root
			vim.keymap.set("n", "<leader>gs", function()
				local ctx = get_buffer_context()
				if not ctx.git_root then
					vim.notify("Not in a git repository", vim.log.levels.WARN)
					return
				end
				vim.cmd.cd(ctx.git_root)
				vim.cmd.Git()
			end, { desc = "Git status" })

			-- Git diff (buffer context aware)
			vim.keymap.set("n", "<leader>gd", function()
				local ctx = get_buffer_context()
				if ctx.git_root then
					vim.cmd.cd(ctx.git_root)
				end
				vim.cmd.Gdiffsplit()
			end, { desc = "Git diff" })

			-- Standard git commands
			vim.keymap.set("n", "<leader>gl", ":Git log<CR>", { desc = "Git log" })
			vim.keymap.set("n", "<leader>gb", ":Git blame<CR>", { desc = "Git blame" })
		end,
	},

	-- Git signs (inline diff markers
	{
		"lewis6991/gitsigns.nvim",
		opts = {
			signs = {
				add = { text = "│" },
				change = { text = "│" },
				delete = { text = "_" },
				topdelete = { text = "‾" },
				changedelete = { text = "~" },
			},
			on_attach = function(bufnr)
				local gs = require("gitsigns")
				local function map(mode, lhs, rhs, opts)
					opts = opts or {}
					opts.buffer = bufnr
					vim.keymap.set(mode, lhs, rhs, opts)
				end

				-- Navigate hunks (respects diff mode)
				map("n", "]c", function()
					if vim.wo.diff then
						return "]c"
					end
					vim.schedule(gs.next_hunk)
					return "<Ignore>"
				end, { expr = true, desc = "Next hunk" })

				map("n", "[c", function()
					if vim.wo.diff then
						return "[c"
					end
					vim.schedule(gs.prev_hunk)
					return "<Ignore>"
				end, { expr = true, desc = "Previous hunk" })

				-- Hunk operations
				map("n", "<leader>hs", gs.stage_hunk, { desc = "Stage hunk" })
				map("n", "<leader>hr", gs.reset_hunk, { desc = "Reset hunk" })
				map("n", "<leader>hp", gs.preview_hunk, { desc = "Preview hunk" })
				map("n", "<leader>hb", function()
					gs.blame_line({ full = true })
				end, { desc = "Blame line" })
			end,
		},
	},

	-- Comment toggling (gcc, gbc)
	{
		"numToStr/Comment.nvim",
		opts = {},
	},

	-- Surround operations (ys, cs, ds)
	"tpope/vim-surround",

	-- Auto pairs for brackets/quotes
	{
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		opts = {},
	},

	-- Statusline
	{
		"nvim-lualine/lualine.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = {
			options = {
				theme = "horizon",
				component_separators = "|",
				section_separators = "",
			},
			sections = {
				lualine_c = {
					{
						function()
							local ctx = get_buffer_context()
							return ctx.git_root and " " .. vim.fn.fnamemodify(ctx.git_root, ":t") or ""
						end,
						color = { fg = "#61afef" },
					},
					{
						"filename",
						path = 1,
					},
				},
			},
		},
	},

	-- Which-key (shows keybinding hints)
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			delay = 300,
		},
	},

	-- LSP
	{
		"neovim/nvim-lspconfig",
		dependencies = {
			"williamboman/mason.nvim",
			"williamboman/mason-lspconfig.nvim",
			{ "j-hui/fidget.nvim", opts = {} },
			{ "folke/neodev.nvim", opts = {} },
		},
		config = function()
			require("mason").setup({
				ui = { border = "rounded" },
			})

			require("mason-lspconfig").setup({
				ensure_installed = { "clangd", "pyright" },
				automatic_installation = false,
			})

			local capabilities = vim.lsp.protocol.make_client_capabilities()
			capabilities = vim.tbl_deep_extend("force", capabilities, require("cmp_nvim_lsp").default_capabilities())

			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("UserLspConfig", {}),
				callback = function(ev)
					local opts = { buffer = ev.buf }
					local builtin = require("telescope.builtin")

					-- Navigation
					vim.keymap.set("n", "gd", builtin.lsp_definitions, opts)
					vim.keymap.set("n", "gr", builtin.lsp_references, opts)
					vim.keymap.set("n", "gi", builtin.lsp_implementations, opts)
					vim.keymap.set("n", "gt", builtin.lsp_type_definitions, opts)
					vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)

					-- Hover/help
					vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
					vim.keymap.set("i", "<C-k>", vim.lsp.buf.signature_help, opts)

					-- Code actions
					vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
					vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)

					-- Diagnostics
					vim.keymap.set("n", "[d", function()
						vim.diagnostic.jump({ count = -1 })
					end, opts)
					vim.keymap.set("n", "]d", function()
						vim.diagnostic.jump({ count = 1 })
					end, opts)
					vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, opts)
					vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, opts)

					-- Inlay hints
					local client = vim.lsp.get_client_by_id(ev.data.client_id)
					if client and client.server_capabilities.inlayHintProvider then
						vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
					end

					vim.keymap.set("n", "<leader>ih", function()
						local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
						vim.lsp.inlay_hint.enable(not enabled, { bufnr = 0 })
					end, { buffer = ev.buf, desc = "Toggle inlay hints" })

					-- Debug: show LSP root
					vim.keymap.set("n", "<leader>pi", function()
						if not client then
							vim.notify("No LSP client attached", vim.log.levels.WARN)
							return
						end
						local root = client.config.root_dir
						vim.notify("LSP root: " .. (root or "none"), vim.log.levels.INFO)
					end, { buffer = ev.buf, desc = "Show LSP root" })
				end,
			})

			-- Clangd configuration
			vim.lsp.config("clangd", {
				cmd = {
					"clangd",
					"--background-index",
					"--clang-tidy",
					"--header-insertion=iwyu",
					"--completion-style=detailed",
					"--function-arg-placeholders=true",
					"--inlay-hints",
				},
				capabilities = capabilities,
				filetypes = { "c", "cpp", "objc", "objcpp", "cuda", "proto" },
				root_markers = {
					"compile_commands.json",
					".clangd",
					".clang-tidy",
					".clang-format",
					"compile_flags.txt",
					".git",
				},
			})

			-- Pyright configuration
			vim.lsp.config("pyright", {
				capabilities = capabilities,
				filetypes = { "python" },
				root_markers = {
					"pyproject.toml",
					"setup.py",
					"setup.cfg",
					"requirements.txt",
					"Pipfile",
					".git",
				},
			})

			vim.lsp.enable("clangd")
			vim.lsp.enable("pyright")
		end,
	},

	-- Autocompletion
	{
		"hrsh7th/nvim-cmp",
		dependencies = {
			"L3MON4D3/LuaSnip",
			"saadparwaiz1/cmp_luasnip",
			"hrsh7th/cmp-nvim-lsp",
			"hrsh7th/cmp-buffer",
			"hrsh7th/cmp-path",
			"hrsh7th/cmp-cmdline",
		},
		config = function()
			local cmp = require("cmp")
			local luasnip = require("luasnip")

			cmp.setup({
				snippet = {
					expand = function(args)
						luasnip.lsp_expand(args.body)
					end,
				},
				mapping = cmp.mapping.preset.insert({
					["<C-b>"] = cmp.mapping.scroll_docs(-4),
					["<C-f>"] = cmp.mapping.scroll_docs(4),
					["<C-Space>"] = cmp.mapping.complete(),
					["<C-e>"] = cmp.mapping.abort(),
					["<CR>"] = cmp.mapping.confirm({ select = true }),
					["<Tab>"] = cmp.mapping(function(fallback)
						if cmp.visible() then
							cmp.select_next_item()
						elseif luasnip.expand_or_jumpable() then
							luasnip.expand_or_jump()
						else
							fallback()
						end
					end, { "i", "s" }),
					["<S-Tab>"] = cmp.mapping(function(fallback)
						if cmp.visible() then
							cmp.select_prev_item()
						elseif luasnip.jumpable(-1) then
							luasnip.jump(-1)
						else
							fallback()
						end
					end, { "i", "s" }),
				}),
				sources = cmp.config.sources({
					{ name = "nvim_lsp" },
					{ name = "luasnip" },
					{ name = "path" },
				}, {
					{ name = "buffer" },
				}),
				window = {
					completion = cmp.config.window.bordered(),
					documentation = cmp.config.window.bordered(),
				},
				formatting = {
					format = function(entry, vim_item)
						vim_item.menu = ({
							nvim_lsp = "[LSP]",
							luasnip = "[Snippet]",
							buffer = "[Buffer]",
							path = "[Path]",
						})[entry.source.name]
						return vim_item
					end,
				},
			})

			-- Command-line completion
			cmp.setup.cmdline("/", {
				mapping = cmp.mapping.preset.cmdline(),
				sources = {
					{ name = "buffer" },
				},
			})

			cmp.setup.cmdline(":", {
				mapping = cmp.mapping.preset.cmdline(),
				sources = cmp.config.sources({
					{ name = "path" },
				}, {
					{ name = "cmdline" },
				}),
			})
		end,
	},

	-- Code formatter
	{
		"stevearc/conform.nvim",
		opts = {
			formatters_by_ft = {
				c = { "clang-format" },
				cpp = { "clang-format" },
				python = { "black" },
				lua = { "stylua" },
				java = { "google-java-format" },
				rust = { "rustfmt" },
				sh = { "shfmt" },
				bash = { "shfmt" },
			},
			format_on_save = false,
		},
		keys = {
			{
				"<leader>f",
				function()
					require("conform").format({ async = true, lsp_fallback = false })
				end,
				desc = "Format buffer",
			},
			{
				"<leader>f",
				function()
					require("conform").format({ async = true, lsp_fallback = false })
				end,
				mode = "v",
				desc = "Format selection",
			},
		},
	},

	-- Auto-save on edit/focus loss
	{
		"okuuva/auto-save.nvim",
		event = { "InsertLeave", "TextChanged" },
		opts = {
			enabled = true,
			execution_message = { enabled = false },
			trigger_events = {
				immediate_save = { "BufLeave", "FocusLost" },
				defer_save = { "InsertLeave", "TextChanged" },
				cancel_defered_save = { "InsertEnter" },
			},
			condition = function(buf)
				return vim.bo[buf].buftype == "" and vim.bo[buf].modifiable and vim.fn.expand("%") ~= ""
			end,
			write_all_buffers = false,
			debounce_delay = 1000,
		},
		keys = {
			{ "<leader>as", ":ASToggle<CR>", desc = "Toggle auto-save" },
		},
	},

	{
		"folke/persistence.nvim",
		event = "BufReadPre",
		opts = {},
		init = function()
			local persistence = require("persistence")

			-- Auto-restore on startup
			vim.api.nvim_create_autocmd("VimEnter", {
				callback = function()
					if vim.fn.argc() == 0 then
						require("persistence").load({ last = true })
						vim.schedule(function()
							-- Force reload all buffers to trigger treesitter
							for _, buf in ipairs(vim.api.nvim_list_bufs()) do
								if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" then
									vim.api.nvim_buf_call(buf, function()
										vim.cmd("edit")
									end)
								end
							end
						end)
					end
				end,
			})

			-- Auto-save every 30s if changes happened
			local dirty = false
			vim.api.nvim_create_autocmd({ "BufWritePost", "BufEnter", "BufLeave" }, {
				callback = function()
					dirty = true
				end,
			})

			local timer = vim.loop.new_timer()
			if timer then
				timer:start(
					30000,
					30000,
					vim.schedule_wrap(function()
						if dirty then
							persistence.save()
							dirty = false
						end
					end)
				)
			end
		end,
		keys = {
			{
				"<leader>qr",
				function()
					require("persistence").stop()
					vim.cmd("bufdo bwipeout | only | enew")
				end,
				desc = "Reset nvim",
			},
		},
	},
})
