import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/utils/photo_source.dart';

/// Полноэкранный просмотр набора фотографий со свайпами между ними
/// и pinch-zoom на каждом фото. Открывается из миниатюр.
class PhotoGalleryScreen extends StatefulWidget {
  const PhotoGalleryScreen({
    super.key,
    required this.photos,
    this.initialIndex = 0,
    this.bucket,
  });

  final List<String> photos;
  final int initialIndex;

  /// Имя бакета Supabase Storage для приватных путей. Например,
  /// `'order-photos'` — в этом бакете лежат фото заказа, к которым
  /// у обеих сторон есть доступ только после accepted-мэтча. Без
  /// `bucket` относительные пути из приватного бакета попадут в
  /// `Image.file` и упадут с FileSystemException.
  final String? bucket;

  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    // photos.isEmpty: clamp(0, -1) бросит RangeError, а PageController
    // c initialPage:-1 — undefined behavior. На практике галерея
    // открывается только из миниатюр (которые её не показали бы при
    // пустом списке), но guard дешевле, чем надёжно полагаться на это.
    if (widget.photos.isEmpty) {
      _index = 0;
    } else {
      _index = widget.initialIndex.clamp(0, widget.photos.length - 1);
    }
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        elevation: 0,
        foregroundColor: Colors.white,
        toolbarHeight: 48.h,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, size: 26.r, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: true,
        title: widget.photos.length > 1
            ? Text(
                '${_index + 1} / ${widget.photos.length}',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              )
            : null,
      ),
      body: widget.photos.isEmpty
          ? const SizedBox.shrink()
          : PageView.builder(
              controller: _controller,
              itemCount: widget.photos.length,
              onPageChanged: (int i) => setState(() => _index = i),
              itemBuilder: (_, int i) => Center(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: photoSmartImage(
                    widget.photos[i],
                    bucket: widget.bucket,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
    );
  }
}
