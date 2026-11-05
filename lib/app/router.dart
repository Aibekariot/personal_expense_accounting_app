import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/db/app_database.dart';
import '../features/accounts/account_form_screen.dart';
import '../features/accounts/accounts_screen.dart';
import '../features/backup/backup_screen.dart';
import '../features/budgets/budget_form_screen.dart';
import '../features/budgets/budgets_screen.dart';
import '../features/categories/categories_screen.dart';
import '../features/categories/category_form_screen.dart';
import '../features/currencies/converter_screen.dart';
import '../features/currencies/currencies_screen.dart';
import '../features/currencies/currency_form_screen.dart';
import '../features/debts/debt_detail_screen.dart';
import '../features/debts/debt_form_screen.dart';
import '../features/debts/debts_screen.dart';
import '../features/more/more_screen.dart';
import '../features/operations/operation_form_screen.dart';
import '../features/operations/operations_screen.dart';
import '../features/stats/stats_screen.dart';
import 'home_shell.dart';

abstract final class Routes {
  static const operations = '/operations';

  /// Новая операция. Открывается поверх любой вкладки.
  static String operationNew({OperationType? type, int? debtId, int? accountId}) => Uri(
    path: '/operation/new',
    queryParameters: {
      if (type != null) 'type': type.name,
      if (debtId != null) 'debt': '$debtId',
      if (accountId != null) 'account': '$accountId',
    },
  ).toString().replaceAll(RegExp(r'\?$'), '');
  static String operationEdit(int id) => '/operation/$id';
  static String operationCopy(int id) => '/operation/new?copy=$id';

  static const accounts = '/accounts';
  static const accountNew = '/accounts/new';
  static String accountEdit(int id) => '/accounts/$id';

  static const stats = '/stats';

  static const more = '/more';
  static const currencies = '/more/currencies';
  static const currencyAdd = '/more/currencies/add';
  static String currencyEdit(String code) => '/more/currencies/edit/$code';
  static const converter = '/more/converter';
  static const budgets = '/more/budgets';
  static const budgetNew = '/more/budgets/new';
  static String budgetEdit(int id) => '/more/budgets/$id';
  static const debts = '/more/debts';
  static const debtNew = '/more/debts/new';
  static String debt(int id) => '/more/debts/$id';
  static String debtEdit(int id) => '/more/debts/$id/edit';
  static const backup = '/more/backup';

  /// Категории открываются и из «Ещё», и из формы операции — поэтому
  /// они поверх вкладок, а не внутри «Ещё».
  static const categories = '/categories';
  static String categoryNew(CategoryType type, {int? parentId}) =>
      '/categories/new?type=${type.name}${parentId == null ? '' : '&parent=$parentId'}';
  static String categoryEdit(int id) => '/categories/$id';
}

/// Навигатор поверх нижней панели — для полноэкранных форм.
final _rootNavigatorKey = GlobalKey<NavigatorState>();

int? _intParam(GoRouterState s, String name) =>
    int.tryParse(s.uri.queryParameters[name] ?? '');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: Routes.operations,
    routes: [
      GoRoute(
        path: '/operation/new',
        builder: (_, state) => OperationFormScreen(
          type: OperationType.values.asNameMap()[state.uri.queryParameters['type']],
          debtId: _intParam(state, 'debt'),
          accountId: _intParam(state, 'account'),
          copyFromId: _intParam(state, 'copy'),
        ),
      ),
      GoRoute(
        path: '/operation/:id',
        builder: (_, state) =>
            OperationFormScreen(operationId: int.tryParse(state.pathParameters['id']!) ?? -1),
      ),
      GoRoute(
        path: Routes.categories,
        builder: (_, _) => const CategoriesScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, state) => CategoryFormScreen(
              type: CategoryType.values.asNameMap()[state.uri.queryParameters['type']] ??
                  CategoryType.expense,
              parentId: _intParam(state, 'parent'),
            ),
          ),
          GoRoute(
            path: ':id',
            builder: (_, state) =>
                CategoryFormScreen(categoryId: int.tryParse(state.pathParameters['id']!) ?? -1),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.operations,
                builder: (_, _) => const OperationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.accounts,
                builder: (_, _) => const AccountsScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, _) => const AccountFormScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, state) => AccountFormScreen(
                      accountId: int.tryParse(state.pathParameters['id']!) ?? -1,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.stats,
                builder: (_, _) => const StatsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.more,
                builder: (_, _) => const MoreScreen(),
                routes: [
                  GoRoute(
                    path: 'currencies',
                    builder: (_, _) => const CurrenciesScreen(),
                    routes: [
                      GoRoute(
                        path: 'add',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, _) => const CurrencyFormScreen(),
                      ),
                      GoRoute(
                        path: 'edit/:code',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, state) =>
                            CurrencyFormScreen(code: state.pathParameters['code']),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'converter',
                    builder: (_, _) => const ConverterScreen(),
                  ),
                  GoRoute(
                    path: 'budgets',
                    builder: (_, _) => const BudgetsScreen(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, _) => const BudgetFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, state) => BudgetFormScreen(
                          budgetId: int.tryParse(state.pathParameters['id']!) ?? -1,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'debts',
                    builder: (_, _) => const DebtsScreen(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (_, _) => const DebtFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (_, state) => DebtDetailScreen(
                          debtId: int.tryParse(state.pathParameters['id']!) ?? -1,
                        ),
                        routes: [
                          GoRoute(
                            path: 'edit',
                            parentNavigatorKey: _rootNavigatorKey,
                            builder: (_, state) => DebtFormScreen(
                              debtId: int.tryParse(state.pathParameters['id']!) ?? -1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'backup',
                    builder: (_, _) => const BackupScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
