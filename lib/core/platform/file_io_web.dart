import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

const fileIoSupported = true;

web.File _file(String name, Uint8List bytes, String mime) =>
    web.File(<JSAny>[bytes.toJS].toJS, name, web.FilePropertyBag(type: mime));

/// Можно ли отправить такой файл через меню «Поделиться» (iPhone, Android).
bool canShareFile(String name, String mime) {
  try {
    final data = web.ShareData(files: <web.File>[_file(name, Uint8List(1), mime)].toJS);
    return web.window.navigator.canShare(data);
  } catch (_) {
    return false;
  }
}

/// Скачивает файл (в «Загрузки» на компьютере и Android).
void downloadFile(String name, Uint8List bytes, String mime) {
  final blob = web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  a.style.display = 'none';
  web.document.body!.appendChild(a);
  a.click();
  a.remove();
  Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
}

/// Открывает системное меню «Поделиться» с файлом: сохранить в «Файлы»,
/// отправить в Telegram и т.п. false — пользователь отменил или не удалось.
/// Вызывать сразу по нажатию кнопки (браузер требует действия пользователя).
Future<bool> shareFile(String name, Uint8List bytes, String mime) async {
  try {
    final data = web.ShareData(files: <web.File>[_file(name, bytes, mime)].toJS);
    await web.window.navigator.share(data).toDart;
    return true;
  } catch (_) {
    return false;
  }
}

/// Выбор файла пользователем; возвращает его текст.
/// null — если пользователь закрыл выбор файла.
Future<String?> pickTextFile() {
  final completer = Completer<String?>();
  final input = web.HTMLInputElement()..type = 'file';
  input.style.display = 'none';
  web.document.body!.appendChild(input);

  void finish(String? text) {
    input.remove();
    if (!completer.isCompleted) completer.complete(text);
  }

  Future<void> read() async {
    final file = input.files?.item(0);
    if (file == null) return finish(null);
    try {
      finish((await file.text().toDart).toDart);
    } catch (e) {
      input.remove();
      if (!completer.isCompleted) completer.completeError(e);
    }
  }

  input.addEventListener('change', ((web.Event _) => unawaited(read())).toJS);
  input.addEventListener('cancel', ((web.Event _) => finish(null)).toJS);
  input.click();
  return completer.future;
}

/// Просит браузер не удалять данные приложения при нехватке места.
Future<bool?> requestPersistentStorage() async {
  try {
    return (await web.window.navigator.storage.persist().toDart).toDart;
  } catch (_) {
    return null;
  }
}

Future<bool?> isStoragePersisted() async {
  try {
    return (await web.window.navigator.storage.persisted().toDart).toDart;
  } catch (_) {
    return null;
  }
}

/// Открыто ли как установленное приложение (с экрана «Домой»).
bool isInstalledApp() {
  try {
    return web.window.matchMedia('(display-mode: standalone)').matches;
  } catch (_) {
    return false;
  }
}
