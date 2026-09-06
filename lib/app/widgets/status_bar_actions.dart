import 'package:flutter/material.dart';

class StatusBarActions extends StatelessWidget {
  final bool isActionButtonEnabled;
  final VoidCallback? onActionPressed;

  const StatusBarActions({
    super.key,
    required this.isActionButtonEnabled,
    this.onActionPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
          disabledForegroundColor: Colors.grey,
        ),
        child: const Text('Action'),
      ),
    );
  }
}
