vim.opt.runtimepath:prepend(vim.fn.getcwd())
local plugin = require("drawiotoimg")
local inline = require("drawiotoimg.inline")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. "/diagrams", "p")
local svg =
	'<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="40" height="20" fill="red"/></svg>'
local function write(path, text)
	vim.fn.writefile(vim.split(text, "\n"), path)
end
local function render(path, settings)
	local done, err = false, nil
	plugin.render(path, function(e)
		done, err = true, e
	end, settings)
	assert(
		vim.wait(10000, function()
			return done
		end),
		"render timed out"
	)
	return err
end
local function png(path)
	local f = assert(io.open(path, "rb"))
	local bytes = f:read(8)
	f:close()
	assert(bytes == "\137PNG\13\10\26\10", path)
end
local ok, err = xpcall(function()
	plugin.setup({ snacks = false, svg_command = os.getenv("RSVG_CONVERT") or "rsvg-convert" })
	write(temp .. "/diagrams/test.svg", svg)
	assert(not render(temp .. "/diagrams/test.svg"))
	png(temp .. "/diagrams/test.png")
	assert(plugin.resolve(temp .. "/README.md", "diagrams/test.svg"))
	assert(not plugin.resolve(temp .. "/README.md", "https://example.com/diagrams/test.svg"))
	assert(not plugin.resolve(temp .. "/README.md", "other.svg"))
	assert(plugin.output("foo.drawio") == "foo.drawio.png")
	assert(plugin.output("foo.drawio.svg") == "foo.drawio.png")
	-- Fake only the unavailable desktop executable. Verify argument boundaries and source snapshot.
	local fake = temp .. "/fake drawio"
	write(
		fake,
		'#!/usr/bin/env python3\nimport sys, pathlib, base64\na=sys.argv[1:]\nassert a[:6] == ["--export", "--format", "png", "--scale", "2", "--output"]\nassert pathlib.Path(a[-1]).read_text().strip() == "<mxfile/>"\npathlib.Path(a[6]).write_bytes(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jMZkAAAAASUVORK5CYII="))'
	)
	vim.uv.fs_chmod(fake, 493)
	plugin.setup({ command = fake })
	for _, ext in ipairs({ ".drawio", ".drawio.svg" }) do
		local path = temp .. "/diagrams/a space" .. ext
		write(path, "<mxfile/>")
		assert(not render(path))
		png(plugin.output(path))
	end
	local old = table.concat(vim.fn.readfile(temp .. "/diagrams/test.png", "b"), "\n")
	local settings = plugin.settings()
	settings.svg_command = "/usr/bin/false"
	local notify = vim.notify
	vim.notify = function() end
	assert(render(temp .. "/diagrams/test.svg", settings))
	vim.notify = notify
	assert(old == table.concat(vim.fn.readfile(temp .. "/diagrams/test.png", "b"), "\n"), "failure overwrote output")
	local blocks = inline.blocks({ "```text", svg, "```", "```svg", svg, "```", svg, "~~~drawio", "<mxfile/>", "~~~" })
	assert(#blocks == 3 and blocks[1].fenced and not blocks[2].fenced and blocks[3].ext == ".drawio")
	assert(#inline.blocks({ "- example", "  ```svg", "  " .. svg, "  ```" }) == 0)
	assert(#inline.blocks({ "```svg", svg }) == 0)
	-- Mermaid SVG links must stay with MmdToImg's theme resolver.
	write(temp .. "/diagrams/mermaid.svg", svg)
	write(temp .. "/diagrams/mermaid.mmd", "flowchart LR; A-->B")
	assert(not plugin.supported(temp .. "/diagrams/mermaid.svg"))
	-- Saving a diagram should render without calling the public render function.
	local saved = temp .. "/saved.drawio"
	vim.cmd.enew()
	vim.api.nvim_buf_set_name(0, saved)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "<mxfile/>" })
	vim.cmd.write()
	assert(
		vim.wait(10000, function()
			return vim.fn.filereadable(plugin.output(saved)) == 1
		end),
		"save did not render"
	)
	vim.cmd.bdelete()
	vim.fn.delete(saved)
	vim.fn.delete(plugin.output(saved))
	-- Directory exclusions and standalone SVG policy.
	vim.fn.mkdir(temp .. "/node_modules", "p")
	write(temp .. "/node_modules/skip.drawio", "<mxfile/>")
	write(temp .. "/outside.svg", svg)
	local finished, count, failure = false
	plugin.render_all(temp, function(e, n)
		finished, failure, count = true, e, n
	end)
	assert(vim.wait(10000, function()
		return finished
	end))
	assert(not failure, failure)
	assert(count == 3, "scan count: " .. tostring(count))
	-- Actual editor lifecycle with a synthetic display backend.
	local active, created = 0, 0
	local image = {
		config = { doc = {} },
		setup = function() end,
		doc = {
			attach = function() end,
			find = function(_, cb)
				cb({})
			end,
		},
		placement = {},
	}
	image.placement.new = function(_, src)
		png(src)
		active = active + 1
		created = created + 1
		return {
			close = function()
				active = active - 1
			end,
		}
	end
	package.loaded.snacks = { did_setup = true, config = { image = {} }, image = image }
	plugin.setup({ snacks = true, inline_svg = true })
	vim.cmd.enew()
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "```svg", svg, "```" })
	vim.bo[buf].filetype = "markdown"
	assert(
		vim.wait(10000, function()
			return active == 1
		end),
		"automatic inline preview missing"
	)
	local before = created
	inline.update(buf)
	assert(created == before, "unchanged placement recreated")
	local mode = vim.api.nvim_get_mode
	vim.api.nvim_get_mode = function()
		return { mode = "i" }
	end
	vim.api.nvim_win_set_cursor(0, { 2, 0 })
	inline.visibility(buf)
	assert(active == 0)
	vim.api.nvim_get_mode = mode
	inline.visibility(buf)
	assert(active == 1)
	plugin.setup({ inline_svg = false })
	assert(active == 0)
	assert(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[2] == svg, "source changed")
	vim.api.nvim_buf_delete(buf, { force = true })
	package.loaded.snacks = nil
end, debug.traceback)
inline.stop()
vim.fn.delete(temp, "rf")
assert(ok, err)
print("DrawioToImg: rendering, rollback, scanning, resolver, parsing and editor lifecycle passed")
vim.cmd.qa({ bang = true })
