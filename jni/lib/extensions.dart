import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'jni_bindings_generated.dart';

// Extension methods on JNIEnv

extension JavaVMUtilMethods on JavaVM {}

// Returns a pointer to initialization args
// The pointer is allocated by calloc,
// and should be deleted by free

extension JObjectMethods on JObject {
  // DeleteRef
}

extension JStringMethods on JString {}

extension StringMethodsForJNI on String {
  Pointer<Char> toNativeChars() {
    return toNativeUtf8().cast<Char>();
  }
}

extension CharPtrMethodsForJNI on Pointer<Char> {
  String toDartString() {
    return cast<Utf8>().toDartString();
  }
}

// JValue array

