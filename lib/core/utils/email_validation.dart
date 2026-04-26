/// Единая валидация email во всём приложении исполнителя. Раньше
/// `edit_profile_screen` и `edit_executor_card_screen` имели каждый свой
/// regex (один строгий, второй пропускал `a@@b.c`) — разные ошибки в
/// двух местах одного и того же поля.
final RegExp _emailRegex = RegExp(
  r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
);

/// True, если строка похожа на корректный email. Допускаем пустую
/// строку — поле необязательное; если строка непустая, но не подходит
/// под формат, валидация в форме покажет ошибку. Дополнительно режем
/// длину: БД ограничивает email 254 символами, формы — 50.
bool isValidEmail(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) return true;
  return _emailRegex.hasMatch(trimmed);
}
