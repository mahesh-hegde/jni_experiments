import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart';

import 'jni_bindings_generated.dart';
import 'extensions.dart';

String _getLibraryFileName(String base) {
  if (Platform.isLinux || Platform.isAndroid) {
    return "lib$base.so";
  } else if (Platform.isWindows) {
    return "$base.dll";
  } else if (Platform.isMacOS) {
    return "lib$base.dylib";
  } else {
    throw Exception("cannot derive library name: unsupported platform");
  }
}

/// Load Dart-JNI Helper library.
///
/// If path is provided, it's used to load the library.
/// Else just the platform-specific filename is passed to DynamicLibrary.open
DynamicLibrary _loadJniHelpersLibrary(
    {String? dir, String baseName = "dartjni"}) {
  final fileName = _getLibraryFileName(baseName);
  final libPath = (dir != null) ? join(dir, fileName) : fileName;
  final dylib = DynamicLibrary.open(libPath);
  return dylib;
}

/// Jni represents a single running JNI instance.
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

  /// Returns the existing Jni object.
  ///
  /// If not running on Android and no Jni is spawned
  /// using Jni.spawn(), throws an exception.
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

  /// Spawn an instance of JVM using JNI.
  /// This instance will be returned by future calls to [getInstance]
  ///
  /// [helperPath] is path of the directory where the wrapper library is found.
  /// This parameter needs to be passed manually on __Dart standalone target__,
  /// since we have no reliable way to bundle it with the package.
  ///
  /// [jvmOptions], [ignoreUnrecognized], and [jniVersion] are passed to the JVM.
  /// Strings in [classPath], if any, are used to construct an additional
  /// JVM option of the form "-Djava.class.path={paths}".
  static Jni spawn({
    String? helperPath,
    int logLevel = JniLogLevel.JNI_INFO,
    List<String> jvmOptions = const [],
    List<String> classPath = const [],
    bool ignoreUnrecognized = false,
    int jniVersion = JNI_VERSION_1_6,
  }) {
    if (_instance != null) {
      throw Exception("Currently only 1 VM is supported.");
    }
    final dylib = _loadJniHelpersLibrary(dir: helperPath);
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
    }
    args.ref.ignoreUnrecognized = ignoreUnrecognized ? 1 : 0;
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

  /// Returns current application context on Android.
  JObject getCachedApplicationContext() {
    return _bindings.GetApplicationContext();
  }

  /// Get the initial classLoader of the application.
  ///
  /// This is especially useful on Android, where
  /// JNI threads cannot access application classes using
  /// the usual `JniEnv.FindClass` method.
  JObject getApplicationClassLoader() {
    return _bindings.GetClassLoader();
  }

  /// Returns class for [qualifiedName] found by platform-specific mechanism.
  ///
  /// TODO: Determine when to use class loader, and when FindClass
  JniClass findClass(String qualifiedName) {
    var nameChars = qualifiedName.toNativeChars();
    final cls = _bindings.LoadClass(nameChars);
    calloc.free(nameChars);
    return JniClass._(getEnv(), cls);
  }

  /// Converts passed arguments to JValue array
  /// for use in methods that take arguments.
  ///
  /// int, bool, double and JObject types are converted out of the box.
  /// wrap values in types such as [JValueLong]
  /// to convert to other primitive types instead.
  static Pointer<JValue> jvalues(List<dynamic> args,
      {Allocator allocator = calloc}) {
    Pointer<JValue> result = allocator<JValue>(args.length);
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
        case JValueLong:
          pos.ref.j = arg;
          break;
        case JValueShort:
          pos.ref.s = arg;
          break;
        case JValueChar:
          pos.ref.c = arg;
          break;
        case JValueByte:
          pos.ref.b = arg;
          break;
        default:
          throw "cannot convert ${arg.runtimeType} to jvalue";
      }
    }
    return result;
  }
}

/// Use this class as wrapper to convert an integer
/// to Java `long` in jvalues method.
class JValueLong {
  int value;
  JValueLong(this.value);
}

/// Use this class as wrapper to convert an integer
/// to Java `short` in jvalues method.
class JValueShort {
  int value;
  JValueShort(this.value);
}

