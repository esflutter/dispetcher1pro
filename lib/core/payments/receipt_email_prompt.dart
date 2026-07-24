import 'package:flutter/material.dart';

import 'package:dispatcher_1/core/payments/payment_service.dart';
import 'package:dispatcher_1/core/utils/email_validation.dart';

/// Возвращает email для фискального чека.
///
/// Если email уже указан в профиле или ранее был сохранён исключительно
/// для чеков, диалог не показывается. Иначе спрашиваем адрес один раз.
/// Сервер сохранит его в `profiles_private.receipt_email`, не меняя поле
/// email в профиле исполнителя.
Future<String?> ensureReceiptEmail(BuildContext context) async {
  final String? stored = await PaymentService.instance.getReceiptEmail();
  if (stored != null) return stored;
  if (!context.mounted) return null;

  final TextEditingController controller = TextEditingController();
  String? errorText;
  final String? result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          void submit() {
            final String value = controller.text.trim().toLowerCase();
            if (value.isEmpty || !isValidEmail(value)) {
              setState(() {
                errorText = value.isEmpty
                    ? 'Укажите email для отправки чека'
                    : 'Проверьте правильность email';
              });
              return;
            }
            Navigator.of(dialogContext).pop(value);
          }

          return AlertDialog(
            title: const Text('Email для чека'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'ЮKassa отправит на этот адрес фискальный чек. '
                  'Email сохранится только для следующих чеков и '
                  'не появится в вашем профиле.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: 'Электронная почта',
                    hintText: 'name@example.ru',
                    errorText: errorText,
                    counterText: '',
                  ),
                  onChanged: (_) {
                    if (errorText != null) {
                      setState(() => errorText = null);
                    }
                  },
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Отмена'),
              ),
              FilledButton(onPressed: submit, child: const Text('Продолжить')),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  return result;
}
