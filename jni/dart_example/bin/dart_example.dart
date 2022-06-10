import 'package:dart_example/dart_example.dart' as dart_example;

import 'package:jni/jni.dart' as jni;

void main(List<String> arguments) {
  jni.spawnJvm();
  print('JNI Version: ${jni.getJniVersion()}!');
}
