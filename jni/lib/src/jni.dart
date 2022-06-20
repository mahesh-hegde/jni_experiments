import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart';

import 'jni_bindings_generated.dart';
import 'extensions.dart';

part 'jniclass_methods_generated.dart';
part 'jniobject_methods_generated.dart';
part 'direct_methods_generated.dart';

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
  ///
  /// On Dart standalone, when calling for the first time from
  /// a new isolate, make sure to pass the library path.
  static Jni getInstance() {
    // TODO: Throw appropriate error on standalone target.
    // if helpers aren't loaded using spawn() or load().

    // TODO: There may be still some edge cases not handled here.
    if (_instance == null) {
      final inst = Jni._(JniBindings(_loadJniHelpersLibrary()));
      if (inst.getJavaVM() == nullptr) {
        throw Exception("Fatal: No JVM associated with this process!"
            " Did you call Jni.spawn?");
      }
      // If no error, save this singleton.
      _instance = inst;
    }
    return _instance!;
  }

  /// Initialize instance from custom helper library path.
  ///
  /// On dart standalone, call this in new isolate before
  /// doing getInstance().
  ///
  /// (The reason is that dylibs need to be loaded in every isolate.
  /// On flutter it's done by library. On dart standalone we don't
  /// know the library path.)
  static void load({required String helperDir}) {
    if (_instance != null) {
      throw Exception('Fatal: a JNI instance already exists in this isolate');
    }
    final inst = Jni._(JniBindings(_loadJniHelpersLibrary(dir: helperDir)));
    if (inst.getJavaVM() == nullptr) {
      throw Exception("Fatal: No JVM associated with this process");
    }
    _instance = inst;
  }

  /// Spawn an instance of JVM using JNI.
  /// This instance will be returned by future calls to [getInstance]
  ///
  /// [helperDir] is path of the directory where the wrapper library is found.
  /// This parameter needs to be passed manually on __Dart standalone target__,
  /// since we have no reliable way to bundle it with the package.
  ///
  /// [jvmOptions], [ignoreUnrecognized], and [jniVersion] are passed to the JVM.
  /// Strings in [classPath], if any, are used to construct an additional
  /// JVM option of the form "-Djava.class.path={paths}".
  static Jni spawn({
    String? helperDir,
    int logLevel = JniLogLevel.JNI_INFO,
    List<String> jvmOptions = const [],
    List<String> classPath = const [],
    bool ignoreUnrecognized = false,
    int jniVersion = JNI_VERSION_1_6,
  }) {
    if (_instance != null) {
      throw Exception("Currently only 1 VM is supported.");
    }
    final dylib = _loadJniHelpersLibrary(dir: helperDir);
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
    final env = getEnv();
    env.checkException();
    calloc.free(nameChars);
    return JniClass._(env, cls);
  }

  /// Constructs an instance of class with given args.
  ///
  /// Use it when you only need one instance, but not the actual class
  /// nor any constructor / static methods.
  JniObject newInstance(
      String qualifiedName, String ctorSignature, List<dynamic> args) {
    final nameChars = qualifiedName.toNativeChars();
    final sigChars = ctorSignature.toNativeChars();
    final env = getEnv();
    final cls = _bindings.LoadClass(nameChars);
    final ctor = env.GetMethodID(cls, _initMethodName, sigChars);
    final obj = env.NewObjectA(cls, ctor, Jni.jvalues(args));
    calloc.free(nameChars);
    calloc.free(sigChars);
    return JniObject._(env, obj, cls);
  }

  static void _jvalueFill(Pointer<JValue> pos, dynamic arg) {
    // switch on runtimeType is not guaranteed to work?
    switch (arg.runtimeType) {
      case int:
        pos.ref.i = arg;
        break;
      case bool:
        pos.ref.z = arg ? 1 : 0;
        break;
      case Pointer<Void>:
      case Pointer<Never>:
        pos.ref.l = arg;
        break;
      case double:
        pos.ref.d = arg;
        break;
      case JValueLong:
        pos.ref.j = (arg as JValueLong).value;
        break;
      case JValueShort:
        pos.ref.s = (arg as JValueShort).value;
        break;
      case JValueChar:
        pos.ref.c = (arg as JValueChar).value;
        break;
      case JValueByte:
        pos.ref.b = (arg as JValueByte).value;
        break;
      default:
        throw "cannot convert ${arg.runtimeType} to jvalue";
    }
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
      _jvalueFill(pos, arg);
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
/// It should be distroyed with [delete] method after done.
///
/// It's valid only in the thread it was created.
/// When passing to code that might run in a different thread (eg: a callback),
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
  JniObject.fromGlobalRef(Pointer<JniEnv> env, JniGlobalObjectRef r)
      : _env = env,
        _obj = env.NewLocalRef(r._obj),
        _cls = env.NewLocalRef(r._cls);

  /// Delete the local reference contained by this object.
  ///
  /// Do not use a JniObject after calling [delete].
  void delete() {
    _env.DeleteLocalRef(_obj);
    if (_cls != nullptr) {
      _env.DeleteLocalRef(_cls);
    }
  }

  JObject get jobject => _obj;
  JObject get jclass => _cls;

  /// Get a JniClass of this object's class.
  JniClass getClass() {
    if (_cls == nullptr) {
      return JniClass._(_env, _env.GetObjectClass(_obj));
    }
    return JniClass._(_env, _env.NewLocalRef(_cls));
  }

  /// if the underlying JObject is string
  /// converts it to string representation.
  String asDartString() {
    return _env.asDartString(_obj);
  }

  /// Returns method id for [name] on this object.
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

  /// Returns field id for [name] on this object.
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

  /// Get a global reference.
  ///
  /// This is useful for passing a JniObject between threads.
  JniGlobalObjectRef getGlobalRef() {
    return JniGlobalObjectRef._(
      _env.NewGlobalRef(_obj),
      _env.NewGlobalRef(_cls),
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

  JniClass.fromGlobalRef(Pointer<JniEnv> env, JniGlobalClassRef r)
      : _env = env,
        _cls = env.NewLocalRef(r._cls);

  JMethodID getConstructorID(String signature) {
    final methodSig = signature.toNativeChars();
    final methodID = _env.GetMethodID(_cls, _initMethodName, methodSig);
    _env.checkException();
    calloc.free(methodSig);
    return methodID;
  }

  /// Construct new object using [ctor].
  JniObject newObject(JMethodID ctor, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final newObj = _env.NewObjectA(_cls, ctor, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return JniObject._(_env, newObj, nullptr);
  }

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

  JClass get jclass => _cls;

  JniGlobalClassRef getGlobalRef() =>
      JniGlobalClassRef._(_env.NewGlobalRef(_cls));
  void delete() {
    _env.DeleteLocalRef(_cls);
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
class JniGlobalObjectRef {
  final JObject _obj;
  final JClass _cls;
  JniGlobalObjectRef._(this._obj, this._cls);

  JObject get jobject => _obj;
  JObject get jclass => _cls;

  void delete(Pointer<JniEnv> env) {
    env.DeleteGlobalRef(_obj);
    env.DeleteGlobalRef(_cls);
  }
}

class JniGlobalClassRef {
  JniGlobalClassRef._(this._cls);
  final JClass _cls;
  JClass get jclass => _cls;

  void delete(Pointer<JniEnv> env) {
    env.DeleteGlobalRef(_cls);
  }
}

// TODO: Any better way to allocate this?
final _initMethodName = "<init>".toNativeChars();

