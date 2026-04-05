-- ============================================================================
-- init.lua -- Neovim configuration
--
-- Single-file setup (no lua/ subdirectory). Plugins are managed by lazy.nvim.
--
-- Sections (in order):
--   BASIC SETTINGS              core editor options and UI
--   CONTEXT RESOLVER            buffer-centric working directory helpers
--   KEY MAPPINGS                global keymaps (not plugin-specific)
--   AUTOCMDS                    global autocommands and diagnostic config
--   CLAUDE CODE EDITOR INTEGRATION   $EDITOR float for Claude Code prompts
--   CLAUDE CODE DIFF VIEW WINBAR     winbar labels for Claude Code diffs
--   FILE GIT HISTORY NAVIGATOR  3-window git blame/diff browser
--   PLUGIN MANAGER              lazy.nvim bootstrap
--   PLUGINS                     plugin specs and their configs/keymaps
-- ============================================================================

-- ============================================================================
-- BASIC SETTINGS
--
-- Core editor options: UI, splits, search, indentation, editing behavior, and
-- persistence. All settings below deviate from Neovim defaults unless noted.
-- ============================================================================
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Disabled because vim-fugitive (and telescope-file-browser) handle directory
-- browsing. Netrw and fugitive conflict when opening directories.
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- UI
vim.opt.number = false
vim.opt.relativenumber = false
vim.opt.signcolumn = "yes" -- Always show to avoid layout shifts when diagnostics/git signs appear.
vim.opt.cursorline = true
vim.opt.termguicolors = true
vim.opt.scrolloff = 8 -- Keep 8 lines of context visible above/below the cursor.
vim.opt.sidescrolloff = 8 -- Keep 8 columns of context visible left/right of the cursor.

-- Splits
-- New vertical splits open to the right; horizontal splits open below.
-- More natural than Vim's default (left/above).
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Search
-- ignorecase: searches are case-insensitive by default.
-- smartcase: override -- if the pattern contains any uppercase, match exactly.
-- Together: /foo matches Foo, but /Foo matches only Foo.
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true

-- Indentation (4-space, expand tabs to spaces)
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Editing
vim.opt.wrap = true
vim.opt.undofile = true -- Persist undo history across sessions.
vim.opt.swapfile = false
vim.opt.backup = false
-- Reload file from disk when changed externally. autoread alone is not enough:
-- Neovim only acts on it when checktime is called. The autocmd below triggers
-- checktime on FocusGained and BufEnter so refocusing the buffer or switching
-- to it always picks up external changes before the user can overwrite them.
vim.opt.autoread = true

-- Performance
-- updatetime drives CursorHold events. Since virtual_text is disabled, diagnostics
-- appear via a CursorHold autocmd -- lower value = faster popup response.
vim.opt.updatetime = 250
-- How long to wait for a key sequence to complete. Also drives which-key delay.
vim.opt.timeoutlen = 300

-- ShaDa (persistent state across sessions):
--   "!":   persist global variables (used by plugins that store state in vim.g)
--   '1000: remember marks for up to 1000 files
--   <50:   save at most 50 lines per register entry
--   s10:   skip registers whose content exceeds 10 KB
--   h:     do not restore hlsearch state on startup
vim.opt.shada = { "!", "'1000", "<50", "s10", "h" }

-- Sync yank/delete/paste with the system clipboard by default.
-- See also <leader>p and <leader>d for paste/delete without touching the clipboard.
vim.opt.clipboard = "unnamedplus"

-- Spell checking on by default. Disabled per-buffer in terminal windows (see AUTOCMDS).
vim.opt.spell = true
vim.opt.spelllang = { "en_us" }

-- ============================================================================
-- CONTEXT RESOLVER
--
-- All directory-sensitive operations (Telescope, terminal, git commands) use
-- get_smart_cwd() rather than vim.fn.getcwd(). This keeps the global working
-- directory stable -- changing it would break plugins that rely on it -- while
-- still rooting searches/terminals in the current project.
-- ============================================================================

-- Returns path, dir, git_root, and is_real_file for the current editing context,
-- falling back to the last real file buffer when in a special buffer.
local function get_buffer_context()
    local bufnr = vim.api.nvim_get_current_buf()

    -- Special buffers (terminal, quickfix, help, etc.) have no meaningful path.
    -- Walk the buffer list and use the first real file buffer instead so that
    -- opening a terminal does not lose the project context.
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
    local git_root = vim.fn.systemlist(
        "git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null"
    )[1]

    return {
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
--
-- Window navigation, resizing, visual-mode indenting, cursor centering,
-- clipboard-safe paste/delete, search highlight clearing, and buffer switching.
-- Plugin-specific keymaps are defined in each plugin's config block (PLUGINS).
-- ============================================================================

-- Window navigation (normal mode)
vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })

-- Terminal mode: exit + window navigation
-- Double-Esc exits terminal mode. Single <Esc> is left alone so programs
-- running in the terminal (e.g. vim, fzf) can receive it.
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
vim.keymap.set("t", "<C-h>", "<C-\\><C-n><C-w>h", { desc = "Go to left window from terminal" })
vim.keymap.set("t", "<C-j>", "<C-\\><C-n><C-w>j", { desc = "Go to lower window from terminal" })
vim.keymap.set("t", "<C-k>", "<C-\\><C-n><C-w>k", { desc = "Go to upper window from terminal" })
vim.keymap.set("t", "<C-l>", "<C-\\><C-n><C-w>l", { desc = "Go to right window from terminal" })

