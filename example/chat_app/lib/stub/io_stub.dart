// Stub for dart:io on web
class Platform {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;
  static bool get isWindows => false;
}

class File {
  File(String path);
  String get path => '';
  bool existsSync() => false;
  int lengthSync() => 0;
  Future<void> delete() async {}
  void deleteSync() {}
}

class Directory {
  Directory(String path);
  String get path => '';
  bool existsSync() => false;
  void createSync({bool recursive = false}) {}
}
