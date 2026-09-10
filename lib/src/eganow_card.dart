import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'card_input_formatters.dart';
import 'css_gradients.dart';
import 'eganow_fonts.dart';
import 'eganow_tokens.dart';

/// Concealed stand-ins used when [EganowCard.hideDetails] is set. The real
/// characters are never painted — the name uses a fixed-length run so its
/// length isn't leaked either, while the structured fields keep their shape.
const String _concealedName = '••••••••••••';
const String _concealedExpiry = '••/••';
const String _concealedCvc = '•••';

/// A fixed-length run, so a concealed balance doesn't leak its magnitude the
/// way a per-digit mask would — `••••••` reads the same for 5 and 50,000.
const String _concealedBalance = '••••••';

/// Which card design to render. The tier picks the artwork, its measured
/// corner radius and the gradient on the back.
enum EganowCardTier { boss, freedom }

/// How editable fields are collected.
enum EganowCardEntry {
  /// Tap a value on the artwork and type into it in place.
  onCard,

  /// The card stays read-only and mirrors a form rendered beneath it.
  form,
}

/// Whether the card exists as a piece of plastic or only in the app.
///
/// Named `medium` rather than `form` throughout, so it is never mistaken for
/// [EganowCardEntry.form], which is about where fields are typed, not about
/// what kind of card this is.
enum EganowCardMedium {
  physical,
  virtual;

  /// The badge caption, e.g. `Virtual`.
  String get label => '${name[0].toUpperCase()}${name.substring(1)}';
}

/// What the security code is called on this card. It is the same three digits
/// either way — issuers and networks simply differ on what they print, so the
/// label follows the card being represented rather than the code itself.
enum EganowSecurityCodeLabel {
  cvv,
  cvc;

  String get label => name.toUpperCase();
}

/// The four data slots on the card. Pass any of these in [EganowCard.editable]
/// to turn that slot into a live text field on the artwork itself.
enum EganowCardField { pan, holder, expiry, cvc }

extension EganowCardTierArt on EganowCardTier {
  String get label => this == EganowCardTier.boss ? 'boss' : 'freedom';

  String get faceAsset => this == EganowCardTier.boss
      ? 'assets/images/eganow_boss_card.png'
      : 'assets/images/eganow_freedom_card.png';

  /// Each artwork's pre-rounded corner radius as a fraction of card width,
  /// measured from its own alpha channel — the two designs differ.
  double get cornerRadiusFraction =>
      this == EganowCardTier.boss ? 0.040 : 0.028;

  List<Color> get backGradient => this == EganowCardTier.boss
      ? const [
          EganowColors.bossBackTop,
          EganowColors.bossBackMid,
          EganowColors.bossBackEnd,
        ]
      : const [
          EganowColors.freedomBackTop,
          EganowColors.freedomBackMid,
          EganowColors.freedomBackEnd,
        ];

  /// The mid stop sits at 46% on Boss, 52% on Freedom.
  List<double> get backStops => this == EganowCardTier.boss
      ? const [0.0, 0.46, 1.0]
      : const [0.0, 0.52, 1.0];
}

/// Geometry for one rendered card.
///
/// The design expresses every overlay size as `cqw` — a percentage of the
/// card's rendered *width* — so a single layout pass drives the whole face.
class EganowCardMetrics {
  const EganowCardMetrics({required this.width, required this.height});

  final double width;
  final double height;

  /// `n` cqw in logical pixels, i.e. n% of the card's width.
  double cqw(double n) => width * n / 100;

  /// `n`% of the card's height.
  double ch(double n) => height * n / 100;
}

/// The Eganow card face — front and back, with a 3D flip between them.
///
/// The chip, contactless mark and wordmark are baked into the artwork and its
/// corners are pre-rounded in the alpha channel, so nothing on the front is
/// redrawn; only live text is overlaid.
///
/// ```dart
/// // Display only.
/// EganowCard(
///   tier: EganowCardTier.boss,
///   pan: '5399  8402  1174  4821',
///   holder: 'Kwaku Ananse',
///   expiry: '09/28',
///   cvc: '418',
/// )
///
/// // Entry: any listed field becomes a text field on the card.
/// EganowCard(
///   tier: EganowCardTier.freedom,
///   editable: EganowCardField.values.toSet(),
///   onChanged: (field, value) => print('$field = $value'),
/// )
/// ```
class EganowCard extends StatefulWidget {
  const EganowCard({
    super.key,
    this.tier = EganowCardTier.boss,
    this.pan,
    this.holder,
    this.expiry,
    this.cvc,
    this.editable = const <EganowCardField>{},
    this.entry = EganowCardEntry.onCard,
    this.controllers,
    this.onChanged,
    this.legalText = defaultLegalText,
    this.balance,
    this.currency,
    this.hideBalance,
    this.onBalanceVisibilityChanged,
    this.medium,
    this.securityCodeLabel = EganowSecurityCodeLabel.cvv,
    this.hideDetails = false,
    this.isLoading = false,
    this.animateContactless = true,
    this.contactlessCycle = const Duration(milliseconds: 1400),
    this.flipped,
    this.onTap,
    this.width,
  });

  /// Which card design to show.
  final EganowCardTier tier;

  /// Initial values. For an editable field these seed its controller; for a
  /// read-only one they are simply displayed.
  final String? pan;
  final String? holder;
  final String? expiry;
  final String? cvc;

  /// Fields that can be edited.
  final Set<EganowCardField> editable;

