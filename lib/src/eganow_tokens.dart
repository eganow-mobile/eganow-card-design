import 'package:flutter/material.dart';

/// Colours and motion lifted verbatim from `Eganow Card Mockups.dc.html`.
class EganowColors {
  const EganowColors._();

  static const brandRed = Color(0xFFB21C33);

  /// Card back — Boss.
  static const bossBackTop = Color(0xFF111011);
  static const bossBackMid = Color(0xFF1E1D1F);
  static const bossBackEnd = Color(0xFF080708);

  /// Card back — Freedom.
  static const freedomBackTop = Color(0xFFB21C33);
  static const freedomBackMid = Color(0xFF8F1226);
  static const freedomBackEnd = Color(0xFF6D0C1C);

  /// Magnetic stripe.
  static const stripeTop = Color(0xFF191919);
  static const stripeMid = Color(0xFF0A0A0A);
  static const stripeEnd = Color(0xFF141414);

  /// Signature panel weave.
  static const signatureLight = Color(0xFFF2EDE4);
  static const signatureDark = Color(0xFFE2DBCF);
  static const signatureInk = Color(0xFF2B2B2B);

  static const cvcInk = Color(0xFF1A1A1A);
}

/// The mockup animates the flip over .7s on `cubic-bezier(.55,.06,.25,1)`.
class EganowMotion {
  const EganowMotion._();

  static const flipDuration = Duration(milliseconds: 700);
  static const flipCurve = Cubic(0.55, 0.06, 0.25, 1);
}
