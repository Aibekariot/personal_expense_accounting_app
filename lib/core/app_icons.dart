import 'package:flutter/material.dart';

import '../data/db/tables.dart';

/// Иконки категорий. В базе хранится ключ (строка), а не сама иконка.
const Map<String, IconData> categoryIcons = {
  'shopping_cart': Icons.shopping_cart_outlined,
  'restaurant': Icons.restaurant_outlined,
  'directions_bus': Icons.directions_bus_outlined,
  'directions_car': Icons.directions_car_outlined,
  'home': Icons.home_outlined,
  'wifi': Icons.wifi,
  'medical': Icons.medical_services_outlined,
  'checkroom': Icons.checkroom_outlined,
  'spa': Icons.spa_outlined,
  'movie': Icons.movie_outlined,
  'subscriptions': Icons.subscriptions_outlined,
  'school': Icons.school_outlined,
  'child_care': Icons.child_care_outlined,
  'gift': Icons.card_giftcard_outlined,
  'flight': Icons.flight_outlined,
  'more': Icons.more_horiz,
  'work': Icons.work_outline,
  'handyman': Icons.handyman_outlined,
  'savings': Icons.savings_outlined,
  'pets': Icons.pets_outlined,
  'sports': Icons.sports_soccer_outlined,
  'phone': Icons.phone_android_outlined,
  'coffee': Icons.local_cafe_outlined,
  'fuel': Icons.local_gas_station_outlined,
  'taxi': Icons.local_taxi_outlined,
  'pharmacy': Icons.local_pharmacy_outlined,
  'books': Icons.menu_book_outlined,
  'games': Icons.sports_esports_outlined,
  'tools': Icons.build_outlined,
  'charity': Icons.volunteer_activism_outlined,
};

IconData categoryIcon(String key) => categoryIcons[key] ?? Icons.category_outlined;

IconData accountTypeIcon(AccountType type) => switch (type) {
  AccountType.cash => Icons.payments_outlined,
  AccountType.card => Icons.credit_card,
  AccountType.deposit => Icons.savings_outlined,
  AccountType.other => Icons.account_balance_wallet_outlined,
  AccountType.credit => Icons.account_balance_outlined,
};

String accountTypeLabel(AccountType type) => switch (type) {
  AccountType.cash => 'Наличные',
  AccountType.card => 'Карта',
  AccountType.deposit => 'Вклад',
  AccountType.other => 'Другое',
  AccountType.credit => 'Кредит',
};