  /// Whether [editable] fields are typed into on the artwork, or collected in
  /// a form below it. In form mode the card itself stays read-only and simply
  /// reflects what is typed — and focusing the CVC still turns it over.
  final EganowCardEntry entry;

  /// Supply your own controllers to drive fields from an enclosing form.
  /// Any field left out gets an internal controller seeded from its value.
  final Map<EganowCardField, TextEditingController>? controllers;

  /// Fired whenever an editable field changes.
  final void Function(EganowCardField field, String value)? onChanged;

  /// The balance amount shown on the front, already formatted — the card
  /// prints it verbatim, so grouping and rounding are the caller's.
  ///
  /// Null, the default, draws no balance and no eye at all. Pass the currency
  /// separately in [currency] rather than baking it in here, so it can stay
  /// on show once the amount is concealed.
  final String? balance;

  /// The currency [balance] is denominated in, e.g. `GHS`.
  ///
  /// Kept out of [balance] because it survives concealment: hiding a balance
  /// is about the figure, not about which currency you hold. A concealed
  /// balance reads `GHS••••••`, which still tells the holder they are looking
  /// at the right account.
  final String? currency;

  /// Whether the balance is concealed.
  ///
  /// Leave null — the default — and the card owns the toggle: the eye flips it
  /// and the card rebuilds itself. Pass a value to drive it from outside, in
  /// which case the eye only reports through [onBalanceVisibilityChanged] and
  /// the card waits to be given the new value, as [flipped] does.
  ///
  /// This is deliberately nothing to do with [hideDetails]. A balance is worth
  /// covering in a room full of people even while the card number is on show,
  /// and worth showing while the number is masked; tying the two together
  /// would make either impossible.
  final bool? hideBalance;

  /// Fired when the eye is tapped, with the concealment state being asked for.
  /// It fires whether or not the card owns the toggle, so a driven card still
  /// hears about the tap.
  final ValueChanged<bool>? onBalanceVisibilityChanged;

  /// Badges the front of the card `Virtual` or `Physical`, top left.
  ///
  /// Left null — the default — no badge is drawn at all, so a card that has
  /// no need to make the distinction looks exactly as it did before. It is
  /// deliberately not concealed by [hideDetails]: which medium a card is
  /// isn't a secret, and a badge blinking out alongside the real values would
  /// only draw the eye.
  final EganowCardMedium? medium;

  /// Whether the security code is captioned CVV or CVC — on the back of the
  /// card and, in form mode, on the field below it. Only the caption changes;
  /// the slot is [EganowCardField.cvc] whichever name is shown.
  final EganowSecurityCodeLabel securityCodeLabel;

  /// Conceals the card's data: the PAN keeps only its last four digits, and
  /// the holder, expiry, CVC and signature are blurred out. An editable field
  /// reveals itself while it holds focus, so entry still works.
  final bool hideDetails;

  /// Whether the card's details are being fetched.
  ///
  /// While true the values stay concealed and shimmering, taps on them are
  /// ignored, and the contactless mark runs its chase. The caller owns this —
  /// drive it from the request rather than from a timer here, so the card
  /// stops animating exactly when the data lands.
  final bool isLoading;

  /// Sweeps the contactless mark while the details are loading — the arcs
  /// draw on one after another, standing in for a progress indicator.
  ///
  /// The mark is drawn by the widget rather than baked into the artwork, so
  /// it can animate at all. Outside the loading window it is always drawn at
  /// rest, exactly as it was printed.
  final bool animateContactless;

  /// How long the highlight takes to travel from the innermost arc to past
  /// the outermost — one full cycle of the chase. Shorter is faster.
  final Duration contactlessCycle;

  /// Leave null to let the card manage its own flip — tapping turns it over,
  /// and focusing the CVC field shows the back. Pass a value to drive it.
  final bool? flipped;

  /// Overrides the default tap-to-flip.
  final VoidCallback? onTap;

  /// Renders full-width of its parent when null.
  final double? width;

  /// The small print along the bottom of the card's back. Pass an empty
  /// string to leave it off.
  final String legalText;

  /// The artwork's aspect ratio, 2016 × 1278.
  static const double aspectRatio = 2016 / 1278;

  static const String samplePan = '5399  8402  1174  4821';

  /// Assets ship with this package, so they resolve through
  /// `packages/<name>/…` in whatever app bundles it rather than through the
  /// host's own asset tree.
  static const String assetPackage = 'eganow_card';

  static const String defaultLegalText =
      'Issued by Eganow. Use of this card is subject to the cardholder '
      'agreement. If found, return to any Eganow branch.';

  @override
  State<EganowCard> createState() => _EganowCardState();
}

class _EganowCardState extends State<EganowCard> with TickerProviderStateMixin {
  final _owned = <EganowCardField, TextEditingController>{};
  final _focus = <EganowCardField, FocusNode>{};

  bool _selfFlipped = false;
  bool _selfBalanceHidden = false;

  late final AnimationController _contactless = AnimationController(
    vsync: this,
    duration: widget.contactlessCycle,
  );

