import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import 'triage.dart';

/// A screenshot in the photo library.
class Screenshot {
  /// Creates a screenshot.
  const Screenshot({
    required this.id,
    required this.createdAt,
    required this.preview,
  });

  /// Photo library identifier.
  final String id;

  /// When it was taken.
  final DateTime createdAt;

  /// JPEG at most [previewEdge] pixels on its long edge, shown on its card
  /// and read by the model.
  final Uint8List preview;
}

/// Where the inbox reads screenshots from and deletes them.
abstract interface class ScreenshotLibrary {
  /// The newest screenshots, at most [limit].
  Future<List<Screenshot>> recent({int limit});

  /// Deletes [ids] after the system asks the user, and returns the ids that
  /// were deleted.
  Future<List<String>> delete(List<String> ids);
}

/// Thrown when the user has not given the app photo access.
class PhotoAccessDenied implements Exception {
  /// Creates the exception.
  const PhotoAccessDenied();

  @override
  String toString() => 'Photo access was denied.';
}

/// Screenshots in the device photo library, through `photo_manager`.
class PhotoLibrary implements ScreenshotLibrary {
  /// Images checked for screenshots, newest first.
  static const int _scanned = 400;

  // PHAssetMediaSubtypePhotoScreenshot.
  static const int _darwinScreenshot = 1 << 2;

  @override
  Future<List<Screenshot>> recent({int limit = 30}) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) throw const PhotoAccessDenied();
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
      filterOption: FilterOptionGroup(orders: [const OrderOption()]),
    );
    if (paths.isEmpty) return const [];
    final assets = await paths.first.getAssetListPaged(page: 0, size: _scanned);
    final screenshots = <Screenshot>[];
    for (final asset in assets.where(_isScreenshot)) {
      final scale = previewEdge / math.max(asset.width, asset.height);
      final preview = await asset.thumbnailDataWithSize(
        ThumbnailSize(
          math.max(1, (asset.width * math.min(1, scale)).round()),
          math.max(1, (asset.height * math.min(1, scale)).round()),
        ),
        quality: 90,
      );
      if (preview == null) continue;
      screenshots.add(
        Screenshot(
          id: asset.id,
          createdAt: asset.createDateTime,
          preview: preview,
        ),
      );
      if (screenshots.length == limit) break;
    }
    return screenshots;
  }

  // Apple marks screenshots with a media subtype; Android keeps them in a
  // Screenshots folder.
  static bool _isScreenshot(AssetEntity asset) => Platform.isAndroid
      ? (asset.relativePath ?? '').toLowerCase().contains('screenshot')
      : asset.subtype & _darwinScreenshot != 0;

  @override
  Future<List<String>> delete(List<String> ids) =>
      PhotoManager.editor.deleteWithIds(ids);
}
