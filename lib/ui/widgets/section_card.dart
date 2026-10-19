import 'package:flutter/material.dart';
import 'package:sendix/ui/theme/colors.dart';
import 'package:sendix/ui/theme/text_styles.dart';
import 'package:sendix/widgets/Glass Card/glass_carrd.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.subtitleTrailing,
    this.centerTitle = false,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? subtitleTrailing;
  final bool centerTitle;
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

    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      tintColor: Colors.white,
      tintOpacity: 0.025,
      borderColor: Colors.white,
      borderOpacity: 0.13,
      blurSigma: 14,
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 8)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: centerTitle
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      textAlign: centerTitle
                          ? TextAlign.center
                          : TextAlign.start,
                      style: AppTextStyles.titleMedium.copyWith(
                        height: 1.1,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle case final s?) ...[
                      const SizedBox(height: 8),
                      Text(
                        s,
                        textAlign: centerTitle
                            ? TextAlign.center
                            : TextAlign.start,
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