  /// Concealment dips the values out and back rather than swapping them in a
  /// single frame. A mask is a short strip of dots and a real value is a tall
  /// block of type, so an instant swap reads as the text jumping — even though
  /// the line box never moves. Fading through zero hides the change of shape.
  ///
  /// It dips rather than cross-dissolves on purpose: a cross-dissolve would
  /// have to paint the real characters underneath the mask, and concealment
  /// promises they never reach the screen at all.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 90),
  );

  /// The concealment the card is currently *painting*, which lags the widget
  /// by half a dip so the swap lands at the trough where nothing is visible.
  late bool _concealedNow = widget.hideDetails || widget.isLoading;

  bool get _selfManaged => widget.flipped == null;
  bool get _flipped => widget.flipped ?? _selfFlipped;

  bool get _balanceHidden => widget.hideBalance ?? _selfBalanceHidden;

  void _toggleBalance() {
    final next = !_balanceHidden;
    // Only move state we own; a driven card is the caller's to change.
    if (widget.hideBalance == null) {
      setState(() => _selfBalanceHidden = next);
    }
    widget.onBalanceVisibilityChanged?.call(next);
  }

  @override
  void initState() {
    super.initState();
    _wireFields();
    if (_chaseRunning) _contactless.repeat();
  }

  /// Whether the values should be concealed, ignoring the dip in progress.
  bool get _concealTarget => widget.hideDetails || widget.isLoading;

  /// Fade the values out, trade the mask for the value where nothing is on
  /// screen to see it happen, then fade back in. The swap reads the target
  /// afresh at the floor, in case it moved on the way down.
  void _dip() {
    _reveal.reverse().then((_) {
      if (!mounted) return;
      if (_concealedNow != _concealTarget) {
        setState(() => _concealedNow = _concealTarget);
      }
      _reveal.forward();
    });
  }

  @override
  void didUpdateWidget(EganowCard old) {
    super.didUpdateWidget(old);
    if (old.editable != widget.editable ||
        old.controllers != widget.controllers) {
      _wireFields();
    }

    // Concealment exempts the focused field so it stays typeable — but that
    // exemption must not outlive the moment concealment is switched on, or
    // whatever the caller was editing would sit there in the clear while
    // every other value masks. Drop focus so the whole card hides at once.
    if (!old.hideDetails && widget.hideDetails) {
      for (final node in _focus.values) {
        if (node.hasFocus) node.unfocus();
      }
    }

    // Guarded on the status: the parent may rebuild many times over a dip
    // (an `onChanged` per keystroke, say) and restarting it each time would
    // leave the values stranded at half strength.
    if (_concealedNow != _concealTarget &&
        _reveal.status != AnimationStatus.reverse) {
      _dip();
    }

    final shouldRun = _chaseRunning;
    if (shouldRun && !_contactless.isAnimating) {
      _contactless.repeat();
    } else if (!shouldRun && _contactless.isAnimating) {
      _contactless
        ..stop()
        ..value = 0;
    }

    if (old.contactlessCycle != widget.contactlessCycle) {
      _contactless.duration = widget.contactlessCycle;
      // repeat() latches the duration, so restart to pick the new one up.
      if (_contactless.isAnimating) _contactless.repeat();
    }
  }

  void _wireFields() {
    for (final field in widget.editable) {
      _owned.putIfAbsent(
        field,
        () => _CardFieldController(
          text: _seed(field),
          // `text-transform: uppercase` on the holder, per the design.
          display: field == EganowCardField.holder
              ? (raw) => raw.toUpperCase()
              : null,
          mask: _maskFor(field),
        ),
      );
      _focus.putIfAbsent(field, () {
        final node = FocusNode();
        node.addListener(() => _onFocusChanged(field, node));
        return node;
      });
    }
  }

  static String Function(String) _maskFor(EganowCardField field) {
    switch (field) {
      case EganowCardField.pan:
        return maskPan;
      case EganowCardField.holder:
        return (_) => _concealedName;
      case EganowCardField.expiry:
        return (_) => _concealedExpiry;
      case EganowCardField.cvc:
        return (_) => _concealedCvc;
    }
  }

  /// Wires concealment for an editable field. The internal controller masks as
  /// it paints, so the field stays focusable and shows its real value once
  /// focused. A caller-supplied controller can't do that, so while concealed it
  /// falls back to static masked text rather than painting the real value.
  Widget _maskAware({
    required EganowCardField field,
    required EganowCardMetrics metrics,
    required TextStyle style,
    required Widget Function() input,
    bool alignEnd = false,
  }) {
    final controller = _controllerFor(field);
    final hidden = _isHidden(field);

    if (controller is _CardFieldController) {
      controller.masked = hidden;
      return input();
    }
    if (!hidden) return input();

    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: metrics.cqw(0.4)),
        child: Text(
          _maskFor(field)(controller?.text ?? ''),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }

  String _seed(EganowCardField field) {
    switch (field) {
      case EganowCardField.pan:
        return widget.pan ?? '';
      case EganowCardField.holder:
        return widget.holder ?? '';
      case EganowCardField.expiry:
        return widget.expiry ?? '';
      case EganowCardField.cvc:
        return widget.cvc ?? '';
    }
  }

  void _onFocusChanged(EganowCardField field, FocusNode node) {
    if (!node.hasFocus) {
      setState(() {}); // repaint the underline and re-hide the value
      return;
    }
    setState(() {
      // The CVC lives on the back, so focusing it turns the card over.
      if (_selfManaged) {
        _selfFlipped = field == EganowCardField.cvc;
      }
    });
  }

  @override
  void dispose() {
    _reveal.dispose();
    _contactless.dispose();
    for (final c in _owned.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// Display-only: nothing on the card can be typed into, so no on-card
  /// inputs and no form are built. It says nothing about the contactless
  /// mark, which is printed on every card whether or not this one can be
  /// edited.
  bool get _readOnly => widget.editable.isEmpty;

  /// Whether the chase is travelling. This is the whole of what [isLoading]
  /// controls: the mark itself is always drawn, and loading only decides
  /// whether the highlight is running through it.
  bool get _chaseRunning => widget.isLoading && widget.animateContactless;

  /// Rendered as an input on the artwork itself.
  bool _isEditable(EganowCardField field) =>
      widget.entry == EganowCardEntry.onCard && widget.editable.contains(field);

  TextEditingController? _controllerFor(EganowCardField field) =>
      widget.controllers?[field] ?? _owned[field];

  /// The value to work with, whether it comes from a controller or a plain
  /// parameter.
  String _valueOf(EganowCardField field) {
    final controller = _controllerFor(field);
    if (controller != null) return controller.text;
    return _seed(field);
  }

  /// Hidden unless this field currently holds focus — otherwise an editable
  /// field could not be typed into while [EganowCard.hideDetails] is set.
  /// While a fetch is in flight everything stays hidden, focus or not.
  ///
  /// This follows [_concealedNow] rather than the widget so the mask and the
  /// value trade places at the bottom of the dip. Focus is read live, though:
  /// tapping a concealed field to type into it should not wait on a fade.
  bool _isHidden(EganowCardField field) =>
      _concealedNow &&
      (widget.isLoading || !(_focus[field]?.hasFocus ?? false));

  /// Shimmers a concealed value while the details are being fetched, and
  /// blocks interaction so a tap can't shortcut the wait.
  Widget _revealWrap(Widget child, {bool onDarkGround = true}) {
    final faded = FadeTransition(opacity: _reveal, child: child);
    if (!widget.isLoading) return faded;
    return AbsorbPointer(
      child: _Shimmer(onDarkGround: onDarkGround, child: faded),
    );
  }

  void _handleTap() {
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }
    if (_selfManaged) setState(() => _selfFlipped = !_selfFlipped);
  }

  @override
  Widget build(BuildContext context) {
    final card = AspectRatio(
      aspectRatio: EganowCard.aspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final metrics = EganowCardMetrics(
            width: w,
            height: w / EganowCard.aspectRatio,
          );

          return TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: _flipped ? 1 : 0),
            duration: EganowMotion.flipDuration,
            curve: EganowMotion.flipCurve,
            builder: (context, t, _) {
              final angle = t * math.pi;

              // `perspective: 1400px` in the design.
              final transform = Matrix4.identity()
                ..setEntry(3, 2, -1 / 1400)
                ..rotateY(angle);

              return Transform(
                alignment: Alignment.center,
                transform: transform,
                child: angle < math.pi / 2
                    ? _buildFront(metrics)
                    : Transform(
                        // Counter-rotate so the back reads the right way round.
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateY(math.pi),
                        child: _buildBack(metrics),
                      ),
              );
            },
          );
        },
      ),
    );

    final sized = widget.width == null
        ? card
        : SizedBox(width: widget.width, child: card);

    final tappable = GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.deferToChild,
      child: sized,
    );

    if (widget.entry == EganowCardEntry.onCard || _readOnly) {
      return tappable;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [tappable, const SizedBox(height: 24), _buildForm(context)],
    );
  }

  // ----------------------------------------------------------------- form --

  Widget _buildForm(BuildContext context) {
    final onDark = Theme.of(context).brightness == Brightness.dark;

    Widget? fieldFor(EganowCardField field) {
      if (!widget.editable.contains(field)) return null;

      // The card face masks its own text, but the form below is fed straight
      // from the controllers — so tell them to mask too. Same rule as on the
      // card: concealed unless this field currently holds focus.
      final controller = _controllerFor(field)!;
      if (controller is _CardFieldController) {
        controller.masked = _isHidden(field);
      }

      return _FormField(
        onDark: onDark,
        label: _formLabel(field),
        hint: _formHint(field),
        controller: controller,
        focusNode: _focus[field]!,
        formatters: _formattersFor(field),
        keyboardType: field == EganowCardField.holder
            ? TextInputType.text
            : TextInputType.number,
        textCapitalization: field == EganowCardField.holder
            ? TextCapitalization.words
            : TextCapitalization.none,
        monospaced: field != EganowCardField.holder,
        letterSpacing: switch (field) {
          EganowCardField.expiry => 1,
          EganowCardField.cvc => 3,
          _ => null,
        },
        onChanged: (v) => _emit(field, v),
      );
    }

    final rows = <Widget>[];
    for (final field in [EganowCardField.pan, EganowCardField.holder]) {
      final f = fieldFor(field);
      if (f != null) rows.add(f);
    }

    // Expiry and CVC share a row when both are collected, as in the design.
    final expiry = fieldFor(EganowCardField.expiry);
    final cvc = fieldFor(EganowCardField.cvc);
    if (expiry != null && cvc != null) {
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: expiry),
            const SizedBox(width: 12),
            Expanded(child: cvc),
          ],
        ),
      );
    } else if (expiry != null) {
      rows.add(expiry);
    } else if (cvc != null) {
      rows.add(cvc);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          rows[i],
        ],
      ],
    );
  }

  String _formLabel(EganowCardField field) => switch (field) {
    EganowCardField.pan => 'Card number',
    EganowCardField.holder => 'Name on card',
    EganowCardField.expiry => 'Expiry',
    EganowCardField.cvc => widget.securityCodeLabel.label,
  };

  static String _formHint(EganowCardField field) => switch (field) {
    EganowCardField.pan => '0000  0000  0000  0000',
    EganowCardField.holder => 'e.g. Kwaku Ananse',
    EganowCardField.expiry => 'MM/YY',
    EganowCardField.cvc => _concealedCvc,
  };

  static List<TextInputFormatter> _formattersFor(EganowCardField field) =>
      switch (field) {
        EganowCardField.pan => panFormatters,
        EganowCardField.holder => cardNameFormatters,
        EganowCardField.expiry => expiryFormatters,
        EganowCardField.cvc => cvcFormatters,
      };

  // ---------------------------------------------------------------- front --

  Widget _buildFront(EganowCardMetrics m) {
    final w = m.width;
    final h = m.height;

    final shadows = <Shadow>[
      Shadow(
        color: Colors.black.withValues(alpha: 0.45),
        offset: Offset(0, m.cqw(0.2)),
        blurRadius: m.cqw(0.8),
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          w * widget.tier.cornerRadiusFraction,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            offset: Offset(0, m.cqw(3)),
            blurRadius: m.cqw(5),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            widget.tier.faceAsset,
            package: EganowCard.assetPackage,
            fit: BoxFit.cover,
          ),

          // Medium badge, sharing the 9% margin the card number is set on and
          // sitting clear above the chip (which starts at 37% of the height).
          if (widget.medium != null)
            Positioned(
              left: w * 0.09,
              top: h * 0.085,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(m.cqw(1.6)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: m.cqw(2.2),
                    vertical: m.cqw(1.2),
                  ),
                  child: Text(
                    widget.medium!.label,
                    style: EganowFonts.urbanist(
                      color: Colors.white,
                      fontSize: m.cqw(2.35),
                      fontWeight: FontWeight.w600,
                      letterSpacing: m.cqw(0.05),
                      shadows: shadows,
                    ),
                  ),
                ),
              ),
            ),

          // The mark is no longer part of the artwork — it is drawn here, and
          // drawn always: it is part of the card's face, not a state of it.
          // Loading only sets the highlight travelling through it.
          Positioned.fill(
            child: RepaintBoundary(
              child: _chaseRunning
                  ? AnimatedBuilder(
                      animation: _contactless,
                      builder: (context, _) => CustomPaint(
                        painter: ContactlessMarkPainter(
                          progress: _contactless.value,
                        ),
                      ),
                    )
                  : const CustomPaint(painter: ContactlessMarkPainter()),
            ),
          ),

          // Balance, set against the right margin at the chip's own height.
          if (widget.balance != null) _balanceSlot(m, shadows),

          // Card number.
          Positioned(
            left: w * 0.09,
            right: w * 0.09,
            top: h * 0.585,
            child: _revealWrap(_panSlot(m, shadows)),
          ),

          // Card holder and expiry.
          Positioned(
            left: w * 0.09,
            right: w * 0.09,
            bottom: h * 0.075,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: _holderSlot(m, shadows)),
                SizedBox(width: m.cqw(4)),
                SizedBox(
                  // 20% of the row, which is itself 82% of the card.
                  width: w * 0.82 * 0.20,
                  child: _expirySlot(m, shadows),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The balance and its eye, right-aligned level with the chip.
  ///
  /// The eye carries its own gesture, which wins the arena against the card's
  /// tap-to-flip because it sits deeper in the tree — so revealing a balance
  /// never turns the card over by accident.
  Widget _balanceSlot(EganowCardMetrics m, List<Shadow> shadows) {
    final hidden = _balanceHidden;

    return Positioned(
      right: m.width * 0.09,
      top: m.height * 0.398,
      child: _revealWrap(
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  // The currency is not concealed with the figure — see
                  // [EganowCard.currency].
                  if (widget.currency != null) TextSpan(text: widget.currency),
                  TextSpan(text: hidden ? _concealedBalance : widget.balance!),
                ],
              ),
              maxLines: 1,
              softWrap: false,
              style: EganowFonts.urbanist(
                color: Colors.white,
                fontSize: m.cqw(4),
                fontWeight: FontWeight.w700,
                letterSpacing: m.cqw(0.08),
                shadows: shadows,
              ),
            ),
            SizedBox(width: m.cqw(1.5)),
            GestureDetector(
              onTap: _toggleBalance,
              // Opaque so the whole padded square is a target, not just the
              // glyph's own strokes.
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.all(m.cqw(0.8)),
                child: Icon(
                  hidden
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: m.cqw(4.6),
                  color: Colors.white,
                  shadows: shadows,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panSlot(EganowCardMetrics m, List<Shadow> shadows) {
    final style = _fittedPanStyle(m, shadows);

    if (_isEditable(EganowCardField.pan)) {
      return _maskAware(
        field: EganowCardField.pan,
        metrics: m,
        style: style,
        input: () => _OnCardInput(
          metrics: m,
          controller: _controllerFor(EganowCardField.pan)!,
          focusNode: _focus[EganowCardField.pan]!,
          formatters: panFormatters,
          keyboardType: TextInputType.number,
          style: style,
          hint: '••••  ••••  ••••  ••••',
          onChanged: (v) => _emit(EganowCardField.pan, v),
        ),
      );
    }

    final value = _valueOf(EganowCardField.pan);
    final shown = value.isEmpty ? EganowCard.samplePan : value;

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        _isHidden(EganowCardField.pan) ? maskPan(shown) : shown,
        maxLines: 1,
        softWrap: false,
        // Never truncated: [_fittedPanStyle] has already sized it to fit.
        overflow: TextOverflow.visible,
        style: style,
      ),
    );
  }

  /// The design sets the number at 6.1cqw, but a full 16-digit PAN grouped
  /// two spaces apart is 22 monospace characters — a shade wider than the 82%
  /// band between the card's 9% margins. Measure it, and scale the type down
  /// only as far as it takes to fit.
  ///
  /// The measurement always uses a full-length reference, so the number does
  /// not resize character by character as someone types it in.
  TextStyle _fittedPanStyle(EganowCardMetrics m, List<Shadow> shadows) {
    TextStyle styled(double fontSize, double letterSpacing) =>
        EganowFonts.robotoMono(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          letterSpacing: letterSpacing,
          shadows: shadows,
        );

    var fontSize = m.cqw(6.1);
    var letterSpacing = m.cqw(0.15);

    final value = _valueOf(EganowCardField.pan);
    final reference = value.length > EganowCard.samplePan.length
        ? value
        : EganowCard.samplePan;

    final painter = TextPainter(
      text: TextSpan(text: reference, style: styled(fontSize, letterSpacing)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final available = m.width * 0.82;
    if (painter.width > available && painter.width > 0) {
      // Width scales linearly with both, so one pass lands it.
      final scale = available / painter.width;
      fontSize *= scale;
      letterSpacing *= scale;
    }

    return styled(fontSize, letterSpacing);
  }

  Widget _holderSlot(EganowCardMetrics m, List<Shadow> shadows) {
    final value = _valueOf(EganowCardField.holder).trim();
    final style = EganowFonts.urbanist(
      color: Colors.white,
      fontSize: m.cqw(3.7),
      fontWeight: FontWeight.w700,
      letterSpacing: m.cqw(0.12),
      shadows: shadows,
    );

    final hidden = _isHidden(EganowCardField.holder);
    final Widget field;
    if (_isEditable(EganowCardField.holder)) {
      field = _maskAware(
        field: EganowCardField.holder,
        metrics: m,
        style: style,
        input: () => _OnCardInput(
          metrics: m,
          controller: _controllerFor(EganowCardField.holder)!,
          focusNode: _focus[EganowCardField.holder]!,
          formatters: cardNameFormatters,
          textCapitalization: TextCapitalization.words,
          style: style,
          hint: 'TAP TO ADD NAME',
          underline: false,
          onChanged: (v) => _emit(EganowCardField.holder, v),
        ),
      );
    } else {
      field = Opacity(
        opacity: (value.isEmpty && !hidden) ? 0.34 : 1,
        child: Text(
          hidden
              ? _concealedName
              : (value.isEmpty ? 'CARDHOLDER NAME' : value.toUpperCase()),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      );
    }

    return _LabelledSlot(
      metrics: m,
      label: 'Card holder',
      child: _revealWrap(field),
    );
  }

  Widget _expirySlot(EganowCardMetrics m, List<Shadow> shadows) {
    final value = _valueOf(EganowCardField.expiry).trim();
    final style = EganowFonts.urbanist(
      color: Colors.white,
      fontSize: m.cqw(3.7),
      fontWeight: FontWeight.w700,
      letterSpacing: m.cqw(0.12),
      shadows: shadows,
    );

    final hidden = _isHidden(EganowCardField.expiry);
    final Widget field;
    if (_isEditable(EganowCardField.expiry)) {
      field = _maskAware(
        field: EganowCardField.expiry,
        metrics: m,
        style: style,
        alignEnd: true,
        input: () => _OnCardInput(
          metrics: m,
          controller: _controllerFor(EganowCardField.expiry)!,
          focusNode: _focus[EganowCardField.expiry]!,
          formatters: expiryFormatters,
          keyboardType: TextInputType.number,
          style: style,
          hint: 'MM/YY',
          alignEnd: true,
          onChanged: (v) => _emit(EganowCardField.expiry, v),
        ),
      );
    } else {
      field = Opacity(
        opacity: (value.isEmpty && !hidden) ? 0.34 : 1,
        child: Text(
          hidden ? _concealedExpiry : (value.isEmpty ? 'MM/YY' : value),
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.right,
          style: style,
        ),
      );
    }

    return _LabelledSlot(
      metrics: m,
      label: 'Expiry',
      alignEnd: true,
      child: _revealWrap(field),
    );
  }

  // ----------------------------------------------------------------- back --

  Widget _buildBack(EganowCardMetrics m) {
    final w = m.width;
    final h = m.height;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(m.cqw(3.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            offset: Offset(0, m.cqw(3)),
            blurRadius: m.cqw(5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(m.cqw(3.4)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: cssAngleBegin(128),
                  end: cssAngleEnd(128),
                  colors: widget.tier.backGradient,
                  stops: widget.tier.backStops,
                ),
              ),
            ),

            // Magnetic stripe.
            Positioned(
              left: 0,
              right: 0,
              top: h * 0.095,
              height: h * 0.175,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      EganowColors.stripeTop,
                      EganowColors.stripeMid,
                      EganowColors.stripeEnd,
                    ],
                    stops: [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            ),

            // Signature panel. Left blank, the way an unsigned strip is — the
            // holder's name belongs on the front, and repeating it here only
            // gave the same value a second place to leak from.
            Positioned(
              left: w * 0.06,
              top: h * 0.35,
              width: w * 0.58,
              height: h * 0.135,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(m.cqw(0.5)),
                  gradient: _signatureWeave(m),
                ),
              ),
            ),

            // CVC panel.
            Positioned(
              left: w * 0.67,
              top: h * 0.35,
              width: w * 0.19,
              height: h * 0.135,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(m.cqw(0.5)),
                ),
                child: _revealWrap(_cvcSlot(m), onDarkGround: false),
              ),
            ),

            Positioned(
              left: w * 0.67,
              top: h * 0.505,
              child: Text(
                widget.securityCodeLabel.label,
                style: EganowFonts.urbanist(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: m.cqw(2.3),
                  fontWeight: FontWeight.w700,
                  letterSpacing: m.cqw(0.4),
                ),
              ),
            ),

            // Wordmark.
            Positioned(
              right: w * 0.06,
              bottom: h * 0.15,
              width: w * 0.23,
              child: AspectRatio(
                aspectRatio: 579 / 128,
                child: Image.asset(
                  'assets/images/eganow_logo.png',
                  package: EganowCard.assetPackage,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerRight,
                ),
              ),
            ),

            // Legal small print.
            if (widget.legalText.isNotEmpty)
              Positioned(
                left: w * 0.06,
                right: w * 0.06,
                bottom: h * 0.05,
                child: Text(
                  widget.legalText,
                  style: EganowFonts.urbanist(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: m.cqw(2.15),
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cvcSlot(EganowCardMetrics m) {
    final style = EganowFonts.robotoMono(
      color: EganowColors.cvcInk,
      fontSize: m.cqw(4.6),
      fontWeight: FontWeight.w600,
      letterSpacing: m.cqw(0.6),
    );

    if (_isEditable(EganowCardField.cvc)) {
      return Padding(
        padding: EdgeInsets.only(left: m.cqw(0.6)),
        child: _maskAware(
          field: EganowCardField.cvc,
          metrics: m,
          style: style,
          input: () => TextField(
            controller: _controllerFor(EganowCardField.cvc)!,
            focusNode: _focus[EganowCardField.cvc]!,
            inputFormatters: cvcFormatters,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            cursorColor: EganowColors.cvcInk,
            style: style,
            onChanged: (v) => _emit(EganowCardField.cvc, v),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: _concealedCvc,
              hintStyle: style.copyWith(
                color: Colors.black.withValues(alpha: 0.25),
              ),
            ),
          ),
        ),
      );
    }

    final value = _valueOf(EganowCardField.cvc).trim();
    final hidden = _isHidden(EganowCardField.cvc);

    return Center(
      child: Padding(
        padding: EdgeInsets.only(left: m.cqw(0.6)),
        child: Opacity(
          opacity: (value.isEmpty && !hidden) ? 0.35 : 1,
          child: Text(
            hidden || value.isEmpty ? _concealedCvc : value,
            style: style,
          ),
        ),
      ),
    );
  }

  void _emit(EganowCardField field, String value) {
    widget.onChanged?.call(field, value);
    setState(() {});
  }
}

/// The uppercase label stacked above a value on the card face.
class _LabelledSlot extends StatelessWidget {
  const _LabelledSlot({
    required this.metrics,
    required this.label,
    required this.child,
    this.alignEnd = false,
  });

  final EganowCardMetrics metrics;
  final String label;
  final Widget child;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          style: EganowFonts.urbanist(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: metrics.cqw(2.4),
            fontWeight: FontWeight.w600,
            letterSpacing: metrics.cqw(0.35),
          ),
        ),
        SizedBox(height: metrics.cqw(0.7)),
        child,
      ],
    );
  }
}

