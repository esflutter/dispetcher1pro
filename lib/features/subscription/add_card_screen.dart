import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Экран добавления банковской карты («Новая карта»).
class AddCardScreen extends StatefulWidget {
  const AddCardScreen({super.key});

  @override
  State<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends State<AddCardScreen> {
  final TextEditingController _number = TextEditingController();
  final TextEditingController _exp = TextEditingController();
  final TextEditingController _cvv = TextEditingController();

  final MaskTextInputFormatter _numberMask = MaskTextInputFormatter(
    mask: '#### #### #### ####',
    filter: <String, RegExp>{'#': RegExp(r'[0-9]')},
  );
  final MaskTextInputFormatter _expMask = MaskTextInputFormatter(
    mask: '##/##',
    filter: <String, RegExp>{'#': RegExp(r'[0-9]')},
  );

  @override
  void dispose() {
    _number.dispose();
    _exp.dispose();
    _cvv.dispose();
    super.dispose();
  }

  bool get _valid =>
      _number.text.replaceAll(' ', '').length == 16 &&
      _exp.text.length == 5 &&
      _cvv.text.length == 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Новая карта', style: AppTextStyles.titleS),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(AppSpacing.screenH, AppSpacing.md,
                    AppSpacing.screenH, AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _Label('Номер карты'),
                    _Field(
                      controller: _number,
                      hint: '0000 0000 0000 0000',
                      keyboardType: TextInputType.number,
                      formatters: <TextInputFormatter>[_numberMask],
                      onChanged: (_) => setState(() {}),
                    ),
                    SizedBox(height: AppSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _Label('Дата'),
                              _Field(
                                controller: _exp,
                                hint: '00/00',
                                keyboardType: TextInputType.number,
                                formatters: <TextInputFormatter>[_expMask],
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _Label('CVV / CVC'),
                              _Field(
                                controller: _cvv,
                                hint: '000',
                                obscure: true,
                                keyboardType: TextInputType.number,
                                formatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(3),
                                ],
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.screenH, 0, AppSpacing.screenH, AppSpacing.lg),
              child: PrimaryButton(
                label: 'Добавить',
                enabled: _valid,
                onPressed: () {
                  // Возвращаем последние 4 цифры в `PaymentScreen` —
                  // он их подставляет в чекаут «•••• 1234». Без этого
                  // кнопка «Оплатить» оставалась disabled, и оплатить
                  // было невозможно.
                  final String digits =
                      _number.text.replaceAll(' ', '');
                  final String last4 = digits.length >= 4
                      ? digits.substring(digits.length - 4)
                      : digits;
                  context.pop(last4);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(text,
            style: AppTextStyles.subBody.copyWith(color: AppColors.textSecondary)),
      );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.formatters,
    this.obscure = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;
  final bool obscure;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      obscureText: obscure,
      onChanged: onChanged,
      style: AppTextStyles.body,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            AppTextStyles.body.copyWith(color: AppColors.textTertiary),
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
