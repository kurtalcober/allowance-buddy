import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const AllowanceBuddy());

// ---------------------------------------------------------------------------
// Design tokens (one place for colors and text = consistency)
// ---------------------------------------------------------------------------
class AppColors {
  static const bg = Color(0xFF0E1412);
  static const surface = Color(0xFF17201C);
  static const surfaceHigh = Color(0xFF1F2B26);
  static const accent = Color(0xFF3DDC97);
  static const warn = Color(0xFFFFB454);
  static const danger = Color(0xFFFF6B6B);
  static const text = Color(0xFFF2F7F4);
  static const textDim = Color(0xFF8FA39A);
}

class AppText {
  static const label = TextStyle(
    color: AppColors.textDim,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
  );
  static const dim = TextStyle(color: AppColors.textDim, fontSize: 13);
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------
class AllowanceBuddy extends StatelessWidget {
  const AllowanceBuddy({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppColors.accent,
          onPrimary: Colors.black,
          surface: AppColors.surface,
        );

    return MaterialApp(
      title: 'Allowance Buddy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: AppColors.bg,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceHigh,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: Color(0x333DDC97),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: AppColors.surfaceHigh,
          contentTextStyle: TextStyle(color: AppColors.text),
          actionTextColor: AppColors.accent,
        ),
      ),
      home: const AppShell(),
    );
  }
}

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------
class SpendCategory {
  final String name;
  final IconData icon;
  const SpendCategory(this.name, this.icon);
}

const categories = [
  SpendCategory('Food', Icons.restaurant_rounded),
  SpendCategory('Fare', Icons.directions_bus_rounded),
  SpendCategory('School', Icons.school_rounded),
  SpendCategory('Load', Icons.phone_android_rounded),
  SpendCategory('Other', Icons.category_rounded),
];

class Expense {
  final String note;
  final double amount;
  final SpendCategory category;
  int day = 0; // which budget day it belongs to (0 = first day)
  Expense({required this.note, required this.amount, required this.category});
}

String peso(double v, {int decimals = 2}) {
  final neg = v < -0.004;
  final s = v.abs().toStringAsFixed(decimals);
  final parts = s.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
  final dec = parts.length > 1 ? '.${parts[1]}' : '';
  return '${neg ? '-' : ''}₱$whole$dec';
}

class Budget extends ChangeNotifier {
  double startMoney = 0;
  double moneyLeft = 0;
  int totalDays = 0;
  int dayIndex = 0; // 0-based
  final List<Expense> expenses = [];

  bool get isSetUp => totalDays > 0;
  int get daysLeft => totalDays - dayIndex;

  double get spentToday => expenses
      .where((e) => e.day == dayIndex)
      .fold(0.0, (sum, e) => sum + e.amount);

  double get spentTotal => startMoney - moneyLeft;

  double get limitToday =>
      daysLeft > 0 ? (moneyLeft + spentToday) / daysLeft : 0;

  double get remainingToday => limitToday - spentToday;

  bool get isOver => spentToday > limitToday + 0.005;

  double get ratio {
    if (limitToday <= 0) return spentToday > 0 ? 1.0 : 0.0;
    return (spentToday / limitToday).clamp(0.0, 1.0).toDouble();
  }

  // The "runway": how many more days the money lasts at your average pace.
  double? get paceDays {
    if (spentTotal <= 0) return null;
    final avg = spentTotal / (dayIndex + 1);
    return moneyLeft <= 0 ? 0 : moneyLeft / avg;
  }

  bool get paceOk {
    final p = paceDays;
    return p == null || p >= daysLeft;
  }

  String get insight {
    final p = paceDays;
    if (p == null) {
      return "Add your first expense and I'll predict how long your money will last.";
    }
    if (moneyLeft <= 0) {
      return 'You have used all your money. Try not to spend until your next allowance.';
    }
    if (p >= daysLeft) {
      return 'At this pace, your money lasts until your next allowance.';
    }
    final early = (daysLeft - p).ceil();
    final unit = early == 1 ? 'day' : 'days';
    return 'At this pace, you could run out about $early $unit early.';
  }

