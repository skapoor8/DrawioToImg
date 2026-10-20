# Usage showcase

Open this page in Neovim to try file links, inline SVG, and inline Draw.io diagrams. The PNG images below also show the expected output on GitHub.

```sh
cd ~/Projects/DrawioToImg
nvim docs/usage.md
```

For another checkout, use that repository's directory instead. DrawioToImg, Snacks image previews, and a supported terminal must be enabled. See the [installation instructions](../README.md#installation).

## 1. Preview a Draw.io file

This is a real link to an editable `.drawio` file. In Neovim, Snacks displays its PNG preview:

[Preview pipeline](diagrams/pipeline.drawio)

To use it in your own document, copy this Markdown:

```markdown
[Preview pipeline](diagrams/pipeline.drawio)
```

Expected image:

![Save source in Neovim, the plugin regenerates PNG automatically, and the preview updates automatically](diagrams/pipeline.drawio.png)

Save [pipeline.drawio](diagrams/pipeline.drawio) in Neovim and the plugin regenerates its PNG and refreshes the preview automatically. No export command is needed for this workflow.

If you edit in Draw.io Desktop instead, save there and reopen the Markdown preview in Neovim. The plugin checks for a missing or stale PNG when it resolves the link and regenerates it automatically. It does not continuously watch files changed outside Neovim.

To force a refresh at any time, you can optionally run:

```vim
:DrawioToImg docs/diagrams/pipeline.drawio
```

Both automatic rendering and the optional command write `docs/diagrams/pipeline.drawio.png`. Keep the current directory at the repository root for the relative commands on this page.

## 2. Preview an editable Draw.io SVG

This SVG was exported from Draw.io with **Include a copy of my diagram** enabled. Its embedded diagram data lets Draw.io export a fresh PNG.

![Editable Draw.io SVG](diagrams/editable.drawio.svg)

```markdown
![Editable Draw.io SVG](diagrams/editable.drawio.svg)
```

The plugin displays `diagrams/editable.drawio.png`. The two Draw.io examples use different names so their generated PNGs remain separate.

## 3. Preview a plain SVG file

A regular SVG inside `diagrams/` also works:

![SVG file preview](diagrams/inline.svg)

```markdown
![SVG file preview](diagrams/inline.svg)
```

This uses `rsvg-convert`, while the Draw.io examples use Draw.io Desktop. Expected image:

![SVG source flowing into an inline preview](diagrams/inline.png)

## 4. Keep fenced SVG visible as code

The following `svg` code fence stays visible as source in both Neovim and GitHub. This is an example to copy, not an automatic image preview.

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="640" height="140" viewBox="0 0 640 140">
  <rect width="640" height="140" rx="16" fill="#f8fafc"/>
  <rect x="24" y="30" width="240" height="80" rx="12" fill="#dbeafe" stroke="#2563eb" stroke-width="2"/>
  <path d="M280 70h76m-10-8 10 8-10 8" fill="none" stroke="#64748b" stroke-width="3"/>
  <rect x="376" y="30" width="240" height="80" rx="12" fill="#dcfce7" stroke="#16a34a" stroke-width="2"/>
  <g font-family="sans-serif" font-size="20" text-anchor="middle" fill="#172033">
    <text x="144" y="77">SVG source</text>
    <text x="496" y="77">Inline preview</text>
  </g>
