# Icon Credits

## App icon

The artwork is [`media-sources/icon.png`](media-sources/icon.png): a magnifier over an
open book whose text carries numbered citations — search, and the evidence it rests
on. It is part of this repository and shared under the same terms as everything else
in it.

Every size the platforms use is exported from that one file by
[`media-sources/make_appicon.py`](media-sources/make_appicon.py), a small Pillow
script:

```bash
python3 media-sources/make_appicon.py
```

- `Vervellum/Resources/Assets.xcassets/AppIcon.appiconset` — macOS, ten sizes, the
  rounded-square shape of the macOS icon grid cut out on the full canvas.
- `packaging/icons/hicolor/<size>x<size>/apps/ch.lkmc.Vervellum.png` — Linux, the
  sizes the hicolor icon theme indexes, which `packaging/build-deb.sh` installs.

Edit the artwork, run the script, and commit both the source and the exports. Nothing
under either output directory is hand-edited.

## Interface symbols

Every symbol in the interface is an **SF Symbol** drawn from the system font, used
under Apple's terms: they are rendered by the system rather than redistributed, and no
symbol is used as part of the app's own mark or icon.

The symbols in use, and what each means:

| Symbol | Where |
| --- | --- |
| `text.magnifyingglass` | menu-bar item, panel header |
| `checkmark.seal` | a *supported* verdict |
| `xmark.seal` | a *contradicted* verdict |
| `arrow.triangle.branch` | a *mixed* verdict |
| `questionmark.circle` | a *not established* verdict |
| `bubble.left.and.bubble.right` | an *opinion* verdict |
| `exclamationmark.triangle` | a notice about the run |
| `magnifyingglass` | a search query in the process trail |
| `arrow.up.forward.square` | opening a source |
| `eye.slash` | redacted text in the composer |
| `square.and.pencil`, `clock`, `gearshape`, `xmark`, `stop.fill`, `arrow.up` | header and composer controls |
| `key`, `command`, `info.circle` | Settings tabs |

## Fonts

System fonts only — SF Pro for text and SF Mono for code and citation numbers, both
requested through SwiftUI's `.system(...)` rather than bundled.