  void setup(double money, int days) {
    if (!money.isFinite || money <= 0) {
      throw ArgumentError.value(money, 'money', 'Must be a positive amount');
    }
    if (days <= 0) {
      throw ArgumentError.value(days, 'days', 'Must be a positive number');
    }
    startMoney = money;
    moneyLeft = money;
    totalDays = days;
    dayIndex = 0;
    expenses.clear();
    notifyListeners();
  }

  void add(Expense e) {
    if (!isSetUp) {
      throw StateError('Set up an allowance before adding expenses');
    }
    if (!e.amount.isFinite || e.amount <= 0) {
      throw ArgumentError.value(
        e.amount,
        'amount',
        'Must be a positive amount',
      );
    }
    e.day = dayIndex;
    expenses.insert(0, e);
    moneyLeft -= e.amount;
    notifyListeners();
  }

  void remove(Expense e) {
    if (expenses.remove(e)) {
      moneyLeft += e.amount;
      notifyListeners();
    }
  }

  void restore(Expense e, int index) {
    final i = index.clamp(0, expenses.length).toInt();
    expenses.insert(i, e);
    moneyLeft -= e.amount;
    notifyListeners();
  }

  void nextDay() {
    if (daysLeft > 1) {
      dayIndex++;
      notifyListeners();
    }
  }
}

// ---------------------------------------------------------------------------
// Shell: bottom navigation + one primary action
// ---------------------------------------------------------------------------
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final budget = Budget();
  int tab = 0;

  void _toast(String msg, {String? actionLabel, VoidCallback? onAction}) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: actionLabel == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
  }

  void _sheet(Widget Function(BuildContext) builder) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: builder,
    );
  }

  void _openSetup() {
    _sheet(
      (ctx) => SetupSheet(
        isEdit: budget.isSetUp,
        onDone: (money, days) {
          budget.setup(money, days);
          Navigator.pop(ctx);
          HapticFeedback.mediumImpact();
          _toast('Ready! Safe to spend ${peso(budget.limitToday)} a day.');
        },
      ),
    );
  }

  void _openAdd() {
    if (!budget.isSetUp) {
      _openSetup();
      return;
    }
    _sheet(
      (ctx) => AddExpenseSheet(
        onAdd: (e) {
          budget.add(e);
          Navigator.pop(ctx);
          HapticFeedback.lightImpact();
          _toast(
            '${peso(e.amount)} added to ${e.note}',
            actionLabel: 'Undo',
            onAction: () => budget.remove(e),
          );
        },
      ),
    );
  }

  void _delete(Expense e) {
    final index = budget.expenses.indexOf(e);
    budget.remove(e);
    HapticFeedback.mediumImpact();
    _toast(
      'Deleted ${e.note}',
      actionLabel: 'Undo',
      onAction: () => budget.restore(e, index),
    );
  }

  void _nextDay() {
    budget.nextDay();
    HapticFeedback.selectionClick();
    _toast(
      'Day ${budget.dayIndex + 1} of ${budget.totalDays}. New limit: ${peso(budget.limitToday)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: budget,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: tab == 0
                  ? HomePage(
                      key: const ValueKey('home'),
                      budget: budget,
                      onSetup: _openSetup,
                      onSeeAll: () => setState(() => tab = 1),
                      onNextDay: _nextDay,
                    )
                  : HistoryPage(
                      key: const ValueKey('history'),
                      budget: budget,
                      onDelete: _delete,
                    ),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openAdd,
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.black,
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'Add expense',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'History',
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable pieces
// ---------------------------------------------------------------------------
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: child,
    );
  }
}

class StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppText.dim),
        ],
      ),
    );
  }
}

