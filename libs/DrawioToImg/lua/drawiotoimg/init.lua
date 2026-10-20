local M = {}
local uv = vim.uv
local plugin_dir = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))
local options = {
	command = "drawio",
	svg_command = "rsvg-convert",
	auto_render = true,
	snacks = true,
	inline_svg = true,
	inline_fences = false,
	scale = 2,
	timeout = 120000,
}
local pending, queue, active = {}, {}, false

function M.settings()
	local snapshot = vim.deepcopy(options)
	if
		snapshot.command == "drawio"
		and vim.fn.executable("drawio") == 0
		and vim.fn.executable("/Applications/draw.io.app/Contents/MacOS/draw.io") == 1
	then
		snapshot.command = "/Applications/draw.io.app/Contents/MacOS/draw.io"
	end
	return snapshot
end

function M.supported(path)
	return path:match("%.drawio$")
		or path:match("%.drawio%.svg$")
		or (
			path:match("%.svg$")
			and path:match("/diagrams/")
			and vim.fn.filereadable((path:gsub("%.svg$", ".mmd"))) == 0
		)
end

function M.output(path)
	-- Preserve .drawio in the output name so diagram.svg and diagram.drawio never collide.
	return path:match("%.svg$") and path:gsub("%.svg$", ".png") or path .. ".png"
end

function M.refresh()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if
			vim.api.nvim_buf_is_loaded(buf)
			and vim.bo[buf].filetype == "markdown"
			and vim.b[buf].snacks_image_attached
		then
			-- Refresh only Snacks' image observer, never scroll animations or other plugins.
			local group = "snacks.image.inline." .. buf
			if vim.fn.exists("#" .. group .. "#WinScrolled") == 1 then
				vim.api.nvim_exec_autocmds("WinScrolled", { group = group, buffer = buf, modeline = false })
			end
		end
	end
end

-- Resolve symlink chains before naming cached PNGs. Chained resolvers must not
-- keep appending cache prefixes to a basename on every refresh.
function M.cache_png(path)
	if path:match("^%a[%w+.-]*:") or not path:lower():match("%.png$") then
		return path
	end
	local source = uv.fs_realpath(path)
	local stat = source and uv.fs_stat(source)
	if not stat or stat.type ~= "file" then
		return path
	end
	local cache = vim.fn.stdpath("cache") .. "/drawiotoimg"
	local version = vim.fn.sha256(source .. stat.mtime.sec .. stat.mtime.nsec .. stat.size)
	local cached = cache .. "/" .. version .. ".png"
	if not uv.fs_stat(cached) then
		vim.fn.mkdir(cache, "p")
		if not uv.fs_symlink(source, cached) then
			return source
		end
	end
	return cached
end

-- Only claim our source files; other resolvers (including MmdToImg) retain ownership.
local resolving = {}
function M.resolve(file, src)
	if src:match("^%a[%w+.-]*:") or src:sub(1, 2) == "//" then
		return
	end
	local path = vim.fs.normalize(src:sub(1, 1) == "/" and src or vim.fs.dirname(file) .. "/" .. src)
	if not M.supported(path) or vim.fn.filereadable(path) ~= 1 then
		return
	end
	local output = M.output(path)
	local stat, source = uv.fs_stat(output), uv.fs_stat(path)
	if
		(
			not stat
			or stat.mtime.sec < source.mtime.sec
			or (stat.mtime.sec == source.mtime.sec and stat.mtime.nsec < source.mtime.nsec)
		) and not resolving[path]
	then
		resolving[path] = true
		M.render(path, function()
			resolving[path] = nil
		end)
	end
	if not stat then
		return
	end
	return M.cache_png(output)
end

-- Attach after Snacks loads without requiring it for users who do not install it.
local snacks_resolver, resolver_backend
function M.attach_snacks()
	local snacks = package.loaded["snacks"]
	if not options.snacks or not snacks or not snacks.did_setup then
		return
	end
	snacks.config.image.enabled = true
	local image = snacks.image
	image.config.enabled = true
	image.config.doc.enabled = true
	require("drawiotoimg.inline").setup(M, options, plugin_dir, image)
	if resolver_backend ~= image then
		local previous = image.config.resolve
		snacks_resolver = function(file, src)
			local resolved = (options.snacks and M.resolve(file, src)) or (previous and previous(file, src) or nil)
			return resolved and M.cache_png(resolved) or nil
		end
		resolver_backend = image
		image.config.resolve = snacks_resolver
		snacks.config.image.resolve = snacks_resolver
	end
	image.setup()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "markdown" then
			image.doc.attach(buf)
		end
	end
end

