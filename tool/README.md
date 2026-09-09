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
