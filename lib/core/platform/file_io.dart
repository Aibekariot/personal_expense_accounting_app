/// Работа с файлами и хранилищем браузера. В браузере — настоящая
/// реализация, в тестах и на других платформах — заглушка.
library;

export 'file_io_stub.dart' if (dart.library.js_interop) 'file_io_web.dart';