-- Window resizing
vim.keymap.set("n", "<C-Up>", "<cmd>resize -2<CR>", { desc = "Decrease window height" })
vim.keymap.set("n", "<C-Down>", "<cmd>resize +2<CR>", { desc = "Increase window height" })
vim.keymap.set("n", "<C-Left>", "<cmd>vertical resize -2<CR>", { desc = "Decrease window width" })
vim.keymap.set("n", "<C-Right>", "<cmd>vertical resize +2<CR>", { desc = "Increase window width" })

-- Re-select the visual range after indenting so repeated < / > work without
-- re-selecting manually.
vim.keymap.set("v", "<", "<gv")
vim.keymap.set("v", ">", ">gv")

-- Page up/down with cursor centered. zz re-centers; zv opens any fold the
-- cursor lands inside.
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- Paste using the black-hole register ("_) so the clipboard is not overwritten.
-- Allows the same yanked text to be pasted repeatedly.
vim.keymap.set({ "n", "x" }, "<leader>p", '"_dP', { desc = "Paste without yanking" })

-- Delete to the black-hole register -- clipboard is unaffected.
vim.keymap.set({ "n", "x" }, "<leader>d", '"_d', { desc = "Delete without yanking" })

-- Clear search highlight (overrides the default no-op <Esc> in normal mode).
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Buffer switching
vim.keymap.set("n", "<S-l>", "<cmd>bnext<CR>", { desc = "Next buffer" })
vim.keymap.set("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
vim.keymap.set("n", "<leader>x", "<cmd>bdelete!<CR>", { desc = "Close buffer" })

-- ============================================================================
-- AUTOCMDS
--
-- Global behaviors: auto-create directories on save, restore cursor position,
-- quickfix UX, terminal gf navigation, external file reload, and diagnostic
-- display configuration.
-- ============================================================================

-- Companion to autoread: trigger the on-disk check whenever Neovim gains focus
-- or a buffer is entered, so external writes are picked up before a save can
-- overwrite them. CmdlineLeave catches the case where the user runs a shell
-- command via :! that modifies the file.
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CmdlineLeave" }, {
    callback = function()
        vim.cmd("checktime")
    end,
})

-- Auto-create parent directories when saving a new file in a non-existent path.
-- Eliminates "No such file or directory" errors from :w.
vim.api.nvim_create_autocmd("BufWritePre", {
    callback = function(event)
        local dir = vim.fn.fnamemodify(event.match, ":h")
        if vim.fn.isdirectory(dir) == 0 then
            vim.fn.mkdir(dir, "p")
        end
    end,
})

-- Restore cursor to the last known position when reopening a file.
-- '"' is the mark Neovim writes for the last cursor position in a file.
-- Bounds-check needed: the file may have shrunk since the mark was recorded.
vim.api.nvim_create_autocmd("BufReadPost", {
    callback = function()
        local mark = vim.api.nvim_buf_get_mark(0, '"')
        local line_count = vim.api.nvim_buf_line_count(0)
        if mark[1] > 0 and mark[1] <= line_count then
            vim.api.nvim_win_set_cursor(0, mark)
        end
    end,
})

-- Quickfix UX: jump to a result and close the window in one step (<CR>),
-- or close without jumping (q / <Esc>).
vim.api.nvim_create_autocmd("FileType", {
    pattern = "qf",
    callback = function(event)
        local opts = { buffer = event.buf, silent = true }
        vim.keymap.set("n", "<CR>", "<CR>:cclose<CR>", opts)
        vim.keymap.set("n", "q", ":cclose<CR>", opts)
        vim.keymap.set("n", "<Esc>", ":cclose<CR>", opts)
    end,
})

vim.api.nvim_create_autocmd("TermOpen", {
    callback = function(event)
        vim.opt_local.spell = false -- Spell checking is meaningless inside a terminal.

        -- Override gf so it opens the file under cursor in an existing editor window
        -- rather than inside the terminal. Falls back to aboveleft split if no editor
        -- window is found. aboveleft avoids accidentally nesting a new terminal.
        vim.keymap.set("n", "gf", function()
            local file = vim.fn.expand("<cfile>")
            if file == "" then
                vim.notify("No file under cursor", vim.log.levels.WARN)
                return
            end

            for _, win in ipairs(vim.api.nvim_list_wins()) do
                local buf = vim.api.nvim_win_get_buf(win)
                if vim.bo[buf].buftype ~= "terminal" then
                    vim.api.nvim_set_current_win(win)
                    vim.cmd.edit(vim.fn.fnameescape(file))
                    return
                end
            end

            vim.cmd("aboveleft split " .. vim.fn.fnameescape(file))
        end, { buffer = event.buf })
    end,
})

