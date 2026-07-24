import 'package:dispatcher_1/core/payments/models.dart';

bool isPaymentPriceReady({
  required PaymentKind kind,
  required int? amount,
  required bool activateTrial,
  required int? renewalAmount,
}) {
  if (activateTrial) return renewalAmount != null;
  if (kind == PaymentKind.cardBinding) return true;
  return amount != null;
}

bool shouldSaveNewCard({
  required PaymentKind kind,
  required bool hasSelectedSavedCard,
  required bool activateTrial,
  required bool saveServiceCard,
}) {
  if (hasSelectedSavedCard) return false;
  if (kind == PaymentKind.cardBinding) return true;
  if (kind == PaymentKind.subscription || activateTrial) return true;
  return saveServiceCard;
}