/// A text field sitting directly on the artwork. It carries no rule at rest —
/// the card reads exactly as printed — and takes a solid white underline only
/// while it holds focus.
class _OnCardInput extends StatelessWidget {
  const _OnCardInput({
    required this.metrics,
    required this.controller,
    required this.focusNode,
    required this.formatters,
    required this.style,
    required this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.alignEnd = false,
    this.underline = true,
    this.onChanged,
  });

  final EganowCardMetrics metrics;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<TextInputFormatter> formatters;
  final TextStyle style;
  final String hint;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool alignEnd;

  /// Draws the focus underline beneath the field.
  final bool underline;

  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final focused = focusNode.hasFocus;

    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      inputFormatters: formatters,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      textAlign: alignEnd ? TextAlign.right : TextAlign.left,
      cursorColor: Colors.white,
      style: style,
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: m.cqw(0.4)),
        hintText: hint,
        hintStyle: style.copyWith(color: Colors.white.withValues(alpha: 0.32)),
      ),
    );

    if (!underline || !focused) return field;

    return CustomPaint(
      foregroundPainter: _UnderlinePainter(
        thickness: m.cqw(0.35),
        color: Colors.white,
      ),
      child: field,
    );
  }
}

/// A labelled field in the form-mode entry sheet below the card.
class _FormField extends StatelessWidget {
  const _FormField({
    required this.onDark,
    required this.label,
    required this.hint,
    required this.controller,
    required this.focusNode,
    required this.formatters,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.monospaced = false,
    this.letterSpacing,
    this.onChanged,
  });

