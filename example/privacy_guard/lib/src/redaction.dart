import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'scanner.dart';

/// Long edge, in pixels, of the image the model reads.
const int modelEdge = 1024;

/// Long edge, in pixels, of a shared photo.
const int shareEdge = 2048;

/// A photo decoded and ready to scan.
class PreparedPhoto {
  /// Creates a prepared photo.
  const PreparedPhoto({
    required this.modelImage,
    required this.width,
    required this.height,
    required this.hasLocation,
  });

  /// JPEG at most [modelEdge] pixels on its long edge, upright.
  final Uint8List modelImage;

  /// Upright width of the original.
  final int width;

  /// Upright height of the original.
  final int height;

  /// Whether the file's metadata holds a GPS location.
  final bool hasLocation;
}

/// Decodes [encoded], turns it upright and shrinks a copy for the model.
/// Throws [FormatException] for bytes that are not an image.
PreparedPhoto preparePhoto(Uint8List encoded) {
  final decoded = img.decodeImage(encoded);
  if (decoded == null) throw const FormatException('Not a supported image');
  final upright = img.bakeOrientation(decoded);
  return PreparedPhoto(
    modelImage: img.encodeJpg(_fit(upright, modelEdge), quality: 90),
    width: upright.width,
    height: upright.height,
    hasLocation: !decoded.exif.gpsIfd.isEmpty,
  );
}

/// [encoded] upright, at most [shareEdge] pixels on its long edge, with
/// every box in [boxes] filled solid black and no metadata, as a JPEG.
///
/// Solid fill, not blur or pixelation, because blurred text can often be
/// read back. Each box grows by 1% of the image to cover loose boxes.
Uint8List redactPhoto(Uint8List encoded, List<Box> boxes) {
  final decoded = img.decodeImage(encoded);
  if (decoded == null) throw const FormatException('Not a supported image');
  final image = _fit(img.bakeOrientation(decoded), shareEdge);
  final black = img.ColorRgb8(0, 0, 0);
  for (final box in boxes) {
    final b = box.inflate(0.01);
    img.fillRect(
      image,
      x1: (b.left * image.width).floor(),
      y1: (b.top * image.height).floor(),
      x2: (b.right * image.width).ceil() - 1,
      y2: (b.bottom * image.height).ceil() - 1,
      color: black,
    );
  }
  image.exif = img.ExifData();
  return img.encodeJpg(image, quality: 90);
}

img.Image _fit(img.Image image, int edge) {
  if (math.max(image.width, image.height) <= edge) return image;
  return image.width >= image.height
      ? img.copyResize(image, width: edge)
      : img.copyResize(image, height: edge);
}
