import 'dart:ffi';

import 'package:ffi/ffi.dart';

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

