import 'package:flutter/material.dart';

/// Defers building a pushed route's heavy body until the route's entrance
/// transition completes, then fades the real content in (150 ms).
///
/// Why: pushing a screen builds its whole subtree in the FIRST frame of the
/// 250 ms slide (measured UI 12.7 ms / raster 30.4 ms spikes on cold pushes)
/// — exactly when the transition needs headroom. A lightweight placeholder
/// keeps the slide cheap; content lands right after the settle.
///
/// No-ops (builds child immediately) when there is no route, no transition
/// animation, or the transition is already complete (e.g. re-builds, desktop
/// side-sheets, warm returns).
class DeferredPageBody extends StatefulWidget {
  const DeferredPageBody({
    super.key,
    required this.child,
    this.placeholder,
  });

  final Widget child;

  /// Shown during the entrance transition. Defaults to empty space (the
  /// scaffold chrome + mesh behind it carry the visual weight).
  final Widget? placeholder;

  @override
  State<DeferredPageBody> createState() => _DeferredPageBodyState();
}

class _DeferredPageBodyState extends State<DeferredPageBody> {
  bool _ready = false;
  Animation<double>? _animation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      _ready = true;
      return;
    }
    if (!identical(_animation, animation)) {
      _animation?.removeStatusListener(_onStatus);
      _animation = animation..addStatusListener(_onStatus);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _animation?.removeStatusListener(_onStatus);
    if (mounted && !_ready) {
      setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return widget.placeholder ?? const SizedBox.expand();
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: widget.child,
      builder: (_, t, child) => Opacity(opacity: t, child: child!),
    );
  }
}
