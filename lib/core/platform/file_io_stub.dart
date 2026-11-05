import 'dart:typed_data';

const fileIoSupported = false;

bool canShareFile(String name, String mime) => false;

void downloadFile(String name, Uint8List bytes, String mime) =>
    throw UnsupportedError('Доступно только в браузере');

Future<bool> shareFile(String name, Uint8List bytes, String mime) =>
    throw UnsupportedError('Доступно только в браузере');

Future<String?> pickTextFile() =>
    throw UnsupportedError('Доступно только в браузере');

Future<bool?> requestPersistentStorage() async => null;

Future<bool?> isStoragePersisted() async => null;

bool isInstalledApp() => false;
