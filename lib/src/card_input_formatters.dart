import 'package:flutter/services.dart';

/// Letters, spaces, dots, apostrophes and hyphens only, capped at 24
/// characters — the mockup's `fmtName`.
final List<TextInputFormatter> cardNameFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z .'\-]")),
  LengthLimitingTextInputFormatter(24),
];

/// Three digits — the mockup's `fmtCvv`.
final List<TextInputFormatter> cvcFormatters = [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(3),
];

/// Digits only, a slash inserted after the month once a third digit arrives,
/// four digits maximum — the mockup's `fmtExp`.
class ExpiryInputFormatter extends TextInputFormatter {
  const ExpiryInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped = digits.length > 4 ? digits.substring(0, 4) : digits;
    final text = capped.length > 2
        ? '${capped.substring(0, 2)}/${capped.substring(2)}'
        : capped;

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

final List<TextInputFormatter> expiryFormatters = [
  const ExpiryInputFormatter(),
];

/// Sixteen digits, grouped in fours. The design sets the groups two spaces
/// apart, which is what [panGroupSeparator] preserves.
class PanInputFormatter extends TextInputFormatter {
  const PanInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped = digits.length > 16 ? digits.substring(0, 16) : digits;
    final text = groupPan(capped);

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

final List<TextInputFormatter> panFormatters = [const PanInputFormatter()];

const String panGroupSeparator = '  ';

/// `5399840211744821` → `5399  8402  1174  4821`.
String groupPan(String digits) {
  final groups = <String>[];
  for (var i = 0; i < digits.length; i += 4) {
    groups.add(
      digits.substring(i, i + 4 > digits.length ? digits.length : i + 4),
    );
  }
  return groups.join(panGroupSeparator);
}

/// Masks every digit but the last four, keeping the grouping:
/// `5399  8402  1174  4821` → `••••  ••••  ••••  4821`.
String maskPan(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return value;

  final visibleFrom = digits.length > 4 ? digits.length - 4 : digits.length;
  final masked = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    masked.write(i < visibleFrom ? '•' : digits[i]);
  }
  return groupPan(masked.toString());
}
