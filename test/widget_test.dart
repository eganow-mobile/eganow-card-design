import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/rendering.dart';
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
    expect(find.text('09/28'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('editable fields become text fields on the artwork', (
    tester,
  ) async {
    await pumpCard(
      tester,
      EganowCard(editable: EganowCardField.values.toSet()),
    );

    // PAN, holder and expiry live on the front; the CVC is on the back.
    expect(find.byType(TextField), findsNWidgets(3));
  });

  testWidgets('tapping turns the card over to reveal the CVC', (tester) async {
    await pumpCard(tester, const EganowCard(editable: {EganowCardField.cvc}));

    expect(find.text('CVV'), findsNothing);

    await tester.tap(find.byType(EganowCard));
    await settle(tester);

    expect(find.text('CVV'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
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

    await tester.enterText(find.byType(TextField), '0928');
    await settle(tester);

    expect(seen[EganowCardField.expiry], '09/28');
  });

  testWidgets('hideDetails conceals every value on the front', (tester) async {
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
    expect(find.text('••/••'), findsOneWidget);
  });

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

    testWidgets('leaves the contactless mark off', (tester) async {
      await pumpCard(tester, const EganowCard(pan: EganowCard.samplePan));
      expect(markFinder(), findsNothing);
    });

    testWidgets('leaves it off while loading, too', (tester) async {
      await pumpCard(
        tester,
        const EganowCard(pan: EganowCard.samplePan, isLoading: true),
      );
      expect(markFinder(), findsNothing);
    });

    testWidgets('still draws the mark once a field is editable', (
      tester,
    ) async {
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

  group('the security code caption', () {
    testWidgets('is CVV by default, on the back and in the form', (
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

    testWidgets('follows securityCodeLabel', (tester) async {
      await pumpCard(
        tester,
        const EganowCard(
          cvc: '418',
          editable: {EganowCardField.cvc},
          entry: EganowCardEntry.form,
          flipped: true,
          securityCodeLabel: EganowSecurityCodeLabel.cvc,
        ),
      );

      expect(find.text('CVC'), findsNWidgets(2));
      expect(find.text('CVV'), findsNothing);
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
}
