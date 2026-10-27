import 'dart:math' as math;

import 'package:core_lock/core_lock.dart' show LockShake;
import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:openlock/src/features/auth/services/pin_auth_service.dart';

/// PIN dots, a one-line error under them, and a numeric keypad. Collects at
/// least [PinAuthService.minPinLength] digits and calls [onSubmit] when the
/// check key is tapped. When [randomize] is on, the digit positions are
/// shuffled to defeat shoulder-surfing.
///
/// The dots shake each time [failures] changes (it stays still under reduced motion).
/// The native lock overlay (`LockActivity.kt`) draws the same dots and keys.
class PinEntryPanel extends StatefulWidget {
  const PinEntryPanel({
    required this.onSubmit,
    required this.keyHeight,
    this.enabled = true,
    this.randomize = false,
    this.error,
    this.failures = 0,
    super.key,
  });

  final ValueChanged<String> onSubmit;
  final bool enabled;
  final bool randomize;

  /// The wrong-PIN or cooldown line under the dots.
  final String? error;

  /// Wrong attempts so far; each change shakes the dots.
  final int failures;

  /// Height of one keypad key, so the whole keypad fits the screen.
  final double keyHeight;

  /// Vertical space between keypad rows.
  static const double rowGap = AppSpacing.sm;

  /// Everything but the four key rows: dots, error line and their gaps.
  static const double chromeHeight =
      _dotSize + _dotGap + _errorHeight + _errorGap;

  static const double _dotSize = 14;
  static const double _dotGap = 6;
  static const double _errorHeight = 16;
  static const double _errorGap = AppSpacing.sm;

  /// The panel's height for a given [keyHeight].
  static double heightFor(double keyHeight) =>
      chromeHeight + keyHeight * 4 + rowGap * 3;

  @override
  State<PinEntryPanel> createState() => PinEntryPanelState();
}

class PinEntryPanelState extends State<PinEntryPanel> {
  String _pin = '';
  late List<String> _digits = _buildDigits();

  List<String> _buildDigits() {
    // Phone-keypad order: 1-9 across three rows, 0 beside the check key.
    final digits = [for (var i = 1; i <= 10; i++) (i % 10).toString()];
    if (widget.randomize) digits.shuffle(math.Random.secure());
    return digits;
  }

  void clear() => setState(() {
        _pin = '';
        _digits = _buildDigits();
      });

  @override
  void didUpdateWidget(covariant PinEntryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.randomize != widget.randomize) {
      setState(() => _digits = _buildDigits());
    }
  }

  void _append(String digit) {
    if (!widget.enabled || _pin.length >= 12) return;
    setState(() => _pin += digit);
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _submit() {
    if (_pin.length < PinAuthService.minPinLength) return;
    widget.onSubmit(_pin);
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final canSubmit =
        widget.enabled && _pin.length >= PinAuthService.minPinLength;
    final error = widget.error;
    Widget key({String? label, IconData? icon, VoidCallback? onTap}) => _Key(
          label: label,
          icon: icon,
          height: widget.keyHeight,
          onTap: onTap,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LockShake(
          trigger: widget.failures,
          child: _PinDots(count: _pin.length),
        ),
        const SizedBox(height: PinEntryPanel._dotGap),
        SizedBox(
          height: PinEntryPanel._errorHeight,
          child: error == null
              ? null
              : Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(color: c.negative),
                  ),
                ),
        ),
        const SizedBox(height: PinEntryPanel._errorGap),
        for (var row = 0; row < 3; row++) ...[
          _keyRow([
            for (var col = 0; col < 3; col++)
              key(
                label: _digits[row * 3 + col],
                onTap: widget.enabled
                    ? () => _append(_digits[row * 3 + col])
                    : null,
              ),
          ]),
          const SizedBox(height: PinEntryPanel.rowGap),
        ],
        _keyRow([
          key(
            icon: Icons.backspace_outlined,
            onTap: widget.enabled && _pin.isNotEmpty ? _backspace : null,
          ),
          key(
            label: _digits[9],
            onTap: widget.enabled ? () => _append(_digits[9]) : null,
          ),
          _Key(
            icon: Icons.check_rounded,
            height: widget.keyHeight,
            emphasized: true,
            onTap: canSubmit ? _submit : null,
          ),
        ]),
      ],
    );
  }

  Widget _keyRow(List<Widget> keys) => Row(
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.smd),
            Expanded(child: keys[i]),
          ],
        ],
      );
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final shown = math.max(count, PinAuthService.minPinLength);
    return Semantics(
      label: '$count digits entered',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < shown; i++)
              AnimatedContainer(
                duration: AppMotion.fast,
                width: PinEntryPanel._dotSize,
                height: PinEntryPanel._dotSize,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < count ? c.accent : null,
                  border: Border.all(
                    color: i < count ? c.accent : c.textTertiary,
                    width: 1.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One keypad key. Digits and backspace are surface tiles with a hairline
/// edge; the check key is the solid accent. A disabled key fades as a whole
/// so it keeps its shape in both modes.
class _Key extends StatelessWidget {
  const _Key({
    required this.height,
    this.label,
    this.icon,
    this.onTap,
    this.emphasized = false,
  });

  final String? label;
  final IconData? icon;
  final double height;
  final VoidCallback? onTap;
  final bool emphasized;

  /// Shared with the native overlay's keys (14 dp corners, 24 sp Mona Sans
  /// Medium digits).
  static const double radius = AppSpacing.radiusMd;
  static final TextStyle digitStyle = AppTextStyles.h2.copyWith(
    fontFamily: AppTextStyles.fontFamily,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final fg = emphasized ? c.onAccent : c.textPrimary;
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: emphasized ? c.accent : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: emphasized ? BorderSide.none : BorderSide(color: c.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Center(
              child: label != null
                  ? Text(
                      label!,
                      style: digitStyle.copyWith(color: fg),
                    )
                  : Icon(
                      icon,
                      color: fg,
                      size: 24,
                      semanticLabel: emphasized ? 'Unlock' : 'Delete digit',
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