</svg>
```

To opt in to previewing top-level SVG and Draw.io fences, set `inline_fences = true` in the plugin options. Keep the default `false` to read code examples without image replacements.

## 5. Render raw SVG inline

A standalone SVG element does not need a code fence. This is a live example; GitHub may omit it from the page:

<svg xmlns="http://www.w3.org/2000/svg" width="640" height="140" viewBox="0 0 640 140">
  <rect width="640" height="140" rx="16" fill="#f8fafc"/>
  <rect x="24" y="30" width="240" height="80" rx="12" fill="#dbeafe" stroke="#2563eb" stroke-width="2"/>
  <path d="M280 70h76m-10-8 10 8-10 8" fill="none" stroke="#64748b" stroke-width="3"/>
  <rect x="376" y="30" width="240" height="80" rx="12" fill="#dcfce7" stroke="#16a34a" stroke-width="2"/>
  <g font-family="sans-serif" font-size="20" text-anchor="middle" fill="#172033">
    <text x="144" y="77">SVG source</text>
    <text x="496" y="77">Inline preview</text>
  </g>
</svg>

Move the cursor here to leave the example above. Its expected image is the same as the plain SVG preview in section 3. Start `<svg>` on its own line, and keep external resources out of the SVG so the cached copy is self-contained.

## 6. Keep fenced Draw.io XML visible as code

A `drawio` fence also stays visible as source by default. If you opt in with `inline_fences = true`, it uses the same exporter as a `.drawio` file:

```drawio
<mxfile host="app.diagrams.net">
  <diagram name="Preview pipeline" id="preview-pipeline">
    <mxGraphModel background="#ffffff" page="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <mxCell id="2" value="Save source&#10;in Neovim" style="rounded=1;whiteSpace=wrap;html=0;fillColor=#dbeafe;strokeColor=#2563eb;fontColor=#172033;fontSize=18;fontFamily=Helvetica;strokeWidth=2;" vertex="1" parent="1">
          <mxGeometry as="geometry" x="24" y="24" width="192" height="88" />
        </mxCell>
        <mxCell id="3" value="Plugin regenerates&#10;PNG automatically" style="rounded=1;whiteSpace=wrap;html=0;fillColor=#ede9fe;strokeColor=#7c3aed;fontColor=#172033;fontSize=18;fontFamily=Helvetica;strokeWidth=2;" vertex="1" parent="1">
          <mxGeometry as="geometry" x="256" y="24" width="192" height="88" />
        </mxCell>
        <mxCell id="4" value="Preview updates&#10;automatically" style="rounded=1;whiteSpace=wrap;html=0;fillColor=#dcfce7;strokeColor=#16a34a;fontColor=#172033;fontSize=18;fontFamily=Helvetica;strokeWidth=2;" vertex="1" parent="1">
          <mxGeometry as="geometry" x="488" y="24" width="192" height="88" />
        </mxCell>
        <mxCell id="5" style="edgeStyle=orthogonalEdgeStyle;rounded=0;html=0;endArrow=block;endFill=1;strokeColor=#64748b;strokeWidth=2;" edge="1" parent="1" source="2" target="3">
          <mxGeometry as="geometry" relative="1" />
        </mxCell>
        <mxCell id="6" style="edgeStyle=orthogonalEdgeStyle;rounded=0;html=0;endArrow=block;endFill=1;strokeColor=#64748b;strokeWidth=2;" edge="1" parent="1" source="3" target="4">
          <mxGeometry as="geometry" relative="1" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

With fenced previews enabled, the expected image is the automatic rendering pipeline in section 1. The block can contain uncompressed XML, as above, or an ordinary Draw.io document with compressed diagram data.

## Optional: force a refresh of all file examples

Saving sources in Neovim and opening Markdown previews already trigger automatic rendering. To regenerate all file examples at once, run this from the repository root:

```vim
:DrawioToImgAll docs/diagrams
```

This regenerates three PNG files beside the editable sources. Raw inline SVG (and fenced diagrams when opted in) refresh independently as you edit this Markdown page; they do not add files to `docs/diagrams/`.

For a Markdown page that must show images on GitHub, link to the committed PNG:

```markdown
![Preview pipeline](diagrams/pipeline.drawio.png)
```

## If the image does not appear

- Restart Neovim after adding the plugin, then check that `:DrawioToImg` exists.
- Run `:DrawioToImg docs/diagrams/pipeline.drawio` to check Draw.io export, and `:DrawioToImg docs/diagrams/inline.svg` to check SVG export. Errors appear in `:messages`.
- If the PNG exists but the preview is missing, check Snacks with `:checkhealth snacks` and use an image-capable terminal such as Ghostty or Kitty.
- File links need the Markdown and Markdown-inline Treesitter parsers. Inline block detection does not.
- Move the cursor outside the diagram if your source-visibility policy reveals nearby source. Enter normal mode after editing.

See the [README](../README.md#commands-and-configuration) for renderer paths, preview switches, timeouts, and the source-visibility callback.
