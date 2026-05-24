import 'package:flutter/material.dart' show Brightness, Color, Colors;
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Единый билдер `SystemUiOverlayStyle` для всех экранов.
///
/// Раньше глобальный стиль в `main.dart` задавал только цвет иконок
/// статус-бара и не трогал nav-bar. На Android 10+ это давало:
///   - дефолтный чёрный фон под навигационными кнопками (некорректно
///     для светлого приложения, edge-to-edge компенсирует);
///   - полупрозрачный «контрастный» оверлей системы поверх нав-бара,
///     визуально похожий на лишнюю полосу.
///
/// Билдер принимает три параметра:
///   - `navBarColor` — цвет фона под нав-баром (равен фону Scaffold);
///   - `navIconBrightness` — яркость иконок нав-бара под цвет;
///   - `statusIconBrightness` — яркость иконок статус-бара;
///
/// Сразу же отключает `*ContrastEnforced`, чтобы полупрозрачная полоса
/// не появлялась.
SystemUiOverlayStyle dispatcherSystemBarStyle({
  Color navBarColor = AppColors.background,
  Brightness navIconBrightness = Brightness.dark,
  Brightness statusIconBrightness = Brightness.dark,
}) {
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: statusIconBrightness,
    statusBarBrightness: statusIconBrightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarColor: navBarColor,
    systemNavigationBarDividerColor: navBarColor,
    systemNavigationBarIconBrightness: navIconBrightness,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );
}
