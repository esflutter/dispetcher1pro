// DTO для таблицы `public.services` (услуги исполнителя).
// Хранит как id-шные поля (как в БД), так и резолвнутые названия
// категорий/техники — UI показывает строки, а сервис выполняет
// конвертацию через кэш справочников в `CatalogService`.

class MyServiceSummary {
  const MyServiceSummary({
    required this.id,
    required this.title,
    required this.description,
    required this.machineryIds,
    required this.categoryIds,
    required this.machineryTitles,
    required this.categoryTitles,
    required this.pricePerHour,
    required this.pricePerDay,
    required this.minHours,
    required this.isPaid,
  });

  final String id;
  final String title;
  final String? description;
  final List<int> machineryIds;
  final List<int> categoryIds;
  final List<String> machineryTitles;
  final List<String> categoryTitles;
  final double? pricePerHour;
  final double? pricePerDay;
  final int? minHours;
  final bool isPaid;
}

class MyServiceDetail {
  const MyServiceDetail({
    required this.id,
    required this.title,
    required this.description,
    required this.machineryIds,
    required this.categoryIds,
    required this.machineryTitles,
    required this.categoryTitles,
    required this.pricePerHour,
    required this.pricePerDay,
    required this.minHours,
    required this.photos,
    required this.locationAddress,
    required this.locationLat,
    required this.locationLng,
    required this.radiusKm,
    required this.isPaid,
    required this.isArchived,
  });

  final String id;
  final String title;
  final String? description;
  final List<int> machineryIds;
  final List<int> categoryIds;
  final List<String> machineryTitles;
  final List<String> categoryTitles;
  final double? pricePerHour;
  final double? pricePerDay;
  final int? minHours;
  final List<String> photos;
  final String? locationAddress;
  final double? locationLat;
  final double? locationLng;
  final int? radiusKm; // 10 / 20 / 50
  final bool isPaid;
  final bool isArchived;
}

/// Черновик услуги для INSERT/UPDATE.
class ServiceDraft {
  const ServiceDraft({
    required this.title,
    required this.description,
    required this.machineryTitles,
    required this.categoryTitles,
    required this.pricePerHour,
    required this.pricePerDay,
    required this.minHours,
    required this.photos,
    required this.locationAddress,
    required this.radiusKm,
  });

  final String title;
  final String? description;
  final List<String> machineryTitles;
  final List<String> categoryTitles;
  final double? pricePerHour;
  final double? pricePerDay;
  final int? minHours;
  final List<String> photos;
  final String? locationAddress;
  final int? radiusKm;
}
