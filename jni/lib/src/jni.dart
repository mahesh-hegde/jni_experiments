import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'jni_bindings_generated.dart';
import 'extensions.dart';

String _getLibraryFilename(String base) {
  if (Platform.isLinux || Platform.isAndroid) {
    return "lib$base.so";
  } else if (Platform.isWindows) {
    return "$base.dll";
  } else if (Platform.isMacOS) {
    return "lib$base.dll";
  } else {
    throw Exception("cannot derive library name: unsupported platform");
  }
}

/// Load Dart-JNI Helper library (libdartjni.so).
///
/// In Flutter, this doesn't need to be called explicitly.
///
/// If path is provided, it's used to load the library.
/// Else it's searched for in the
/// directory where script / exe is located
DynamicLibrary _loadJniHelpersLibrary({String? path}) {
  // TODO: On standalone target, look in current directory
  final libPath = path ?? _getLibraryFilename("dartjni");
  final dylib = DynamicLibrary.open(libPath);
  return dylib;
}

/// Jni represents a single JNI instance running.
///
/// It provides convenience functions for looking up and invoking functions
/// without several FFI conversions.
///
/// You can also get access to instance of underlying JavaVM and JniEnv, and
/// then use them in a way similar to JNI C++ API.
class Jni {
  final JniBindings _bindings;

  Jni._(this._bindings);

  static Jni? _instance;

  static Jni getInstance() {
    if (Platform.isAndroid) {
      _instance ??= Jni._(JniBindings(_loadJniHelpersLibrary()));
      return _instance!;
    }
    final inst = _instance;
    if (inst == null) {
      throw Exception("No JNI Instance associated with the process");
    }
    return inst;
  }

  static Jni spawn({
    String? helperPath,
    int logLevel = JniLogLevel.JNI_INFO,
    List<String> jvmOptions = const [],
    List<String> classPath = const [],
    bool ignoreUnrecognized = false,
    int jniVersion = JNI_VERSION_1_6,
  }) {
    // currently only one VM per process
    if (_instance != null) {
      throw Exception("Currently only 1 VM is supported.");
    }
    final dylib = _loadJniHelpersLibrary(path: helperPath);
    final inst = Jni._(JniBindings(dylib));
    _instance = inst;
    inst._bindings.SetJNILogging(logLevel);
    final jArgs = _createVMArgs(
      options: jvmOptions,
      classPath: classPath,
      version: jniVersion,
      ignoreUnrecognized: ignoreUnrecognized,
    );
    inst._bindings.SpawnJvm(jArgs);
    _freeVMArgs(jArgs);
    return inst;
  }

  static Pointer<JavaVMInitArgs> _createVMArgs({
    List<String> options = const [],
    List<String> classPath = const [],
    bool ignoreUnrecognized = false,
    int version = JNI_VERSION_1_6,
    // TODO: JNI_OnLoad, JNI_OnUnload, exit hooks
  }) {
    final args = calloc<JavaVMInitArgs>();
    if (options.isNotEmpty || classPath.isNotEmpty) {
      var length = options.length;
      var count = length + (classPath.isNotEmpty ? 1 : 0);

      final optsPtr = (count != 0) ? calloc<JavaVMOption>(count) : nullptr;
      args.ref.options = optsPtr;
      for (int i = 0; i < options.length; i++) {
        optsPtr.elementAt(i).ref.optionString = options[i].toNativeChars();
      }
      if (classPath.isNotEmpty) {
        final classPathString = classPath.join(Platform.isWindows ? ';' : ":");
        optsPtr.elementAt(count - 1).ref.optionString =
            "-Djava.class.path=$classPathString".toNativeChars();
      }
      args.ref.nOptions = count;
      args.ref.ignoreUnrecognized = ignoreUnrecognized ? 1 : 0;
    }
    args.ref.version = version;
    return args;
  }

  static void _freeVMArgs(Pointer<JavaVMInitArgs> argPtr) {
    if (argPtr.ref.nOptions != 0) {
      calloc.free(argPtr.ref.options);
    }
    calloc.free(argPtr);
  }

  /// Returns pointer to current JNI JavaVM instance
  Pointer<JavaVM> getJavaVM() {
    return _bindings.GetJavaVM();
  }

  /// Returns JniEnv associated with current thread.
  ///
  /// Do not reuse JniEnv between threads, it's only valid
  /// in the thread it is obtained.
  Pointer<JniEnv> getEnv() {
    return _bindings.GetJniEnv();
  }

  void setJniLogging(int loggingLevel) {
    _bindings.SetJNILogging(loggingLevel);
  }

  /// Returns current application context
  JObject getCachedApplicationContext() {
    return _bindings.GetApplicationContext();
  }

  JObject getApplicationClassLoader() {
    return _bindings.GetClassLoader();
  }

  /// example fn using JNI
  String toJavaString(int n) {
    final jniEnv = getEnv();
    final cls = jniEnv.FindClass("java/lang/String".toNativeChars());
    jniEnv.ExceptionDescribe();
    final mId = jniEnv.GetStaticMethodID(cls, "valueOf".toNativeChars(),
        "(I)Ljava/lang/String;".toNativeChars());
	final i = jvalues([n]);
    final res = jniEnv.CallStaticObjectMethodA(cls, mId, i);
	calloc.free(i);
    final resChars =
        jniEnv.GetStringUTFChars(res, nullptr).cast<Utf8>().toDartString();
    return resChars;
  }

  /// Returns class for [qualifiedName] found by platform-specific mechanism.
  JniClass findClass(String qualifiedName) {
    final cls = _bindings.LoadClass(qualifiedName.toNativeChars());
    return JniClass._(cls);
  }

  Pointer<jvalue> jvalues(List<dynamic> args, {Allocator allocator = calloc}) {
    Pointer<jvalue> result = allocator<jvalue>(args.length);
    for (int i = 0; i < args.length; i++) {
      final arg = args[i];
      final pos = result.elementAt(i);
      switch (arg.runtimeType) {
        case int:
          pos.ref.i = arg;
          break;
        case bool:
          pos.ref.z = arg ? 1 : 0;
          break;
        case Pointer<Void>:
          pos.ref.l = arg;
          break;
        case double:
          pos.ref.d = arg;
          break;
        default:
          throw "cannot convert ${arg.runtimeType} to jvalue";
      }
    }
    return result;
  }
}

// Wrapper types for easy use
// and less Pointer<Pointer<Void>> in type signatures

class JniObject {
  final JObject pointer;
  JniObject._(this.pointer);
}

class JniClass extends JniObject {
  JniClass._(JClass pointer) : super._(pointer);
  // Call methods
  // Call constructors
}

// JValueAllocator(allocator)
//      jInt(value)
//      jByte(value)
//      jObject(Pointer<Void>)
//      etc..
