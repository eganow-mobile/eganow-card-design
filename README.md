# Eganow card

A Flutter widget for the Eganow card designs — Boss and Freedom — front and
back, with a 3D flip, optional in-place editing, concealment, and a loading
state. Built to be dropped into a host app as an internal package.

```dart
EganowCard(
  tier: EganowCardTier.boss,
  pan: '5399  8402  1174  4821',
  holder: 'Kwaku Ananse',
  expiry: '09/28',
  cvc: '418',
)
```

## Parameters

| | |
| --- | --- |
| `tier` | Which design to render — picks the artwork, its measured corner radius, and the back gradient. |
| `pan` `holder` `expiry` `cvc` | Values. For an editable field these seed its controller. |
| `editable` | The set of fields that can be edited. Leave it empty for a read-only card: no inputs and no form. |
| `entry` | `onCard` types in place on the artwork; `form` keeps the card read-only and collects the fields beneath it. |
| `controllers` | Supply your own per field to drive the card from an enclosing form. |
| `onChanged` | Fires as `(field, value)` on every edit. |
| `hideDetails` | Conceals the values — see below. |
| `isLoading` | You own this. While true the values stay concealed and shimmering, taps are ignored, and the contactless mark runs its chase. It never hides the mark — the mark is always drawn. |
| `animateContactless` / `contactlessCycle` | Whether the mark animates while loading, and how long one sweep takes. |
| `legalText` | The small print on the back. Empty string leaves it off. |
| `balance` | The formatted amount shown on the right of the front, with an eye beside it. Printed verbatim — grouping and rounding are yours. Null draws nothing. |
| `currency` | The currency `balance` is in, e.g. `GHS`. Kept separate because it survives concealment. |
| `hideBalance` | Whether the balance is concealed. Null (the default) lets the card own the eye; pass a value to drive it. Independent of `hideDetails` — see below. |
| `onBalanceVisibilityChanged` | Fires with the concealment state being asked for when the eye is tapped, driven or not. |
| `medium` | Badges the front `Virtual` or `Physical`, top left. Null (the default) draws no badge. Not concealed by `hideDetails` — which medium a card is isn't a secret. |
| `securityCodeLabel` | Captions the security code `CVV` (the default) or `CVC`, on the back and on the form field. Only the caption — the slot stays `EganowCardField.cvc`. |
| `flipped` | Leave null to let the card manage its own flip; pass a value to drive it. |
| `width` | Fills its parent when null. |

## Concealment

`hideDetails` never paints the real characters — the substitution happens in
the field's controller at paint time, so zooming or screenshotting yields the
mask, while `controller.text` and `onChanged` still see the true value.

The PAN keeps its last four digits so the card stays identifiable; the holder
is replaced by a fixed-length run so its length isn't leaked either. An
editable field reveals itself while focused, otherwise it could not be typed
into — but that exemption ends the moment `hideDetails` is switched on: the
card drops focus so nothing is left in the clear mid-edit. In form mode the
fields below the card mask under the same rule as the card face.

Switching concealment fades the values out and back over ~180ms rather than
swapping them in a frame. The line box never moves, but a mask is a thin strip
of dots and a real value is a tall block of type, so an instant swap reads as
the text jumping. It dips through zero rather than cross-dissolving on
purpose: a cross-dissolve would have to paint the real characters underneath
the mask, and concealment promises they never reach the screen at all.
Focusing a field to type into it still reveals it immediately — no fade.

## The balance

`balance` is printed verbatim, so formatting is the caller's. The eye beside it
toggles concealment, replacing the figure with a fixed-length `••••••` — fixed
so a concealed balance doesn't leak its magnitude the way a per-digit mask
would.

`currency` is a separate parameter rather than part of `balance` because it
rides through concealment: a hidden balance reads `GHS••••••`, which still
tells the holder which account they are looking at. Hiding a balance is about
the figure, not about which currency you hold.

**It has nothing to do with `hideDetails`.** A balance is worth covering in a
room full of people while the card number is on show, and worth showing while
the number is masked; tying the two together would make either impossible.

Left null, `hideBalance` lets the card own the toggle. Pass a value and you own
it — the eye then only reports through `onBalanceVisibilityChanged` and the
card waits to be given the new value, the same contract `flipped` uses:

```dart
EganowCard(
  balance: '1,000.00',
  currency: 'GHS ',
  hideBalance: _hidden,
  onBalanceVisibilityChanged: (hidden) => setState(() => _hidden = hidden),
)
```

The eye sits deeper in the tree than the card's tap-to-flip, so it wins the
gesture arena — revealing a balance never turns the card over by accident. The
row is anchored to the right margin, so the eye keeps its place when the
shorter mask swaps in rather than sliding out from under your finger.

## Loading

`isLoading` is caller-owned — drive it from the request, not from a timer:

```dart
setState(() => loading = true);
final details = await api.fetchCard(id);
setState(() => loading = false);
```

## The contactless mark

It used to be baked into the artwork, which made it impossible to animate. It
has been inpainted out of both PNGs and is drawn by the widget instead, at
geometry fitted to the original — then drawn at 85% of that fit, which sits
better against the chip, re-centred so the smaller mark holds the printed one's
optical position. See [`tool/README.md`](tool/README.md).

Solid at rest; while loading, a highlight travels outward through the arcs.

The mark is always drawn. It is part of the card's face rather than a state of
it, so neither `editable` nor `isLoading` takes it away — `isLoading` only sets
the highlight travelling through it, and a read-only card wears it exactly as
an editable one does.

Leave `editable` empty and the card is read-only — no on-card inputs, and no
form even under `EganowCardEntry.form`. That governs what can be typed into,
nothing about the mark.

## Packaging notes

- **Assets resolve through `packages/<name>/…`.** `EganowCard.assetPackage`
  must match the `name:` in `pubspec.yaml`. If you rename the package for the
  host project, change it in both places or the artwork will not load.
- **Fonts are bundled, not fetched.** Urbanist and Roboto Mono ship in
  [`assets/fonts/`](assets/fonts) and are declared in `pubspec.yaml`, so the
  card's metrics hold offline and the package has no third-party dependency.
  Only the weights the card paints are included (400/500/600/700, plus
  Urbanist italic at 400 and 600) — reach for them through `EganowFonts`
  rather than naming the families by hand, so the `package:` prefix that
  resolves them stays in one place. Both are SIL Open Font Licensed; the
  licences sit beside the faces.