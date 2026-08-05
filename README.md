# cave.koplugin

A Cave puzzle plugin for [KOReader](https://github.com/koreader/koreader).

## Screenshot

![Screenshot](images/cave.png)

## Rules

Shade cells black to carve a connected white "cave". Numbered white cells show exactly how many white cells are visible from that position in all four orthogonal directions (including itself). All white cells must be connected; no black cell may be completely enclosed by white cells.

## Features

- **Multiple grid sizes**
- **Three difficulty levels** — Easy, Medium, Hard
- **Visibility lines** — see the line of sight from any numbered cell
- **Check** — validates connectivity and visibility counts
- **Auto-save** — puzzle state saved and restored on next launch

## Installation

1. Download `cave.koplugin.zip` from the [latest release](../../releases/latest).
2. Extract into the `plugins/` folder of your KOReader data directory.
3. Restart KOReader.
4. Open the menu → **Tools** → **Cave**.

## Controls

| Action | How |
|--------|-----|
| Shade / unshade a cell | Tap it |
| Check progress | Tap **Check** |
| New puzzle | Tap **New** |
| Show rules | Tap **Rules** |

## Known limitations

At most sizes and difficulties, every generated puzzle is guaranteed to
have exactly one solution. Medium difficulty at 7×7 and 8×8 is the
exception: proving uniqueness there is occasionally too expensive within
generation's time budget, so a small fraction of those puzzles ship
without that guarantee (still fully valid and completable, just not
proven to be the only possible solution).

## License

GPL-3.0 — see [LICENSE](LICENSE).
