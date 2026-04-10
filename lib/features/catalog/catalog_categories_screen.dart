import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
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
  static const List<_Category> _categories = <_Category>[
    _Category('excavator_loader', 'Экскаватор-погрузчик',
        'assets/images/catalog/excavator_loader.webp'),
    _Category('excavator', 'Экскаватор',
        'assets/images/catalog/excavator.webp', tight: true),
    _Category('loader', 'Погрузчик', 'assets/images/catalog/loader.webp'),
    _Category('mini_excavator', 'Миниэкскаватор',
        'assets/images/catalog/mini_excavator.webp'),
    _Category('auger', 'Буроям', 'assets/images/catalog/auger.webp'),
    _Category('samogruz', 'Самогруз', 'assets/images/catalog/samogruz.webp'),
    _Category('autocrane', 'Автокран', 'assets/images/catalog/autocrane.webp'),
    _Category('concrete_pump', 'Бетононасос',
        'assets/images/catalog/concrete_pump.webp'),
    _Category('tow_truck', 'Эвакуатор', 'assets/images/catalog/tow_truck.webp'),
    _Category('aerial_platform', 'Автовышка',
        'assets/images/catalog/aerial_platform.webp'),
    _Category('manipulator', 'Манипулятор',
        'assets/images/catalog/manipulator.webp'),
    _Category('mini_loader', 'Минипогрузчик',
        'assets/images/catalog/mini_loader.webp', tight: true),
    _Category('dump_truck', 'Самосвал',
        'assets/images/catalog/dump_truck.webp', tight: true),
    _Category('mini_tractor', 'Минитрактор',
        'assets/images/catalog/mini_tractor.webp', tight: true),
  ];

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
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: GridView.builder(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        itemCount: _categories.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12.h,
          crossAxisSpacing: 12.w,
          childAspectRatio: 168 / 112,
        ),
        itemBuilder: (BuildContext context, int i) {
          final _Category c = _categories[i];
          return CategoryCard(
            title: c.title,
            imageAsset: c.asset,
            imageTight: c.tight,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OrderFeedScreen(
                      categoryId: c.id, categoryTitle: c.title),
                ),
              );
            },
          );
        },
      ),
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
      padding: EdgeInsets.only(bottom: 24.h),
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
                onTap: () => context.push('/catalog/filter'),
                child: Container(
                  width: 44.h,
                  height: 44.h,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                  ),
                  child: Icon(Icons.tune,
                      color: AppColors.surface, size: 20.r),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Category {
  const _Category(this.id, this.title, this.asset, {this.tight = false});
  final String id;
  final String title;
  final String asset;
  final bool tight;
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
