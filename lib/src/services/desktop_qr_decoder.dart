import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:zxing_lib/common.dart';
import 'package:zxing_lib/qrcode.dart';
import 'package:zxing_lib/zxing.dart';

/// Pure Dart QR code decoder for desktop (Linux, macOS, Windows).
/// Decodes QR codes from screenshots, gallery image files, or raw bytes.
class DesktopQrDecoder {
  /// Decode QR code from raw image bytes (PNG, JPEG, WebP, GIF, etc.)
  static String? decodeImageBytes(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final width = image.width;
      final height = image.height;
      final pixels = Uint8List(width * height);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final pixel = image.getPixel(x, y);
          final r = pixel.r.toInt();
          final g = pixel.g.toInt();
          final b = pixel.b.toInt();
          pixels[y * width + x] = ((r * 299 + g * 587 + b * 114) ~/ 1000).clamp(0, 255);
        }
      }

      final source = RGBLuminanceSource.orig(width, height, pixels);
      final bitmap = BinaryBitmap(HybridBinarizer(source));
      final reader = QRCodeReader();
      final result = reader.decode(bitmap);
      return result.text;
    } catch (_) {
      try {
        final image = img.decodeImage(bytes);
        if (image == null) return null;
        final width = image.width;
        final height = image.height;
        final pixels = Uint8List(width * height);

        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final pixel = image.getPixel(x, y);
            final lum = (pixel.luminanceNormalized * 255).round();
            pixels[y * width + x] = lum.clamp(0, 255);
          }
        }

        final source = RGBLuminanceSource.orig(width, height, pixels);
        final bitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
        final reader = MultiFormatReader();
        final result = reader.decode(bitmap);
        return result.text;
      } catch (_) {
        return null;
      }
    }
  }

  /// Decode QR code from file path
  static Future<String?> decodeFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return decodeImageBytes(bytes);
    } catch (_) {
      return null;
    }
  }
}
