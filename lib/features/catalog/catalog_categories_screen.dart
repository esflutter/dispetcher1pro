import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/catalog/catalog_service.dart';
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

  static const List<_SearchableOrder> _allOrders = <_SearchableOrder>[
    _SearchableOrder(
      id: '1',
      title: 'Нужен экскаватор для копки траншеи',
      address: 'Московская область, Москва, Улица1, д 144',
      rentDate: '15 июня · 09:00–18:00',
      publishedAgo: '2 часа назад',
      equipment: <String>['Экскаватор'],
    ),
    _SearchableOrder(
      id: '2',
      title: 'Земляные работы',
      address: 'Московская область, Москва, Улица1, д 144',
      rentDate: '15 июня · 09:00–18:00',
      publishedAgo: 'Сегодня в 11:30',
      equipment: <String>['Автокран', 'Экскаватор'],
    ),
    _SearchableOrder(
      id: '3',
      title: 'Разработка котлована под фундамент',
      address: 'Московская область, Москва, Улица1, д 144',
      rentDate: '15 июня · 09:00–18:00',
      publishedAgo: 'Сегодня в 11:30',
      equipment: <String>[
        'Экскаватор',
        'Автокран',
        'Эвакуатор',
        'Манипулятор',
        'Автовышка',
      ],
    ),
    _SearchableOrder(
      id: '4',
      title: 'Погрузка и вывоз строительного мусора',
      address: 'Московская область, Москва, Улица1, д 144',
      rentDate: '16 июня · 09:00–18:00',
      publishedAgo: 'Сегодня в 09:10',
      equipment: <String>['Самосвал', 'Погрузчик'],
    ),
    _SearchableOrder(
      id: '5',
      title: 'Монтаж вентиляции на крыше',
      address: 'Московская область, Москва, Улица1, д 144',
      rentDate: '17 июня · 09:00–18:00',
      publishedAgo: 'Вчера',
      equipment: <String>['Автовышка'],
    ),
  ];

  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _machineryFuture = CatalogService.instance.listActiveMachinery();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_SearchableOrder> get _filtered {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return const <_SearchableOrder>[];
    return _allOrders.where((_SearchableOrder o) {
      if (o.title.toLowerCase().contains(q)) return true;
      if (o.address.toLowerCase().contains(q)) return true;
      for (final String e in o.equipment) {
        if (e.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
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
            onChanged: (String v) => setState(() => _query = v),
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
    final List<_SearchableOrder> results = _filtered;
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Text(
            'Ничего не найдено',
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
        final _SearchableOrder o = results[i];
        return OrderCard(
          title: o.title,
          address: o.address,
          rentDate: o.rentDate,
          publishedAgo: o.publishedAgo,
          equipment: o.equipment,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => OrderDetailScreen(
                orderId: o.id,
                multipleEquipment: o.equipment.length > 1,
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

class _SearchableOrder {
  const _SearchableOrder({
    required this.id,
    required this.title,
    required this.address,
    required this.rentDate,
    required this.publishedAgo,
    required this.equipment,
  });
  final String id;
  final String title;
  final String address;
  final String rentDate;
  final String publishedAgo;
  final List<String> equipment;
}
