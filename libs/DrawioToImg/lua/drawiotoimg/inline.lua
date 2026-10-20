local M = {}
local states = {}
local enabled = false
local plugin, options, plugin_dir, image
local original_find, wrapped_find
local rendering = {}
local generation = 0
local attached = false
local fences_ns = vim.api.nvim_create_namespace("drawiotoimg.fences")

-- Parse fences without requiring Treesitter, and ignore examples inside other fences.
function M.blocks(lines)
	local blocks, fences, fence, raw, list_indent = {}, {}, nil, nil, nil
	for row, line in ipairs(lines) do
		if not fence and not raw then
			local spaces = #(line:match("^ *") or "")
			if list_indent and line:find("%S") and spaces < list_indent then
				list_indent = nil
			end
			local leading, marker = line:match("^( *)([-+*]%s+)")
			if not marker then
				leading, marker = line:match("^( *)(%d+[.)]%s+)")
			end
			if marker then
				list_indent = list_indent or (#leading + #marker)
			end
		end
		local indent, marker, info = line:match("^( *)([`~]+)(.*)$")
		if
			not raw
			and marker
			and not list_indent
			and #indent <= 3
			and #marker >= 3
			and not marker:find("[^" .. marker:sub(1, 1) .. "]")
		then
			if not fence then
				local lang = vim.trim(info)
				fence = { first = row, marker = marker, lang = lang, indent = #indent }
			elseif marker:sub(1, 1) == fence.marker:sub(1, 1) and #marker >= #fence.marker and vim.trim(info) == "" then
				fences[#fences + 1] = { first = fence.first, last = row }
				if (fence.lang == "svg" or fence.lang == "drawio") and row > fence.first + 1 then
					local content = {}
					for i = fence.first + 1, row - 1 do
						content[#content + 1] = lines[i]:gsub("^" .. string.rep(" ", fence.indent), "", 1)
					end
					blocks[#blocks + 1] = {
						first = fence.first,
						last = row,
						content = table.concat(content, "\n"),
						ext = fence.lang == "svg" and ".svg" or ".drawio",
						fenced = true,
					}
				end
				fence = nil
			end
		elseif not fence and not list_indent then
			-- Only standalone SVG elements; do not consume surrounding prose or quoted examples.
			if not raw and line:match("^ ? ? ?<svg[%s>]") then
				raw = row
			end
			if raw and line:match("</svg>%s*$") then
				local content = table.concat(vim.list_slice(lines, raw, row), "\n")
				blocks[#blocks + 1] = { first = raw, last = row, content = content, ext = ".svg", fenced = false }
				raw = nil
			end
		end
	end
	if fence then
		fences[#fences + 1] = { first = fence.first, last = #lines }
	end
	return blocks, fences
end

local function settings()
	return plugin.settings()
end

function M.key(content, snapshot)
	snapshot = snapshot or settings()
	return vim.fn.sha256(
		content .. vim.inspect({ snapshot.command, snapshot.svg_command, snapshot.scale, snapshot.timeout })
	)
end

function M.bounds(buf)
	local width, height = 80, 40
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		local info = vim.fn.getwininfo(win)[1]
		-- Reserve sign/number columns and margins; Snacks fits the PNG proportionally.
		width = math.min(width, info.width - info.textoff - 2)
		height = math.min(height, info.height - 4)
	end
	return math.max(1, width), math.max(1, height)
end

local function clear(buf)
	require("drawiotoimg.scroll").detach(buf)
	local state = states[buf]
	if state then
		for _, placement in ipairs(state.placements) do
			placement:close()
		end
		for win, saved in pairs(state.windows) do
			if vim.api.nvim_win_is_valid(win) then
				if vim.wo[win].conceallevel == saved.applied_level then
					vim.wo[win].conceallevel = saved.level
				end
				if vim.wo[win].concealcursor == saved.applied_cursor then
					vim.wo[win].concealcursor = saved.cursor
				end
			end
		end
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_clear_namespace(buf, fences_ns, 0, -1)
		end
	end
	states[buf] = nil
end

local function editing(buf, blocks)
	local hidden = {}
	local current = vim.api.nvim_get_current_buf() == buf
	local row = current and vim.api.nvim_win_get_cursor(0)[1] or -1
	local mode = vim.api.nvim_get_mode().mode
	for index, block in ipairs(blocks) do
		local policy = options.inline_source_visible
		local reveal
		if type(policy) == "function" then
			reveal = policy(buf, block.first, block.last)
		end
		if reveal == nil then
			reveal = current
				and (mode:sub(1, 1) == "i" or mode:sub(1, 1) == "R")
				and row >= block.first
				and row <= block.last
		end
		if reveal then
			hidden[index] = true
		end
	end
	return hidden
end

function M.visibility(buf)
	local state = states[buf]
	if state and not vim.deep_equal(editing(buf, state.blocks), state.editing) then
		-- Remove placements entirely when editing, including any concealed lines.
		M.update(buf)
	end
end

function M.update(buf)
	if not enabled then
		return
	end
	if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
		return
	end
	if not options.inline_svg or not options.snacks or vim.bo[buf].filetype ~= "markdown" then
		clear(buf)
		return
	end
	local wins = vim.fn.win_findbuf(buf)
	if #wins == 0 then
		clear(buf)
		return
	end
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	local previous = states[buf]
	local blocks = previous and previous.tick == tick and previous.blocks or M.blocks(lines)
	local visible_source = editing(buf, blocks)
	local ok, snapshot = pcall(settings)
	if not ok then
		vim.notify("DrawioToImg: " .. tostring(snapshot), vim.log.levels.ERROR)
		return
	end
	local width, height = M.bounds(buf)
	local signature = vim.inspect({ tick, wins, width, height, visible_source, vim.o.background, M.key("", snapshot) })
	-- Keep extmarks and virtual rows stable while scrolling or revisiting a buffer.
	if previous and not previous.failed and previous.signature == signature then
		return
	end
	clear(buf)
	local state =
		{ placements = {}, windows = {}, blocks = blocks, editing = visible_source, tick = tick, signature = signature }
	states[buf] = state
	for index, block in ipairs(blocks) do
		if block.content ~= "" then
			local key = M.key(block.content, snapshot)
			local dir = vim.fn.stdpath("cache") .. "/drawiotoimg/inline"
			vim.fn.mkdir(dir, "p")
			local base = dir .. "/" .. key
			local theme = vim.o.background
			local function display(err)
				if err and states[buf] == state then
					state.failed = true
				end
				if err or states[buf] ~= state or not vim.api.nvim_buf_is_valid(buf) or state.editing[index] then
					return
				end
				if tick ~= vim.api.nvim_buf_get_changedtick(buf) or theme ~= vim.o.background then
					return
				end
				require("drawiotoimg.scroll").attach(buf)
				-- Conceal must remain active on the cursor line in normal mode.
				-- Restore the user's window settings when source editing resumes or we detach.
				for _, win in ipairs(vim.fn.win_findbuf(buf)) do
					if not state.windows[win] then
						local level, cursor = vim.wo[win].conceallevel, vim.wo[win].concealcursor
						local applied_level = math.max(2, level)
						local applied_cursor = cursor:find("n", 1, true) and cursor or cursor .. "n"
						state.windows[win] = {
							level = level,
							cursor = cursor,
							applied_level = applied_level,
							applied_cursor = applied_cursor,
						}
						vim.wo[win].conceallevel, vim.wo[win].concealcursor = applied_level, applied_cursor
					end
				end
				for _, row in ipairs(block.fenced and { block.first, block.last } or {}) do
					vim.api.nvim_buf_set_extmark(buf, fences_ns, row - 1, 0, { end_col = #lines[row], conceal = "" })
				end
				local width, height = M.bounds(buf)
				local placement = image.placement.new(buf, plugin.output(base .. block.ext), {
					pos = { block.first + (block.fenced and 1 or 0), 0 },
					-- Fence delimiters may have conceal_lines from Markdown highlighting.
					-- Anchor and reserve image rows on visible content instead.
					range = {
						block.first + (block.fenced and 1 or 0),
						0,
						block.last - (block.fenced and 1 or 0),
						#lines[block.last - (block.fenced and 1 or 0)],
					},
					inline = true,
					conceal = true,
					type = "chart",
					max_width = width,
					max_height = height,
				})
				state.placements[#state.placements + 1] = placement
			end
			if vim.fn.filereadable(plugin.output(base .. block.ext)) == 1 then
				display()
			else
				if vim.fn.filereadable(base .. block.ext) == 0 then
					vim.fn.writefile(vim.split(block.content, "\n"), base .. block.ext)
				end
				if rendering[base] then
					rendering[base][#rendering[base] + 1] = display
				else
					rendering[base] = { display }
					plugin.render(base .. block.ext, function(err)
						local callbacks = rendering[base] or {}
						rendering[base] = nil
						for _, callback in ipairs(callbacks) do
							callback(err)
						end
					end, snapshot)
				end
			end
		end
	end
end

function M.stop()
	enabled = false
	attached = false
	generation = generation + 1
	pcall(vim.api.nvim_del_augroup_by_name, "DrawioToImgInline")
	for buf in pairs(states) do
		clear(buf)
	end
	if image and image.doc.find == wrapped_find then
		image.doc.find = original_find
		original_find, wrapped_find = nil, nil
	end
end

local function update()
	generation = generation + 1
	local current = generation
	vim.defer_fn(function()
		if not enabled or current ~= generation then
			return
		end
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			M.update(buf)
		end
	end, 150)
end

-- Markdown fenced examples can have their own injected parser. Snacks sees
-- image links in those injected trees as ordinary document images.
function M.filter(buf, matches)
	if not options.snacks or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "markdown" then
		return matches
	end
	local blocks, fences = M.blocks(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
	return vim.tbl_filter(function(match)
		local range = match.range
		if not range then
			return true
		end
		for _, fence in ipairs(fences) do
			if range[1] >= fence.first and range[1] <= fence.last then
				-- Preserve native charts that span their own top-level fence (e.g. math
				-- and Mermaid), but never image links or nested charts inside examples.
				if match.type == "image" or range[1] > fence.first then
					return false
				end
			end
		end
		if options.inline_svg then
			for _, block in ipairs(blocks) do
				-- Also own Snacks' HTML match for raw SVG, avoiding duplicate placements.
				if range[1] >= block.first and range[3] <= block.last then
					return false
				end
			end
		end
		return true
	end, matches)
end

function M.setup(renderer, opts, root, backend)
	if image ~= backend then
		M.stop()
		original_find, wrapped_find = nil, nil
	end
	plugin, options, plugin_dir, image = renderer, opts, root, backend
	if not opts.snacks then
		M.stop()
		return
	end
	-- Keep Snacks previews for blocks and document types this module cannot handle.
	-- Another plugin may wrap our finder. Keep our existing wrapper in that chain.
	if not wrapped_find then
		original_find = image.doc.find
		local previous = original_find
		wrapped_find = function(buf, callback, find_opts)
			return previous(buf, function(matches)
				callback(M.filter(buf, matches))
			end, find_opts)
		end
		image.doc.find = wrapped_find
	end
	if not opts.inline_svg then
		enabled, attached = false, false
		generation = generation + 1
		pcall(vim.api.nvim_del_augroup_by_name, "DrawioToImgInline")
		for buf in pairs(states) do
			clear(buf)
		end
		return
	end
	enabled = true
	if attached then
		update()
		return
	end
	attached = true
	local group = vim.api.nvim_create_augroup("DrawioToImgInline", { clear = true })
	vim.api.nvim_create_autocmd({
		"BufEnter",
		"BufWinEnter",
		"FileType",
		"TextChanged",
		"TextChangedI",
		"BufWritePost",
		"WinResized",
		"ColorScheme",
	}, { group = group, callback = update })
	vim.api.nvim_create_autocmd("OptionSet", { group = group, pattern = "background", callback = update })
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
		group = group,
		callback = function()
			M.visibility(vim.api.nvim_get_current_buf())
		end,
	})
	vim.api.nvim_create_autocmd({ "BufWipeout", "BufWinLeave" }, {
		group = group,
		callback = function(ev)
			clear(ev.buf)
			update()
		end,
	})
	update()
end

return M
