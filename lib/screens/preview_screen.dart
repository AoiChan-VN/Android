import 'package:flutter/material.dart';

import '../models/wallpaper_model.dart';
import '../services/gyroscope_service.dart';
import '../widgets/parallax_wallpaper.dart';

class PreviewScreen extends StatefulWidget {
  final WallpaperModel wallpaper;

  const PreviewScreen(this.wallpaper,
      {super.key});

  @override
  State<PreviewScreen> createState() =>
      _PreviewScreenState();
}

class _PreviewScreenState
    extends State<PreviewScreen> {

  double x = 0;
  double y = 0;

  final gyro = GyroscopeService();

  @override
  void initState() {
    super.initState();

    gyro.start((gx, gy) {
      setState(() {
        x = gx;
        y = gy;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ParallaxWallpaper(
        layers: widget.wallpaper.layers,
        offsetX: x,
        offsetY: y,
      ),
    );
  }
} 
