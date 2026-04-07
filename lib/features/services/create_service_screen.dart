import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Экран «Создание / редактирование услуги».
/// При передаче [serviceId] работает в режиме редактирования.
class CreateServiceScreen extends StatefulWidget {
  const CreateServiceScreen({super.key, this.serviceId});

  final String? serviceId;

  @override
  State<CreateServiceScreen> createState() => _CreateServiceScreenState();
}

class _CreateServiceScreenState extends State<CreateServiceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  final _categoryCtrl = TextEditingController();
  final _equipmentCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceHourCtrl = TextEditingController();
  final _minHoursCtrl = TextEditingController();
  final _priceDayCtrl = TextEditingController();
  final _aiPromptCtrl = TextEditingController();

  bool get _isEdit => widget.serviceId != null;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    if (_isEdit) {
      _titleCtrl.text = 'Аренда экскаватора-погрузчика';
      _descCtrl.text =
          'Опытный машинист, собственный экскаватор-погрузчик JCB 3CX.';
      _priceHourCtrl.text = '1800';
      _minHoursCtrl.text = '4';
      _priceDayCtrl.text = '14000';
      _categoryCtrl.text = 'Спецтехника';
      _equipmentCtrl.text = 'Экскаватор-погрузчик';
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _categoryCtrl.dispose();
    _equipmentCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceHourCtrl.dispose();
    _minHoursCtrl.dispose();
    _priceDayCtrl.dispose();
    _aiPromptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navBarDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          _isEdit ? 'Редактирование услуги' : 'Создание услуги',
          style: AppTextStyles.titleS.copyWith(color: Colors.white),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              size: 20.sp, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_isEdit)
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: TabBar(
                    controller: _tab,
                    indicator: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusPill),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: Colors.white,
                    unselectedLabelColor: AppColors.textSecondary,
                    labelStyle: AppTextStyles.tabActive,
                    unselectedLabelStyle: AppTextStyles.tabInactive,
                    tabs: const [
                      Tab(text: 'Вручную'),
                      Tab(text: 'Заполнить автоматически'),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _isEdit
                  ? _ManualForm(state: this)
                  : TabBarView(
                      controller: _tab,
                      children: [
                        _ManualForm(state: this),
                        _AiForm(state: this),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualForm extends StatelessWidget {
  const _ManualForm({required this.state});
  final _CreateServiceScreenState state;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label('Категория услуг'),
          _Field(
            controller: state._categoryCtrl,
            hint: 'Выберите категорию',
            suffix: Icon(Icons.expand_more,
                size: 22.sp, color: AppColors.textTertiary),
          ),
          SizedBox(height: AppSpacing.md),
          _Label('Спецтехника'),
          _Field(
            controller: state._equipmentCtrl,
            hint: 'Выберите тип техники',
            suffix: Icon(Icons.expand_more,
                size: 22.sp, color: AppColors.textTertiary),
          ),
          SizedBox(height: AppSpacing.md),
          _Label('Название услуги'),
          _Field(
            controller: state._titleCtrl,
            hint: 'Например: Экскаватор для земляных работ',
          ),
          SizedBox(height: AppSpacing.md),
          _Label('Описание услуги'),
          _Field(
            controller: state._descCtrl,
            hint: 'Опишите, какие работы вы выполняете и условия работы',
            maxLines: 4,
          ),
          SizedBox(height: AppSpacing.md),
          _Label('Фото'),
          Text(
            'По желанию добавьте изображения к услуге, до 8 шт',
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textSecondary),
          ),
          SizedBox(height: AppSpacing.xs),
          _PhotoPicker(),
          SizedBox(height: AppSpacing.md),
          _Label('Стоимость'),
          Row(
            children: [
              Expanded(
                child: _Field(
                  controller: state._priceHourCtrl,
                  hint: '₽ / час',
                  keyboardType: TextInputType.number,
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Field(
                  controller: state._priceDayCtrl,
                  hint: '₽ / день',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          _Label('Минимальный заказ'),
          _Field(
            controller: state._minHoursCtrl,
            hint: 'часов',
            keyboardType: TextInputType.number,
          ),
          SizedBox(height: AppSpacing.xs),
          Text(
            'Укажите минимальное количество часов для заказа',
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textSecondary),
          ),
          SizedBox(height: AppSpacing.md),
          _Label('Местоположение'),
          _Field(
            controller: TextEditingController(text: 'Москва'),
            hint: 'Москва',
            suffix: Icon(Icons.location_on_outlined,
                size: 20.sp, color: AppColors.textTertiary),
          ),
          SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: state._isEdit ? 'Сохранить' : 'Создать',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Сохранено'),
                  duration: Duration(seconds: 2),
                ),
              );
              Navigator.of(context).maybePop();
            },
          ),
        ],
      ),
    );
  }
}

class _AiForm extends StatelessWidget {
  const _AiForm({required this.state});
  final _CreateServiceScreenState state;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(AppSpacing.radiusM),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome,
                    color: AppColors.primary, size: 24.sp),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Опишите услугу — текстом или голосом, я заполню всё за вас',
                    style: AppTextStyles.body
                        .copyWith(color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.lg),
          _Label('Опишите услугу текстом'),
          _Field(
            controller: state._aiPromptCtrl,
            hint:
                'Например: сдаю в аренду экскаватор-погрузчик JCB, опыт 10 лет...',
            maxLines: 8,
          ),
          SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'Создать с ИИ',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('ИИ-генерация скоро будет доступна'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        text,
        style: AppTextStyles.bodyMedium.copyWith(
          fontSize: 20.sp,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.suffix,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: AppTextStyles.body,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            AppTextStyles.body.copyWith(color: AppColors.textTertiary),
        filled: true,
        fillColor: AppColors.fieldFill,
        suffixIcon: suffix,
        suffixIconConstraints: BoxConstraints(minWidth: 32.w, minHeight: 24.h),
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

class _PhotoPicker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88.w,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _AddPhotoTile(),
          SizedBox(width: AppSpacing.xs),
          _PhotoTile(),
          SizedBox(width: AppSpacing.xs),
          _PhotoTile(),
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88.w,
      height: 88.w,
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.add_a_photo_outlined,
          color: AppColors.primary, size: 28.sp),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88.w,
      height: 88.w,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined,
          color: AppColors.textTertiary, size: 28.sp),
    );
  }
}
