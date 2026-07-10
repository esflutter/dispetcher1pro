import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dispatcher_1/core/my_services/models.dart';
import 'package:dispatcher_1/core/my_services/my_services_service.dart';
import 'package:dispatcher_1/core/storage/storage_service.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/utils/photo_source.dart';
import 'package:dispatcher_1/core/widgets/dark_sub_app_bar.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Экран «Документы услуги» (режим `verification.per_service_docs`):
/// исполнитель прикладывает фото документов на технику (СТС/ПТС, право
/// управления) по конкретной услуге. После отправки RPC
/// `submit_service_verification` переводит услугу в статус 'pending',
/// решение принимает администратор в панели верификации.
class ServiceDocsScreen extends StatefulWidget {
  const ServiceDocsScreen({super.key, required this.serviceId});

  final String serviceId;

  @override
  State<ServiceDocsScreen> createState() => _ServiceDocsScreenState();
}

class _ServiceDocsScreenState extends State<ServiceDocsScreen> {
  /// Максимум фото документов за одну подачу. Сервер допускает до 12,
  /// но 8 достаточно (СТС/ПТС с двух сторон + права + пара запасных).
  static const int _maxDocs = 8;

  /// Услуга из БД — ради статуса и причины отказа (при 'rejected').
  late Future<MyServiceDetail?> _future;

  /// Локальные пути выбранных фото (ещё не загружены).
  final List<String> _photos = <String>[];

  /// true пока идёт загрузка фото и RPC — блокирует повторный тап.
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _future = MyServicesService.instance.getMine(widget.serviceId);
  }

  Future<void> _addPhotos() async {
    final int remaining = _maxDocs - _photos.length;
    if (remaining <= 0) return;
    final List<String> picked = await pickMultipleImagesFromGallery(
      limit: remaining,
      context: context,
    );
    if (!mounted || picked.isEmpty) return;
    setState(() {
      // Лимит соблюдаем и здесь: не все галереи честно уважают `limit`
      // (Android <13 и вендорские пикеры возвращают больше).
      for (final String p in picked) {
        if (_photos.length >= _maxDocs) break;
        if (!_photos.contains(p)) _photos.add(p);
      }
    });
  }

  Future<void> _submit() async {
    if (_sending || _photos.isEmpty) return;
    setState(() => _sending = true);
    // Объявлено ДО try, чтобы catch мог подчистить уже залитые сканы,
    // если регистрация на сервере не пройдёт (как в чате ассистента).
    final List<String> uploaded = <String>[];
    try {
      for (final String local in _photos) {
        // Таймаут на каждое фото: зависшее соединение не должно держать
        // кнопку «Отправить» в спиннере вечно.
        final String path = await StorageService.instance
            .uploadServiceVerificationDocument(File(local))
            .timeout(const Duration(seconds: 40));
        uploaded.add(path);
      }
      await Supabase.instance.client.rpc(
        'submit_service_verification',
        params: <String, dynamic>{
          'p_service_id': widget.serviceId,
          'p_paths': uploaded,
        },
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Документы отправлены на проверку')),
      );
      Navigator.of(context).pop();
    } on TimeoutException {
      // Таймаут НЕ означает провал: сервер мог уже закоммитить (вставить
      // документы и перевести услугу в pending), а ответ не дошёл. Файлы
      // НЕ удаляем — иначе у зарегистрированных документов пропали бы фото.
      // Повторная подача на сервере сама заменит этот круг (миграция 111).
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Долго нет ответа. Проверьте раздел «Мои услуги»: если статус '
            'стал «на проверке» — документы отправлены.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (_) {
      // Явная ошибка ДО коммита (нет сети, отказ RPC): документы нигде не
      // зарегистрированы — подчищаем осиротевшие файлы в приватном бакете.
      unawaited(StorageService.instance.removeVerificationDocuments(uploaded));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось отправить документы. '
            'Проверьте интернет и попробуйте ещё раз.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const DarkSubAppBar(title: 'Документы услуги'),
      body: FutureBuilder<MyServiceDetail?>(
        future: _future,
        builder:
            (BuildContext context, AsyncSnapshot<MyServiceDetail?> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _RetryView(
              onRetry: () => setState(() {
                _future =
                    MyServicesService.instance.getMine(widget.serviceId);
              }),
            );
          }
          final MyServiceDetail? s = snap.data;
          if (s == null) {
            return Center(
              child: Text('Услуга не найдена', style: AppTextStyles.body),
            );
          }
          return _buildContent(s);
        },
      ),
    );
  }

  Widget _buildContent(MyServiceDetail s) {
    final bool rejected = s.verificationStatus == 'rejected';
    return Column(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  s.title,
                  style: AppTextStyles.titleL.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: 12.h),
                if (rejected) ...<Widget>[
                  _RejectReasonBlock(reason: s.verificationRejectReason),
                  SizedBox(height: 12.h),
                ],
                Text(
                  'Приложите документы на технику: СТС/ПТС, право '
                  'управления. Проверка занимает до 1 рабочего дня.',
                  style: AppTextStyles.body
                      .copyWith(color: AppColors.textSecondary),
                ),
                SizedBox(height: 16.h),
                Text(
                  'Фото документов',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: 8.h),
                _DocsGrid(
                  photos: _photos,
                  canAdd: _photos.length < _maxDocs && !_sending,
                  onAdd: _addPhotos,
                  onRemove: _sending
                      ? null
                      : (int i) => setState(() => _photos.removeAt(i)),
                ),
                SizedBox(height: 8.h),
                Text(
                  'До $_maxDocs фото',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(
            16.w,
            12.h,
            16.w,
            16.h + MediaQuery.of(context).padding.bottom,
          ),
          child: PrimaryButton(
            label: _sending ? 'Отправляем…' : 'Отправить на проверку',
            enabled: _photos.isNotEmpty && !_sending,
            onPressed:
                _photos.isNotEmpty && !_sending ? _submit : null,
          ),
        ),
      ],
    );
  }
}

