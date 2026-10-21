import 'package:flutter/material.dart';

/// Brand header pinned to the top of the sidebar: the app mark (rounded
/// like a Yaru app tile) followed by the app name, with a light separator
/// line underneath. Mirrors the model-editor rail brand header.
///
/// The header spans the sidebar's *full* width so its separator line runs
/// edge to edge. The caption row carries its own horizontal padding so the
/// icon and text line up with the inset content below. The sidebar must
/// therefore place this widget *outside* any horizontal padding (see
/// [GadgetEditorSidebar]).
class SidebarHeader extends StatelessWidget {
  const SidebarHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Caption: app mark + name, inset to match the content below.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            children: [
              const _AppMark(size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Gadget Editor',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        // Light separator under the caption, edge to edge (no horizontal
        // padding, so it spans the whole sidebar).
        Container(height: 1, color: Theme.of(context).dividerColor),
      ],
    );
  }
}

/// The app mark: the launcher icon, rounded like a Yaru app tile.
class _AppMark extends StatelessWidget {
  final double size;

  const _AppMark({required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset('assets/icon.png', width: size, height: size),
    );
  }
}
