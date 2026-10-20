-- Neovim loads this entry point from the repository root.
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))
local library = root .. "/libs/DrawioToImg"
vim.opt.runtimepath:append(library)
return assert(loadfile(library .. "/lua/drawiotoimg/init.lua"))()
