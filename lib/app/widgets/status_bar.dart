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
            child: Tooltip(
              message: message,
              child: Text(
                key: const ValueKey('status-bar-message'),
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF8E8E8E),
                ),
              ),
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
