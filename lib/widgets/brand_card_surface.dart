import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// GL-003 "shadow primary" (design library 7ef88b82): in light mode a resting
/// card gets a 1.5 px #E2E1E2 border, a 12 px radius and
/// BoxShadow(0x14000000, offset (0, 2), blur 8). Material elevation cannot
/// express that exact shadow, so the light CardTheme stays at elevation 0 and
/// this wrapper paints it. Dark mode returns [child] unchanged.
class BrandCardSurface extends StatelessWidget {
  const BrandCardSurface({super.key, required this.child});

  final Widget child;

  static const Color borderColor = Color(0xFFE2E1E2);
  static const double borderWidth = 1.5;
  static const BoxShadow shadowPrimary = BoxShadow(
    color: Color(0x14000000),
    offset: Offset(0, 2),
    blurRadius: 8,
  );

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).brightness != Brightness.light) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: const <BoxShadow>[shadowPrimary],
      ),
      child: child,
    );
  }
}

/// Drop-in [Card] that adds the GL-003 light-mode surface via
/// [BrandCardSurface]. Shape, color and margin still come from the CardTheme.
class BrandCard extends StatelessWidget {
  const BrandCard({super.key, this.margin, required this.child});

  final EdgeInsetsGeometry? margin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Widget card = Card(margin: EdgeInsets.zero, child: child);
    final Widget surface = BrandCardSurface(child: card);
    final EdgeInsetsGeometry m =
        margin ?? Theme.of(context).cardTheme.margin ?? EdgeInsets.zero;
    return m == EdgeInsets.zero ? surface : Padding(padding: m, child: surface);
  }
}
