import 'package:flutter/material.dart';

/// The two faces the card is drawn in, bundled with the package so nothing is
/// fetched at runtime and the widget renders identically offline.
///
/// Both families ship as static weights under `assets/fonts/`; the weights
/// declared in `pubspec.yaml` are the ones the card actually paints, so avoid
/// asking for a weight that isn't there — Flutter would synthesise it.
abstract final class EganowFonts {
  /// The package the faces are declared in, so styles resolve to the bundled
  /// files rather than to a same-named family in the host app.
  static const String _package = 'eganow_card';

  /// Urbanist — labels, holder name, expiry and the signature.
  static TextStyle urbanist({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
    List<Shadow>? shadows,
  }) => TextStyle(
    fontFamily: 'Urbanist',
    package: _package,
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
    letterSpacing: letterSpacing,
    height: height,
    shadows: shadows,
  );

  /// Roboto Mono — the card number and CVC, where digits need to hold a column.
  static TextStyle robotoMono({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
    List<Shadow>? shadows,
  }) => TextStyle(
    fontFamily: 'RobotoMono',
    package: _package,
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
    letterSpacing: letterSpacing,
    height: height,
    shadows: shadows,
  );
}
