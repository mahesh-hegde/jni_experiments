import 'package:jni/jni.dart';

import 'dart:io';
import 'package:path/path.dart';

void main(List<String> arguments) {
  final libPath = join(
      dirname(Platform.script.toFilePath(windows: Platform.isWindows)),
      "libdartjni.so");
  Jni jni = Jni.spawn(helperDir: libPath);
  jni.setJniLogging(JniLogLevel.JNI_DEBUG);
}
