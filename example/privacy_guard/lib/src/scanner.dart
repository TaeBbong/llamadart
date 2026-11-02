import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';

/// A kind of private detail a photo can show.
enum PrivateKind {
  idDocument('id_document', 'ID document'),
  personName('person_name', 'Name'),
  paymentCard('payment_card', 'Payment card'),
  bankAccount('bank_account', 'Bank account'),
  phoneNumber('phone_number', 'Phone number'),
  emailAddress('email_address', 'Email address'),
  address('address', 'Address'),
  licensePlate('license_plate', 'License plate'),
  barcode('barcode', 'Barcode or QR code'),
  referenceNumber('reference_number', 'Tracking or booking number'),
  secret('secret', 'Password or code'),
  other('other', 'Other');

  const PrivateKind(this.wire, this.title);

  /// Name the model uses.
  final String wire;

  /// Name shown to the user.
  final String title;
}

/// A rectangle in fractions of the image size, from 0 to 1.
class Box {
  /// Creates a box from its edges.
  const Box(this.left, this.top, this.right, this.bottom);

  /// The box for corners in the model's 0 to 1000 grid, clamped to the
  /// image and put in order.
  factory Box.fromGrid(num x1, num y1, num x2, num y2) {
    double f(num v) => (v / 1000).clamp(0, 1).toDouble();
    final (l, r) = x1 <= x2 ? (f(x1), f(x2)) : (f(x2), f(x1));
    final (t, b) = y1 <= y2 ? (f(y1), f(y2)) : (f(y2), f(y1));
    return Box(l, t, r, b);
  }

  /// Left edge.
  final double left;

  /// Top edge.
  final double top;

  /// Right edge.
  final double right;

  /// Bottom edge.
  final double bottom;

  /// Whether the box covers no area.
  bool get isEmpty => right <= left || bottom <= top;

  /// The box grown by [margin] on every side, within the image.
  Box inflate(double margin) => Box(
    (left - margin).clamp(0, 1),
    (top - margin).clamp(0, 1),
    (right + margin).clamp(0, 1),
    (bottom + margin).clamp(0, 1),
  );

  @override
  bool operator ==(Object other) =>
      other is Box &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'Box($left, $top, $right, $bottom)';
}

/// A private detail the model found.
class Finding {
  /// Creates a finding.
  const Finding({required this.kind, required this.label, required this.box});

  /// What it is.
  final PrivateKind kind;

  /// What the model read, such as `Visa ending 4242`.
  final String label;

  /// Where it is.
  final Box box;
}

/// The tool the model reports with: every private detail in one call.
/// [onReport] receives the findings and the verdict.
///
/// One call carries everything because the small Qwen3.5 models make one
/// call per reply, and a second round would evaluate the whole prompt, image
/// included, again: their recurrent layers cannot reuse part of a cached
/// prompt.
ToolDefinition reportTool(
  void Function(List<Finding> findings, String verdict) onReport,
) => ToolDefinition(
  name: 'report_private_details',
  description:
      'Reports every private detail visible in the photo, with a box '
      'around each, so the app can black it out before sharing.',
  parameters: [
    ToolParam.array(
      'findings',
      description: 'One entry per detail. Empty when the photo is safe.',
      required: true,
      itemType: ToolParam.object(
        'finding',
        properties: [
          // A string, not an enum: a kind outside the list would fail the
          // whole call's validation, and the detail is still worth hiding.
          ToolParam.string(
            'kind',
            description: [
              for (final k in PrivateKind.values) k.wire,
            ].join(', '),
            required: true,
          ),
          ToolParam.string(
            'label',
            description: 'What it is, without repeating the private value.',
            required: true,
          ),
          ToolParam.array(
            'box',
            description:
                '[x1, y1, x2, y2]: top-left and bottom-right corners, each '
                'from 0 to 1000 across the image.',
            required: true,
            itemType: ToolParam.integer('coordinate'),
          ),
        ],
      ),
    ),
    ToolParam.string(
      'verdict',
      description: 'One sentence: is the photo safe to share, and why.',
      required: true,
    ),
  ],
  handler: (params) async {
    final findings = <Finding>[];
    for (final entry in params.getRequiredList<Object?>('findings')) {
      if (entry is! Map) continue;
      final box = entry['box'];
      if (box is! List || box.length != 4 || box.any((v) => v is! num)) {
        continue;
      }
      final corners = box.cast<num>();
      final area = Box.fromGrid(corners[0], corners[1], corners[2], corners[3]);
      if (area.isEmpty) continue;
      findings.add(
        Finding(
          kind: PrivateKind.values.firstWhere(
            (k) => k.wire == entry['kind'],
            orElse: () => PrivateKind.other,
          ),
          label: '${entry['label'] ?? ''}'.trim(),
          box: area,
        ),
      );
    }
    onReport(findings, params.getRequiredString('verdict').trim());
    return {'status': 'reported', 'findings': findings.length};
  },
);

/// The system prompt.
const String scanInstructions = '''
You check photos for private details before the user shares them. Look for:
ID cards, passports and driver's licenses; people's names on documents, labels or tickets; payment card numbers; bank account numbers; phone numbers; email addresses; home or delivery addresses; license plates; barcodes and QR codes on tickets, boarding passes or parcels; tracking, booking and order numbers; passwords, PINs and one-time codes.

Call report_private_details once. Give each detail its own entry with a tight box, in a 0 to 1000 grid over the whole image. Box a whole ID card or payment card as one entry. Report nothing for scenery, food, pets or plain text without personal details.''';

/// What the model found in one photo.
class ScanReport {
  /// Creates a report.
  const ScanReport({
    required this.findings,
    required this.verdict,
    required this.elapsed,
  });

  /// Private details, in the order the model listed them.
  final List<Finding> findings;

  /// The model's one-sentence verdict.
  final String verdict;

  /// How long the model took.
  final Duration elapsed;
}

/// Checks photos with a vision model that calls [reportTool].
class PrivacyScanner {
  /// Creates a scanner on [engine], which must have a projector loaded.
  PrivacyScanner(this._engine);

  final LlamaEngine _engine;

  /// Checks one photo, sent as encoded JPEG or PNG [image] bytes.
  ///
  /// A reply without a usable call reports no findings, with the model's
  /// text as the verdict.
  Future<ScanReport> scan(Uint8List image) async {
    final stopwatch = Stopwatch()..start();
    var findings = const <Finding>[];
    String? verdict;
    final tool = reportTool((f, v) {
      findings = f;
      verdict = v;
    });
    final reply = await _engine.complete(
      [
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: scanInstructions,
        ),
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            LlamaImageContent(bytes: image),
            const LlamaTextContent('Check this photo.'),
          ],
        ),
      ],
      tools: [tool],
      toolChoice: ToolChoice.required,
      enableThinking: false,
      params: const GenerationParams(maxTokens: 1024, temp: 0),
    );
    if (reply.toolCalls.firstOrNull case final call?) {
      try {
        await tool.invoke(call.arguments);
      } on Exception {
        // Arguments the tool rejects leave the photo without findings.
      }
    }
    return ScanReport(
      findings: findings,
      verdict: verdict ?? reply.text.trim(),
      elapsed: stopwatch.elapsed,
    );
  }
}
