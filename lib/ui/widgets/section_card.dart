import 'package:flutter/material.dart';
import 'package:sendix/ui/theme/colors.dart';
import 'package:sendix/ui/theme/text_styles.dart';
import 'package:sendix/ui/widgets/themed_card.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.subtitleTrailing,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? subtitleTrailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final trailingChildren = <Widget>[];
    if (trailing != null) {
      trailingChildren.add(trailing!);
    }
    if (subtitleTrailing != null) {
      if (trailingChildren.isNotEmpty) {
        trailingChildren.add(const SizedBox(height: 2));
      }
      trailingChildren.add(subtitleTrailing!);
    }

    return SecondaryCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleMedium.copyWith(height: 1.1),
                    ),
                    if (subtitle case final s?) ...[
                      const SizedBox(height: 8),
                      Text(
                        s,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailingChildren.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: trailingChildren,
                ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
