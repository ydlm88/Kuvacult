// scroll_refresh.dart — RefreshIndicator wrapper that also responds to the
// mouse scroll wheel scrolling up past the top, matching trackpad behaviour.
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

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        _pixels = n.metrics.pixels;
        return false;
      },
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent &&
              event.scrollDelta.dy < 0 &&
              _pixels <= 0) {
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
