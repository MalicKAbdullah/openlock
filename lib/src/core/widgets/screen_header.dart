import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';

/// The title block that opens each top-level tab: an eyebrow, the screen
/// name in `h2`, and an optional trailing action.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    required this.title,
    this.eyebrow,
    this.trailing,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdl),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null)
                  Text(
                    eyebrow!,
                    style: AppTextStyles.label.copyWith(color: c.textSecondary),
                  ),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: AppTextStyles.h2.copyWith(color: c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A scrollable page body with the suite gutter, centred and capped at a
/// readable width on tablets.
class PageList extends StatelessWidget {
  const PageList({
    required this.children,
    this.bottomPadding = AppSpacing.xl,
    super.key,
  });

  final List<Widget> children;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            bottomPadding,
          ),
          children: children,
        ),
      ),
    );
  }
}

/// A section title with the suite's 24 px lead-in.
class SectionLead extends StatelessWidget {
  const SectionLead(this.title, {this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: _Header(title: title, subtitle: subtitle),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        0,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: AppTextStyles.h3.copyWith(color: c.textPrimary),
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// One row of a lazily-built grouped list. Draws the card edge, rounding the
/// first and last rows, so a long `ListView.builder` looks like a `RowGroup`.
class GroupedRowItem extends StatelessWidget {
  const GroupedRowItem({
    required this.child,
    required this.isFirst,
    required this.isLast,
    super.key,
  });

  final Widget child;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    const radius = Radius.circular(AppSpacing.radiusLg);
    final side = BorderSide(color: c.hairline);
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: isFirst ? radius : Radius.zero,
          bottom: isLast ? radius : Radius.zero,
        ),
        side: BorderSide.none,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: side,
            right: side,
            top: isFirst ? side : BorderSide.none,
            bottom: isLast ? side : BorderSide.none,
          ),
          borderRadius: BorderRadius.vertical(
            top: isFirst ? radius : Radius.zero,
            bottom: isLast ? radius : Radius.zero,
          ),
        ),
        child: Column(
          children: [
            child,
            if (!isLast)
              Divider(
                height: 1,
                thickness: 1,
                indent: 68,
                color: c.hairline,
              ),
          ],
        ),
      ),
    );
  }
}

/// A list row whose explanation wraps instead of truncating, for rows that
/// carry a sentence the user has to read (permissions, schedules).
class DetailRow extends StatelessWidget {
  const DetailRow({
    required this.title,
    required this.detail,
    this.leading,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String title;
  final String detail;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 66),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.smd,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppSpacing.smd + 2),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.body.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
