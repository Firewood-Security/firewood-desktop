import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';
import 'package:firewood_desktop/src/services/desktop_qr_decoder.dart';

void main() {
  test('DesktopQrDecoder decodes generated QR code image', () {
    const testUri = 'firewood://spark?pk=testkey12345&nonce=abcd1234efgh&name=DesktopPeer';

    // Generate QR Code matrix using qr package
    final qrCode = QrCode.fromData(
      data: testUri,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final qrImage = QrImage(qrCode);

    // Render to an image.Image
    const scale = 8;
    const border = 4;
    final totalModules = qrImage.moduleCount + (border * 2);
    final width = totalModules * scale;
    final height = totalModules * scale;

    final image = img.Image(width: width, height: height);
    // Fill white
    img.fill(image, color: img.ColorRgb8(255, 255, 255));

    for (int x = 0; x < qrImage.moduleCount; x++) {
      for (int y = 0; y < qrImage.moduleCount; y++) {
        if (qrImage.isDark(y, x)) {
          final px = (x + border) * scale;
          final py = (y + border) * scale;
          img.fillRect(
            image,
            x1: px,
            y1: py,
            x2: px + scale,
            y2: py + scale,
            color: img.ColorRgb8(0, 0, 0),
          );
        }
      }
    }

    final pngBytes = Uint8List.fromList(img.encodePng(image));

    // Decode with DesktopQrDecoder
    final decodedText = DesktopQrDecoder.decodeImageBytes(pngBytes);

    expect(decodedText, equals(testUri));
  });
}
