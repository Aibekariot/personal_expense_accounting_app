import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Объединяет несколько асинхронных значений в одно:
/// ошибка, если хоть одно с ошибкой; загрузка, если хоть одно ещё не готово;
/// иначе — результат [build] (внутри можно использовать `.requireValue`).
AsyncValue<R> combineAsync<R>(
  List<AsyncValue<Object?>> values,
  R Function() build,
) {
  for (final v in values) {
    if (v.hasError) {
      return AsyncError(v.error!, v.stackTrace ?? StackTrace.current);
    }
  }
  if (values.any((v) => !v.hasValue)) return const AsyncLoading();
  try {
    return AsyncData(build());
  } catch (e, st) {
    return AsyncError(e, st);
  }
}
