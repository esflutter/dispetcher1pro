import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:dispatcher_1/core/theme/app_colors.dart';
import 'package:dispatcher_1/core/theme/app_spacing.dart';
import 'package:dispatcher_1/core/theme/app_text_styles.dart';
import 'package:dispatcher_1/core/widgets/primary_button.dart';

/// Длинная форма создания / редактирования карточки исполнителя.
/// Поля точно как в Figma: имя, телефон, местоположение, спецтехника,
/// категории услуг, опыт работы, статус, о себе.
class EditExecutorCardScreen extends StatefulWidget {
  const EditExecutorCardScreen({super.key});

  @override
  State<EditExecutorCardScreen> createState() => _EditExecutorCardScreenState();
}

class _EditExecutorCardScreenState extends State<EditExecutorCardScreen> {
  final _name = TextEditingController(text: 'Александр Иванов');
  final _phone = TextEditingController(text: '+7 999 123-45-67');
  final _location = TextEditingController();
  final _experience = TextEditingController(text: '5 лет');
  final _about = TextEditingController();

  static const _machinery = [
    'Экскаватор-погрузчик',
    'Погрузчик',
    'Миниэкскаватор',
    'Минипогрузчик',
    'Буроям',
    'Самогруз',
    'Автокран',
    'Самосвалы (до 5тн, 15, 25)',
    'Бетононасос',
    'Эвакуатор',
    'Автовышка',
    'Манипулятор',
    'Минитрактор',
    'Экскаватор',
    'Инертные материалы',
  ];
  static const _categories = [
    'Земляные работы',
    'Погрузочно-разгрузочные работы',
    'Перевозка материалов',
    'Строительные работы',
    'Дорожные работы',
    'Буровые работы',
    'Высотные работы',
    'Демонтажные работы',
    'Благоустройство территории',
  ];

  final Set<String> _selMach = {'Экскаватор-погрузчик', 'Погрузчик'};
  final Set<String> _selCat = {
    'Земляные работы',
    'Погрузочно-разгрузочные работы',
  };

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _location.dispose();
    _experience.dispose();
    _about.dispose();
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20.r, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Моя карточка исполнителя',
          style: AppTextStyles.titleS.copyWith(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              AppSpacing.screenH, AppSpacing.md, AppSpacing.screenH, AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TintField(controller: _name, icon: Icons.person_outline),
              SizedBox(height: AppSpacing.sm),
              _TintField(controller: _phone, icon: Icons.phone_outlined),
              SizedBox(height: AppSpacing.lg),
              _Section(title: 'Местоположение'),
              SizedBox(height: AppSpacing.xs),
              _TintField(
                controller: _location,
                icon: Icons.location_on_outlined,
                hint: 'Укажите ваше местоположение',
              ),
              SizedBox(height: AppSpacing.lg),
              _Section(title: 'Спецтехника'),
              SizedBox(height: AppSpacing.sm),
              _ChipWrap(
                items: _machinery,
                selected: _selMach,
                onToggle: (v) => setState(() {
                  _selMach.contains(v) ? _selMach.remove(v) : _selMach.add(v);
                }),
              ),
              SizedBox(height: AppSpacing.lg),
              _Section(title: 'Категории услуг'),
              SizedBox(height: AppSpacing.sm),
              _ChipWrap(
                items: _categories,
                selected: _selCat,
                onToggle: (v) => setState(() {
                  _selCat.contains(v) ? _selCat.remove(v) : _selCat.add(v);
                }),
              ),
              SizedBox(height: AppSpacing.lg),
              _Section(title: 'Опыт работы'),
              SizedBox(height: AppSpacing.xs),
              _TintField(
                controller: _experience,
                icon: Icons.work_outline_rounded,
              ),
              SizedBox(height: AppSpacing.lg),
              _Section(title: 'Статус'),
              SizedBox(height: AppSpacing.xs),
              _TintField(
                controller: TextEditingController(),
                icon: Icons.badge_outlined,
                hint: 'Укажите статус',
                trailing: Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20.r, color: AppColors.textPrimary),
              ),
              SizedBox(height: AppSpacing.lg),
              _Section(title: 'О себе'),
              SizedBox(height: AppSpacing.xs),
              _TintField(
                controller: _about,
                icon: Icons.edit_note_rounded,
                hint: 'Расскажите о себе',
                maxLines: 3,
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                'Информация о вас помогает другим лучше понять, '
                'с кем они будут работать.',
                style: AppTextStyles.caption
                    .copyWith(color: const Color(0xFF707070)),
              ),
              SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Сохранить',
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
              SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: 'Отправить документы на верификацию',
                onPressed: () => context.push('/executor-card/verification'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: AppTextStyles.h3.copyWith(
          fontSize: 20.sp,
          fontWeight: FontWeight.w700,
        ));
  }
}

class _TintField extends StatelessWidget {
  const _TintField({
    required this.controller,
    required this.icon,
    this.hint,
    this.maxLines = 1,
    this.trailing,
  });
  final TextEditingController controller;
  final IconData icon;
  final String? hint;
  final int maxLines;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: AppTextStyles.body,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
        prefixIcon: Icon(icon, size: 22.r, color: AppColors.textSecondary),
        suffixIcon: trailing,
        filled: true,
        fillColor: AppColors.fieldFill,
        contentPadding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({
    required this.items,
    required this.selected,
    required this.onToggle,
  });
  final List<String> items;
  final Set<String> selected;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: items.map((label) {
        final on = selected.contains(label);
        return GestureDetector(
          onTap: () => onToggle(label),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: on ? AppColors.primary : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: AppTextStyles.chip.copyWith(
                      fontSize: 13.sp,
                      color: on ? Colors.white : AppColors.textPrimary,
                    )),
                if (on) ...[
                  SizedBox(width: 6.w),
                  Icon(Icons.close_rounded, size: 12.r, color: Colors.white),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