vim.diagnostic.config({
    -- No inline ghost text -- it clutters the editor and competes with code.
    -- Diagnostics appear in a float via the CursorHold autocmd below instead.
    virtual_text = false,
    signs = true,
    underline = true,
    -- Don't re-evaluate diagnostics while typing; wait until leaving insert mode.
    update_in_insert = false,
    -- Show errors above warnings in floats and the sign column.
    severity_sort = true,
    float = {
        border = "rounded",
        -- Include the LSP source name only when multiple clients are attached
        -- (avoids noise in the common single-client case).
        source = "if_many",
        focusable = true,
        wrap = true,
        max_width = math.floor(vim.o.columns * 0.8),
        max_height = math.floor(vim.o.lines * 0.6),
    },
})

-- Companion to virtual_text=false: show a diagnostic float when the cursor rests
-- on a line. focus=false keeps focus in the editing window.
-- Triggered by updatetime (250ms, set in BASIC SETTINGS).
vim.api.nvim_create_autocmd("CursorHold", {
    callback = function()
        vim.diagnostic.open_float(nil, { focus = false, scope = "cursor" })
    end,
})

-- ============================================================================
-- CLAUDE CODE EDITOR INTEGRATION
-- Sets $EDITOR/$VISUAL to scripts/nvim-editor so Claude Code's "open in editor"
-- shortcut opens files inside the running Neovim instance rather than spawning
-- a new one. The script calls _nvim_editor_open via --remote-expr, which opens
-- the file in a centered floating window without disturbing the current layout.
-- q/<Esc> writes the buffer to disk and signals the sentinel file, unblocking
-- the shell script so Claude Code reads the result.
-- ============================================================================

local _editor_script = vim.fn.stdpath("config") .. "/scripts/nvim-editor"
if vim.fn.executable(_editor_script) == 1 then
    vim.env.EDITOR = _editor_script
    vim.env.VISUAL = _editor_script
end

_G._nvim_editor_open = function(file, sentinel)
    local abs_file = vim.fn.fnamemodify(file, ":p")

    -- Load the buffer without touching any existing window.
    -- buftype=nofile prevents premature writes that could confuse Claude Code's
    -- file watcher before the user finishes editing.
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

    -- Disable nvim-cmp in this buffer (completions are irrelevant and confirming
    -- a completion was triggering Claude Code's file-watcher prematurely)
    local cmp_ok, cmp = pcall(require, "cmp")
    if cmp_ok then
        cmp.setup.buffer({ enabled = false })
    end

    -- Guard against double-signalling: BufDelete/BufWipeout autocmd and the
    -- close() function can both fire in some paths (e.g. external :bwipeout).
    -- The flag ensures the sentinel file is written exactly once.
    local sentinel_written = false
    local function write_sentinel()
        if not sentinel_written then
            sentinel_written = true
            vim.fn.writefile({}, sentinel)
        end
    end

    -- Fallback: if the buffer is wiped externally (e.g. :bwipeout), still signal
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        buffer = bufnr,
        once = true,
        callback = write_sentinel,
    })

    local function close()
        if vim.api.nvim_buf_is_valid(bufnr) then
            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            vim.fn.writefile(lines, abs_file)
        end
        write_sentinel()
        pcall(vim.api.nvim_win_close, win, true)
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end

    vim.keymap.set("n", "q", close, { buffer = bufnr, desc = "Send to Claude" })
    vim.keymap.set("n", "<Esc>", close, { buffer = bufnr, desc = "Send to Claude" })

    -- Position cursor at end of last line and enter insert mode so the user
    -- can immediately continue typing where they left off.
    -- feedkeys("A") is used instead of startinsert! because remote-expr
    -- invocations suppress mode changes via vim.cmd.
    vim.schedule(function()
        vim.api.nvim_set_current_win(win)
        local last_line = vim.api.nvim_buf_line_count(bufnr)
        local last_col = #vim.api.nvim_buf_get_lines(bufnr, last_line - 1, last_line, false)[1]
        vim.api.nvim_win_set_cursor(win, { last_line, last_col })
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("A", true, false, true), "n", false)
    end)
end

-- ============================================================================
-- CLAUDE CODE DIFF VIEW WINBAR
--
-- Adds [ ORIGINAL ] / [ PROPOSED ] labels to winbars during Claude Code diff
-- reviews, using the claudecode_diff_tab_name buffer variable set by
-- claudecode.nvim as the marker that identifies the proposed-change window.
-- ============================================================================

local function set_winbar(win, text)
    pcall(vim.api.nvim_set_option_value, "winbar", text, { win = win })
end

local function update_claudecode_diff_winbars()
    local all_wins = vim.api.nvim_tabpage_list_wins(0)
    local has_proposed = false

    -- Pass 1: label proposed windows and check if any exist.
    for _, win in ipairs(all_wins) do
        if vim.api.nvim_win_is_valid(win) then
            local tab_name = vim.b[vim.api.nvim_win_get_buf(win)].claudecode_diff_tab_name
            if tab_name then
                has_proposed = true
                set_winbar(win, "[ PROPOSED ]  " .. vim.fn.fnamemodify(tab_name, ":~:."))
            end
        end
    end

    -- Pass 2: for unmarked windows, either label as ORIGINAL (if a diff is active
    -- and the window is in diff mode) or clear our winbar (if no diff is active).
    for _, win in ipairs(all_wins) do
        if vim.api.nvim_win_is_valid(win) then
            local buf = vim.api.nvim_win_get_buf(win)
            if not vim.b[buf].claudecode_diff_tab_name then
                if has_proposed and vim.wo[win].diff then
                    local path = vim.api.nvim_buf_get_name(buf)
                    local rel = path ~= "" and vim.fn.fnamemodify(path, ":~:.") or "[No Name]"
                    set_winbar(win, "[ ORIGINAL ]  " .. rel)
                elseif not has_proposed then
                    local ok, wb = pcall(vim.api.nvim_get_option_value, "winbar", { win = win })
                    if
                        ok
                        and wb
                        and (wb:match("^%[ PROPOSED %]") or wb:match("^%[ ORIGINAL %]"))
                    then
                        set_winbar(win, "")
                    end
                end
            end
        end
    end
