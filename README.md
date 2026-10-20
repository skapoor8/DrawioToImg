# DrawioToImg

Render Draw.io diagrams and inline SVG in Neovim. Based on [MmdToImg](https://github.com/skapoor8/MmdToImg), with optional Snacks image previews.

## Prerequisites

- Neovim 0.10 or later.
- [Draw.io Desktop](https://github.com/jgraph/drawio-desktop) for `.drawio` and `.drawio.svg` files, with `drawio` on your PATH. On macOS the plugin also detects `/Applications/draw.io.app/Contents/MacOS/draw.io`.
- `rsvg-convert` from [librsvg](https://gnome.pages.gitlab.gnome.org/librsvg/) for plain SVG and inline SVG. Install with `brew install librsvg` on macOS or `sudo apt install librsvg2-bin` on Debian/Ubuntu.
- Optional previews: [snacks.nvim](https://github.com/folke/snacks.nvim), Markdown and Markdown-inline Treesitter parsers, and a supported terminal such as Kitty or Ghostty.

Draw.io Desktop may require a graphical session. For headless Linux, configure `command` to a wrapper that runs `xvfb-run -a drawio "$@"`.

## Installation

### lazy.nvim

The plugin lives in `libs/DrawioToImg`. Add that directory to Neovim’s runtime path before you call `setup()`. The runtime path is the list of directories that Neovim searches for plugins.

Add this plugin specification:

```lua
{
  "skapoor8/DrawioToImg",
  lazy = false,
  opts = {},
  config = function(plugin, opts)
    vim.opt.runtimepath:append(plugin.dir .. "/libs/DrawioToImg")
    require("drawiotoimg").setup(opts)
  end,
}
```

### vim-plug

Add the plugin to your vim-plug block and run `:PlugInstall`:

```vim
call plug#begin(stdpath('data') . '/plugged')
Plug 'skapoor8/DrawioToImg', { 'tag': '*' }
call plug#end()
```

After `plug#end()`, configure the plugin:

```lua
local root = vim.fn.stdpath("data") .. "/plugged/DrawioToImg"
vim.opt.runtimepath:append(root .. "/libs/DrawioToImg")
require("drawiotoimg").setup()
```

If you use a different vim-plug installation directory, change `root` to match it.

### Native Git packages

Clone the plugin into Neovim's package directory:

```sh
git clone --depth 1 https://github.com/skapoor8/DrawioToImg.git \
  ~/.local/share/nvim/site/pack/plugins/start/DrawioToImg
```

Add this to your Neovim configuration:

```lua
local root = vim.fn.stdpath("data") .. "/site/pack/plugins/start/DrawioToImg"
vim.opt.runtimepath:append(root .. "/libs/DrawioToImg")
require("drawiotoimg").setup()
```

If you use a custom package directory, change `root` to match it.

## Usage

Saving a `.drawio` or `.drawio.svg` file exports a PNG beside it. Plain `.svg` files inside a directory named `diagrams` also export automatically. Opening a Markdown link creates a missing PNG or refreshes a stale one. Draw.io files work outside `diagrams` too.

| Source | Generated PNG |
| --- | --- |
| `diagrams/architecture.drawio` | `diagrams/architecture.drawio.png` |
| `diagrams/architecture.drawio.svg` | `diagrams/architecture.drawio.png` |
| `diagrams/architecture.svg` | `diagrams/architecture.png` |

Use either Markdown image links or ordinary links:

```markdown
![Architecture](diagrams/architecture.drawio.svg)
[Architecture](diagrams/architecture.drawio)
![Flow](diagrams/flow.svg)
```

Keep only one editable source for each base name: `architecture.drawio` and `architecture.drawio.svg` intentionally share their PNG. Commit the generated PNG when readers outside Neovim need it, and link directly to that PNG for portable Markdown. A `.drawio` link itself does not become an image in GitHub's Markdown renderer.

Rendering runs in the background, one diagram at a time. Saving an active diagram queues another render. Failed commands preserve the previous PNG. Draw.io exports the first page, preserving the source diagram's colors; no automatic light/dark recoloring is applied.

The plugin provides these commands:

- `:DrawioToImg [file]` renders the current file or a selected `.drawio`/`.svg` file.
- `:DrawioToImgAll [directory]` renders supported diagrams below a selected directory, the Git root, or the current directory. It skips `.git`, `node_modules`, `target`, `.cache`, and symbolic links.

## Inline SVG and Draw.io blocks

Raw `<svg>...</svg>` elements render automatically outside code fences. Code fences remain visible as source by default, including `svg`, `drawio`, and `markdown` examples.

If you explicitly want top-level `svg` and `drawio` fences to become previews, set `inline_fences = true`. For example:

````markdown
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="120" height="60">
  <rect width="120" height="60" fill="#2563eb"/>
</svg>
```

```drawio
<mxfile><diagram name="Page-1"><mxGraphModel><root>
  <mxCell id="0"/><mxCell id="1" parent="0"/>
  <mxCell id="2" value="Hello" vertex="1" parent="1">
    <mxGeometry x="0" y="0" width="120" height="60" as="geometry"/>
  </mxCell>
</root></mxGraphModel></diagram></mxfile>
```
````

Raw SVG supports both multiline and single-line elements. Start the opening `<svg>` tag on its own line, optionally indented up to three spaces. XML declarations outside the element are not part of the preview. Examples inside other code fences, lists, and block quotes remain source. Image links inside fenced Markdown examples also stay as code.

For raw SVG (and fenced diagrams when opted in), the PNG visually replaces the source in normal mode. Enter Insert mode inside it to edit the source; return to normal mode to restore the preview. Inline images live in Neovim's cache. No links or generated files are inserted into Markdown. Inline detection does not require Treesitter.

Plain SVG uses librsvg: browser-only SVG features such as HTML `foreignObject` labels may render differently. Keep editable Draw.io SVGs named `.drawio.svg` so they use the Draw.io exporter, which retains those labels. Inline SVG should be self-contained; relative external resources are not copied into its cache directory.

## Snacks image previews

DrawioToImg detects Snacks and configures image previews automatically. No resolver configuration is needed. Set `snacks = false` to disable automatic integration.

Snacks displays the generated PNG in place of the link. The source document stays intact. Existing Snacks resolvers, including MmdToImg, remain available for other images. SVG files with a sibling `.mmd` source stay with MmdToImg for themed previews. Ordinary link detection uses the Markdown-inline Treesitter parser; image links use Snacks' normal detection. Spaces in destinations can use Markdown angle brackets or URL encoding.

## Configuration

```lua
require("drawiotoimg").setup({
  command = "drawio",
  svg_command = "rsvg-convert",
  auto_render = true,
  snacks = true,
  inline_svg = true, -- preview raw SVG outside code fences
  inline_fences = false, -- opt in to rendering svg/drawio fences
  scale = 2,
  timeout = 120000, -- milliseconds per export
  -- inline_source_visible = function(buf, first, last)
  --   return nil -- true: source; false: preview; nil: default editing policy
  -- end,
})
```

Use an executable path for a custom command, including paths with spaces. Arguments are passed separately, without a shell. Set `snacks = false` for export-only use, or `inline_svg = false` to retain link previews without inline replacements. The source visibility callback uses one-based inclusive line numbers, matching MmdToImg.

## Development

The implementation, queries, tests, documentation, and development tools live in `libs/DrawioToImg`. The root `doc` symlink exposes `libs/DrawioToImg/docs` to Neovim's help system. Run `:helptags ALL` once after a manual installation, then open `:help drawiotoimg.txt`. Use Mise 2026.10.15 or later to install the locked tool dependencies. Install the tools and run the checks:

```sh
mise trust
mise -C libs/DrawioToImg install --locked
mise run //libs/DrawioToImg:install
mise run //libs/DrawioToImg:build
mise run //libs/DrawioToImg:lint
mise run //libs/DrawioToImg:test
```

The tests use real librsvg conversion and a stub for the Draw.io Desktop executable. They cover CLI arguments, paths with spaces, PNG output, rollback, scan exclusions, link resolution, inline parsing, editor events, source editing, stable placements, and disabling previews. Set `RSVG_CONVERT=/path/to/rsvg-convert` to select a local test binary. Premise runs the checks using the tool versions declared in the library's `mise.toml`. Draw.io Desktop remains an external prerequisite for rendering editable diagrams. The plugin installs from Git and requires no uploaded release artifacts.

## License

[MIT](LICENSE). Adapted from MmdToImg by Siddharth Kapoor.
