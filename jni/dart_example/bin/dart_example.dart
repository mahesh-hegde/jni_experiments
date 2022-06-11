import 'package:jni/jni.dart' as jni;

import 'dart:io';
import 'package:path/path.dart';

void main(List<String> arguments) {
  final libPath = join(dirname(Platform.script.toFilePath(windows: Platform.isWindows)), "libdartjni.so");
  jni.spawnJvm(helpersLibraryPath: libPath);
  print('Got String: ${jni.toJavaString(134)}!');
}