end

-- Defer the update via vim.schedule: winbar changes during BufWinEnter/WinEnter
-- can fire before the window layout is fully resolved, causing stale labels.
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
--
-- Browse the git history of the current file in a 3-window layout:
--   top:          fixed-height info panel (commit metadata + navigation hints)
--   bottom-left:  current file in diff mode
--   bottom-right: historical version in diff mode
-- Trigger with <leader>gH. Navigate with [g (older) / ]g (newer).
-- Close everything with <leader>gq.
-- ============================================================================
local function default_git_history_state()
    return {
        commits = {},
        index = 0,
        original_win = nil,
        diff_buf = nil,
        diff_win = nil,
        info_buf = nil,
        info_win = nil,
    }
end
local git_history_state = default_git_history_state()
local function update_info_win(commit_hash)
    if
        not git_history_state.info_win or not vim.api.nvim_win_is_valid(git_history_state.info_win)
    then
        return
    end

    -- Terminal buffers are append-only, so create a fresh one on each navigation
    -- and delete the previous one. nvim_open_term renders ANSI color codes from
    -- git directly, so no manual token/highlight logic is needed.
    local old_buf = git_history_state.info_buf
    local buf = vim.api.nvim_create_buf(false, true)
    local term = vim.api.nvim_open_term(buf, {})
    vim.api.nvim_win_set_buf(git_history_state.info_win, buf)
    git_history_state.info_buf = buf
    pcall(vim.api.nvim_buf_delete, old_buf, { force = true })

    local fmt = "%C(yellow)commit %H%C(auto)%d%C(reset)%n"
        .. "Author: %C(bold cyan)%an%C(reset) -- %C(green)%ar%C(reset)%n"
        .. "%C(bold)%s%C(reset)%n%b%n"
    local out = vim.fn.system(
        "git show --no-patch --color=always --pretty=tformat:"
            .. vim.fn.shellescape(fmt)
            .. " "
            .. commit_hash
    )
    vim.api.nvim_chan_send(term, out)
end

