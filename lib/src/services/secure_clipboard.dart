// Secure clipboard manager with timed auto-wipe and lock cleanup.
//
// Platform reality (V-018, honesty per G-08): desktop clipboard APIs
// (GTK/X11/Wayland) expose no "sensitive" flag, and clipboard managers
// (GPaste, CopyQ, Klipper, …) record each copy the instant it is made.
// The timed wipe below clears OUR clipboard entry after the timeout — it
// cannot retroactively erase what a manager already stored, and the UI says
// exactly that instead of claiming protection. Retention: the plaintext
// exists only inside the pending wipe's closure (≤ timeout seconds, freed
// earlier on clear()/lock); no static field holds it until wipe or lock,
// and the window-close path wipes before the process dies (best-effort —
// crashes/SIGKILL bypass any Dart-side cleanup).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:firewood_design/firewood_design.dart';

class SecureClipboard {
  SecureClipboard._();

  static Timer? _clearTimer;

  /// Copies sensitive [text] to the clipboard with an automatic [timeoutSeconds] wipe timer.
  static void copy({
    required BuildContext context,
    required String text,
    required String label,
    int timeoutSeconds = 30,
  }) {
    _clearTimer?.cancel();
    // V-018: captured only by the pending wipe closure below — the old
    // `static _lastCopied` (which retained the plaintext until wipe/lock) is
    // gone.
    final expected = text;

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
            const Icon(Icons.shield_outlined,
                color: AppColors.orangeAccent, size: 20),
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
                    'Clearing in ${timeoutSeconds}s — clipboard managers may keep their own history',
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
      // V-018: compare against the closure-captured value — only clear if
      // the clipboard still holds what WE copied (a newer user copy wins).
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == expected) {
        clear();
      }
    });
  }

  /// Immediately zeroes and clears the system clipboard.
  static void clear() {
    _clearTimer?.cancel();
    _clearTimer = null;
    Clipboard.setData(const ClipboardData(text: ''));
  }
}