  final bool onDark;
  final String label;
  final String hint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<TextInputFormatter> formatters;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool monospaced;
  final double? letterSpacing;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final ink = onDark ? Colors.white : Colors.black;
    final focused = focusNode.hasFocus;

    final textStyle = monospaced
        ? EganowFonts.robotoMono(
            color: onDark ? Colors.white : Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: letterSpacing,
          )
        : EganowFonts.urbanist(
            color: onDark ? Colors.white : Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: letterSpacing,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: EganowFonts.urbanist(
            color: ink.withValues(alpha: 0.45),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 7),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: ink.withValues(alpha: focused ? 0.09 : 0.05),
            border: Border.all(
              color: ink.withValues(alpha: focused ? 0.42 : 0.12),
            ),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            inputFormatters: formatters,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            onChanged: onChanged,
            cursorColor: ink,
            style: textStyle,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
              hintText: hint,
              hintStyle: textStyle.copyWith(color: ink.withValues(alpha: 0.3)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Sweeps a highlight across its child while details are being fetched.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child, this.onDarkGround = true});

  final Widget child;

  /// The card front is dark and its text light; the CVC panel is the reverse.
  final bool onDarkGround;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.onDarkGround
        ? Colors.white.withValues(alpha: 0.38)
        : Colors.black.withValues(alpha: 0.30);
    final highlight = widget.onDarkGround
        ? Colors.white
        : Colors.black.withValues(alpha: 0.72);

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        // Slide the highlight band across, rather than moving gradient stops,
        // which would need clamping at both ends.
        final dx = -2.0 + 4.0 * _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(dx - 1, 0),
            end: Alignment(dx + 1, 0),
            colors: [base, highlight, base],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

/// Draws the contactless mark and pulses it.
///
/// The mark used to be baked into the artwork, which made it impossible to
/// animate; it has been inpainted out of both PNGs (see `tool/strip_nfc.py`)
/// and is drawn here instead. The geometry below was fitted to the original
/// artwork, so it lands exactly where the printed mark did.
class ContactlessMarkPainter extends CustomPainter {
  const ContactlessMarkPainter({this.progress});

