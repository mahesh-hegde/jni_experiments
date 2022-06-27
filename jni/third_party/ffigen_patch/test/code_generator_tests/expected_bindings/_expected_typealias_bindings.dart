// ignore_for_file: non_constant_identifier_names

// AUTO GENERATED FILE, DO NOT EDIT.
//
// Generated by `package:ffigen`.
import 'dart:ffi' as ffi;

class Bindings {
  /// Holds the symbol lookup function.
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
      _lookup;

  /// The symbols are looked up in [dynamicLibrary].
  Bindings(ffi.DynamicLibrary dynamicLibrary) : _lookup = dynamicLibrary.lookup;

  /// The symbols are looked up with [lookup].
  Bindings.fromLookup(
      ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
          lookup)
      : _lookup = lookup;

  ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> WithTypealiasStruct1(
    Struct3Typealias t,
  ) {
    return _WithTypealiasStruct1(
      t,
    );
  }

  late final _WithTypealiasStruct1Ptr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> Function(
              Struct3Typealias)>>('WithTypealiasStruct');
  late final _WithTypealiasStruct1 = _WithTypealiasStruct1Ptr.asFunction<
      ffi.Pointer<ffi.NativeFunction<ffi.Void Function()>> Function(
          Struct3Typealias)>();
}

typedef RawUnused = Struct1;

class Struct1 extends ffi.Opaque {}

class WithTypealiasStruct extends ffi.Struct {
  external Struct2Typealias t;
}

typedef Struct2Typealias = Struct2;

class Struct2 extends ffi.Struct {
  @ffi.Double()
  external double a;
}

typedef Struct3Typealias = Struct3;

class Struct3 extends ffi.Opaque {}
