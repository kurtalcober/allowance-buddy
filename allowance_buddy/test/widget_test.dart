import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allowance_buddy/main.dart';

void main() {
  group('Budget', () {
    test('recalculates the daily limit as expenses and days change', () {
      final budget = Budget()..setup(100, 5);
      final lunch = Expense(
        note: 'Lunch',
        amount: 15,
        category: categories.first,
      );

      expect(budget.limitToday, 20);
      budget.add(lunch);
      expect(budget.moneyLeft, 85);
      expect(budget.remainingToday, 5);

      budget.nextDay();
      expect(budget.daysLeft, 4);
      expect(budget.limitToday, 21.25);
      expect(budget.spentToday, 0);

      budget.remove(lunch);
      expect(budget.moneyLeft, 100);
      expect(budget.spentTotal, 0);
    });

    test('rejects invalid budgets and expenses', () {
      final budget = Budget();

      expect(() => budget.setup(0, 5), throwsArgumentError);
      expect(() => budget.setup(100, 0), throwsArgumentError);
      expect(
        () => budget.add(
          Expense(note: 'Invalid', amount: -1, category: categories.first),
        ),
        throwsStateError,
      );

      budget.setup(100, 5);
      expect(
        () => budget.add(
          Expense(note: 'Invalid', amount: -1, category: categories.first),
        ),
        throwsArgumentError,
      );
    });
  });

  testWidgets('sets up an allowance and records an expense', (tester) async {
    await tester.pumpWidget(const AllowanceBuddy());

    expect(find.text('Know how much you can spend today'), findsOneWidget);
    await tester.tap(find.text('Set up allowance'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '100');
    await tester.enterText(fields.at(1), '5');
    await tester.tap(find.text('Start budgeting'));
    await tester.pumpAndSettle();

    expect(find.text('Day 1 of 5'), findsOneWidget);
    expect(find.text('₱20.00'), findsOneWidget);

    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '15');
    await tester.enterText(find.byType(TextField).at(1), 'Lunch');
    final addButton = find.widgetWithText(FilledButton, 'Add expense');
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(find.text('₱5.00'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('-₱15.00'), findsOneWidget);
  });
}