  /// 0…1 and looping, or null to draw the mark at rest.
  final double? progress;

  /// Fitted off the source artwork — centre as a fraction of card width and
  /// height, radii and stroke as fractions of width — then drawn at 85% of
  /// that fit, which reads better against the chip than the printed mark did.
  ///
  /// Scaling alone would have pulled the mark leftwards, since the arcs shrink
  /// towards an origin that sits outside them; the centre is nudged right to
  /// compensate, so the smaller mark keeps the printed one's optical position
  /// rather than drifting towards the chip.
  static const double _centreX = 0.25347;
  static const double _centreY = 0.43545;
  static const List<double> _radii = [0.01685, 0.02848, 0.04151, 0.05493];
  static const double _stroke = 0.0062;

  /// The arcs open rightwards, each spanning a little less than the one
  /// inside it — measured, not assumed.
  static const List<double> _halfSweepDegrees = [62.5, 49.9, 46.2, 43.8];

  /// A highlight travels outward through the arcs on a loop: each brightens
  /// as the head reaches it and fades as the head moves on, so only one or
  /// two are lit at a time and the mark never reads as fully on.
  ///
  /// How many arcs either side of the head still catch light — under 2, so
  /// the whole mark is never lit at once.
  static const double _falloff = 1.35;

  /// Unlit arcs hold a little light, so the mark keeps its printed shape
  /// instead of pieces of it vanishing.
  static const double _dim = 0.2;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width * _centreX, size.height * _centreY);

