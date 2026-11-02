import 'package:flutter/foundation.dart';

import 'library.dart';
import 'triage.dart';

/// Sorts one screenshot.
typedef Sorter = Future<Triage> Function(Uint8List image);

/// Where a screenshot is in the inbox.
enum ItemState { waiting, sorting, sorted, failed }

/// A screenshot and what the agent made of it.
class InboxItem {
  /// Creates an unsorted item.
  InboxItem(this.screenshot);

  /// The screenshot.
  final Screenshot screenshot;

  /// Where it is.
  ItemState state = ItemState.waiting;

  /// The agent's reading, once sorted.
  Triage? triage;

  /// Proposed actions the user has run.
  final Set<InboxAction> ran = {};

  /// Whether the user is finished with it, so it can be deleted.
  bool done = false;
}

/// The screenshots, the sorting run over them and the user's choices.
class InboxController extends ChangeNotifier {
  /// Creates a controller over [library] holding at most [limit]
  /// screenshots.
  InboxController(this._library, {this.limit = 30});

  final ScreenshotLibrary _library;

  /// How many of the newest screenshots to load.
  final int limit;

  /// Loaded screenshots, newest first.
  List<InboxItem> items = const [];

  /// Why loading failed.
  Object? error;

  /// Whether screenshots are loading.
  bool loading = false;

  /// Whether a sorting run is going.
  bool get sorting => _sorting;
  bool _sorting = false;
  bool _stopping = false;

  /// Items not sorted yet, including failed ones.
  int get unsorted => items.where((i) => i.state != ItemState.sorted).length;

  /// Items the user marked done.
  int get doneCount => items.where((i) => i.done).length;

  /// Loads the newest screenshots.
  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      items = [
        for (final s in await _library.recent(limit: limit)) InboxItem(s),
      ];
    } catch (e) {
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  /// Sorts every unsorted item with [sort], newest first, one at a time.
  Future<void> sortAll(Sorter sort) async {
    if (_sorting) return;
    _sorting = true;
    _stopping = false;
    notifyListeners();
    for (final item in items) {
      if (_stopping) break;
      if (item.state == ItemState.sorted) continue;
      item.state = ItemState.sorting;
      notifyListeners();
      try {
        item.triage = await sort(item.screenshot.preview);
        item.state = ItemState.sorted;
      } catch (_) {
        item.state = ItemState.failed;
      }
      notifyListeners();
    }
    _sorting = false;
    notifyListeners();
  }

  /// Stops the run after the screenshot being sorted.
  void stop() {
    _stopping = true;
    notifyListeners();
  }

  /// Records that the user ran [action] on [item].
  void markRan(InboxItem item, InboxAction action) {
    item.ran.add(action);
    notifyListeners();
  }

  /// Marks [item] done or not done.
  void toggleDone(InboxItem item) {
    item.done = !item.done;
    notifyListeners();
  }

  /// Deletes the items marked done from the library, once the system has
  /// asked the user, and from the inbox.
  Future<void> deleteDone() async {
    final ids = [
      for (final i in items)
        if (i.done) i.screenshot.id,
    ];
    if (ids.isEmpty) return;
    final deleted = (await _library.delete(ids)).toSet();
    items = [
      for (final i in items)
        if (!deleted.contains(i.screenshot.id)) i,
    ];
    notifyListeners();
  }
}
