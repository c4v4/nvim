-- ============================================================================
-- BASIC SETTINGS
-- ============================================================================
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Disable netrw (conflicts with fugitive)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

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
vim.opt.hlsearch = false
vim.opt.incsearch = true

-- Indentation
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Editing
vim.opt.wrap = false
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
vim.keymap.set("n", "<leader>x", ":bdelete<CR>", { desc = "Close buffer" })

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
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		opts = {
			ensure_installed = {
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
			},
			auto_install = true,
			highlight = {
				enable = true,
				additional_vim_regex_highlighting = false,
			},
			indent = { enable = true },
			incremental_selection = {
				enable = true,
				keymaps = {
					init_selection = "<CR>",
					node_incremental = "<CR>",
					node_decremental = "<BS>",
					scope_incremental = "<TAB>",
				},
			},
		},
		config = function(_, opts)
			require("nvim-treesitter.configs").setup(opts)
		end,
	},

	-- Fuzzy Finder
	{
		"nvim-telescope/telescope.nvim",
		branch = "0.1.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			{
				"nvim-telescope/telescope-fzf-native.nvim",
				build = "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release",
			},
		},
		config = function()
			local telescope = require("telescope")
			local actions = require("telescope.actions")
			local action_state = require("telescope.actions.state")
			local finders = require("telescope.finders")
			local pickers = require("telescope.pickers")
			local builtin = require("telescope.builtin")
			local conf = require("telescope.config").values

			-- Shared scope navigation mappings
			local function scope_nav_mappings(scope_var, reopen_fn)
				local buffer_dir = get_buffer_context().dir
				return function(prompt_bufnr, map)
					local function get_query()
						return action_state.get_current_picker(prompt_bufnr):_get_prompt()
					end

					local function reopen_with(new_scope)
						local query = get_query()
						actions.close(prompt_bufnr)
						vim.schedule(function()
							reopen_fn(new_scope, query)
						end)
					end

					-- Ctrl-u: up one level
					map("i", "<C-u>", function()
						local parent = vim.fn.fnamemodify(scope_var, ":h")
						if parent == scope_var then
							vim.notify("Already at filesystem root", vim.log.levels.WARN)
							return
						end
						reopen_with(parent)
					end)

					-- Ctrl-d: down to buffer directory
					map("i", "<C-d>", function()
						if buffer_dir == scope_var then
							vim.notify("Already at buffer directory", vim.log.levels.WARN)
							return
						end

						local parent = vim.fn.fnamemodify(buffer_dir, ":h")
						while parent ~= scope_var and parent ~= buffer_dir do
							buffer_dir = parent
							parent = vim.fn.fnamemodify(buffer_dir, ":h")
						end

						if parent == buffer_dir then
							vim.notify("Buffer is not under current scope", vim.log.levels.WARN)
							return
						end

						reopen_with(buffer_dir)
					end)

					return true
				end
			end

			-- Smart file finder with scope expansion
			local current_file_scope = nil
			local function smart_find_files(scope, query)
				current_file_scope = scope
				local find_command = vim.fn.executable("fd") == 1
						and {
							"fd",
							"--type",
							"f",
							"--hidden",
							"--no-ignore-vcs",
							"--exclude",
							".git",
							"--exclude",
							"build",
						}
					or nil

				builtin.find_files({
					cwd = scope,
					find_command = find_command,
					default_text = query or "",
					prompt_title = "📁" .. vim.fn.fnamemodify(scope, ":~"),
					attach_mappings = scope_nav_mappings(current_file_scope, smart_find_files),
				})
			end

			-- Smart live grep with scope expansion and filtering
			local current_grep_scope = nil
			local grep_filters = { include = {}, exclude = {} }

			local function format_filter_display()
				local parts = {}
				if #grep_filters.include > 0 then
					table.insert(parts, "+" .. table.concat(grep_filters.include, " +"))
				end
				if #grep_filters.exclude > 0 then
					table.insert(parts, "-" .. table.concat(grep_filters.exclude, " -"))
				end
				return #parts > 0 and " [" .. table.concat(parts, " ") .. "]" or ""
			end

			local function build_glob_args()
				local args = {}
				for _, pattern in ipairs(grep_filters.include) do
					table.insert(args, "--glob")
					table.insert(args, pattern)
				end
				for _, pattern in ipairs(grep_filters.exclude) do
					table.insert(args, "--glob")
					table.insert(args, "!" .. pattern)
				end
				return args
			end

			local function smart_live_grep(scope, query)
				current_grep_scope = scope
				local additional_args = build_glob_args()
				local filter_display = format_filter_display()

				builtin.live_grep({
					cwd = scope,
					default_text = query or "",
					prompt_title = "🔍 " .. vim.fn.fnamemodify(scope, ":~") .. filter_display,
					additional_args = function()
						return additional_args
					end,
					attach_mappings = function(prompt_bufnr, map)
						scope_nav_mappings(current_grep_scope, smart_live_grep)(prompt_bufnr, map)

						-- <C-f>: Add filters
						map("i", "<C-f>", function()
							local filter_input = vim.fn.input("Filter (+include -exclude): ")
							if filter_input == "" then
								return
							end

							grep_filters = { include = {}, exclude = {} }
							for token in filter_input:gmatch("%S+") do
								if token:sub(1, 1) == "+" then
									table.insert(grep_filters.include, token:sub(2))
								elseif token:sub(1, 1) == "-" then
									table.insert(grep_filters.exclude, token:sub(2))
								else
									table.insert(grep_filters.include, token)
								end
							end

							local current_query = action_state.get_current_picker(prompt_bufnr):_get_prompt()
							actions.close(prompt_bufnr)
							vim.schedule(function()
								smart_live_grep(current_grep_scope, current_query)
							end)
						end)

						-- <C-x>: Clear filters
						map("i", "<C-x>", function()
							grep_filters = { include = {}, exclude = {} }
							local current_query = action_state.get_current_picker(prompt_bufnr):_get_prompt()
							actions.close(prompt_bufnr)
							vim.schedule(function()
								smart_live_grep(current_grep_scope, current_query)
							end)
						end)

						return true
					end,
				})
			end

			-- Two-stage picker: directory → file
			local current_dir_scope = nil
			local function show_dirs(scope, query)
				current_dir_scope = scope
				local dirs = vim.fn.systemlist(
					"fd --type d --max-depth 3 --hidden --exclude .git --exclude node_modules --exclude Library --exclude .cache --exclude .Trash . "
						.. vim.fn.shellescape(scope)
				)

				pickers
					.new({}, {
						prompt_title = "📁 " .. vim.fn.fnamemodify(scope, ":~"),
						default_text = query or "",
						finder = finders.new_table({
							results = dirs,
							entry_maker = function(entry)
								local rel = entry:gsub(vim.pesc(scope), ".")
								return { value = entry, display = rel, ordinal = rel }
							end,
						}),
						sorter = conf.generic_sorter({}),
						previewer = require("telescope.previewers").new_termopen_previewer({
							get_command = function(entry)
								return { "ls", "-lah", "--color=always", entry.value }
							end,
						}),
						attach_mappings = function(prompt_bufnr, map)
							actions.select_default:replace(function()
								local selection = action_state.get_selected_entry()
								actions.close(prompt_bufnr)
								vim.schedule(function()
									smart_find_files(selection.value)
								end)
							end)
							return scope_nav_mappings(current_dir_scope, show_dirs)(prompt_bufnr, map)
						end,
					})
					:find()
			end

			local function two_stage_find()
				show_dirs(get_smart_cwd())
			end

			-- Telescope setup
			telescope.setup({
				defaults = {
					mappings = {
						i = {
							["<esc>"] = actions.close,
							["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
						},
						n = {
							["q"] = actions.close,
							["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
						},
					},
					path_display = { "smart" },
					file_ignore_patterns = {
						"%.git/",
						"node_modules/",
						"build/",
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
			})

			pcall(telescope.load_extension, "fzf")

			-- Helper wrappers for context-aware pickers
			local function with_context(fn)
				return function()
					fn(get_smart_cwd())
				end
			end

			local function with_cwd(telescope_fn)
				return function()
					telescope_fn({ cwd = get_smart_cwd() })
				end
			end

			-- PRIMARY KEYMAPS
			vim.keymap.set("n", "<C-p>", with_context(smart_find_files), { desc = "Find files" })
			vim.keymap.set("n", "<C-S-p>", two_stage_find, { desc = "Find files (dir → file)" })

			-- SEARCH NAMESPACE (leader-s)
			vim.keymap.set("n", "<leader>sr", builtin.resume, { desc = "Resume search" })
			vim.keymap.set("n", "<leader>sf", with_context(smart_find_files), { desc = "Search files" })
			vim.keymap.set("n", "<leader>sg", with_context(smart_live_grep), { desc = "Search grep" })
			vim.keymap.set("n", "<leader>sw", with_cwd(builtin.grep_string), { desc = "Search word" })
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
			vim.keymap.set("n", "<leader>st", builtin.colorscheme, { desc = "Search themes" })

			-- QUICK ACCESS
			vim.keymap.set("n", "<leader>/", with_context(smart_live_grep), { desc = "Grep (quick)" })
			vim.keymap.set("n", "<leader>*", with_cwd(builtin.grep_string), { desc = "Grep word under cursor" })
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
			open_mapping = [[<C-\\>]],
			hide_numbers = true,
			shade_terminals = false,
			start_in_insert = true,
			direction = "horizontal",
			close_on_exit = true,
			shell = vim.o.shell,
		},
		config = function(_, opts)
			require("toggleterm").setup(opts)

			-- Single terminal instance, reused across all directories
			local term = nil

			vim.keymap.set({ "n", "t" }, "<C-\\>", function()
				if not term then
					term = require("toggleterm.terminal").Terminal:new({ dir = get_smart_cwd() })
				end
				term:toggle()
			end, { desc = "Toggle terminal" })
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
				vim.cmd("cd " .. ctx.git_root)
				vim.cmd("Git")
			end, { desc = "Git status" })

			-- Git diff (buffer context aware)
			vim.keymap.set("n", "<leader>gd", function()
				local ctx = get_buffer_context()
				if ctx.git_root then
					vim.cmd("cd " .. ctx.git_root)
				end
				vim.cmd("Gdiffsplit")
			end, { desc = "Git diff" })

			-- Standard git commands
			vim.keymap.set("n", "<leader>gl", ":Git log<CR>", { desc = "Git log" })
			vim.keymap.set("n", "<leader>gb", ":Git blame<CR>", { desc = "Git blame" })
		end,
	},

	-- Git signs (inline diff markers)
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
					vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)

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
						persistence.load({ last = true })
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

-- Reload treesitter since sometimes it gets messed up by persistent auto-load
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		if vim.fn.argc() == 0 then
			require("persistence").load({ last = true })
			vim.schedule(function()
				vim.cmd("doautocmd BufRead")
			end)
		end
	end,
})