    for (var i = 0; i < _radii.length; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = size.width * _stroke
        ..color = Colors.white.withValues(alpha: opacityAt(i));

      final halfSweep = _halfSweepDegrees[i] * math.pi / 180;
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: size.width * _radii[i]),
        -halfSweep,
        2 * halfSweep,
        false,
        paint,
      );
    }
  }

  /// Brightness of arc `index` as the highlight passes it. With no
  /// [progress] every arc is solid — the mark as printed.
  @visibleForTesting
  double opacityAt(int index) {
    final t = progress;
    if (t == null) return 1;

    // The head runs from just inside the first arc to just past the last, so
    // each cycle starts and ends with the mark clear.
    final head = -1.5 + (_radii.length + 2) * t;
    final lit = (1 - (index - head).abs() / _falloff).clamp(0.0, 1.0);

    return _dim + (1 - _dim) * lit;
  }

  @override
  bool shouldRepaint(ContactlessMarkPainter old) => old.progress != progress;
}

/// CSS `border-bottom: … dashed` has no Flutter equivalent, so it is drawn.
class _UnderlinePainter extends CustomPainter {
  const _UnderlinePainter({required this.thickness, required this.color});

  final double thickness;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;

    final y = size.height - thickness / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(_UnderlinePainter old) =>
      old.thickness != thickness || old.color != color;
}