/// Заметный блок с причиной отказа (при статусе 'rejected').
class _RejectReasonBlock extends StatelessWidget {
  const _RejectReasonBlock({required this.reason});
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final String text = (reason == null || reason!.trim().isEmpty)
        ? 'Документы не прошли проверку. Приложите новые фото и '
            'отправьте ещё раз.'
        : reason!.trim();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.errorTint,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Документы отклонены',
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            text,
            style: AppTextStyles.body.copyWith(
              fontSize: 14.sp,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Сетка превью выбранных фото + плитка «добавить».
class _DocsGrid extends StatelessWidget {
  const _DocsGrid({
    required this.photos,
    required this.canAdd,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> photos;
  final bool canAdd;
  final VoidCallback onAdd;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    final int count = photos.length + (canAdd ? 1 : 0);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 4.r,
        crossAxisSpacing: 4.r,
      ),
      itemCount: count,
      itemBuilder: (BuildContext ctx, int i) {
        if (i >= photos.length) {
          // Плитка «добавить фото» — как поле ввода: мягкая заливка.
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAdd,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.fieldFill,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(
                Icons.add_rounded,
                size: 28.r,
                color: AppColors.primary,
              ),
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8.r),
              child: Image.file(
                File(photos[i]),
                fit: BoxFit.cover,
                cacheWidth: 300,
              ),
            ),
            if (onRemove != null)
              Positioned(
                top: 2.r,
                right: 2.r,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onRemove!(i),
                  child: Container(
                    width: 20.r,
                    height: 20.r,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 14.r,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RetryView extends StatelessWidget {
  const _RetryView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Не удалось загрузить услугу',
                style: AppTextStyles.bodyMRegular
                    .copyWith(color: AppColors.textPrimary)),
            SizedBox(height: 12.h),
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}