/// Use this class as wrapper to convert an integer
/// to Java `byte` in jvalues method.
class JValueByte {
  int value;
  JValueByte(this.value);
}

/// Use this class as wrapper to convert an integer
/// to Java `byte` in jvalues method.
class JValueChar {
  int value;
  JValueChar(this.value);
  JValueChar.fromString(String s) : value = 0 {
    if (s.length != 1) {
      throw "Expected string of length 1";
    }
    value = s.codeUnitAt(0).toInt();
  }
}

/// JniObject is a convenience wrapper around a JNI local object reference.
///
/// It holds the object, its associated associated jniEnv etc..
/// It should be distroyed with [dispose] method after done.
///
/// It's valid only in the thread it was created.
/// When passing to code that might run in a different thread,
/// consider obtaining a global reference and reconstructing the object.
class JniObject {
  JClass _cls;
  final JObject _obj;
  final Pointer<JniEnv> _env;
  JniObject._(this._env, this._obj, this._cls);

  /// Reconstructs a JniObject from [r]
  ///
  /// [r] still needs to be explicitly deleted when
  /// it's no longer needed to construct any JniObjects.
  JniObject.fromGlobalRef(this._env, JniGlobalRef r)
      : _cls = _env.NewLocalRef(r._cls),
        _obj = _env.NewLocalRef(r._obj);

