# Icon Credits

## App icon

`Vervellum/Resources/Assets.xcassets/AppIcon.appiconset` is generated, not drawn. The
source is [`media-sources/make_appicon.py`](media-sources/make_appicon.py), a small
Pillow script that renders the mark at 8× and downsamples, so the 16pt and 32pt sizes
stay legible without hand-hinting.

```bash
python3 media-sources/make_appicon.py
```

The mark is a magnifier over three evidence rules, the middle one struck through in the
accent colour — search plus a verdict, which is what the app does. No third-party
artwork is involved, and the generated PNGs are public domain along with the rest of
the repository.

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
