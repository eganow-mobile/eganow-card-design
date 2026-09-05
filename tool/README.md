# Asset tooling

The contactless mark used to be baked into both card PNGs, which made it
impossible to animate. These scripts removed it so the widget can draw and
animate it instead. They are one-off; the stripped PNGs in
`assets/images/` are the committed result.

Originals (with the mark still printed) are **not** in this repo — they came
from the design export.

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

The geometry they produced is baked into `_ContactlessMarkPainter`:

- centre `(0.24777w, 0.43545h)`
- radii `[0.01982, 0.03351, 0.04883, 0.06462] × w`
- half-sweeps `[62.5°, 49.9°, 46.2°, 43.8°]`
- stroke `0.00729w`