class ExpenseTile extends StatelessWidget {
  final Expense e;
  const ExpenseTile({super.key, required this.e});

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0x1F3DDC97),
              shape: BoxShape.circle,
            ),
            child: Icon(e.category.icon, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  '${e.category.name} · Day ${e.day + 1}',
                  style: AppText.dim,
                ),
              ],
            ),
          ),
          Text(
            '-${peso(e.amount)}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  RingPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 10;
    final track = Paint()
      ..color = const Color(0x1AFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.progress != progress || old.color != color;
}

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------
class HomePage extends StatelessWidget {
  final Budget budget;
  final VoidCallback onSetup;
  final VoidCallback onSeeAll;
  final VoidCallback onNextDay;

  const HomePage({
    super.key,
    required this.budget,
    required this.onSetup,
    required this.onSeeAll,
    required this.onNextDay,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
      children: [
        _header(),
        const SizedBox(height: 20),
        if (!budget.isSetUp) _emptyState() else ..._dashboard(),
      ],
    );
  }

  Widget _header() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Allowance Buddy',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              SizedBox(height: 2),
              Text('Spend smart until payday', style: AppText.dim),
            ],
          ),
        ),
        IconButton(
          onPressed: onSetup,
          tooltip: 'Edit allowance',
          icon: const Icon(Icons.tune_rounded, color: AppColors.textDim),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Panel(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0x1F3DDC97),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.savings_rounded,
              size: 36,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Know how much you can spend today',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tell me your money and how many days until your next allowance. I will do the math.',
            textAlign: TextAlign.center,
            style: AppText.dim,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: onSetup,
              child: const Text(
                'Set up allowance',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _dashboard() {
    final b = budget;
    final recent = b.expenses.take(3).toList();
    return [
      _hero(),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: StatTile(
              icon: Icons.account_balance_wallet_rounded,
              label: 'Money left',
              value: peso(b.moneyLeft, decimals: 0),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatTile(
              icon: Icons.calendar_today_rounded,
              label: 'Days left',
              value: '${b.daysLeft}',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatTile(
              icon: Icons.shopping_bag_rounded,
              label: 'Spent today',
              value: peso(b.spentToday, decimals: 0),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Panel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              b.paceOk
                  ? Icons.trending_up_rounded
                  : Icons.warning_amber_rounded,
              color: b.paceOk ? AppColors.accent : AppColors.warn,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('RUNWAY', style: AppText.label),
                  const SizedBox(height: 4),
                  Text(
                    b.insight,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton.icon(
          onPressed: b.daysLeft > 1 ? onNextDay : null,
          icon: const Icon(Icons.wb_sunny_outlined),
          label: Text(
            b.daysLeft > 1
                ? 'Start next day'
                : 'Last day before your next allowance',
          ),
        ),
      ),
      const SizedBox(height: 26),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Recent',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
          ),
          if (b.expenses.isNotEmpty)
            TextButton(onPressed: onSeeAll, child: const Text('See all')),
        ],
      ),
      const SizedBox(height: 8),
      if (recent.isEmpty)
        const Panel(
          child: Text(
            'No expenses yet. Tap "Add expense" when you buy something.',
            style: AppText.dim,
          ),
        )
      else
        for (final e in recent)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ExpenseTile(e: e),
          ),
    ];
  }

  Widget _hero() {
    final b = budget;
    final Color color = b.isOver
        ? AppColors.danger
        : (b.ratio >= 0.75 ? AppColors.warn : AppColors.accent);
    final String status = b.isOver
        ? "Over today's limit"
        : (b.ratio >= 0.75 ? 'Almost at your limit' : "You're on track");
    final remaining = b.remainingToday;

    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          const Text('SAFE TO SPEND TODAY', style: AppText.label),
          const SizedBox(height: 20),
          SizedBox(
            width: 230,
            height: 230,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: b.ratio),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => CustomPaint(
                    size: const Size(230, 230),
                    painter: RingPainter(v, color),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 170,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(end: remaining),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            peso(v),
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      remaining >= 0 ? 'left today' : 'over the limit',
                      style: AppText.dim,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: color.withAlpha(40),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  status,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('Day ${b.dayIndex + 1} of ${b.totalDays}', style: AppText.dim),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------
class HistoryPage extends StatelessWidget {
  final Budget budget;
  final void Function(Expense) onDelete;

  const HistoryPage({super.key, required this.budget, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final b = budget;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
      children: [
        const Text(
          'History',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 4),
        const Text('Swipe left on an expense to delete it', style: AppText.dim),
        const SizedBox(height: 18),
        if (b.isSetUp)
          Panel(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SPENT SO FAR', style: AppText.label),
                      const SizedBox(height: 4),
                      Text(
                        peso(b.spentTotal),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'of ${peso(b.startMoney, decimals: 0)}',
                  style: AppText.dim,
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        if (b.expenses.isEmpty)
          const Panel(
            child: Text(
              'Nothing here yet. Your expenses will show up here.',
              style: AppText.dim,
            ),
          )
        else
          for (final e in b.expenses)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Dismissible(
                key: ValueKey(e),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => onDelete(e),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 22),
                  decoration: BoxDecoration(
                    color: const Color(0x33FF6B6B),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.danger,
                  ),
                ),
                child: ExpenseTile(e: e),
              ),
            ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom sheets
// ---------------------------------------------------------------------------
Widget _sheetHandle() {
  return Center(
    child: Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class AddExpenseSheet extends StatefulWidget {
  final void Function(Expense) onAdd;
  const AddExpenseSheet({super.key, required this.onAdd});

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  SpendCategory _cat = categories.first;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    // Accepts messy input like "₱ 1,250" or "50 pesos"
    final v = double.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (v == null || !v.isFinite || v <= 0) {
      setState(() => _error = 'Enter an amount, like 50');
      return;
    }
    final note = _note.text.trim();
    widget.onAdd(
      Expense(note: note.isEmpty ? _cat.name : note, amount: v, category: _cat),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sheetHandle(),
          const SizedBox(height: 18),
          const Text(
            'Add expense',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              prefixText: '₱ ',
              prefixStyle: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: AppColors.accent,
              ),
              hintText: '0',
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in categories)
                ChoiceChip(
                  avatar: Icon(
                    c.icon,
                    size: 18,
                    color: _cat == c ? AppColors.accent : AppColors.textDim,
                  ),
                  label: Text(c.name),
                  selected: _cat == c,
                  showCheckmark: false,
                  selectedColor: const Color(0x333DDC97),
                  backgroundColor: AppColors.surfaceHigh,
                  side: BorderSide(
                    color: _cat == c ? AppColors.accent : Colors.transparent,
                  ),
                  onSelected: (_) => setState(() => _cat = c),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              hintText: 'What was it for? (optional)',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _submit,
              child: const Text(
                'Add expense',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SetupSheet extends StatefulWidget {
  final bool isEdit;
  final void Function(double money, int days) onDone;
  const SetupSheet({super.key, required this.isEdit, required this.onDone});

  @override
  State<SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<SetupSheet> {
  final _money = TextEditingController();
  final _days = TextEditingController();
  String? _moneyErr;
  String? _daysErr;

  @override
  void dispose() {
    _money.dispose();
    _days.dispose();
    super.dispose();
  }

  void _submit() {
    final money = double.tryParse(
      _money.text.replaceAll(RegExp(r'[^0-9.]'), ''),
    );
    final days = int.tryParse(_days.text.replaceAll(RegExp(r'[^0-9]'), ''));
    String? me;
    String? de;
    if (money == null || !money.isFinite || money <= 0) {
      me = 'Enter how much money you have';
    }
    if (days == null || days <= 0) de = 'Enter the number of days';
    if (me != null || de != null) {
      setState(() {
        _moneyErr = me;
        _daysErr = de;
      });
      return;
    }
    widget.onDone(money!, days!);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sheetHandle(),
          const SizedBox(height: 18),
          const Text(
            'Set up your allowance',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          if (widget.isEdit) ...[
            const SizedBox(height: 6),
            const Text(
              'Saving starts a fresh budget and clears your history.',
              style: AppText.dim,
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _money,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Money you have now',
              prefixText: '₱ ',
              errorText: _moneyErr,
            ),
            onChanged: (_) {
              if (_moneyErr != null) setState(() => _moneyErr = null);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _days,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Days until next allowance',
              errorText: _daysErr,
            ),
            onChanged: (_) {
              if (_daysErr != null) setState(() => _daysErr = null);
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final d in const [7, 14, 15, 30])
                ActionChip(
                  label: Text('$d days'),
                  backgroundColor: AppColors.surfaceHigh,
                  onPressed: () => setState(() {
                    _days.text = '$d';
                    _daysErr = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _submit,
              child: const Text(
                'Start budgeting',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
