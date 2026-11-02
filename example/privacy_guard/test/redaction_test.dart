import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privacy_guard_example/src/redaction.dart';
import 'package:privacy_guard_example/src/scanner.dart';

/// A white JPEG of [width] by [height], with a GPS position when
/// [withLocation].
Uint8List whitePhoto(int width, int height, {bool withLocation = false}) {
  final image = img.Image(width: width, height: height)
    ..clear(img.ColorRgb8(255, 255, 255));
  if (withLocation) {
    image.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
    image.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(37, 1);
  }
  return img.encodeJpg(image);
}

void main() {
  group('preparePhoto', () {
    test('shrinks a large photo for the model and keeps its size', () {
      final photo = preparePhoto(whitePhoto(3000, 1500));

      final modelImage = img.decodeJpg(photo.modelImage)!;
      expect((modelImage.width, modelImage.height), (modelEdge, 512));
      expect((photo.width, photo.height), (3000, 1500));
      expect(photo.hasLocation, isFalse);
    });

    test('notices a GPS location in the metadata', () {
      expect(
        preparePhoto(whitePhoto(40, 30, withLocation: true)).hasLocation,
        isTrue,
      );
    });

    test('rejects bytes that are not an image', () {
      expect(
        () => preparePhoto(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });
  });

  group('redactPhoto', () {
    test('fills each box black, with a margin, and nothing else', () {
      final out = img.decodeJpg(
        redactPhoto(whitePhoto(200, 100), [const Box(0.25, 0.4, 0.5, 0.6)]),
      )!;

      int luminance(int x, int y) => out.getPixel(x, y).luminance.toInt();
      expect(luminance(75, 50), lessThan(20));
      // The 1% margin reaches two pixels left of the box on a 200 px image.
      expect(luminance(49, 50), lessThan(20));
      expect(luminance(150, 50), greaterThan(235));
      expect(luminance(75, 10), greaterThan(235));
    });

    test('drops the metadata, location included', () {
      final out = redactPhoto(whitePhoto(40, 30, withLocation: true), []);

      expect(img.decodeJpgExif(out)?.gpsIfd.isEmpty ?? true, isTrue);
    });

    test('shrinks a photo to the share size', () {
      final out = img.decodeJpg(redactPhoto(whitePhoto(4096, 1024), []))!;

      expect((out.width, out.height), (shareEdge, 512));
    });
  });
}
