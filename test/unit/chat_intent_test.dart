import 'package:flutter_test/flutter_test.dart';
import 'package:dispatcher_1/core/ai/chat_intent.dart';

/// Эвристика «это поиск или обычный вопрос» для роутинга чата ассистента.
/// Проверяем, что явные поисковые запросы уходят в поиск, а FAQ/личные
/// вопросы — нет (и наоборот при возврате из поиска в чат).
void main() {
  group('looksLikeCatalogSearch (исполнитель — ищет заказы)', () {
    bool exec(String s) => looksLikeCatalogSearch(s, isCustomer: false);

    test('явные поисковые запросы → true', () {
      expect(exec('есть заказы поблизости на неделю?'), isTrue);
      expect(exec('найди заказы рядом'), isTrue);
      expect(exec('найди мне заказы рядом'), isTrue); // «мне» — это поиск, не «мои»
      expect(exec('покажи заказы на завтра'), isTrue);
      expect(exec('какие есть заказы на неделю'), isTrue);
      expect(exec('ищу работу рядом'), isTrue);
      expect(exec('заказы на 15-20 июня'), isTrue);
      expect(exec('подбери заказы для экскаватора'), isTrue);
      expect(exec('есть ли заказы недалеко'), isTrue);
      expect(exec('что есть по заказам сегодня'), isTrue);
    });

    test('FAQ и как-вопросы → false', () {
      expect(exec('как откликнуться на заказ?'), isFalse);
      expect(exec('почему мой заказ пропал'), isFalse);
      expect(exec('что делать если заказчик не отвечает'), isFalse);
      expect(exec('как найти заказы'), isFalse); // «как …» — это инструкция
      expect(exec('сколько стоит подписка'), isFalse);
      expect(exec('можно ли отказаться от заказа'), isFalse);
    });

    test('личные «мои/у меня» заказы → false (отвечает чат с контекстом)', () {
      expect(exec('покажи мои заказы'), isFalse);
      expect(exec('есть ли у меня заказы завтра'), isFalse);
      expect(exec('какой у меня заказ на послезавтра'), isFalse);
    });

    test('про аккаунт/функции → false', () {
      expect(exec('моя подписка активна?'), isFalse);
      expect(exec('какой у меня рейтинг'), isFalse);
      expect(exec('как пройти верификацию'), isFalse);
    });

    test('болтовня и приветствия → false', () {
      expect(exec('привет'), isFalse);
      expect(exec('спасибо'), isFalse);
      expect(exec('как дела'), isFalse);
      expect(exec('ок'), isFalse);
    });
  });

  group('looksLikeCatalogSearch (заказчик — ищет исполнителей/технику)', () {
    bool cust(String s) => looksLikeCatalogSearch(s, isCustomer: true);

    test('явные поисковые запросы → true', () {
      expect(cust('найди экскаватор в москве'), isTrue);
      expect(cust('нужен самосвал рядом'), isTrue);
      expect(cust('ищу исполнителя на завтра'), isTrue);
      expect(cust('найди кран'), isTrue);
      expect(cust('подбери технику поблизости'), isTrue);
      expect(cust('есть ли исполнители недалеко'), isTrue);
    });

    test('FAQ/личное → false', () {
      expect(cust('как создать заказ'), isFalse);
      expect(cust('мои заказы'), isFalse);
      expect(cust('сколько стоит разместить заказ'), isFalse);
      expect(cust('как пополнить баланс'), isFalse);
    });
  });

  group('looksLikeFaqQuestion (возврат из поиска в чат)', () {
    test('FAQ/личные вопросы → true', () {
      expect(looksLikeFaqQuestion('как откликнуться на этот заказ?'), isTrue);
      expect(looksLikeFaqQuestion('сколько стоит подписка'), isTrue);
      expect(looksLikeFaqQuestion('какой у меня рейтинг'), isTrue);
      expect(looksLikeFaqQuestion('как пройти проверку'), isTrue);
    });

    test('уточнения поиска остаются в поиске → false', () {
      expect(looksLikeFaqQuestion('а подешевле есть?'), isFalse);
      expect(looksLikeFaqQuestion('поближе'), isFalse);
      expect(looksLikeFaqQuestion('только экскаватор'), isFalse);
      expect(looksLikeFaqQuestion('подальше за город'), isFalse);
      expect(looksLikeFaqQuestion('ещё варианты'), isFalse);
    });
  });
}
