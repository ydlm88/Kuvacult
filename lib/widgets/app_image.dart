import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Drop-in replacement for CachedNetworkImage that automatically sets
/// memCacheWidth/memCacheHeight based on the device pixel ratio.
///
/// When explicit width/height are provided, cache size = dimension × dpr.
/// When size is dynamic (Expanded, SizedBox.expand, etc.), a LayoutBuilder
/// reads the parent constraints to compute the cache size.
/// Infinite constraints (e.g. unbounded height in a Column) are skipped —
/// those images cache at full resolution, which is correct for hero images.
class AppImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;
  final Widget Function(BuildContext, String)? placeholder;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;

  const AppImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorWidget,
    this.placeholder,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.fadeOutDuration = Duration.zero,
  });

  Widget _image(BuildContext context, int? mcw, int? mch) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: mcw,
      memCacheHeight: mch,
      errorWidget: errorWidget,
      placeholder: placeholder,
      fadeInDuration: fadeInDuration,
      fadeOutDuration: fadeOutDuration,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);

    final bool hasW = width != null && width!.isFinite;
    final bool hasH = height != null && height!.isFinite;

    if (hasW || hasH) {
      return _image(
        context,
        hasW ? (width! * dpr).ceil() : null,
        hasH ? (height! * dpr).ceil() : null,
      );
    }

    // Dynamic size: use LayoutBuilder to discover constraints.
    // Only set memCacheWidth — setting both dimensions forces the image to decode
    // at the exact container size, destroying aspect ratio when width >> height
    // (e.g. banner images inside Expanded rows on wide desktop windows).
    // BoxFit handles the display crop; only width drives decode quality.
    return LayoutBuilder(
      builder: (context, constraints) {
        final mcw = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * dpr).ceil()
            : (constraints.maxHeight.isFinite
                ? (constraints.maxHeight * dpr).ceil()
                : null);
        return _image(context, mcw, null);
      },
    );
  }
}
