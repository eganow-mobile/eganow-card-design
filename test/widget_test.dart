import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show CachingAssetBundle, rootBundle;
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eganow_card/eganow_card.dart';
import 'package:eganow_card/src/eganow_card.dart' show ContactlessMarkPainter;

void main() {
  /// [WidgetTester.pumpAndSettle] never returns while the contactless mark is
  /// pulsing, so advance a bounded amount instead — long enough to carry the
  /// 700ms flip through to its end.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  }

  Widget wrap(EganowCard card, {double width = 362}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: card),
      ),
    ),
  );

  Future<void> pumpCard(
    WidgetTester tester,
    EganowCard card, {
    double width = 362,
  }) async {
    tester.view.physicalSize = const Size(402, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: card),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  group('PAN helpers', () {
    test('groups digits in fours, two spaces apart', () {
      expect(groupPan('5399840211744821'), '5399  8402  1174  4821');
      expect(groupPan('539984'), '5399  84');
    });

    test('masks every digit but the last four', () {
      expect(maskPan('5399  8402  1174  4821'), '••••  ••••  ••••  4821');
    });

    test('leaves a value with no digits alone', () {
      expect(maskPan(''), '');
    });
  });

  group('packaging', () {
    // The card is bundled into host apps as an internal package, so its
    // artwork has to resolve through `packages/<name>/…`, not the host's own
    // asset tree. Loading the bare path would work here and break there.
    for (final asset in [
      'eganow_boss_card.png',
      'eganow_freedom_card.png',
      'eganow_logo.png',
    ]) {
      testWidgets('$asset resolves as a package asset', (tester) async {
        final data = await rootBundle.load(
          'packages/${EganowCard.assetPackage}/assets/images/$asset',
        );
        expect(data.lengthInBytes, greaterThan(0));
      });

      testWidgets('$asset also resolves bare, for the demo app', (
        tester,
      ) async {
        // Running this project directly (rather than as a dependency) serves
        // the assets under both keys; the widget always uses the package one.
        final data = await rootBundle.load('assets/images/$asset');
        expect(data.lengthInBytes, greaterThan(0));
      });
    }
  });

  group('contactless chase', () {
    const arcs = [0, 1, 2, 3];

    test('is solid at rest', () {
      const painter = ContactlessMarkPainter();
      for (final arc in arcs) {
        expect(painter.opacityAt(arc), 1.0);
      }
    });

    test('never lights the whole mark at once', () {
      for (var step = 0; step <= 200; step++) {
        final t = step / 200;
        final painter = ContactlessMarkPainter(progress: t);
        final bright = arcs.where((a) => painter.opacityAt(a) > 0.9).length;
        expect(bright, lessThanOrEqualTo(2), reason: 'at progress $t');
      }
    });

    test('carries every arc to effectively full brightness in a cycle', () {
      for (final arc in arcs) {
        final peak = List.generate(
          201,
          (step) => ContactlessMarkPainter(progress: step / 200).opacityAt(arc),
        ).reduce((a, b) => a > b ? a : b);
        // Sampled on a 200-step grid, so the exact peak falls between steps.
        expect(peak, greaterThan(0.99), reason: 'arc $arc');
      }
    });

    test('travels outward — each arc peaks after the one inside it', () {
      double peakAt(int arc) {
        var best = 0.0, bestT = 0.0;
        for (var step = 0; step <= 200; step++) {
          final t = step / 200;
          final v = ContactlessMarkPainter(progress: t).opacityAt(arc);
          if (v > best) {
            best = v;
            bestT = t;
          }
        }
        return bestT;
      }

      final peaks = arcs.map(peakAt).toList();
      for (var i = 1; i < peaks.length; i++) {
        expect(peaks[i], greaterThan(peaks[i - 1]));
      }
    });
  });

  testWidgets('renders supplied values read-only', (tester) async {
    await pumpCard(
      tester,
      const EganowCard(
        pan: '5399  8402  1174  4821',
        holder: 'Alex Tantuo',
        expiry: '09/28',
      ),
    );

    expect(find.text('5399  8402  1174  4821'), findsOneWidget);
    expect(find.text('ALEX TANTUO'), findsOneWidget);
    expect(find.text('09/28'), findsNothing);
    expect(find.text('Card holder'), findsNothing);
    expect(find.text('CARD HOLDER'), findsNothing);
    expect(find.text('EXPIRY'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the back shows the expiry, read-only', (tester) async {
    await pumpCard(
      tester,
      const EganowCard(expiry: '09/28', cvc: '418', flipped: true),
    );

    expect(find.text('EXPIRY'), findsOneWidget);
    expect(find.text('09/28'), findsOneWidget);
  });

  testWidgets('the back hints MM/YY at reduced opacity when empty', (
    tester,
  ) async {
    await pumpCard(tester, const EganowCard(flipped: true));

    final hint = find.text('MM/YY');
    expect(hint, findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: hint, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, lessThan(1));
  });

  testWidgets('the back conceals the expiry under hideDetails', (tester) async {
    await pumpCard(
      tester,
      const EganowCard(expiry: '09/28', flipped: true, hideDetails: true),
    );

    expect(find.text('09/28'), findsNothing);
    expect(find.text('••/••'), findsOneWidget);
  });

  testWidgets('a caller-supplied expiry controller is concealed on the back', (
    tester,
  ) async {
    final controller = TextEditingController(text: '09/28');
    addTearDown(controller.dispose);

    await pumpCard(
      tester,
      EganowCard(
        editable: const {EganowCardField.expiry},
        controllers: {EganowCardField.expiry: controller},
        flipped: true,
        hideDetails: true,
      ),
    );

    expect(find.text('09/28'), findsNothing);
    expect(find.text('••/••'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('focusing the expiry in the form flips the card to the back', (
    tester,
  ) async {
    await pumpCard(
      tester,
      const EganowCard(
        editable: {EganowCardField.expiry},
        entry: EganowCardEntry.form,
      ),
    );

    expect(find.text('EXPIRY'), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await settle(tester);

    expect(find.text('EXPIRY'), findsNWidgets(2));
  });

  testWidgets('editable fields become text fields on the artwork', (
    tester,
  ) async {
    await pumpCard(
      tester,
      EganowCard(editable: EganowCardField.values.toSet()),
    );

    // PAN and holder live on the front; the expiry and CVC are on the back.
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('tapping turns the card over to reveal the CVC', (tester) async {
    await pumpCard(tester, const EganowCard(editable: {EganowCardField.cvc}));

    expect(find.text('CVV'), findsNothing);

    await tester.tap(find.byType(EganowCard));
    await settle(tester);

    expect(find.text('CVV'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  group('the form fields drive the flip', () {
    Future<void> pumpForm(WidgetTester tester, {bool? flipped}) => pumpCard(
      tester,
      EganowCard(
        editable: const {EganowCardField.pan, EganowCardField.expiry},
        entry: EganowCardEntry.form,
        flipped: flipped,
      ),
    );

    final onBack = find.text(EganowCard.defaultLegalText);

    testWidgets('focusing PAN or holder after the expiry un-flips', (
      tester,
    ) async {
      await pumpCard(
        tester,
        const EganowCard(
          editable: {
            EganowCardField.pan,
            EganowCardField.holder,
            EganowCardField.expiry,
          },
          entry: EganowCardEntry.form,
        ),
      );
      final fields = find.byType(TextField);

      expect(onBack, findsNothing);

      await tester.tap(fields.at(2));
      await settle(tester);
      expect(onBack, findsOneWidget);

      await tester.tap(fields.at(0));
      await settle(tester);
      expect(onBack, findsNothing);

      await tester.tap(fields.at(2));
      await settle(tester);
      expect(onBack, findsOneWidget);

      await tester.tap(fields.at(1));
      await settle(tester);
      expect(onBack, findsNothing);
    });

    testWidgets('a driven flipped: false ignores expiry focus', (tester) async {
      await pumpForm(tester, flipped: false);

      await tester.tap(find.byType(TextField).last);
      await settle(tester);

      expect(onBack, findsNothing);
    });
  });

  testWidgets('PAN entry is grouped and reported', (tester) async {
    final seen = <EganowCardField, String>{};

    await pumpCard(
      tester,
      EganowCard(
        editable: const {EganowCardField.pan},
        onChanged: (field, value) => seen[field] = value,
      ),
    );

    await tester.enterText(find.byType(TextField), '5399840211744821');
    await settle(tester);

    expect(seen[EganowCardField.pan], '5399  8402  1174  4821');
  });

  testWidgets('expiry entry masks to MM/YY', (tester) async {
    final seen = <EganowCardField, String>{};

    await pumpCard(
      tester,
      EganowCard(
        editable: const {EganowCardField.expiry},
        onChanged: (field, value) => seen[field] = value,
      ),
    );

    await tester.tap(find.byType(EganowCard));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '0928');
    await settle(tester);

    expect(seen[EganowCardField.expiry], '09/28');
  });

  testWidgets(
    'hideDetails conceals the PAN and holder on the front, which has no expiry',
    (tester) async {
      await pumpCard(
        tester,
        const EganowCard(
          pan: '5399  8402  1174  4821',
          holder: 'Alex Tantuo',
          expiry: '09/28',
          hideDetails: true,
        ),
      );

      // The PAN keeps its last four so the card stays identifiable.
      expect(find.text('••••  ••••  ••••  4821'), findsOneWidget);
      expect(find.text('5399  8402  1174  4821'), findsNothing);

      // Name and expiry are replaced outright — the name by a fixed-length run,
      // so its length isn't leaked either.
      expect(find.text('ALEX TANTUO'), findsNothing);
      expect(find.text('••••••••••••'), findsOneWidget);
      expect(find.text('09/28'), findsNothing);
      expect(find.text('••/••'), findsNothing);
    },
  );

  testWidgets('the full PAN fits between the card margins at any size', (
    tester,
  ) async {
    const pan = '5399  8402  1174  4821';

    for (final width in <double>[362, 280, 200]) {
      await pumpCard(tester, const EganowCard(pan: pan), width: width);

      final paragraph = tester.renderObject<RenderParagraph>(find.text(pan));

      // Every character is present — nothing elided.
      expect(paragraph.text.toPlainText(), pan);
      expect(paragraph.didExceedMaxLines, isFalse);

      // And it genuinely fits the 82% band, rather than overhanging it.
      expect(
        paragraph.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(width * 0.82 + 0.5),
      );
    }
  });

  testWidgets('values stay concealed while loading, and land when it clears', (
    tester,
  ) async {
    EganowCard card({required bool loading}) => EganowCard(
      pan: '5399  8402  1174  4821',
      holder: 'Alex Tantuo',
      isLoading: loading,
      animateContactless: false,
    );

    await pumpCard(tester, card(loading: true));

    expect(find.text('5399  8402  1174  4821'), findsNothing);
    expect(find.text('••••  ••••  ••••  4821'), findsOneWidget);
    expect(find.text('ALEX TANTUO'), findsNothing);

    // The caller owns the request; clearing it reveals the values at once.
    await tester.pumpWidget(wrap(card(loading: false)));
    await settle(tester);

    expect(find.text('5399  8402  1174  4821'), findsOneWidget);
    expect(find.text('ALEX TANTUO'), findsOneWidget);
  });

  testWidgets('form mode keeps the card read-only and collects below it', (
    tester,
  ) async {
    await pumpCard(
      tester,
      EganowCard(
        pan: '5399  8402  1174  4821',
        editable: EganowCardField.values.toSet(),
        entry: EganowCardEntry.form,
      ),
    );

    // All four fields are collected in the form, including the CVC — which
    // on-card would only exist once the card was turned over.
    expect(find.byType(TextField), findsNWidgets(4));
    expect(find.text('CARD NUMBER'), findsOneWidget);
    expect(find.text('NAME ON CARD'), findsOneWidget);

    // The artwork still shows the value as static text, not as an input.
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && w.data == '5399  8402  1174  4821',
      ),
      findsOneWidget,
    );
  });

  testWidgets('typing in the form updates the card face', (tester) async {
    await pumpCard(
      tester,
      const EganowCard(
        editable: {EganowCardField.holder},
        entry: EganowCardEntry.form,
      ),
    );

    expect(find.text('CARDHOLDER NAME'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Alex Tantuo');
    await settle(tester);

    expect(find.text('ALEX TANTUO'), findsOneWidget);
  });

  testWidgets('the chase speed follows contactlessCycle', (tester) async {
    // The mark is only drawn on a card that can be edited, so give it a field.
    EganowCard card({required bool loading}) => EganowCard(
      pan: '5399  8402  1174  4821',
      editable: const {EganowCardField.pan},
      isLoading: loading,
      contactlessCycle: const Duration(milliseconds: 400),
    );

    double? progress() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<ContactlessMarkPainter>()
        .single
        .progress;

    await pumpCard(tester, card(loading: false));
    await tester.pumpWidget(wrap(card(loading: true)));
    await tester.pump();

    // A quarter of a 400ms cycle in, the head is a quarter of the way round.
    await tester.pump(const Duration(milliseconds: 100));
    expect(progress(), closeTo(0.25, 0.02));

    await tester.pump(const Duration(milliseconds: 100));
    expect(progress(), closeTo(0.50, 0.02));

    // Clear the request so the ticker stops.
    await tester.pumpWidget(wrap(card(loading: false)));
    await tester.pump();
  });

  testWidgets('the mark is solid at rest and only sweeps while loading', (
    tester,
  ) async {
    EganowCard card({required bool loading}) => EganowCard(
      pan: '5399  8402  1174  4821',
      editable: const {EganowCardField.pan},
      isLoading: loading,
    );

    ContactlessMarkPainter mark() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<ContactlessMarkPainter>()
        .single;

    await pumpCard(tester, card(loading: false));

    // At rest the mark is drawn exactly as it was printed: every arc solid.
    expect(mark().progress, isNull);
    for (var i = 0; i < 4; i++) {
      expect(mark().opacityAt(i), 1.0);
    }

    await tester.pumpWidget(wrap(card(loading: true)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(mark().progress, isNotNull);
    expect(mark().opacityAt(3), lessThan(1.0));

    // Once the request lands, the mark goes back to solid.
    await tester.pumpWidget(wrap(card(loading: false)));
    await tester.pump();
    expect(mark().progress, isNull);
    expect(mark().opacityAt(3), 1.0);
  });

  testWidgets('the legal small print is caller-supplied', (tester) async {
    await pumpCard(
      tester,
      const EganowCard(legalText: 'Property of Eganow Ghana Ltd.'),
    );
    await tester.tap(find.byType(EganowCard));
    await settle(tester);

    expect(find.text('Property of Eganow Ghana Ltd.'), findsOneWidget);
    expect(find.textContaining('cardholder agreement'), findsNothing);
  });

  testWidgets('an empty legalText leaves the small print off', (tester) async {
    await pumpCard(tester, const EganowCard(legalText: ''));
    await tester.tap(find.byType(EganowCard));
    await settle(tester);

    expect(find.textContaining('Issued by Eganow'), findsNothing);
    // The rest of the back is still there.
    expect(find.text('CVV'), findsOneWidget);
  });

  testWidgets('hiding a card mid-edit conceals the field being edited', (
    tester,
  ) async {
    // The focus exemption keeps a concealed field typeable, but it must not
    // survive concealment being switched on — the value would stay in the
    // clear on the card face while everything around it masked.
    late StateSetter setOuter;
    var hide = false;

    tester.view.physicalSize = const Size(402, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return SizedBox(
                width: 362,
                child: EganowCard(
                  pan: '5399  8402  1174  4821',
                  holder: 'Alex Tantuo',
                  expiry: '09/28',
                  editable: const {EganowCardField.pan},
                  hideDetails: hide,
                ),
              );
            },
          ),
        ),
      ),
    );
    await settle(tester);

    String painted() => tester.allRenderObjects
        .whereType<RenderEditable>()
        .first
        .text!
        .toPlainText();

    await tester.tap(find.byType(TextField));
    await settle(tester);
    expect(painted(), '5399  8402  1174  4821');

    setOuter(() => hide = true);
    await settle(tester);
    expect(painted(), '••••  ••••  ••••  4821');
  });

  testWidgets('hideDetails conceals the form fields too, not just the card', (
    tester,
  ) async {
    await pumpCard(
      tester,
      const EganowCard(
        pan: '5399  8402  1174  4821',
        holder: 'Alex Tantuo',
        expiry: '09/28',
        cvc: '418',
        editable: {
          EganowCardField.pan,
          EganowCardField.holder,
          EganowCardField.expiry,
          EganowCardField.cvc,
        },
        entry: EganowCardEntry.form,
        hideDetails: true,
      ),
    );

    // The form is fed from the same controllers as the card, so it has to
    // mask as well — otherwise concealing the card just moves the values
    // a few pixels down the screen.
    final painted = tester.allRenderObjects
        .whereType<RenderEditable>()
        .map((e) => e.text!.toPlainText())
        .toList();

    expect(painted, isNot(contains('5399  8402  1174  4821')));
    expect(painted, contains('••••  ••••  ••••  4821'));
    expect(painted, isNot(contains('ALEX TANTUO')));
    expect(painted, isNot(contains('09/28')));
    expect(painted, isNot(contains('418')));
  });

  group('a read-only card', () {
    Finder markFinder() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is ContactlessMarkPainter,
    );

    // The mark is part of the card's face, not a state of it, so `editable`
    // and `isLoading` between them never take it away.
    for (final (name, card) in [
      ('at rest', EganowCard(pan: EganowCard.samplePan)),
      ('while loading', EganowCard(pan: EganowCard.samplePan, isLoading: true)),
      (
        'while loading with the chase disabled',
        EganowCard(
          pan: EganowCard.samplePan,
          isLoading: true,
          animateContactless: false,
        ),
      ),
    ]) {
      testWidgets('still wears the contactless mark $name', (tester) async {
        await pumpCard(tester, card);
        expect(markFinder(), findsOneWidget);
      });
    }

    testWidgets('wears it either side of a fetch', (tester) async {
      await pumpCard(
        tester,
        const EganowCard(pan: EganowCard.samplePan, isLoading: true),
      );
      expect(markFinder(), findsOneWidget);

      await tester.pumpWidget(
        wrap(const EganowCard(pan: EganowCard.samplePan)),
      );
      await settle(tester);
      expect(markFinder(), findsOneWidget);
    });

    testWidgets('wears it once a field is editable too', (tester) async {
      await pumpCard(
        tester,
        const EganowCard(
          pan: EganowCard.samplePan,
          editable: {EganowCardField.pan},
        ),
      );
      expect(markFinder(), findsOneWidget);
    });

    testWidgets('builds no inputs and no form', (tester) async {
      await pumpCard(
        tester,
        const EganowCard(
          pan: EganowCard.samplePan,
          holder: 'Alex Tantuo',
          // An entry mode without anything to collect stays display-only.
          entry: EganowCardEntry.form,
        ),
      );
      expect(find.byType(TextField), findsNothing);
    });
  });

  testWidgets('revealing dips the values out and back, swapping at the floor', (
    tester,
  ) async {
    late StateSetter setOuter;
    var hide = true;

    tester.view.physicalSize = const Size(402, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return SizedBox(
                width: 362,
                child: EganowCard(
                  pan: '5399  8402  1174  4821',
                  holder: 'Alex Tantuo',
                  expiry: '09/28',
                  hideDetails: hide,
                ),
              );
            },
          ),
        ),
      ),
    );
    await settle(tester);

    // Anchor on the PAN itself — the enclosing route has a FadeTransition of
    // its own, and the card's other slots dip alongside this one.
    double opacityOf(String text) => tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.text(text),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;

    const mask = '••••  ••••  ••••  4821';
    const real = '5399  8402  1174  4821';

    expect(opacityOf(mask), 1.0);

    setOuter(() => hide = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 45));

    // Half a dip in: faded down, and still showing the mask — the value must
    // not appear until the values are invisible.
    expect(opacityOf(mask), lessThan(1.0));
    expect(find.text(real), findsNothing);

    // Safe here: this card is read-only and not loading, so neither the
    // contactless chase nor the shimmer is running to hold settling open.
    await tester.pumpAndSettle();

    // Back to full strength, now carrying the real value.
    expect(opacityOf(real), 1.0);
    expect(find.text(mask), findsNothing);
  });

  testWidgets('the back carries no cardholder name', (tester) async {
    await pumpCard(
      tester,
      const EganowCard(
        pan: EganowCard.samplePan,
        holder: 'Alex Tantuo',
        expiry: '09/28',
        cvc: '418',
        flipped: true,
      ),
    );

    // The signature strip is blank: neither the name, nor the old placeholder,
    // nor the concealment mask that used to stand in for it.
    expect(find.text('Alex Tantuo'), findsNothing);
    expect(find.text('ALEX TANTUO'), findsNothing);
    expect(find.text('Cardholder signature'), findsNothing);
    expect(find.text('••••••••••••'), findsNothing);
  });

  testWidgets('and still carries none when the details are concealed', (
    tester,
  ) async {
    await pumpCard(
      tester,
      const EganowCard(
        pan: EganowCard.samplePan,
        holder: 'Alex Tantuo',
        cvc: '418',
        flipped: true,
        hideDetails: true,
      ),
    );

    expect(find.text('Alex Tantuo'), findsNothing);
    expect(find.text('ALEX TANTUO'), findsNothing);
    expect(find.text('••••••••••••'), findsNothing);
  });

  group('the balance', () {
    Finder eye() => find.byIcon(Icons.visibility_outlined);
    Finder eyeOff() => find.byIcon(Icons.visibility_off_outlined);

    /// The balance is a [Text.rich], so it has to be read span-and-all —
    /// the currency and the figure are separate spans.
    String balanceText(WidgetTester tester) => tester
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .firstWhere((t) => t.contains('GHS'), orElse: () => '<none>');

    testWidgets('is absent unless a balance is given', (tester) async {
      await pumpCard(tester, const EganowCard(pan: EganowCard.samplePan));
      expect(eye(), findsNothing);
      expect(eyeOff(), findsNothing);
    });

    testWidgets('shows the value verbatim, with an open eye', (tester) async {
      await pumpCard(
        tester,
        const EganowCard(
          pan: EganowCard.samplePan,
          balance: '1000',
          currency: 'GHS',
        ),
      );
      expect(balanceText(tester), 'GHS1000');
      expect(eye(), findsOneWidget);
    });

    testWidgets('the eye conceals and reveals, and reports both ways', (
      tester,
    ) async {
      final seen = <bool>[];
      await pumpCard(
        tester,
        EganowCard(
          pan: EganowCard.samplePan,
          balance: '1000',
          currency: 'GHS',
          onBalanceVisibilityChanged: seen.add,
        ),
      );

      await tester.tap(eye());
      await settle(tester);
      // The currency rides through concealment; only the figure is masked.
      expect(balanceText(tester), 'GHS••••••');
      expect(eyeOff(), findsOneWidget);

      await tester.tap(eyeOff());
      await settle(tester);
      expect(balanceText(tester), 'GHS1000');
      expect(seen, [true, false]);
    });

    testWidgets('a driven card reports but does not move itself', (
      tester,
    ) async {
      final seen = <bool>[];
      await pumpCard(
        tester,
        EganowCard(
          pan: EganowCard.samplePan,
          balance: '1000',
          currency: 'GHS',
          hideBalance: true,
          onBalanceVisibilityChanged: seen.add,
        ),
      );
      expect(balanceText(tester), 'GHS••••••');

      await tester.tap(eyeOff());
      await settle(tester);

      // The caller owns the value, so the card waits to be given the new one.
      expect(seen, [false]);
      expect(balanceText(tester), 'GHS••••••');
    });

    testWidgets('is not concealed by hideDetails', (tester) async {
      await pumpCard(
        tester,
        const EganowCard(
          pan: EganowCard.samplePan,
          holder: 'Kwaku Ananse',
          balance: '1000',
          currency: 'GHS',
          hideDetails: true,
        ),
      );
      expect(balanceText(tester), 'GHS1000');
      expect(find.text('••••••••••••'), findsOneWidget);
    });

    testWidgets('and does not conceal the rest of the card', (tester) async {
      await pumpCard(
        tester,
        const EganowCard(
          pan: EganowCard.samplePan,
          holder: 'Kwaku Ananse',
          balance: '1000',
          currency: 'GHS',
          hideBalance: true,
        ),
      );
      expect(balanceText(tester), 'GHS••••••');
      expect(find.text(EganowCard.samplePan), findsOneWidget);
      expect(find.text('KWAKU ANANSE'), findsOneWidget);
    });

    testWidgets('tapping the eye does not turn the card over', (tester) async {
      await pumpCard(
        tester,
        const EganowCard(
          pan: EganowCard.samplePan,
          cvc: '418',
          balance: '1000',
          currency: 'GHS',
        ),
      );

      await tester.tap(eye());
      await settle(tester);

      // The eye's gesture sits deeper than the card's tap-to-flip, so it
      // wins the arena outright.
      expect(find.text('CVV'), findsNothing);
      expect(balanceText(tester), 'GHS••••••');
    });

    testWidgets('is gone entirely when showBalance is false', (tester) async {
      await pumpCard(
        tester,
        const EganowCard(
          pan: EganowCard.samplePan,
          balance: '1000',
          currency: 'GHS',
          showBalance: false,
        ),
      );
      expect(balanceText(tester), '<none>');
      expect(eye(), findsNothing);
      expect(eyeOff(), findsNothing);
    });

    testWidgets('gives its corner back to the card\'s tap-to-flip', (
      tester,
    ) async {
      await pumpCard(
        tester,
        const EganowCard(
          pan: EganowCard.samplePan,
          cvc: '418',
          balance: '1000',
          currency: 'GHS',
          hideBalance: true,
        ),
      );
      final corner = tester.getCenter(eyeOff());

      await pumpCard(
        tester,
        const EganowCard(
          pan: EganowCard.samplePan,
          cvc: '418',
          balance: '1000',
          currency: 'GHS',
          hideBalance: true,
          showBalance: false,
        ),
      );
      await tester.tapAt(corner);
      await settle(tester);

      // Flipping proves the row is gone from the tree rather than merely
      // unpainted — anything left behind would swallow the tap.
      expect(find.text('CVV'), findsOneWidget);
    });

    testWidgets('keeps its concealment across being taken away and put back', (
      tester,
    ) async {
      late StateSetter setOuter;
      var show = true;

      tester.view.physicalSize = const Size(402, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  setOuter = setState;
                  return SizedBox(
                    width: 362,
                    child: EganowCard(
                      pan: EganowCard.samplePan,
                      balance: '1000',
                      currency: 'GHS',
                      showBalance: show,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await settle(tester);

      await tester.tap(eye());
      await settle(tester);
      expect(balanceText(tester), 'GHS••••••');

      setOuter(() => show = false);
      await settle(tester);
      expect(balanceText(tester), '<none>');

      setOuter(() => show = true);
      await settle(tester);
      expect(balanceText(tester), 'GHS••••••');
      expect(eyeOff(), findsOneWidget);
    });
  });

  group('the medium badge', () {
    testWidgets('is absent unless a medium is given', (tester) async {
      await pumpCard(tester, const EganowCard(pan: EganowCard.samplePan));
      expect(find.text('Virtual'), findsNothing);
      expect(find.text('Physical'), findsNothing);
    });

    for (final (medium, caption) in [
      (EganowCardMedium.virtual, 'Virtual'),
      (EganowCardMedium.physical, 'Physical'),
    ]) {
      testWidgets('captions the front $caption', (tester) async {
        await pumpCard(
          tester,
          EganowCard(pan: EganowCard.samplePan, medium: medium),
        );
        expect(find.text(caption), findsOneWidget);
      });
    }

    testWidgets('stays put while the values are concealed', (tester) async {
      // The medium isn't a secret, so hideDetails must not take it with it.
      await pumpCard(
        tester,
        const EganowCard(
          pan: EganowCard.samplePan,
          holder: 'Kwaku Ananse',
          medium: EganowCardMedium.virtual,
          hideDetails: true,
        ),
      );
      expect(find.text('Virtual'), findsOneWidget);
      expect(find.text('••••••••••••'), findsOneWidget);
    });

    testWidgets('belongs to the front, not the back', (tester) async {
      await pumpCard(
        tester,
        const EganowCard(
          pan: EganowCard.samplePan,
          cvc: '418',
          medium: EganowCardMedium.virtual,
          flipped: true,
        ),
      );
      expect(find.text('Virtual'), findsNothing);
    });
  });

  testWidgets('the back expiry never overlaps the legal text', (tester) async {
    tester.view.physicalSize = const Size(402, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final width in <double>[200, 280, 362]) {
      for (final scale in <double>[1.0, 1.5, 2.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: width,
                    child: const EganowCard(
                      expiry: '09/28',
                      cvc: '418',
                      flipped: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await settle(tester);

        final value = tester.getRect(find.text('09/28'));
        final legal = tester.getRect(find.text(EganowCard.defaultLegalText));
        expect(
          value.bottom,
          lessThanOrEqualTo(legal.top),
          reason: 'width $width, scale $scale',
        );
      }
    }
  });

  group('the network logo', () {
    Finder logo(String label) => find.bySemanticsLabel(label);

    testWidgets('is absent unless a network is given', (tester) async {
      await pumpCard(tester, const EganowCard(pan: EganowCard.samplePan));
      expect(logo('Visa'), findsNothing);
      expect(logo('Mastercard'), findsNothing);
    });

    for (final (network, label) in [
      (EganowCardNetwork.visa, 'Visa'),
      (EganowCardNetwork.mastercard, 'Mastercard'),
    ]) {
      testWidgets('draws $label on the front only', (tester) async {
        await pumpCard(
          tester,
          EganowCard(pan: EganowCard.samplePan, network: network),
        );
        expect(logo(label), findsOneWidget);

        await tester.tap(find.byType(EganowCard));
        await settle(tester);
        expect(find.text(EganowCard.defaultLegalText), findsOneWidget);
        expect(logo(label), findsNothing);
      });
    }

    for (final (network, asset) in [
      (EganowCardNetwork.visa, 'assets/images/visa.svg'),
      (EganowCardNetwork.mastercard, 'assets/images/mastercard.svg'),
    ]) {
      testWidgets('${network.name} loads $asset from the package', (
        tester,
      ) async {
        await pumpCard(
          tester,
          EganowCard(pan: EganowCard.samplePan, network: network),
        );
        final loader =
            tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader
                as SvgAssetLoader;
        expect(loader.assetName, asset);
        expect(loader.packageName, EganowCard.assetPackage);
      });
    }

    for (final network in EganowCardNetwork.values) {
      for (final (name, card) in <(String, EganowCard Function())>[
        ('a holder', () => EganowCard(holder: 'Alex Tantuo', network: network)),
        ('no holder', () => EganowCard(network: network)),
        (
          'concealed',
          () => EganowCard(
            holder: 'Alex Tantuo',
            network: network,
            hideDetails: true,
          ),
        ),
        (
          'an editable holder',
          () => EganowCard(
            network: network,
            editable: const {EganowCardField.holder},
          ),
        ),
      ]) {
        testWidgets('${network.name} is centred on the holder with $name', (
          tester,
        ) async {
          await pumpCard(tester, card());
          double centre(RenderBox b) =>
              b.localToGlobal(b.size.center(Offset.zero)).dy;
          final holderBox = find
              .descendant(
                of: find.byType(EganowCard),
                matching: find.byWidgetPredicate(
                  (w) => w is Text || w is EditableText,
                ),
              )
              .evaluate()
              .map((e) => e.renderObject! as RenderBox)
              .reduce((a, b) => centre(a) > centre(b) ? a : b);
          final logoBox = tester.renderObject<RenderBox>(
            find.descendant(
              of: logo(network.label),
              matching: find.byType(DecoratedBox),
            ),
          );
          expect(centre(logoBox), closeTo(centre(holderBox), 0.5));
        });
      }
    }

    testWidgets('is not concealed by hideDetails', (tester) async {
      await pumpCard(
        tester,
        const EganowCard(
          pan: EganowCard.samplePan,
          network: EganowCardNetwork.mastercard,
          hideDetails: true,
        ),
      );
      expect(logo('Mastercard'), findsOneWidget);
    });

    for (final network in EganowCardNetwork.values) {
      testWidgets(
        'does not overflow narrow cards at large text scale: ${network.name}',
        (tester) async {
          tester.view.physicalSize = const Size(402, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 200,
                      child: EganowCard(
                        holder: 'Alexandra Tantuo-Mensah',
                        network: network,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await settle(tester);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );

      for (final stalled in [true, false]) {
        testWidgets(
          '${network.name} is final-size ${stalled ? 'before' : 'after'} '
          'the SVG loads',
          (tester) async {
            tester.view.physicalSize = const Size(402, 900);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              DefaultAssetBundle(
                bundle: stalled ? _StalledBundle() : rootBundle,
                child: MaterialApp(
                  home: Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: 362,
                        child: EganowCard(
                          holder: 'Alex Tantuo',
                          network: network,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            if (!stalled) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 200)),
              );
              await tester.pump();
              await tester.pump();
            }

            final pill = tester.getSize(
              find.descendant(
                of: find.bySemanticsLabel(network.label),
                matching: find.byType(DecoratedBox),
              ),
            );
            final (height, aspect) = switch (network) {
              EganowCardNetwork.visa => (3.4, 81 / 27),
              EganowCardNetwork.mastercard => (5.2, 72 / 56),
            };
            const pad = 362 * 0.008;
            expect(pill.height, closeTo(362 * height / 100 + 2 * pad, 0.01));
            expect(
              pill.width,
              closeTo(362 * height / 100 * aspect + 2 * pad, 0.01),
            );
          },
        );
      }
    }
  });

  group('the security code caption', () {
    for (final (network, caption) in [
      (EganowCardNetwork.visa, 'CVV'),
      (EganowCardNetwork.mastercard, 'CVC'),
    ]) {
      testWidgets('follows the network: ${network.name} is $caption', (
        tester,
      ) async {
        await pumpCard(
          tester,
          EganowCard(
            cvc: '418',
            editable: const {EganowCardField.cvc},
            entry: EganowCardEntry.form,
            flipped: true,
            network: network,
          ),
        );

        expect(find.text(caption), findsNWidgets(2));
      });
    }

    testWidgets('is CVV with no network, on the back and in the form', (
      tester,
    ) async {
      await pumpCard(
        tester,
        const EganowCard(
          cvc: '418',
          editable: {EganowCardField.cvc},
          entry: EganowCardEntry.form,
          flipped: true,
        ),
      );

      // Once on the artwork, once as the form field's label.
      expect(find.text('CVV'), findsNWidgets(2));
      expect(find.text('CVC'), findsNothing);
    });
  });

  testWidgets('a concealed editable field paints the mask, never the value', (
    tester,
  ) async {
    await pumpCard(
      tester,
      const EganowCard(
        pan: '5399  8402  1174  4821',
        editable: {EganowCardField.pan},
        hideDetails: true,
      ),
    );

    // EditableText's nearest render object isn't the RenderEditable itself.
    String painted() => tester.allRenderObjects
        .whereType<RenderEditable>()
        .first
        .text!
        .toPlainText();

    // What reaches the screen is the mask...
    expect(painted(), '••••  ••••  ••••  4821');
    // ...while the real value stays intact behind it.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '5399  8402  1174  4821',
    );

    // Focusing reveals it, so the field is still usable for entry.
    await tester.tap(find.byType(TextField));
    await settle(tester);
    expect(painted(), '5399  8402  1174  4821');
  });

  group('the card number stays inside the card margins', () {
    const pan = '5399  8402  1174  4821';
    const masked = '••••  ••••  ••••  4821';

    // A paragraph's own size is clamped to its constraints even when the
    // glyphs paint beyond them, so measure the boxes the text really occupies.
    double paintedRight(RenderBox renderer, InlineSpan text) {
      final selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.toPlainText().length,
      );
      final boxes = renderer is RenderEditable
          ? renderer.getBoxesForSelection(selection)
          : (renderer as RenderParagraph).getBoxesForSelection(selection);

      return boxes
          .map((b) => renderer.localToGlobal(Offset(b.right, 0)).dx)
          .reduce((a, b) => a > b ? a : b);
    }

    RenderBox paragraphOf(WidgetTester tester, String text) =>
        tester.renderObject<RenderParagraph>(find.text(text));

    RenderBox editableOf(WidgetTester tester) =>
        tester.allRenderObjects.whereType<RenderEditable>().single;

    Future<void> pumpScaled(
      WidgetTester tester,
      EganowCard card, {
      required double width,
      required double scale,
    }) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Tear the previous combination down so no state carries over.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: width, child: card),
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
    }

    void variant(
      String name,
      EganowCard Function() card,
      RenderBox Function(WidgetTester tester) locate,
    ) {
      testWidgets(name, (tester) async {
        for (final width in [200.0, 280.0, 320.0, 362.0]) {
          for (final scale in [1.0, 1.3, 1.5, 2.0]) {
            await pumpScaled(tester, card(), width: width, scale: scale);

            final renderer = locate(tester);
            final text = renderer is RenderEditable
                ? renderer.text!
                : (renderer as RenderParagraph).text;

            // Trailing letter-spacing on the last glyph overshoots by < 0.2dp.
            // The hint and the concealed fallback ellipsize instead of
            // spilling, so their boxes stay in bounds while the number is cut.
            if (renderer is RenderParagraph) {
              expect(
                renderer.didExceedMaxLines,
                isFalse,
                reason: '$name at ${width}dp, text scale $scale is truncated',
              );
            }
            expect(
              paintedRight(renderer, text),
              lessThanOrEqualTo(width * 0.91 + 0.2),
              reason: '$name at ${width}dp, text scale $scale',
            );
          }
        }
      });
    }

    variant(
      'revealed',
      () => const EganowCard(pan: pan),
      (tester) => paragraphOf(tester, pan),
    );

    variant(
      'masked',
      () => const EganowCard(pan: pan, hideDetails: true),
      (tester) => paragraphOf(tester, masked),
    );

    variant(
      'a 19-digit number',
      () => const EganowCard(pan: '5399  8402  1174  4821  123'),
      (tester) => paragraphOf(tester, '5399  8402  1174  4821  123'),
    );

    variant(
      'editable',
      () => const EganowCard(pan: pan, editable: {EganowCardField.pan}),
      editableOf,
    );

    variant(
      'editable and masked',
      () => const EganowCard(
        pan: pan,
        editable: {EganowCardField.pan},
        hideDetails: true,
      ),
      editableOf,
    );

    // With no text the RenderEditable has nothing to measure; the hint is its
    // own paragraph.
    variant(
      'editable with no value',
      () => const EganowCard(editable: {EganowCardField.pan}),
      (tester) => paragraphOf(tester, '••••  ••••  ••••  ••••'),
    );

    variant('editable with a caller-supplied controller, concealed', () {
      final controller = TextEditingController(text: pan);
      addTearDown(controller.dispose);
      return EganowCard(
        controllers: {EganowCardField.pan: controller},
        editable: const {EganowCardField.pan},
        hideDetails: true,
      );
    }, (tester) => paragraphOf(tester, masked));
  });
}

class _StalledBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Completer<ByteData>().future;
}
