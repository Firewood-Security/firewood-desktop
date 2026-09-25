// Password Generator Dialog & Page Component for Firewood Desktop
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_design/firewood_design.dart';
import 'package:hugeicons/hugeicons.dart';

import '../services/secure_clipboard.dart';
import '../theme/app_icons.dart';

class PasswordGeneratorDialog extends StatefulWidget {
  final Function(String password)? onUsePassword;
  final bool isDialog;

  const PasswordGeneratorDialog({
    super.key,
    this.onUsePassword,
    this.isDialog = false,
  });

  static Future<String?> show(
    BuildContext context, {
    Function(String password)? onUsePassword,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF13151A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF262A33)),
            ),
            child: PasswordGeneratorDialog(
              isDialog: true,
              onUsePassword: (pwd) {
                Navigator.of(ctx).pop(pwd);
                if (onUsePassword != null) onUsePassword(pwd);
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<PasswordGeneratorDialog> createState() => _PasswordGeneratorDialogState();
}

class _PasswordGeneratorDialogState extends State<PasswordGeneratorDialog> {
  double _length = 20;
  bool _uppercase = true;
  bool _lowercase = true;
  bool _numbers = true;
  bool _symbols = true;
  bool _copied = false;
  String _generatedPassword = '';

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  void _regenerate() {
    setState(() {
      _generatedPassword = GeneratorService.generatePassword(
        length: _length.toInt(),
        includeUppercase: _uppercase,
        includeLowercase: _lowercase,
        includeDigits: _numbers,
        includeSymbols: _symbols,
      );
      _copied = false;
    });
  }

  void _copy() {
    SecureClipboard.copy(
      context: context,
      text: _generatedPassword,
      label: 'Generated Password',
      timeoutSeconds: 30,
    );
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  double get _entropyBits {
    int pool = 0;
    if (_uppercase) pool += 26;
    if (_lowercase) pool += 26;
    if (_numbers) pool += 10;
    if (_symbols) pool += 33;
    if (pool == 0) return 0;
    return _length * (math.log(pool) / math.ln2);
  }

  Color get _strengthColor {
    final e = _entropyBits;
    if (e >= 80) return AppColors.mintAccent;
    if (e >= 60) return const Color(0xFF4EE4FF);
    if (e >= 40) return AppColors.orangeAccent;
    return AppColors.roseAccent;
  }

  String get _strengthLabel {
    final e = _entropyBits;
    if (e >= 80) return 'Very Strong';
    if (e >= 60) return 'Strong';
    if (e >= 40) return 'Moderate';
    return 'Weak';
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 580),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const AppIcon(AppIcons.generate, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Password Generator',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Generate cryptographically secure random passwords',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.isDialog)
                  IconButton(
                    tooltip: 'Close',
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      color: Colors.white60,
                      size: 20,
                      strokeWidth: 1.8,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
              ],
            ),
            const SizedBox(height: 22),

            // Password Output Display Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF161922),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF262B38)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _generatedPassword,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: AppColors.orangeAccent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Regenerate',
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedRefresh,
                      size: 20,
                      color: AppColors.orangeAccent,
                      strokeWidth: 1.8,
                    ),
                    onPressed: _regenerate,
                  ),
                  IconButton(
                    tooltip: _copied ? 'Copied!' : 'Copy to clipboard',
                    icon: HugeIcon(
                      icon: _copied
                          ? HugeIcons.strokeRoundedTick02
                          : HugeIcons.strokeRoundedCopy01,
                      size: 20,
                      color: _copied ? AppColors.mintAccent : Colors.white70,
                      strokeWidth: 1.8,
                    ),
                    onPressed: _copy,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Entropy & Strength Indicator
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _strengthColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$_strengthLabel (${_entropyBits.toInt()}-bit entropy)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _strengthColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Length Slider + Header + Presets
            Row(
              children: [
                const Text(
                  'Password Length',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E222D),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF2C3242)),
                  ),
                  child: Text(
                    '${_length.toInt()} chars',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.orangeAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: _length,
                min: 8,
                max: 64,
                divisions: 56,
                activeColor: AppColors.orangeAccent,
                inactiveColor: const Color(0xFF242836),
                onChanged: (v) {
                  setState(() => _length = v);
                  _regenerate();
                },
              ),
            ),
            const SizedBox(height: 6),

            // Quick Presets Row
            Row(
              children: [
                const Text(
                  'Presets:',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                const SizedBox(width: 8),
                for (final p in [16, 20, 24, 32, 48])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        setState(() => _length = p.toDouble());
                        _regenerate();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: _length.toInt() == p
                              ? AppColors.orangeAccent.withOpacity(0.18)
                              : const Color(0xFF1A1D26),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _length.toInt() == p
                                ? AppColors.orangeAccent
                                : const Color(0xFF2A2F3D),
                          ),
                        ),
                        child: Text(
                          '$p',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _length.toInt() == p
                                ? AppColors.orangeAccent
                                : Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 22),

            // Character Set Toggles
            const Text(
              'Character Sets',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildCompactToggle('A-Z Uppercase', _uppercase, (v) {
                  if (!v && !_lowercase && !_numbers && !_symbols) return;
                  setState(() => _uppercase = v);
                  _regenerate();
                }),
                _buildCompactToggle('a-z Lowercase', _lowercase, (v) {
                  if (!v && !_uppercase && !_numbers && !_symbols) return;
                  setState(() => _lowercase = v);
                  _regenerate();
                }),
                _buildCompactToggle('0-9 Numbers', _numbers, (v) {
                  if (!v && !_uppercase && !_lowercase && !_symbols) return;
                  setState(() => _numbers = v);
                  _regenerate();
                }),
                _buildCompactToggle('!@# Symbols', _symbols, (v) {
                  if (!v && !_uppercase && !_lowercase && !_numbers) return;
                  setState(() => _symbols = v);
                  _regenerate();
                }),
              ],
            ),
            const SizedBox(height: 28),

            // Action Buttons: compact, right-aligned, NOT full-width
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedRefresh,
                    size: 16,
                    color: Colors.white70,
                    strokeWidth: 1.8,
                  ),
                  label: const Text('Regenerate'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    side: const BorderSide(color: Color(0xFF2E333F)),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _regenerate,
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: HugeIcon(
                    icon: _copied
                        ? HugeIcons.strokeRoundedTick02
                        : HugeIcons.strokeRoundedCopy01,
                    size: 16,
                    color: Colors.black,
                    strokeWidth: 1.8,
                  ),
                  label: Text(_copied ? 'Copied!' : 'Copy Password'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _copied ? AppColors.mintAccent : AppColors.orangeAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _copy,
                ),
                if (widget.onUsePassword != null) ...[
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedTick02,
                      size: 16,
                      color: Colors.white,
                      strokeWidth: 1.8,
                    ),
                    label: const Text('Use in Field'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF262C38),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: () => widget.onUsePassword!(_generatedPassword),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactToggle(String label, bool value, Function(bool) onChanged) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: value
              ? AppColors.orangeAccent.withOpacity(0.12)
              : const Color(0xFF161922),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value
                ? AppColors.orangeAccent.withOpacity(0.6)
                : const Color(0xFF262B38),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: value
                  ? HugeIcons.strokeRoundedTick02
                  : HugeIcons.strokeRoundedSquare,
              size: 16,
              color: value ? AppColors.orangeAccent : Colors.white38,
              strokeWidth: 2,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: value ? FontWeight.w600 : FontWeight.normal,
                color: value ? Colors.white : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
