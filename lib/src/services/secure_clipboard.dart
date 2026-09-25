// Secure clipboard manager with timed auto-wipe and lock cleanup.
// Protects secrets from persistent exposure in system clipboard history.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:firewood_design/firewood_design.dart';

class SecureClipboard {
  SecureClipboard._();

  static Timer? _clearTimer;
  static String? _lastCopied;

  /// Copies sensitive [text] to the clipboard with an automatic [timeoutSeconds] wipe timer.
  static void copy({
    required BuildContext context,
    required String text,
    required String label,
    int timeoutSeconds = 30,
  }) {
    _clearTimer?.cancel();
    _lastCopied = text;

    Clipboard.setData(ClipboardData(text: text));

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: Duration(seconds: timeoutSeconds),
        backgroundColor: const Color(0xFF1B1E28),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.orangeAccent.withOpacity(0.3)),
        ),
        content: Row(
          children: [
            const Icon(Icons.shield_outlined, color: AppColors.orangeAccent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label copied to clipboard',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Auto-clearing in ${timeoutSeconds}s to protect memory',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Clear Now',
          textColor: AppColors.roseAccent,
          onPressed: () {
            clear();
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );

    _clearTimer = Timer(Duration(seconds: timeoutSeconds), () async {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == _lastCopied) {
        clear();
      }
    });
  }

  /// Immediately zeroes and clears the system clipboard.
  static void clear() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _lastCopied = null;
    Clipboard.setData(const ClipboardData(text: ''));
  }
}