  /// Calls method pointed to by [methodID] with [args] as arguments
  JObject callObjectMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallObjectMethodA(_obj, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getMethodID]
  /// and [callObjectMethod].
  JObject callObjectMethodByName(
      String name, String signature, List<dynamic> args) {
    final mID = getMethodID(name, signature);
    final result = callObjectMethod(mID, args);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  bool callBooleanMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallBooleanMethodA(_obj, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result != 0;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getMethodID]
  /// and [callBooleanMethod].
  bool callBooleanMethodByName(
      String name, String signature, List<dynamic> args) {
    final mID = getMethodID(name, signature);
    final result = callBooleanMethod(mID, args);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  int callByteMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallByteMethodA(_obj, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getMethodID]
  /// and [callByteMethod].
  int callByteMethodByName(String name, String signature, List<dynamic> args) {
    final mID = getMethodID(name, signature);
    final result = callByteMethod(mID, args);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  int callCharMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallCharMethodA(_obj, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getMethodID]
  /// and [callCharMethod].
  int callCharMethodByName(String name, String signature, List<dynamic> args) {
    final mID = getMethodID(name, signature);
    final result = callCharMethod(mID, args);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  int callShortMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallShortMethodA(_obj, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getMethodID]
  /// and [callShortMethod].
  int callShortMethodByName(String name, String signature, List<dynamic> args) {
    final mID = getMethodID(name, signature);
    final result = callShortMethod(mID, args);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  int callIntMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallIntMethodA(_obj, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getMethodID]
  /// and [callIntMethod].
  int callIntMethodByName(String name, String signature, List<dynamic> args) {
    final mID = getMethodID(name, signature);
    final result = callIntMethod(mID, args);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  int callLongMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallLongMethodA(_obj, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getMethodID]
  /// and [callLongMethod].
  int callLongMethodByName(String name, String signature, List<dynamic> args) {
    final mID = getMethodID(name, signature);
    final result = callLongMethod(mID, args);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  double callFloatMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallFloatMethodA(_obj, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getMethodID]
  /// and [callFloatMethod].
  double callFloatMethodByName(
      String name, String signature, List<dynamic> args) {
    final mID = getMethodID(name, signature);
    final result = callFloatMethod(mID, args);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  double callDoubleMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallDoubleMethodA(_obj, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getMethodID]
  /// and [callDoubleMethod].
  double callDoubleMethodByName(
      String name, String signature, List<dynamic> args) {
    final mID = getMethodID(name, signature);
    final result = callDoubleMethod(mID, args);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  void callVoidMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallVoidMethodA(_obj, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getMethodID]
  /// and [callVoidMethod].
  void callVoidMethodByName(String name, String signature, List<dynamic> args) {
    final mID = getMethodID(name, signature);
    final result = callVoidMethod(mID, args);
    return result;
  }

  void delete() {
    _env.DeleteLocalRef(_obj);
    if (_cls != nullptr) {
      _env.DeleteLocalRef(_cls);
    }
  }

  JObject get object => _obj;

  JMethodID getMethodID(String name, String signature) {
    if (_cls == nullptr) {
      _cls = _env.GetObjectClass(_obj);
    }
    final methodName = name.toNativeChars();
    final methodSig = signature.toNativeChars();
    final result = _env.GetMethodID(_cls, methodName, methodSig);
    _env.checkException();
    calloc.free(methodName);
    calloc.free(methodSig);
    return result;
  }

  JFieldID getFieldID(String name, String signature) {
    if (_cls == nullptr) {
      _cls = _env.GetObjectClass(_obj);
    }
    final methodName = name.toNativeChars();
    final methodSig = signature.toNativeChars();
    final result = _env.GetFieldID(_cls, methodName, methodSig);
    _env.checkException();
    calloc.free(methodName);
    calloc.free(methodSig);
    return result;
  }

  JniGlobalRef getGlobalRef() {
    return JniGlobalRef._(
      _env.NewGlobalRef(_cls),
      _env.NewGlobalRef(_obj),
    );
  }
}

/// Convenience wrapper around a JNI local class reference.
///
/// Reference lifetime semantics are same as [JniObject].
class JniClass {
  final JClass _cls;
  final Pointer<JniEnv> _env;
  JniClass._(this._env, this._cls);

  JniClass.fromGlobalRef(Pointer<JniEnv> env, JniGlobalRef r)
      : _env = env,
        _cls = env.NewLocalRef(r._cls);

  JMethodID getConstructorID(String signature) {
    final methodSig = signature.toNativeChars();
    final methodID = _env.GetMethodID(_cls, _initMethodName, methodSig);
    _env.checkException();
    calloc.free(methodSig);
    return methodID;
  }

  JniObject newObject(JMethodID ctor, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final newObj = _env.NewObjectA(_cls, ctor, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return JniObject._(_env, newObj, nullptr);
  }

  // call static methods
  JMethodID _getMethodID(String name, String signature, bool isStatic) {
    final methodName = name.toNativeChars();
    final methodSig = signature.toNativeChars();
    final result = isStatic
        ? _env.GetStaticMethodID(_cls, methodName, methodSig)
        : _env.GetMethodID(_cls, methodName, methodSig);
    _env.checkException();
    calloc.free(methodName);
    calloc.free(methodSig);
    return result;
  }

  JFieldID _getFieldID(String name, String signature, bool isStatic) {
    final methodName = name.toNativeChars();
    final methodSig = signature.toNativeChars();
    final result = isStatic
        ? _env.GetStaticFieldID(_cls, methodName, methodSig)
        : _env.GetFieldID(_cls, methodName, methodSig);
    _env.checkException();
    calloc.free(methodName);
    calloc.free(methodSig);
    return result;
  }

  @pragma('vm:prefer-inline')
  JMethodID getMethodID(String name, String signature) {
    return _getMethodID(name, signature, false);
  }

  @pragma('vm:prefer-inline')
  JMethodID getStaticMethodID(String name, String signature) {
    return _getMethodID(name, signature, true);
  }

  @pragma('vm:prefer-inline')
  JFieldID getFieldID(String name, String signature) {
    return _getFieldID(name, signature, false);
  }

  @pragma('vm:prefer-inline')
  JFieldID getStaticFieldID(String name, String signature) {
    return _getFieldID(name, signature, true);
  }
}

/// Represents a JNI global reference
/// which is safe to be passed through threads.
///
/// In a different thread, actual object can be reconstructed
/// using [JniObject.fromGlobalRef] or [JniClass.fromGlobalRef]
///
/// It should be explicitly deleted after done, using
/// [delete(env)] method, passing some env, eg: obtained using [Jni.getEnv].
class JniGlobalRef {
  final JObject _obj;
  final JClass _cls;
  JniGlobalRef._(this._obj, this._cls);

  JObject get object => _obj;
}

final _initMethodName = "<init>".toNativeChars();
