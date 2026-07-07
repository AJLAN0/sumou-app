import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../constants/app_assets.dart';
import '../../theme/app_colors.dart';

/// An animated brand loader that "fills" the Sumou logo with liquid white while
/// content loads.
///
/// The logo art (white on transparent) is used as an alpha mask: a faint ghost
/// of the mark is always visible, and a rising, rippling liquid surface is
/// clipped to the logo shape so it looks like the mark fills up with water. The
/// fill gently rises and drains in a loop, so it works as an indefinite loader.
class LiquidLogoLoader extends StatefulWidget {
  const LiquidLogoLoader({
    super.key,
    this.width = 150,
    this.asset = AppAssets.logoIcon,
    this.fillColor = AppColors.textWhite,
    this.duration = const Duration(milliseconds: 2200),
    this.waveDuration = const Duration(milliseconds: 1600),
  });

  /// Rendered width; height follows the logo's aspect ratio.
  final double width;

  /// Which logo art to use as the fill mask.
  final String asset;

  /// The liquid (and full-logo) color.
  final Color fillColor;

  /// One full rise-and-drain cycle.
  final Duration duration;

  /// One horizontal wave travel cycle.
  final Duration waveDuration;

  @override
  State<LiquidLogoLoader> createState() => _LiquidLogoLoaderState();
}

class _LiquidLogoLoaderState extends State<LiquidLogoLoader>
    with TickerProviderStateMixin {
  // Trimmed icon art is ~1.83:1; used until the real image loads to avoid a
  // layout jump.
  static const double _defaultAspect = 2078 / 1136;

  late final AnimationController _fill;
  late final AnimationController _wave;
  ui.Image? _logo;

  @override
  void initState() {
    super.initState();
    _fill = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    _wave = AnimationController(vsync: this, duration: widget.waveDuration)
      ..repeat();
    _loadLogo();
  }

  Future<void> _loadLogo() async {
    try {
      final data = await rootBundle.load(widget.asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _logo = frame.image);
    } catch (_) {
      // Leave the ghost/empty state if the asset can't be decoded.
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    _wave.dispose();
    _logo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logo = _logo;
    final aspect = logo == null ? _defaultAspect : logo.width / logo.height;
    return SizedBox(
      width: widget.width,
      height: widget.width / aspect,
      child:
          logo == null
              ? const SizedBox.shrink()
              : AnimatedBuilder(
                animation: Listenable.merge([_fill, _wave]),
                builder: (context, _) {
                  return CustomPaint(
                    painter: _LiquidLogoPainter(
                      logo: logo,
                      fillLevel: Curves.easeInOut.transform(_fill.value),
                      wavePhase: _wave.value,
                      fillColor: widget.fillColor,
                      ghostColor: widget.fillColor.withValues(alpha: 0.16),
                    ),
                  );
                },
              ),
    );
  }
}

class _LiquidLogoPainter extends CustomPainter {
  _LiquidLogoPainter({
    required this.logo,
    required this.fillLevel,
    required this.wavePhase,
    required this.fillColor,
    required this.ghostColor,
  });

  final ui.Image logo;

  /// 0 = empty (surface at the bottom), 1 = full (surface at the top).
  final double fillLevel;

  /// 0..1 horizontal phase of the traveling wave.
  final double wavePhase;

  final Color fillColor;
  final Color ghostColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final src = Rect.fromLTWH(
      0,
      0,
      logo.width.toDouble(),
      logo.height.toDouble(),
    );

    // 1) Faint "empty" logo so the mark is always readable.
    canvas.drawImageRect(
      logo,
      src,
      rect,
      Paint()..colorFilter = ColorFilter.mode(ghostColor, BlendMode.srcIn),
    );

    // 2) Liquid layer, masked to the logo shape.
    canvas.saveLayer(rect, Paint());

    final amplitude = size.height * 0.035;
    final surfaceY =
        (size.height + amplitude * 2) * (1 - fillLevel) - amplitude;
    const wavesAcross = 2;

    final path = Path()..moveTo(0, size.height);
    path.lineTo(0, surfaceY);
    for (double x = 0; x <= size.width; x += 2) {
      final y =
          surfaceY +
          math.sin(
                (x / size.width) * wavesAcross * 2 * math.pi +
                    wavePhase * 2 * math.pi,
              ) *
              amplitude;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, Paint()..color = fillColor);

    // Keep only the intersection of the liquid and the logo alpha.
    canvas.drawImageRect(logo, src, rect, Paint()..blendMode = BlendMode.dstIn);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiquidLogoPainter old) =>
      old.fillLevel != fillLevel ||
      old.wavePhase != wavePhase ||
      old.fillColor != fillColor ||
      old.logo != logo;
}
