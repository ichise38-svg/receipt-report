import 'package:flutter/material.dart';

/// 横幅の広い画面（タブレット・PCブラウザ）で、アプリの内容を
/// 中央寄せの最大幅（[maxWidth]）に収める。
///
/// 幅が [maxWidth] 以下の端末（スマートフォン）では何も変わらない。
class AdaptiveWidthFrame extends StatelessWidget {
  const AdaptiveWidthFrame({
    super.key,
    required this.child,
    this.maxWidth = 720,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
