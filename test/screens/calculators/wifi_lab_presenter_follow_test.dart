// PresenterFollow rebuilds on a change of the selected value, and only then.
// Regression: the first change after mount was missed while the remembered
// value was a lazily initialized `late` field (read for the first time inside
// the change handler, after the change).

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_lab_presenter_follow.dart';

class _State extends ChangeNotifier {
  int mode = 0;
  int tick = 0;

  void setMode(int m) {
    mode = m;
    notifyListeners();
  }

  void bump() {
    tick++;
    notifyListeners();
  }
}

void main() {
  testWidgets('the first change of the selected value rebuilds; other '
      'changes do not', (WidgetTester tester) async {
    final _State s = _State();
    addTearDown(s.dispose);
    int builds = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PresenterFollow(
          listenable: s,
          select: () => s.mode,
          builder: (BuildContext context) {
            builds++;
            return Text('mode ${s.mode}');
          },
        ),
      ),
    );
    expect(builds, 1);
    s.setMode(1);
    await tester.pump();
    expect(find.text('mode 1'), findsOneWidget);
    expect(builds, 2);
    s.bump();
    s.bump();
    await tester.pump();
    expect(builds, 2);
    s.setMode(2);
    await tester.pump();
    expect(builds, 3);
  });
}