/// The signature panel's `repeating-linear-gradient(115deg, …)` weave:
/// 1.4cqw of light, 1.4cqw of dark, tiled.
Gradient _signatureWeave(EganowCardMetrics metrics) {
  const angleDeg = 115.0;
  final period = metrics.cqw(2.8);

  // Half-extents of the panel, so px offsets can be expressed in the
  // -1..1 Alignment space the gradient uses.
  final halfWidth = metrics.width * 0.58 / 2;
  final halfHeight = metrics.height * 0.135 / 2;

  final radians = angleDeg * math.pi / 180;
  final dx = math.sin(radians) * period;
  final dy = -math.cos(radians) * period;

  return LinearGradient(
    begin: Alignment.center,
    end: Alignment(dx / halfWidth, dy / halfHeight),
    colors: const [
      EganowColors.signatureLight,
      EganowColors.signatureLight,
      EganowColors.signatureDark,
      EganowColors.signatureDark,
    ],
    stops: const [0.0, 0.5, 0.5, 1.0],
    tileMode: TileMode.repeated,
  );
}

/// Backs an editable field. [display] is applied whenever the field paints
/// (the holder's uppercase treatment); [mask] replaces it entirely while
/// [masked] is set, so the real characters are never rendered. Both leave
/// [text] untouched, which is what callers and `onChanged` observe.
class _CardFieldController extends TextEditingController {
  _CardFieldController({super.text, this.display, this.mask});

  final String Function(String raw)? display;
  final String Function(String raw)? mask;

  bool masked = false;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final shown = masked
        ? (mask?.call(text) ?? text)
        : (display?.call(text) ?? text);
    return TextSpan(text: shown, style: style);
  }
}