local run_next
local function render(job, finish)
	local temp = vim.fn.tempname()
	local settings = job.settings
	local output = M.output(job.path)
	local function done(err)
		vim.fn.delete(temp, "rf")
		if err then
			vim.notify("DrawioToImg: " .. err, vim.log.levels.ERROR)
		else
			M.refresh()
		end
		finish(err)
	end
	local ok, err = pcall(function()
		vim.fn.mkdir(temp, "p")
		local ext = job.path:match("%.drawio%.svg$") and ".drawio.svg"
			or (job.path:match("%.drawio$") and ".drawio" or ".svg")
		local input = temp .. "/source" .. ext
		assert(uv.fs_copyfile(job.path, input))
		local png = temp .. "/output.png"
		local args
		if ext == ".svg" then
			args = { settings.svg_command, "--format=png", "--zoom=" .. settings.scale, "--output=" .. png, input }
		else
			args = {
				settings.command,
				"--export",
				"--format",
				"png",
				"--scale",
				tostring(settings.scale),
				"--output",
				png,
				input,
			}
		end
		vim.system(args, { text = true, timeout = settings.timeout }, function(result)
			vim.schedule(function()
				if result.code ~= 0 then
					done(
						(result.stderr ~= "" and result.stderr or result.stdout or "Renderer failed")
							.. " (exit "
							.. result.code
							.. ")"
					)
					return
				end
				local published, publish_err = pcall(function()
					local data = assert(io.open(png, "rb"))
					local signature = data:read(8)
					data:close()
					assert(signature == "\137PNG\13\10\26\10", "Renderer did not produce a PNG")
					-- Stage beside destination: rename is atomic even when cache and project use different volumes.
					local stage = output .. "." .. vim.fn.sha256(temp):sub(1, 12) .. ".tmp"
					assert(uv.fs_copyfile(png, stage))
					local renamed, rename_err = uv.fs_rename(stage, output)
					if not renamed then
						uv.fs_unlink(stage)
						error(rename_err)
					end
				end)
				done(not published and tostring(publish_err) or nil)
			end)
		end)
	end)
	if not ok then
		done(tostring(err))
	end
end

run_next = function()
	if active or #queue == 0 then
		return
	end
	active = true
	local job = table.remove(queue, 1)
	pending[job.path] = nil
	render(job, function(err)
		active = false
		for _, callback in ipairs(job.callbacks) do
			local ok, callback_err = pcall(callback, err)
			if not ok then
				vim.notify("DrawioToImg: " .. tostring(callback_err), vim.log.levels.ERROR)
			end
		end
		run_next()
	end)
end

function M.render(path, callback, settings)
	path = vim.fs.normalize(vim.fn.fnamemodify(path or vim.api.nvim_buf_get_name(0), ":p"))
	if not (M.supported(path) or path:match("%.svg$")) or vim.fn.filereadable(path) ~= 1 then
		error("DrawioToImg requires an existing .drawio or .svg file: " .. path)
	end
	settings = settings or M.settings()
	local job = pending[path]
	if not job then
		job = { path = path, callbacks = {} }
		pending[path] = job
		queue[#queue + 1] = job
	end
	job.settings = settings
	if callback then
		job.callbacks[#job.callbacks + 1] = callback
	end
	run_next()
end

function M.render_all(dir, callback)
	dir = vim.fn.fnamemodify(dir or vim.fs.root(0, ".git") or uv.cwd(), ":p")
	local files = {}
	local excluded = { [".git"] = true, node_modules = true, target = true, [".cache"] = true }
	local function scan(path)
		for name, kind in vim.fs.dir(path) do
			local child = path .. "/" .. name
			if kind == "directory" and not excluded[name] then
				scan(child)
			elseif kind == "file" and M.supported(child) then
				files[#files + 1] = child
			end
		end
	end
	scan(dir)
	table.sort(files)
	local remaining, failures = #files, {}
	if remaining == 0 then
		if callback then
			callback(nil, 0)
		end
		return
	end
	for _, file in ipairs(files) do
		M.render(file, function(err)
			if err then
				failures[#failures + 1] = file .. ": " .. err
			end
			remaining = remaining - 1
			if remaining == 0 and callback then
				callback(#failures > 0 and table.concat(failures, "\n") or nil, #files)
			end
		end)
	end
end

function M.setup(opts)
	local updated = vim.tbl_extend("force", options, opts or {})
	assert(type(updated.scale) == "number" and updated.scale > 0, "scale must be positive")
	assert(type(updated.timeout) == "number" and updated.timeout > 0, "timeout must be positive")
	options = updated
	if not options.snacks then
		local inline = package.loaded["drawiotoimg.inline"]
		if inline then
			inline.stop()
		end
	end
	vim.api.nvim_create_user_command("DrawioToImg", function(args)
		M.render(args.args ~= "" and args.args or nil)
	end, { nargs = "?", complete = "file", force = true })
	vim.api.nvim_create_user_command("DrawioToImgAll", function(args)
		M.render_all(args.args ~= "" and args.args or nil, function(err, count)
			if not err then
				vim.notify("DrawioToImg: rendered " .. count .. " diagrams")
			end
		end)
	end, { nargs = "?", complete = "dir", force = true })
	local group = vim.api.nvim_create_augroup("DrawioToImg", { clear = true })
	if options.auto_render then
		vim.api.nvim_create_autocmd("BufWritePost", {
			group = group,
			pattern = { "*.drawio", "*.svg" },
			callback = function(ev)
				if M.supported(ev.file) then
					M.render(ev.file)
				end
			end,
		})
	end
	vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "ColorScheme", "VimEnter" }, {
		group = group,
		callback = function()
			M.attach_snacks()
			M.refresh()
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = { "LazyLoad", "VeryLazy" },
		callback = M.attach_snacks,
	})
	M.attach_snacks()
	vim.api.nvim_create_autocmd("OptionSet", {
		group = group,
		pattern = "background",
		callback = function()
			vim.schedule(M.refresh)
		end,
	})
end

return M
