import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:dispatcher_1/core/config/env.dart';

/// Один кандидат адреса от DaData Suggest API. Кроме строкового
/// представления нас интересуют только координаты — всё остальное
/// (FIAS, КЛАДР, индекс и т.п.) можно дочитать позднее, если понадобится
/// строгая валидация на стороне госуслуг.
class DadataAddress {
  const DadataAddress({
    required this.value,
    required this.unrestrictedValue,
    required this.lat,
    required this.lon,
  });

  /// Каноническая строка адреса в обычном виде («г Москва, ул Тверская, д 1»).
  final String value;

  /// То же, но с регионом, субъектом и индексом — для отображения
  /// в подсказках полная строка иногда полезна (если в `value` тождество
  /// домов в разных округах).
  final String unrestrictedValue;

  /// Широта/долгота (WGS84). Если DaData вернул адрес без координат
  /// (редкие случаи: новостройка без привязки в ФИАС), оба поля null,
  /// и UI не должен пытаться рисовать его на карте.
  final double? lat;
  final double? lon;

  bool get hasCoords => lat != null && lon != null;

  factory DadataAddress.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> data =
        (json['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return DadataAddress(
      value: (json['value'] as String?) ?? '',
      unrestrictedValue: (json['unrestricted_value'] as String?) ?? '',
      lat: _parseCoord(data['geo_lat']),
      lon: _parseCoord(data['geo_lon']),
    );
  }

  static double? _parseCoord(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }
}

/// Клиент DaData Suggest API. Только Suggest (подсказки + координаты в
/// одном ответе), без Standardize — стандартизация требует Secret-ключ,
/// который в клиент мы не пускаем.
///
/// Бесплатный тариф DaData — 10к запросов/день. На 1 ввод адреса с
/// debounce (300 мс) обычно уходит 5–10 запросов, что даёт ~1–2к
/// введённых адресов/день в free-тарифе.
class DadataService {
  DadataService._();
  static final DadataService instance = DadataService._();

  static const String _suggestUrl =
      'https://suggestions.dadata.ru/suggestions/api/4_1/rs/suggest/address';

  /// Дефолтный таймаут — 4 секунды. DaData обычно отвечает за 100–300 мс,
  /// 4 сек — запас на медленный мобильный интернет.
  static const Duration _timeout = Duration(seconds: 4);

  /// `count=5` — стандартный размер выпадающего списка подсказок.
  /// Больше 10 пользователю не показывают: длинные списки в дроп-дауне
  /// выглядят перегруженно и реже кликаются по нужной строке.
  static const int _defaultCount = 5;

  /// Возвращает до [count] подсказок по запросу [query].
  ///
  /// Пустой запрос → пустой список (не идём в сеть).
  /// Без ключа [Env.dadataApiKey] → пустой список (UI продолжает работать
  /// без подсказок). Любая сетевая/HTTP/JSON-ошибка → пустой список,
  /// в логах отметка через `print` для отладки. Решили **не пробрасывать
  /// исключения наверх** — подсказки адреса это вспомогательный UX, и
  /// плохой сетевой коннект не должен ломать форму создания заказа.
  Future<List<DadataAddress>> suggest(
    String query, {
    int count = _defaultCount,
  }) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return const <DadataAddress>[];
    if (!Env.hasDadataConfig) return const <DadataAddress>[];

    try {
      final http.Response response = await http
          .post(
            Uri.parse(_suggestUrl),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Token ${Env.dadataApiKey}',
            },
            body: jsonEncode(<String, dynamic>{
              'query': trimmed,
              'count': count,
              // `locations: [{ country: '*' }]` оставляем дефолт — DaData
              // ищет по всем странам, но РФ выдаёт первой как наиболее
              // полную базу. Если впоследствии бизнес ограничится РФ —
              // поменяем на `[{country_iso_code: 'RU'}]`.
            }),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        return const <DadataAddress>[];
      }

      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> raw =
          (body['suggestions'] as List<dynamic>?) ?? const <dynamic>[];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(DadataAddress.fromJson)
          .toList(growable: false);
    } on TimeoutException {
      return const <DadataAddress>[];
    } catch (_) {
      return const <DadataAddress>[];
    }
  }
}
