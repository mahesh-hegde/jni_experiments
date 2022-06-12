import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'jni_bindings_generated.dart';
import 'extensions.dart';

final _helperNullError = Exception("Helpers library is not loaded!");
final _helperPathNeededError = Exception(
    "JNI Helpers are not loaded! Please provide a helpersLibraryPath argument.");

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

late JniBindings _bindings;

DynamicLibrary? _dylib = () {
  final libPath =
      Platform.environment["DART_JNI_LIB"] ?? _getLibraryFilename("dartjni");
  try {
    final library = DynamicLibrary.open(libPath);
	_bindings = JniBindings(library);
	return library;
  } on Exception catch (_) {
    return null;
  }
}();

@pragma('vm:prefer-inline')
void _confirmHelpersLoaded() {
	if (_dylib == null) {
		throw _helperNullError;
	}
}

/// Returns pointer to current JNI JavaVM instance
Pointer<JavaVM> getJavaVM() {
	_confirmHelpersLoaded();
	return _bindings.GetJavaVM();
}

/// Returns a JNIEnv, it's valid only in current thread.
/// Do not reuse a JNIEnv between callbacks that may be scheduled on different threads.
/// Get a new JniEnv instead in such cases.
Pointer<JniEnv> getJniEnv() {
  _confirmHelpersLoaded();
  final env = _bindings.GetJniEnv();
  if (env == nullptr) {
    throw Exception(
        "GetJNIEnv() returned null! Ensure a JVM is spawned in non-android code.");
  }
  return env;
}

JClass findClass(String name) {
	_confirmHelpersLoaded();
	return _bindings.LoadClass(name.toNativeChars());
}

void setJniLogging(int loggingLevel) {
	_confirmHelpersLoaded();
	_bindings.SetJNILogging(loggingLevel);
}

/// Returns current application context
JObject getCachedApplicationContext() {
	_confirmHelpersLoaded();
	return _bindings.GetApplicationContext();
}

JObject getApplicationClassLoader() {
	_confirmHelpersLoaded();
	return _bindings.GetClassLoader();
}

/// Returns if helpers library is loaded
bool isHelpersLibraryLoaded() {
  return _dylib != null;
}

/// Spawns a JVM on non-android platforms for use by JNI.
///
/// If [helpersLibraryPath] is provided, it's used to load dartjni helper library.
/// On flutter, the framework takes care of library loading. But this can be helpful
/// on dart standalone target.
///
/// [options], [ignoreUnrecognized] and [version] are passed to JVM
/// if [classPath] is non-empty, it will be used to derive an additonal option
/// of the form -Djava.class.path=paths
///
/// TODO: Examples
///
/// Footnote: Options for dart standalone, other than passing helper library path
/// are either placing libdartjni.so in same folder as compiled executable,
/// or when running with `dart run`, setting LD_LIBRARY_PATH.
Pointer<JniEnv> spawnJvm({
  String? helpersLibraryPath,
  List<String> options = const [],
  List<String> classPath = const [],
  bool ignoreUnrecognized = false,
  int version = JNI_VERSION_1_6,
}) {
  if (helpersLibraryPath != null) {
    final dylib = DynamicLibrary.open(helpersLibraryPath);
    _dylib = dylib;
	_bindings = JniBindings(dylib);
  }

  Pointer<JavaVMInitArgs> jInitArgs = _JavaVMUtils.createJavaVMInitArgs(
      options: options,
      classPath: classPath,
      ignoreUnrecognized: ignoreUnrecognized,
      version: version);
  if (_dylib == null) {
    throw _helperPathNeededError;
  }
  final res = _bindings.SpawnJvm(jInitArgs);
  _JavaVMUtils.freeJavaVMInitArgs(jInitArgs);
  return res;
}

/// example fn using JNI
String toJavaString(int n) {
  final jniEnv = getJniEnv();
  final cls =
      jniEnv.FindClass("java/lang/String".toNativeChars());
  jniEnv.ExceptionDescribe();
  final mId = jniEnv.GetStaticMethodID(
      cls, "valueOf".toNativeChars(), "(I)Ljava/lang/String;".toNativeChars());
  final i = calloc<jvalue>();
  i.ref.i = n;
  final res = jniEnv.CallStaticObjectMethodA(cls, mId, i);
  final resChars = jniEnv.GetStringUTFChars(res, nullptr)
      .cast<Utf8>()
      .toDartString();
  return resChars;
}

class _JavaVMUtils {
  static Pointer<JavaVMInitArgs> createJavaVMInitArgs({
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

  static void freeJavaVMInitArgs(Pointer<JavaVMInitArgs> argPtr) {
    if (argPtr.ref.nOptions != 0) {
      calloc.free(argPtr.ref.options);
    }
    calloc.free(argPtr);
  }
}

