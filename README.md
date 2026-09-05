# Eganow card

A Flutter widget for the Eganow card designs — Boss and Freedom — front and
back, with a 3D flip, optional in-place editing, concealment, and a loading
state. Built to be dropped into a host app as an internal package.

```dart
EganowCard(
  tier: EganowCardTier.boss,
  pan: '5399  8402  1174  4821',
  holder: 'Alex Tantuo',
  expiry: '09/28',
  cvc: '418',
)
```

## Parameters

| | |
| --- | --- |
| `tier` | Which design to render — picks the artwork, its measured corner radius, and the back gradient. |
| `pan` `holder` `expiry` `cvc` | Values. For an editable field these seed its controller. |
| `editable` | The set of fields that can be edited. Leave it empty for a read-only card — see below. |
| `entry` | `onCard` types in place on the artwork; `form` keeps the card read-only and collects the fields beneath it. |
| `controllers` | Supply your own per field to drive the card from an enclosing form. |
| `onChanged` | Fires as `(field, value)` on every edit. |
| `hideDetails` | Conceals the values — see below. |
| `isLoading` | You own this. While true the values stay concealed and shimmering, taps are ignored, and the contactless mark runs its chase. |
| `animateContactless` / `contactlessCycle` | Whether the mark animates while loading, and how long one sweep takes. |
| `legalText` | The small print on the back. Empty string leaves it off. |
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
geometry fitted to the original so it lands exactly where it was printed. See
[`tool/README.md`](tool/README.md).

Solid at rest; while loading, a highlight travels outward through the arcs.

It is drawn only on a card that can be edited. Leave `editable` empty and the
card is read-only — no on-card inputs, no form even under
`EganowCardEntry.form`, and no mark, since a card you cannot edit isn't one you
are about to tap to pay with. That holds while loading too; the shimmer on the
values carries the wait on its own.

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
- **This is a package, not an app** — no `main.dart`, no platform folders.
  The host app in [`../eganow_app`](../eganow_app) consumes it and is where
  you run and exercise the card:

  ```bash
  cd ../eganow_app && flutter run -d macos
  ```
