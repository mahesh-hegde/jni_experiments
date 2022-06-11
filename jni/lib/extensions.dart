import 'dart:ffi';

import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'jni_bindings_generated.dart';

// Extension methods on JNIEnv

typedef EnvPtr = Pointer<JNIEnv>;

extension JNIEnvMethods on Pointer<JNIEnv> {}

extension JavaVMMethods on JavaVM {}

// Returns a pointer to initialization args
// The pointer is allocated by calloc, 
// and should be deleted by free
Pointer<JavaVMInitArgs> createJavaVMInitArgs({
  List<String> options = const [],
}) {
  final args = calloc<JavaVMInitArgs>();
  if (options.isNotEmpty) {}
  return args;
}

void freeJavaVMInitArgs(Pointer<JavaVMInitArgs> argPtr) {}

extension JObjectMethods on jobject {
  // DeleteRef
}

extension JStringMethods on jstring {}

extension StringMethodsForJNI on String {
	ffi.Pointer<Char> toNativeChars() {
		return toNativeUtf8().cast<Char>();
	}
}

