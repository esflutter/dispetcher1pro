import 'package:flutter_test/flutter_test.dart';
import 'package:dispatcher_1/core/ai/ai_client.dart';

/// Unit-тесты для value-классов AiClient. Сам клиент завязан на Supabase
/// singleton и стрим-эндпоинт — для них нужны интеграционные тесты с
/// поднятой Edge Function. Здесь покрываем только чистую логику моделей.
void main() {
  group('AiQuota', () {
    test('left возвращает оставшийся лимит', () {
      const q = AiQuota(used: 10, total: 50);
      expect(q.left, 40);
    });

    test('left не уходит в минус если used больше total', () {
      const q = AiQuota(used: 100, total: 50);
      expect(q.left, 0);
    });

    test('used=0 → left==total', () {
      const q = AiQuota(used: 0, total: 30);
      expect(q.left, 30);
    });
  });

  group('AiReply', () {
    test('dataKind читает kind из data', () {
      const r = AiReply(
        sessionId: 'sid',
        text: 'hi',
        data: <String, dynamic>{'kind': 'order_cards', 'ids': <dynamic>['a', 'b', 1]},
      );
      expect(r.dataKind, 'order_cards');
    });

    test('itemIds фильтрует только строки', () {
      const r = AiReply(
        sessionId: 'sid',
        text: '',
        data: <String, dynamic>{'ids': <dynamic>['a', 1, 'b', null]},
      );
      expect(r.itemIds, <String>['a', 'b']);
    });

    test('isDraftReady возвращает false если поля нет', () {
      const r = AiReply(sessionId: 'sid', text: '', data: <String, dynamic>{});
      expect(r.isDraftReady, isFalse);
    });

    test('isDraftReady=true для готового черновика', () {
      const r = AiReply(
        sessionId: 'sid',
        text: '',
        data: <String, dynamic>{'ready': true, 'kind': 'order_draft'},
      );
      expect(r.isDraftReady, isTrue);
    });

    test('items возвращает массив map-объектов', () {
      const r = AiReply(
        sessionId: 'sid',
        text: '',
        data: <String, dynamic>{
          'items': <dynamic>[
            <String, dynamic>{'id': '1'},
            <String, dynamic>{'id': '2'},
            'not-a-map',
          ],
        },
      );
      expect(r.items.length, 2);
      expect(r.items[0]['id'], '1');
    });

    test('draft возвращает Map когда есть, иначе null', () {
      const a = AiReply(
        sessionId: 'sid',
        text: '',
        data: <String, dynamic>{'draft': <String, dynamic>{'title': 'X'}},
      );
      const b = AiReply(sessionId: 'sid', text: '', data: <String, dynamic>{});
      expect(a.draft, isNotNull);
      expect(a.draft!['title'], 'X');
      expect(b.draft, isNull);
    });
  });

  group('AiChatChunk', () {
    test('done=false → quota=null обычно', () {
      const c = AiChatChunk(text: 'hi', delta: 'hi', done: false);
      expect(c.done, isFalse);
      expect(c.quota, isNull);
    });

    test('done=true несёт квоту', () {
      const c = AiChatChunk(
        text: 'hello',
        delta: '',
        done: true,
        quota: AiQuota(used: 5, total: 50),
      );
      expect(c.done, isTrue);
      expect(c.quota!.left, 45);
    });
  });

  group('AiQuotaExceeded / AiContentFilterError', () {
    test('сообщения передаются и доступны через toString', () {
      final q = AiQuotaExceeded('quota text');
      expect(q.message, 'quota text');
      expect(q.toString(), contains('quota text'));

      final c = AiContentFilterError('filter text');
      expect(c.message, 'filter text');
      expect(c.toString(), contains('filter text'));
    });
  });
}
