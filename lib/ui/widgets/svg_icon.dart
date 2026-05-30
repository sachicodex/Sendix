import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SvgIcon extends StatelessWidget {
  const SvgIcon({
    super.key,
    required this.asset,
    this.color,
    this.size = 20,
    this.fit = BoxFit.contain,
    this.semanticsLabel,
  });

  final String asset;
  final Color? color;
  final double size;
  final BoxFit fit;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      fit: fit,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
      semanticsLabel: semanticsLabel,
    );
  }
}
