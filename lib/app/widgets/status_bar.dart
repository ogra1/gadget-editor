import 'package:flutter/material.dart';

class StatusBar extends StatelessWidget {
  final String message;
  final bool isActionButtonEnabled;
  final VoidCallback? onActionPressed;

  const StatusBar({
    super.key,
    required this.message,
    required this.isActionButtonEnabled,
    this.onActionPressed,
  });

  static const TextStyle _messageStyle = TextStyle(
    fontSize: 14,
    color: Color(0xFF8E8E8E),
  );

  /// Whether [message] is fully visible in the single-line status bar
  /// given [availableWidth]. The bar shows only the first line,
  /// ellipsized when it is too wide, so content is hidden whenever the
  /// message contains a line break or its first line does not fit.
  static bool _messageFits(
      BuildContext context, String message, double availableWidth) {
    // A line break hides everything from the first '\n' onward.
    final int newline = message.indexOf('\n');
    final String firstLine =
        newline == -1 ? message : message.substring(0, newline);
    if (newline != -1) {
      return false;
    }
    if (firstLine.isEmpty || availableWidth.isInfinite) {
      return true;
    }
    final TextPainter painter = TextPainter(
      text: TextSpan(text: firstLine, style: _messageStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: double.infinity);
    return painter.width <= availableWidth;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Error strings can be very long (multi-line snapd/store output).
          // The bar is a fixed 60px strip, so render the message on a single
          // line with an ellipsis and expose the full text via the tooltip —
          // an unconstrained Text would wrap and overflow the bar.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double available = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : double.infinity;
                final Widget text = Text(
                  key: const ValueKey('status-bar-message'),
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: _messageStyle,
                );
                // Only offer a tooltip when something is actually hidden:
                // the first line is wider than the bar, or a line break
                // hides the rest of the message. Short, single-line
                // messages fit, so they get no tooltip.
                final bool fits = _messageFits(context, message, available);
                return fits ? text : Tooltip(message: message, child: text);
              },
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            height: 40,
            child: ElevatedButton(
              onPressed: isActionButtonEnabled ? onActionPressed : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isActionButtonEnabled
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).disabledColor,
                foregroundColor: isActionButtonEnabled
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).disabledColor,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: BorderSide(
                    color: isActionButtonEnabled
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
                elevation: 0,
                disabledBackgroundColor: Theme.of(context).disabledColor,
                disabledForegroundColor: const Color(0xFF8E8E8E),
              ),
              child: const Text('Pack Snap'),
            ),
          ),
        ],
      ),
    );
  }
}
