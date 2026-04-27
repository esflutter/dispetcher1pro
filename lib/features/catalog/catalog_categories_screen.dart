import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/catalog/catalog_service.dart';
import 'package:dispatcher_1/core/catalog/format.dart';
import 'package:dispatcher_1/core/catalog/machinery_visual.dart';
import 'package:dispatcher_1/core/catalog/models.dart';
import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/features/catalog/catalog_filter_screen.dart';
import 'package:dispatcher_1/features/catalog/order_detail_screen.dart';
import 'package:dispatcher_1/features/catalog/order_feed_screen.dart';
import 'package:dispatcher_1/features/catalog/widgets/category_card.dart';
import 'package:dispatcher_1/features/catalog/widgets/order_card.dart';

/// Экран «Каталог / категории» — заголовок «Поиск заказов» в тёмном
/// nav-баре, поле поиска и сетка 2×5 категорий (Figma 8:2139).
class CatalogCategoriesScreen extends StatefulWidget {
  const CatalogCategoriesScreen({super.key});

  @override
  State<CatalogCategoriesScreen> createState() =>
      _CatalogCategoriesScreenState();
}

class _CatalogCategoriesScreenState extends State<CatalogCategoriesScreen> {
  late Future<List<MachineryRef>> _machineryFuture;

  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  /// Последний запрос, по которому уже улетел или летит fetch. Чтобы
  /// не плодить параллельные запросы при каждом нажатии клавиши,
  /// поиск дебаунсится на 300 мс.
  Timer? _debounce;

  /// Текущий результат поиска. `null` — запрос ещё не отправляли
  /// (пустая строка либо первая отрисовка); пустой список — запрос
  /// вернулся без результатов.
  List<OrderListItem>? _results;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _machineryFuture = CatalogService.instance.listActiveMachinery();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    final String trimmed = v.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _fetch(trimmed),
    );
  }

  Future<void> _fetch(String query) async {
    try {
      final List<OrderListItem> rows =
          await CatalogService.instance.listPublishedOrders(search: query);
      if (!mounted) return;
      // Защита от гонки: если пока летел запрос, пользователь ввёл
      // что-то ещё — игнорируем результат.
      if (_query.trim() != query) return;
      setState(() {
        _results = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (_query.trim() != query) return;
      setState(() {
        _results = const <OrderListItem>[];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool searching = _query.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: <Widget>[
          _CatalogHeader(
            controller: _searchCtrl,
            onChanged: _onQueryChanged,
          ),
          Expanded(
            child: searching
                ? _buildSearchResults()
                : _buildCategoriesGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesGrid() {
    return FutureBuilder<List<MachineryRef>>(
      future: _machineryFuture,
      builder: (BuildContext context, AsyncSnapshot<List<MachineryRef>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _CatalogLoadError(
            onRetry: () => setState(() {
              _machineryFuture = CatalogService.instance.listActiveMachinery();
            }),
          );
        }
        final List<MachineryRef> items = snap.data ?? const <MachineryRef>[];
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: GridView.builder(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12.h,
              crossAxisSpacing: 12.w,
              childAspectRatio: 168 / 112,
            ),
            itemBuilder: (BuildContext context, int i) {
              final MachineryRef m = items[i];
              final MachineryVisual v = MachineryVisual.lookup(m.title);
              return CategoryCard(
                title: m.title,
                imageAsset: v.asset,
                imageScale: v.scale,
                imageOffset: v.offset,
                onTap: () {
                  // Выбор техники = быстрый фильтр: заменяем список техники
                  // на одну выбранную и инкрементим ревизию, чтобы лента
                  // перерисовалась с учётом фильтра.
                  AppliedFilter.equipment
                    ..clear()
                    ..add(m.title);
                  AppliedFilter.revision.value =
                      AppliedFilter.revision.value + 1;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => OrderFeedScreen(
                        categoryId: m.id.toString(),
                        categoryTitle: m.title,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSearchResults() {
    if (_loading && _results == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final List<OrderListItem> results = _results ?? const <OrderListItem>[];
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Text(
            _loading ? 'Поиск...' : 'Ничего не найдено',
            style: AppTextStyles.bodyMRegular
                .copyWith(color: AppColors.textTertiary),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: results.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        thickness: 1,
        color: AppColors.divider,
      ),
      itemBuilder: (BuildContext context, int i) {
        final OrderListItem o = results[i];
        return OrderCard(
          title: o.title,
          address: o.address,
          rentDate: formatRentDate(o),
          publishedAgo: formatPublishedAgo(o.publishedAt),
          equipment: o.machineryTitles,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => OrderDetailScreen(
                orderId: o.id,
                initialTitle: o.title,
                multipleEquipment: o.machineryTitles.length > 1,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CatalogHeader extends StatelessWidget {
  const _CatalogHeader({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.navBarDark,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        MediaQuery.of(context).padding.top + 24.h,
        AppSpacing.screenH,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                'Поиск заказов',
                style: AppTextStyles.h1.copyWith(color: AppColors.surface),
              ),
              GestureDetector(
                onTap: () => context.push('/catalog/orders-map'),
                behavior: HitTestBehavior.opaque,
                child: Icon(Icons.map_outlined,
                    color: AppColors.primary, size: 24.r),
              ),
            ],
          ),
          SizedBox(height: 18.h),
          Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  height: 44.h,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  padding: EdgeInsets.only(left: 9.w, right: AppSpacing.sm),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.search,
                          color: AppColors.textTertiary, size: 24.r),
                      SizedBox(width: 5.w),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          onChanged: onChanged,
                          inputFormatters: [LengthLimitingTextInputFormatter(100)],
                          textInputAction: TextInputAction.search,
                          cursorColor: AppColors.primary,
                          style: AppTextStyles.bodyMRegular.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 17.sp,
                          ),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: 'Поиск',
                            hintStyle:
                                AppTextStyles.bodyMRegular.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 17.sp,
                            ),
                          ),
                        ),
                      ),
                      if (controller.text.isNotEmpty)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            controller.clear();
                            onChanged('');
                          },
                          child: Icon(Icons.close_rounded,
                              color: AppColors.textTertiary, size: 20.r),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              GestureDetector(
                onTap: () async {
                  final bool? applied =
                      await context.push<bool>('/catalog/filter');
                  if (applied == true && context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const OrderFeedScreen(
                          categoryId: 'all',
                          categoryTitle: 'Лента заказов',
                        ),
                      ),
                    );
                  }
                },
                child: Image.asset(
                  'assets/icons/ui/filter.webp',
                  width: 44.h,
                  height: 44.h,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CatalogLoadError extends StatelessWidget {
  const _CatalogLoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Не удалось загрузить каталог',
              style: AppTextStyles.bodyMRegular
                  .copyWith(color: AppColors.textPrimary),
            ),
            SizedBox(height: 12.h),
            TextButton(
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

