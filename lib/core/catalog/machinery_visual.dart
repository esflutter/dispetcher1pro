import 'package:flutter/painting.dart';

/// Сопоставление `machinery_types.title` → локальный ассет + визуальная
/// подгонка (scale, offset), использовавшаяся в прежнем хардкоде
/// `catalog_categories_screen`. Поле `image_url` в БД пока не
/// используется — иконки живут в APK; таблица нужна только для
/// маппинга по title.
class MachineryVisual {
  const MachineryVisual(
    this.asset, {
    this.scale = 1.0,
    this.offset = Offset.zero,
  });

  final String asset;
  final double scale;
  final Offset offset;

  static const MachineryVisual _fallback = MachineryVisual(
    'assets/images/catalog/excavator.webp',
  );

  static const Map<String, MachineryVisual> _byTitle = <String, MachineryVisual>{
    'Экскаватор-погрузчик': MachineryVisual(
      'assets/images/catalog/excavator_loader.webp',
      scale: 0.90,
    ),
    'Экскаватор': MachineryVisual(
      'assets/images/catalog/excavator.webp',
      offset: Offset(-2, 0),
    ),
    'Погрузчик': MachineryVisual(
      'assets/images/catalog/loader.webp',
      scale: 1.15,
    ),
    'Миниэкскаватор': MachineryVisual(
      'assets/images/catalog/mini_excavator.webp',
      scale: 0.95,
      offset: Offset(-2, 0),
    ),
    'Буроям': MachineryVisual('assets/images/catalog/auger.webp'),
    'Самогруз': MachineryVisual('assets/images/catalog/samogruz.webp'),
    'Автокран': MachineryVisual('assets/images/catalog/autocrane.webp'),
    'Бетононасос': MachineryVisual('assets/images/catalog/concrete_pump.webp'),
    'Эвакуатор': MachineryVisual('assets/images/catalog/tow_truck.webp'),
    'Автовышка': MachineryVisual(
      'assets/images/catalog/aerial_platform.webp',
      offset: Offset(-2, 0),
    ),
    'Манипулятор': MachineryVisual(
      'assets/images/catalog/manipulator.webp',
      scale: 0.94,
      offset: Offset(-4, 0),
    ),
    'Минипогрузчик': MachineryVisual(
      'assets/images/catalog/mini_loader.webp',
      scale: 0.95,
    ),
    'Самосвал': MachineryVisual(
      'assets/images/catalog/dump_truck.webp',
      scale: 1.03,
    ),
    'Минитрактор': MachineryVisual(
      'assets/images/catalog/mini_tractor.webp',
      scale: 0.9025,
    ),
  };

  static MachineryVisual lookup(String title) =>
      _byTitle[title] ?? _fallback;
}