local function show_commit_diff(commit_hash)
    local file = vim.fn.expand("%:p")
    -- Path relative to git root is required by git show. Using getcwd() was
    -- fragile: if cwd differs from git root the prefix strip failed silently.
    local git_root = get_buffer_context().git_root or vim.fn.getcwd()
    local rel_path = file:sub(#git_root + 2) -- strip "root/" prefix
    local content =
        vim.fn.systemlist("git show " .. commit_hash .. ":" .. vim.fn.shellescape(rel_path))

    -- Capture filetype before any window switching. After creating the diff/info
    -- windows the current buffer changes, so vim.bo.filetype would return "" for
    -- the new scratch buffer instead of the original file's filetype.
    local orig_filetype = vim.bo[vim.api.nvim_win_get_buf(git_history_state.original_win)].filetype
    local cursor_pos = vim.api.nvim_win_get_cursor(git_history_state.original_win)

    -- Create or reuse windows (idempotent: skipped on subsequent navigations)
    if
        not git_history_state.info_win or not vim.api.nvim_win_is_valid(git_history_state.info_win)
    then
        -- topleft creates a horizontal split spanning the full tabpage width,
        -- not just the current column -- so the info bar sits above both file windows.
        vim.api.nvim_set_current_win(git_history_state.original_win)
        vim.cmd("topleft split")
        git_history_state.info_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_height(git_history_state.info_win, 4)
        -- Prevent the info window from being resized when Neovim re-balances
        -- windows (e.g. when the diff window is created below it).
        vim.wo[git_history_state.info_win].winfixheight = true
        vim.wo[git_history_state.info_win].number = false
        vim.wo[git_history_state.info_win].relativenumber = false
        vim.wo[git_history_state.info_win].signcolumn = "no"
        vim.wo[git_history_state.info_win].statusline = " "
        vim.wo[git_history_state.info_win].wrap = false
        vim.wo[git_history_state.info_win].foldenable = false
        vim.wo[git_history_state.info_win].spell = false
        -- Navigation hints in the winbar (content area shows raw git output).
        vim.wo[git_history_state.info_win].winbar = "  [g older    ]g newer   <leader>gq close"

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

    -- Set cursor to same position
    pcall(vim.api.nvim_win_set_cursor, git_history_state.diff_win, cursor_pos)

    -- Enable diff mode on the two file windows only. windo diffthis would also
    -- enable diff on the info panel, which must stay plain text.
    vim.api.nvim_set_current_win(git_history_state.original_win)
    vim.cmd("diffthis")
    vim.api.nvim_set_current_win(git_history_state.diff_win)
    vim.cmd("diffthis")

    -- Neovim automatically enables folding when diff mode is activated (foldmethod
    -- becomes "diff"). Disable it immediately or diff context disappears inside folds.
    vim.wo[git_history_state.original_win].foldenable = false
    vim.wo[git_history_state.diff_win].foldenable = false

    -- Minimal winbars (full context is in info_win)
    local idx = git_history_state.index
    local total = #git_history_state.commits
    set_winbar(git_history_state.diff_win, string.format("%%#Comment#[ %d / %d ]%%*", idx, total))
    set_winbar(git_history_state.original_win, "[ CURRENT ]  " .. vim.fn.fnamemodify(file, ":~:."))

    -- Update info window content
    update_info_win(commit_hash)

    -- Return to original window
    vim.api.nvim_set_current_win(git_history_state.original_win)
end

vim.keymap.set("n", "<leader>gH", function()
    local file = vim.fn.expand("%:p")
    git_history_state.commits =
        vim.fn.systemlist("git log --format=%H -- " .. vim.fn.shellescape(file))
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

-- Close git history: tear down the 3-window layout and reset state.
-- pcall throughout: this is a cleanup path -- if the layout is partially broken
-- (window closed manually, session restored, etc.) we still want to kill whatever
-- is alive and reset state. Partial success is fine.
-- diffoff must be called while the window is current, so we switch before closing.
-- Terminal buffers have bufhidden=hide and survive window close; delete explicitly.
vim.keymap.set("n", "<leader>gq", function()
    if pcall(vim.api.nvim_set_current_win, git_history_state.diff_win) then
        vim.cmd("diffoff")
    end
    pcall(vim.api.nvim_win_close, git_history_state.diff_win, true)
    pcall(vim.api.nvim_win_close, git_history_state.info_win, true)
    pcall(vim.api.nvim_buf_delete, git_history_state.info_buf, { force = true })
    if pcall(vim.api.nvim_set_current_win, git_history_state.original_win) then
        vim.cmd("diffoff")
        set_winbar(git_history_state.original_win, "")
    end
    git_history_state = default_git_history_state()
end, { desc = "Close git history" })

-- ============================================================================
-- PLUGIN MANAGER
--
-- Bootstrap lazy.nvim (the plugin manager) if not already installed, then
-- prepend it to the runtime path so it can be required.
-- ============================================================================

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", -- Use the stable branch to avoid breaking changes from main.
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

-- ============================================================================
-- PLUGINS
--
-- All plugin declarations in lazy.nvim spec format. Each entry can specify:
--   dependencies, event/cmd/ft/keys for lazy loading, and a config function.
-- ============================================================================

require("lazy").setup({
    -- -------------------------------------------------------------------------
    -- Theme: navarasu/onedark.nvim
    -- -------------------------------------------------------------------------
    {
        "navarasu/onedark.nvim",
        lazy = false,
        -- priority = 1000: load before all other plugins so the colorscheme is
        -- applied first and other plugins see the correct highlight groups.
        priority = 1000,
        config = function()
            require("onedark").setup({
                style = "dark",
                -- transparent = false: keep the background opaque (no terminal bleed-through).
                transparent = false,
                term_colors = true,
                -- Custom colors: override default backgrounds with pure black for
                -- maximum contrast on dark/OLED displays.
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

    -- -------------------------------------------------------------------------
    -- Treesitter: nvim-treesitter/nvim-treesitter
    -- -------------------------------------------------------------------------
    -- branch = "main": the 0.12+ API where setup() only accepts install_dir.
    --   Highlighting is wired up manually via a FileType autocmd below.
    -- lazy = false: nvim-treesitter does not support lazy loading on this branch.
    -- No build step: parsers are compiled inside config() via install{}.
    -- Run :TSUpdate manually after plugin updates to refresh parsers.
    {
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        lazy = false,
        config = function()
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

            -- Enable treesitter highlighting and indentation for all filetypes where
            -- a parser is available. pcall: silently skip unsupported filetypes.
            -- indentexpr: use treesitter's smarter indentation for supported languages.
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

    -- -------------------------------------------------------------------------
    -- Fuzzy Finder: nvim-telescope/telescope.nvim
    -- -------------------------------------------------------------------------
    -- branch = "master": 0.1.x was dropped; master has Neovim 0.12 treesitter fixes.
    -- telescope-fzf-native: compiled C extension for significantly faster fuzzy sorting.
    -- telescope-file-browser: directory navigation integrated into the picker workflow.
    {
        "nvim-telescope/telescope.nvim",
        branch = "master",
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

            -- fd is faster than find and correctly respects our ignore patterns.
            -- Falls back to nil so telescope uses its built-in find when fd is absent.
            local fd_command = vim.fn.executable("fd") == 1
                    and { "fd", "--type", "f", "--hidden", "--no-ignore-vcs", "--exclude", ".git" }
                or nil

            -- Shared state for the <C-b> round-trip between the directory picker and
            -- the file/grep picker. mode records which picker to return to;
            -- grep_filters carries over the previous picker's filter configuration.
            local picker_state = {
                mode = nil, -- "find_files" or "live_grep"
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
                        local function open_dir_picker()
                            picker_state.mode = "find_files"
                            actions.close(prompt_bufnr)
                            vim.schedule(function()
                                directory_picker_for_mode(path)
                            end)
                        end
                        map("i", "<C-b>", open_dir_picker)
                        map("n", "<C-b>", open_dir_picker)
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
                        local function open_dir_picker()
                            picker_state.mode = "live_grep"
                            actions.close(prompt_bufnr)
                            vim.schedule(function()
                                directory_picker_for_mode(path)
                            end)
                        end
                        map("i", "<C-b>", open_dir_picker)
                        map("n", "<C-b>", open_dir_picker)

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

                                picker_state.mode = nil
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
                                    picker.results_border:change_title(
                                        "Setting CWD to: " .. vim.fn.fnamemodify(path, ":~")
                                    )
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

            local stop_insert = function()
                vim.cmd("stopinsert")
            end
            telescope.setup({
                defaults = {
                    mappings = {
                        i = {
                            -- <Esc> in insert mode: stop insert but keep the picker open.
                            -- Default behaviour closes the picker entirely.
                            ["<esc>"] = stop_insert,
                            -- <C-q>: send all current results to the quickfix list.
                            ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
                        },
                        n = {
                            ["<esc>"] = actions.close,
                            ["q"] = actions.close,
                            ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
                        },
                    },
                    -- Keep the last 3 path components unshortened (exclude = {-1,-2,-3});
                    -- abbreviate intermediate directories to save screen space.
                    path_display = { shorten = { len = 3, exclude = { -1, -2, -3 } } },
                    dynamic_preview_title = true,
                    -- Exclude build artifacts and common dependency directories globally.
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
                        -- sort_mru: most recently used buffers appear at the top of the list.
                        sort_mru = true,
                        mappings = {
                            -- <C-d>/dd: delete a buffer from within the picker.
                            i = { ["<C-d>"] = actions.delete_buffer },
                            n = { ["dd"] = actions.delete_buffer },
                        },
                    },
                },
                extensions = {
                    file_browser = {
                        -- hijack_netrw = false: netrw is already disabled globally; no conflict.
                        hijack_netrw = false,
                        -- respect_gitignore = false: show gitignored files so they can be inspected.
                        respect_gitignore = false,
                        -- depth = 1: show only immediate children, not a recursive tree.
                        depth = 1,
                        mappings = {
                            i = { ["<esc>"] = stop_insert },
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
                directory_picker_for_mode(start_path)
            end, { desc = "Find files" })

            -- SEARCH NAMESPACE (leader-s)
            vim.keymap.set("n", "<leader>sr", builtin.resume, { desc = "Resume search" })
            vim.keymap.set("n", "<leader>sf", file_browser_mode, { desc = "File browser" })
            vim.keymap.set("n", "<leader>sg", smart_live_grep, { desc = "Search grep" })
            vim.keymap.set("n", "<leader>sb", builtin.buffers, { desc = "Search buffers" })
            vim.keymap.set(
                "n",
                "<leader>ss",
                builtin.lsp_document_symbols,
                { desc = "Search symbols (file)" }
            )
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

    -- -------------------------------------------------------------------------
    -- Terminal: akinsho/toggleterm.nvim
    -- -------------------------------------------------------------------------
    {
        "akinsho/toggleterm.nvim",
        version = "*",
        opts = {
            size = function(term)
                -- 40% of window height/width -- large enough to work in, leaves room for code.
                if term.direction == "horizontal" then
                    return vim.o.lines * 0.4
                end
                if term.direction == "vertical" then
                    return vim.o.columns * 0.4
                end
            end,
            open_mapping = [[<c-\>]],
            hide_numbers = true,
            shade_terminals = false, -- No background dimming in the terminal.
            start_in_insert = true, -- Terminal opens ready to type.
            direction = "horizontal",
            close_on_exit = true, -- Window closes when the shell process exits.
            shell = vim.o.shell,
        },
        config = function(_, opts)
            require("toggleterm").setup(opts)

            -- Single persistent terminal instance, created lazily on first <C-\> press.
            -- Lazy creation ensures get_smart_cwd() reflects the buffer open at that time.
            local term = nil

            vim.keymap.set({ "n", "t" }, "<C-\\>", function()
                if not term then
                    local cwd = get_smart_cwd()
                    if vim.fn.isdirectory(cwd) == 0 then
                        cwd = vim.fn.getcwd()
                    end

                    term = require("toggleterm.terminal").Terminal:new({
                        id = 1,
                        direction = "horizontal",
                        dir = cwd,
                    })
                end
                term:toggle()
            end, { desc = "Toggle terminal" })
        end,
    },

    -- -------------------------------------------------------------------------
    -- Claude Code: coder/claudecode.nvim
    -- -------------------------------------------------------------------------
    {
        "coder/claudecode.nvim",
        dependencies = {
            "folke/snacks.nvim",
        },
        config = function()
            require("claudecode").setup({
                terminal = {
                    split_side = "right",
                    -- 50%: Claude panel takes half the screen width.
                    split_width_percentage = 0.5,
                    -- provider = "snacks": use snacks.nvim for terminal rendering.
                    provider = "snacks",
                    snacks_win_opts = {
                        wo = { winbar = "" },
                    },
                },
                diff_opts = {
                    -- open_in_new_tab: diff reviews open in a new tab, leaving the current
                    -- layout intact instead of inserting windows into the active split.
                    open_in_new_tab = true,
                    -- hide_terminal_in_new_tab: Claude panel is hidden in the diff tab
                    -- to reduce clutter (the diff is the focus there).
                    hide_terminal_in_new_tab = true,
                },
                -- focus_after_send: cursor moves into the Claude panel after <leader>cs
                -- so you can immediately continue the conversation.
                focus_after_send = true,
            })

            -- Keybindings (keeping <leader>c prefix)
            vim.keymap.set(
                { "n", "t" },
                "<leader>cc",
                "<cmd>ClaudeCode<cr>",
                { desc = "Toggle Claude Code" }
            )
            vim.keymap.set("v", "<leader>cs", function()
                vim.cmd("ClaudeCodeSend")
                vim.schedule(function()
                    vim.cmd("startinsert")
                end)
            end, { desc = "Send selection to Claude" })
            vim.keymap.set(
                "n",
                "<leader>cda",
                "<cmd>ClaudeCodeDiffAccept<cr>",
                { desc = "Accept Claude diff" }
            )
            vim.keymap.set(
                "n",
                "<leader>cdd",
                "<cmd>ClaudeCodeDiffDeny<cr>",
                { desc = "Deny Claude diff" }
            )
        end,
    },

    -- -------------------------------------------------------------------------
    -- Git: tpope/vim-fugitive
    -- -------------------------------------------------------------------------
    {
        "tpope/vim-fugitive",
        config = function()
            -- cd to the git root before :Git so fugitive always shows the full
            -- repository status, not a subdirectory. Necessary because the global
            -- cwd may differ from the buffer's git root (see CONTEXT RESOLVER).
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

    -- -------------------------------------------------------------------------
    -- Git Signs: lewis6991/gitsigns.nvim
    -- -------------------------------------------------------------------------
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

                -- expr = true: check vim.wo.diff at call time. When in a diff window
                -- (e.g. fugitive's Gdiffsplit), use Vim's native ]c/[c instead of
                -- gitsigns. Both tools share the same keys without conflict.
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

    -- -------------------------------------------------------------------------
    -- Comment toggling: numToStr/Comment.nvim  (default binds: gcc, gbc)
    -- -------------------------------------------------------------------------
    {
        "numToStr/Comment.nvim",
        opts = {},
    },

    -- -------------------------------------------------------------------------
    -- Surround: tpope/vim-surround  (default binds: ys, cs, ds)
    -- -------------------------------------------------------------------------
    "tpope/vim-surround",

    -- -------------------------------------------------------------------------
    -- Auto pairs: windwp/nvim-autopairs
    -- -------------------------------------------------------------------------
    {
        "windwp/nvim-autopairs",
        event = "InsertEnter",
        opts = {},
    },

    -- -------------------------------------------------------------------------
    -- Statusline: nvim-lualine/lualine.nvim
    -- -------------------------------------------------------------------------
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
                -- lualine_c: repo name (from git root basename) followed by filename.
                -- Shows which project you are in when editing across multiple repositories.
                lualine_c = {
                    {
                        function()
                            local ctx = get_buffer_context()
                            return ctx.git_root and " " .. vim.fn.fnamemodify(ctx.git_root, ":t")
                                or ""
                        end,
                        color = { fg = "#61afef" },
                    },
                    { "filename", path = 1 },
                },
                lualine_x = {},
                lualine_y = { "progress" },
            },
        },
    },

    -- -------------------------------------------------------------------------
    -- Which-key: folke/which-key.nvim
    -- -------------------------------------------------------------------------
    {
        "folke/which-key.nvim",
        event = "VeryLazy",
        opts = {
            delay = 300, -- Matches timeoutlen (set in BASIC SETTINGS).
        },
    },

    -- -------------------------------------------------------------------------
    -- LSP: neovim/nvim-lspconfig + mason + mason-lspconfig
    -- -------------------------------------------------------------------------
    -- mason: manages LSP server binaries.
    -- mason-lspconfig: bridges mason and lspconfig.
    -- fidget: progress spinner for background LSP operations.
    -- neodev: Neovim Lua API type hints when editing init.lua.
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

            -- Merge default capabilities with nvim-cmp's so the server knows the
            -- client supports snippet completion and label-detail fields.
            local capabilities = vim.lsp.protocol.make_client_capabilities()
            capabilities = vim.tbl_deep_extend(
                "force",
                capabilities,
                require("cmp_nvim_lsp").default_capabilities()
            )

            vim.api.nvim_create_autocmd("LspAttach", {
                group = vim.api.nvim_create_augroup("UserLspConfig", {}),
                callback = function(ev)
                    local opts = { buffer = ev.buf }
                    local builtin = require("telescope.builtin")

                    -- gd/gr/gi/gt: route through Telescope for a picker UI instead of the
                    -- default quickfix/location-list (harder to navigate at speed).
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
                        vim.lsp.inlay_hint.enable(false, { bufnr = ev.buf })
                    end

                    vim.keymap.set("n", "<leader>ih", function()
                        local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
                        vim.lsp.inlay_hint.enable(not enabled, { bufnr = 0 })
                    end, { buffer = ev.buf, desc = "Toggle inlay hints" })

                    -- Debug helper: shows which directory the LSP picked as the project root.
                    -- Useful to verify that clangd/pyright found the right compile_commands.json.
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

            -- vim.lsp.config() + vim.lsp.enable(): Neovim 0.10+ API, cleaner than the
            -- older require("lspconfig").clangd.setup() pattern.
            vim.lsp.config("clangd", {
                cmd = {
                    "clangd",
                    "--background-index", -- Build index in background for cross-TU go-to-def.
                    "--clang-tidy", -- Run clang-tidy checks as you edit.
                    "--header-insertion=iwyu", -- Suggest includes based on IWYU analysis.
                    "--completion-style=detailed", -- Show full parameter lists in completion items.
                    "--function-arg-placeholders=true", -- Insert placeholders on function completion.
                    "--inlay-hints",
                },
                capabilities = capabilities,
                filetypes = { "c", "cpp", "objc", "objcpp", "cuda", "proto" },
                -- root_markers: ordered list -- compile_commands.json takes precedence;
                -- .git is the final fallback for projects without a compilation database.
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

    -- -------------------------------------------------------------------------
    -- Autocompletion: hrsh7th/nvim-cmp
    -- -------------------------------------------------------------------------
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
                    -- select = true: confirm the first item even when nothing is explicitly
                    -- highlighted, so Enter always picks something when the menu is visible.
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
                -- Two source groups: group 1 (LSP, snippets, paths) has higher priority
                -- than group 2 (buffer words), so buffer completions don't crowd out LSP.
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

    -- conform.nvim -- explicit formatter, no auto-format on save
    -- <leader>f: format current buffer (or visual selection in visual mode).
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
            -- format_on_save = false: formatting is explicit via <leader>f. Avoids surprises
            -- when a formatter is misconfigured or slow.
            format_on_save = false,
        },
        keys = {
            {
                "<leader>f",
                -- lsp_fallback = false: only use the formatters listed above; no silent LSP fallback.
                function()
                    require("conform").format({ async = true, lsp_fallback = false })
                end,
                mode = { "n", "v" },
                desc = "Format buffer/selection",
            },
        },
    },

    -- okuuva/auto-save.nvim -- two-tier save strategy
    -- immediate_save (BufLeave/FocusLost): write right away when leaving the buffer
    --   or window focus is lost -- safety net so no work is lost unexpectedly.
    -- defer_save (InsertLeave/TextChanged): save after a debounce to avoid hammering
    --   disk on every keystroke.
    -- cancel_defered_save (InsertEnter): cancel the pending save when typing resumes,
    --   restarting the debounce timer.
    {
        "okuuva/auto-save.nvim",
        event = { "InsertLeave", "TextChanged" },
        opts = {
            enabled = true,
            -- execution_message disabled: no status-line noise on each save.
            execution_message = { enabled = false },
            trigger_events = {
                immediate_save = { "BufLeave", "FocusLost" },
                defer_save = { "InsertLeave", "TextChanged" },
                cancel_defered_save = { "InsertEnter" },
            },
            -- condition: only save real files (buftype == "") that are modifiable and named.
            -- Skips terminal buffers, scratch buffers, and unnamed new files.
            condition = function(buf)
                local bo = vim.bo[buf]
                return bo.buftype == "" and bo.modifiable and vim.fn.expand("%") ~= ""
            end,
            -- write_all_buffers = false: save only the current buffer on trigger.
            write_all_buffers = false,
            -- debounce_delay = 1000ms: wait 1 second of inactivity before writing on defer_save.
            debounce_delay = 1000,
        },
        keys = {
            { "<leader>as", ":ASToggle<CR>", desc = "Toggle auto-save" },
        },
    },

    -- folke/persistence.nvim -- session save/restore
    -- Saves and restores the buffer list, window layout, and cursor positions.
    {
        "folke/persistence.nvim",
        event = "BufReadPre",
        opts = {},
        init = function()
            local persistence = require("persistence")

            -- Auto-restore on startup
            vim.api.nvim_create_autocmd("VimEnter", {
                callback = function()
                    -- argc == 0: only restore when Neovim is opened with no arguments.
                    -- Opening with a file argument skips restore to avoid conflicting with
                    -- the explicitly requested file.
                    if vim.fn.argc() == 0 then
                        require("persistence").load({ last = true })
                        vim.schedule(function()
                            -- Force-reload each buffer to re-emit FileType events: persistence restores
                            -- buffers but does not trigger FileType, so treesitter highlighting is not
                            -- applied after restore. vim.cmd("edit") re-triggers FileType and fixes it.
                            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                                if
                                    vim.api.nvim_buf_is_loaded(buf)
                                    and vim.bo[buf].buftype == ""
                                then
                                    vim.api.nvim_buf_call(buf, function()
                                        vim.cmd("edit")
                                    end)
                                end
                            end
                        end)
                    end
                end,
            })

            -- Background timer: save the session every 30 seconds when changes have occurred.
            -- Ensures recovery is possible after a crash even without a clean :wq.
            -- dirty flag: only write when a buffer event has happened since the last save,
            -- avoiding unnecessary disk writes when Neovim is idle.
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
                    -- Stop recording the session first so the wiped state is not saved,
                    -- then close all buffers. Next startup starts fresh with an empty session.
                    require("persistence").stop()
                    vim.cmd("bufdo bwipeout | only | enew")
                end,
                desc = "Reset nvim",
            },
        },
    },
})
