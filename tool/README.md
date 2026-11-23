# Asset tooling

The contactless mark used to be baked into both card PNGs, which made it
impossible to animate. These scripts removed it so the widget can draw and
animate it instead. They are one-off; the stripped PNGs in
`assets/images/` are the committed result.

Originals (with the mark still printed) are **not** in this repo — they came
from the design export. `SRC` in `fit_nfc.py` and `verify_nfc.py` points at the
copy they were last run against: `~/Desktop/eganow/Cards/assets/images`, the
September revision that moved the chip from gold to silver. Re-point it if the
originals move, and re-run `fit_nfc.py` after any artwork change — the geometry
below is only valid for artwork whose mark sits where that fit found it.

| script | purpose |
| --- | --- |
| `png_tool.py` | minimal 8-bit PNG read/write, so no third-party image library is needed |
| `fit_nfc.py` | fits the mark's centre, per-arc radii and sweeps from the original artwork |
| `strip_nfc.py` | inpaints the mark out of both PNGs by interpolating across each row |
| `verify_nfc.py` | checks the fitted geometry reproduces the printed mark |
| `render_check.py` | draws the fitted geometry back onto the stripped artwork as a visual proof |

Run them from the project root with `PYTHONPATH=tool python3 tool/<script>.py`
(needs numpy). `fit_nfc.py` and `verify_nfc.py` read the originals from a path
set at the top of each file.

The geometry they produced:

- centre `(0.24777w, 0.43545h)`
- radii `[0.01982, 0.03351, 0.04883, 0.06462] × w`
- half-sweeps `[62.5°, 49.9°, 46.2°, 43.8°]`
- stroke `0.00729w`

`ContactlessMarkPainter` draws that fit at **85%**, which sits better against
the chip than the printed mark did, with the centre moved to `0.25347w` so the
smaller mark holds the printed one's optical position instead of drifting left
towards the chip. `verify_nfc.py` compares against the *printed* mark, so it
will no longer report a high match — that is expected, not a regression. Re-run
`fit_nfc.py` after any artwork change and re-derive the scaled values from it.

## Shrinking the card-front logo

The Eganow lockup (app icon, wordmark and tier name) is printed at the top-right
of both card fronts. `shrink_logo.py` scales it about its top-right corner, so
the right edge and top stay where they were, and rebuilds the artwork behind it.

- scale: `LOGO_SCALE` at the top of the script (currently `0.75`)
- everything outside the lockup's bounding box is left bit-identical
- the background is rebuilt by interpolating along straight lines through the
  box (so Freedom's stripe edge carries on); Boss's fine lines are re-drawn as
  curves from the ridges matched on either side of the box

The script reads the **pre-shrink** PNGs from a directory and overwrites
`assets/images/`, so it cannot be re-run against its own output. Take the
source from git history (the commit before the shrink) and run:

```
mkdir -p /tmp/card_src
for n in boss freedom; do
  git show <pre-shrink-commit>:assets/images/eganow_${n}_card.png > /tmp/card_src/eganow_${n}_card.png
done
python3 tool/shrink_logo.py /tmp/card_src
```

An optional second argument writes somewhere other than `assets/images`. Change
`LOGO_SCALE` and re-run for another size. Takes about a minute (numpy only).

## Trimming the network logos

`logo_visa.png` and `logo_mastercard.png` are exported as 256x256 squares with
wide transparent padding. `trim_logos.py` crops each one in place to its alpha
bounding box plus a 2px transparent margin (pixels inside the crop are
untouched, still RGBA), so the card can size and align the visible artwork.

```
PYTHONPATH=tool python3 tool/trim_logos.py
```

Needs numpy and `png_tool.py` only. It is idempotent. Current results: Visa
223x76, Mastercard 201x126; `_networkLogo` in `lib/src/eganow_card.dart`
hardcodes those aspect ratios, so update them if the artwork changes.
