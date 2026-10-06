// scroll_refresh.dart — RefreshIndicator wrapper that also responds to the
// mouse scroll wheel scrolling up past the top, matching trackpad behaviour.
// Refresh triggers only after ~1.5 s of continuous upward scrolling at the
// top so a single accidental wheel tick doesn't fire it.
import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class ScrollWheelRefreshIndicator extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Color color;
  final Color backgroundColor;
  final Widget child;

  const ScrollWheelRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.color = Colors.blue,
    this.backgroundColor = Colors.white,
  });

  @override
  State<ScrollWheelRefreshIndicator> createState() =>
      _ScrollWheelRefreshIndicatorState();
}

class _ScrollWheelRefreshIndicatorState
    extends State<ScrollWheelRefreshIndicator> {
  final _key = GlobalKey<RefreshIndicatorState>();
  double _pixels = 0;

  // Accumulate upward-scroll delta while at the top. Once it crosses
  // _kThreshold (≈ 3 wheel clicks) the refresh fires and the counter resets.
  // Any downward scroll or leaving the top cancels the accumulation.
  static const double _kThreshold = 360;
  double _upAccum = 0;

  @override
  void dispose() {
    _upAccum = 0;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        _pixels = n.metrics.pixels;
        if (_pixels > 0) _upAccum = 0;
        return false;
      },
      child: Listener(
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent) return;
          if (_pixels > 0 || event.scrollDelta.dy >= 0) {
            _upAccum = 0;
            return;
          }
          _upAccum += -event.scrollDelta.dy;
          if (_upAccum >= _kThreshold) {
            _upAccum = 0;
            _key.currentState?.show();
          }
        },
        child: RefreshIndicator(
          key: _key,
          color: widget.color,
          backgroundColor: widget.backgroundColor,
          onRefresh: widget.onRefresh,
          child: widget.child,
        ),
      ),
    );
  }
}
