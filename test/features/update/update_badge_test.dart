import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/features/update/update_badge.dart';

void main() {
  testWidgets('UpdateBadge renders the label and fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateBadge(onTap: () => taps++),
        ),
      ),
    );

    expect(find.text('Update'), findsOneWidget);

    await tester.tap(find.byKey(UpdateBadge.badgeKey));
    expect(taps, 1);
  });
}
