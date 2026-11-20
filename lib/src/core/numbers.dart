/// A number as the panel's language writes it (QA 2026-10-24): "4,6" and
/// "1.720" in Turkish, "4.6" and "1,720" in English. The web SDK's
/// `numberIn` writes the same through `Intl.NumberFormat`; the SDK carries no
/// intl package, so the six shipped languages' marks are here by hand, with
/// Latin digits in all of them, as the web SDK writes them.
///
/// [digits] fixes the decimals; without it they are the value's own, at most
/// three. Spanish groups only from five digits ("1720", "12.345"), as CLDR
/// does.
String rendelNumber(num value, String locale, {int? digits}) {
  final language = locale.trim().toLowerCase().split(RegExp('[-_]')).first;
  final (decimal, group, minGroup) = switch (language) {
    'tr' || 'de' => (',', '.', 4),
    'es' => (',', '.', 5),
    'fr' => (',', ' ', 4),
    _ => ('.', ',', 4),
  };
  var fixed = value.abs().toStringAsFixed(digits ?? 3);
  if (digits == null && fixed.contains('.')) {
    fixed = fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  final dot = fixed.indexOf('.');
  final whole = dot == -1 ? fixed : fixed.substring(0, dot);
  final fraction = dot == -1 ? '' : fixed.substring(dot + 1);
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (whole.length >= minGroup && i > 0 && (whole.length - i) % 3 == 0) grouped.write(group);
    grouped.write(whole[i]);
  }
  final negative = value < 0 && double.parse(fixed) != 0;
  return '${negative ? '-' : ''}$grouped${fraction.isEmpty ? '' : '$decimal$fraction'}';
}

/// [amount] of [currency] (an ISO 4217 code) as the panel's language writes
/// money, a whole amount without its zeros: "$149" and "$204.50" in English,
/// "₺1.299,90" in Turkish, "149 €" in German, French and Spanish. The web SDK
/// writes it through `Intl.NumberFormat`; with no intl package here, the
/// currencies the shipped languages meet have their signs by hand and any
/// other is written as its code after the number.
String rendelMoney(num amount, String currency, String locale) {
  const signs = {'USD': r'$', 'EUR': '€', 'GBP': '£', 'TRY': '₺', 'JPY': '¥', 'AUD': r'A$', 'CAD': r'CA$'};
  final language = locale.trim().toLowerCase().split(RegExp('[-_]')).first;
  final number = rendelNumber(amount, locale, digits: amount == amount.roundToDouble() ? 0 : 2);
  final sign = signs[currency];
  if (sign == null) return '$number $currency';
  return switch (language) {
    'de' || 'fr' || 'es' || 'ar' => '$number $sign',
    _ => '$sign$number',
  };
}
