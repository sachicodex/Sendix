import 'package:flutter/material.dart';
import 'package:sendix/ui/theme/colors.dart';
import 'package:sendix/ui/theme/text_styles.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.embedded = false,
    this.animateIntro = false,
    this.showLoading = true,
    this.progressDuration = const Duration(seconds: 2),
  });

  final bool embedded;
  final bool animateIntro;
  final bool showLoading;
  final Duration progressDuration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;
  late final Animation<double> _progressValue;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: widget.progressDuration,
    )..forward();
    _progressValue = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget brandContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LogoBadge(
          image: Image.asset('assets/Logo/Sendix.png', width: 100, height: 100),
        ),
        SizedBox(height: 16),
        Text(
          'SENDIX',
          style: AppTextStyles.headlineSmall.copyWith(
            color: AppColors.textPrimary.withAlpha(210),
            decoration: TextDecoration.none,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.01,
          ),
        ),

        if (widget.showLoading) ...[
          const SizedBox(height: 20),
          _SmoothProgressBar(
            width: 128,
            height: 3.0,
            progress: _progressValue,
            baseColor: AppColors.surfaceTertiary,
            fillColor: AppColors.primaryAccent,
          ),
        ],
      ],
    );

    if (widget.animateIntro) {
      brandContent = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.98, end: 1.0),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: brandContent,
      );
    }

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.2),
            radius: 1.05,
            colors: [AppColors.surfaceSecondary, AppColors.background],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.surface, AppColors.background],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(widget.embedded ? 16 : 24),
                  child: brandContent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoBadge extends StatelessWidget {
  const _LogoBadge({required this.image});

  final Image image;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 100, height: 100, child: Center(child: image));
  }
}

class _SmoothProgressBar extends StatelessWidget {
  const _SmoothProgressBar({
    required this.width,
    required this.height,
    required this.progress,
    required this.baseColor,
    required this.fillColor,
  });

  final double width;
  final double height;
  final Animation<double> progress;
  final Color baseColor;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: AnimatedBuilder(
          animation: progress,
          builder: (context, _) {
            final value = (0.08 + 0.92 * progress.value).clamp(0.0, 1.0);
            return LinearProgressIndicator(
              value: value,
              minHeight: height,
              color: fillColor,
              backgroundColor: baseColor,
            );
          },
        ),
      ),
    );
  }
}
