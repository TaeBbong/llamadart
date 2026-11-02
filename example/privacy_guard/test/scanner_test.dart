import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_guard_example/src/scanner.dart';

void main() {
  group('reportTool', () {
    Future<(List<Finding>, String)> report(Map<String, dynamic> args) async {
      late (List<Finding>, String) reported;
      final tool = reportTool((f, v) => reported = (f, v));
      await tool.invoke(args);
      return reported;
    }

    test('reads each finding and box in the 0 to 1000 grid', () async {
      final (findings, verdict) = await report({
        'findings': [
          {
            'kind': 'payment_card',
            'label': ' Visa card ',
            'box': [250, 275, 750, 690],
          },
        ],
        'verdict': ' Not safe. ',
      });

      expect(verdict, 'Not safe.');
      expect(findings.single.kind, PrivateKind.paymentCard);
      expect(findings.single.label, 'Visa card');
      expect(findings.single.box, const Box(0.25, 0.275, 0.75, 0.69));
    });

    test('keeps a detail of an unknown kind as other', () async {
      final (findings, _) = await report({
        'findings': [
          {
            'kind': 'date',
            'label': 'Issue date',
            'box': [1, 2, 3, 4],
          },
        ],
        'verdict': 'x',
      });

      expect(findings.single.kind, PrivateKind.other);
    });

    test('skips entries without a usable box', () async {
      final (findings, _) = await report({
        'findings': [
          'not an object',
          {
            'kind': 'address',
            'label': 'three corners',
            'box': [1, 2, 3],
          },
          {
            'kind': 'address',
            'label': 'text corners',
            'box': ['a', 2, 3, 4],
          },
          {
            'kind': 'address',
            'label': 'no area',
            'box': [10, 10, 10, 40],
          },
          {
            'kind': 'address',
            'label': 'kept',
            'box': [10, 10, 20, 40],
          },
        ],
        'verdict': 'x',
      });

      expect(findings.map((f) => f.label), ['kept']);
    });

    test('reports a safe photo with no findings', () async {
      final (findings, verdict) = await report({
        'findings': <Object>[],
        'verdict': 'Safe to share.',
      });

      expect(findings, isEmpty);
      expect(verdict, 'Safe to share.');
    });
  });

  group('Box', () {
    test('fromGrid orders corners and clamps them to the image', () {
      expect(Box.fromGrid(800, 900, -50, 1200), const Box(0, 0.9, 0.8, 1));
    });

    test('inflate grows the box within the image', () {
      final box = const Box(0.005, 0.5, 0.6, 0.995).inflate(0.01);

      expect(box.left, 0);
      expect(box.top, closeTo(0.49, 1e-9));
      expect(box.right, closeTo(0.61, 1e-9));
      expect(box.bottom, 1);
    });
  });
}
