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

extension JniObjectCallStringMethod on JniObject {
	/// Call a method that returns a string result
	///
	/// Similar to [JniObjectCallMethods.callObjectMethod] but auto-converts result to string
	/// and deletes the reference to JObject.
	String callStringMethod(JMethodID methodID, List<dynamic> args) {
		final jvArgs = Jni.jvalues(args);
		final ret = _env.CallObjectMethodA(_obj, methodID, jvArgs);
		_env.checkException();
		calloc.free(jvArgs);
		final result = _env.asDartString(ret);
		_env.DeleteLocalRef(ret);
		return result;
	}

	/// Lookup method and call it using [callStringMethod].
	String callStringMethodByName(String name, String signature, List<dynamic> args) {
		final mID = getMethodID(name, signature);
		final result = callStringMethod(mID, args);
		return result;
	}
}

extension JniClassCallStringMethod on JniClass {
	/// Call a method that returns a string result
	///
	/// Similar to [JniClassCallMethods.callStaticObjectMethod] but auto-converts result to string
	/// and deletes the reference to JObject.
	String callStaticStringMethod(JMethodID methodID, List<dynamic> args) {
		final jvArgs = Jni.jvalues(args);
		final ret = _env.CallStaticObjectMethodA(_cls, methodID, jvArgs);
		// TODO: Duplicated code
		calloc.free(jvArgs);
		final result = _env.asDartString(ret);
		_env.DeleteLocalRef(ret);
		return result;
	}

	/// Lookup method and call it using [callStaticStringMethod].
	String callStaticStringMethodByName(String name, String signature, List<dynamic> args) {
		final mID = getStaticMethodID(name, signature);
		final result = callStaticStringMethod(mID, args);
		return result;
	}
}

// AUTO GENERATED DO NOT EDIT
// DELETE NEXT PART AND RE RUN GENERATOR AFTER CHANGING TEMPLATE

extension JniObjectCallMethods on JniObject {
  /// Calls method pointed to by [methodID] with [args] as arguments
  JniObject callObjectMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallObjectMethodA(_obj, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return JniObject._(_env, result, nullptr);
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getMethodID]
  /// and [callObjectMethod].
  JniObject callObjectMethodByName(
      String name, String signature, List<dynamic> args) {
    final mID = getMethodID(name, signature);
    final result = callObjectMethod(mID, args);
    return result;
  }

  /// Retrieves the value of the field denoted by [fieldID]
  JniObject getObjectField(JFieldID fieldID) {
    final result = _env.GetObjectField(_obj, fieldID);
    _env.checkException();
    return JniObject._(_env, result, nullptr);
  }

  /// Retrieve field of given [name] and [signature]
  JniObject getObjectFieldByName(String name, String signature) {
    final fID = getFieldID(name, signature);
    final result = getObjectField(fID);
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

  /// Retrieves the value of the field denoted by [fieldID]
  bool getBooleanField(JFieldID fieldID) {
    final result = _env.GetBooleanField(_obj, fieldID);
    _env.checkException();
    return result != 0;
  }

  /// Retrieve field of given [name] and [signature]
  bool getBooleanFieldByName(String name, String signature) {
    final fID = getFieldID(name, signature);
    final result = getBooleanField(fID);
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

  /// Retrieves the value of the field denoted by [fieldID]
  int getByteField(JFieldID fieldID) {
    final result = _env.GetByteField(_obj, fieldID);
    _env.checkException();
    return result;
  }

  /// Retrieve field of given [name] and [signature]
  int getByteFieldByName(String name, String signature) {
    final fID = getFieldID(name, signature);
    final result = getByteField(fID);
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

  /// Retrieves the value of the field denoted by [fieldID]
  int getCharField(JFieldID fieldID) {
    final result = _env.GetCharField(_obj, fieldID);
    _env.checkException();
    return result;
  }

  /// Retrieve field of given [name] and [signature]
  int getCharFieldByName(String name, String signature) {
    final fID = getFieldID(name, signature);
    final result = getCharField(fID);
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

  /// Retrieves the value of the field denoted by [fieldID]
  int getShortField(JFieldID fieldID) {
    final result = _env.GetShortField(_obj, fieldID);
    _env.checkException();
    return result;
  }

  /// Retrieve field of given [name] and [signature]
  int getShortFieldByName(String name, String signature) {
    final fID = getFieldID(name, signature);
    final result = getShortField(fID);
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

  /// Retrieves the value of the field denoted by [fieldID]
  int getIntField(JFieldID fieldID) {
    final result = _env.GetIntField(_obj, fieldID);
    _env.checkException();
    return result;
  }

  /// Retrieve field of given [name] and [signature]
  int getIntFieldByName(String name, String signature) {
    final fID = getFieldID(name, signature);
    final result = getIntField(fID);
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

  /// Retrieves the value of the field denoted by [fieldID]
  int getLongField(JFieldID fieldID) {
    final result = _env.GetLongField(_obj, fieldID);
    _env.checkException();
    return result;
  }

  /// Retrieve field of given [name] and [signature]
  int getLongFieldByName(String name, String signature) {
    final fID = getFieldID(name, signature);
    final result = getLongField(fID);
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

  /// Retrieves the value of the field denoted by [fieldID]
  double getFloatField(JFieldID fieldID) {
    final result = _env.GetFloatField(_obj, fieldID);
    _env.checkException();
    return result;
  }

  /// Retrieve field of given [name] and [signature]
  double getFloatFieldByName(String name, String signature) {
    final fID = getFieldID(name, signature);
    final result = getFloatField(fID);
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

  /// Retrieves the value of the field denoted by [fieldID]
  double getDoubleField(JFieldID fieldID) {
    final result = _env.GetDoubleField(_obj, fieldID);
    _env.checkException();
    return result;
  }

  /// Retrieve field of given [name] and [signature]
  double getDoubleFieldByName(String name, String signature) {
    final fID = getFieldID(name, signature);
    final result = getDoubleField(fID);
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
}

extension JniClassCallMethods on JniClass {
  /// Calls method pointed to by [methodID] with [args] as arguments
  JniObject callStaticObjectMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallStaticObjectMethodA(_cls, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return JniObject._(_env, result, nullptr);
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getStaticMethodID]
  /// and [callStaticObjectMethod].
  JniObject callStaticObjectMethodByName(
      String name, String signature, List<dynamic> args) {
    final mID = getStaticMethodID(name, signature);
    final result = callStaticObjectMethod(mID, args);
    return result;
  }

  /// Retrieves the value of the field denoted by [fieldID]
  JniObject getStaticObjectField(JFieldID fieldID) {
    final result = _env.GetStaticObjectField(_cls, fieldID);
    _env.checkException();
    return JniObject._(_env, result, nullptr);
  }

  /// Retrieve field of given [name] and [signature]
  JniObject getObjectFieldByName(String name, String signature) {
    final fID = getStaticFieldID(name, signature);
    final result = getStaticObjectField(fID);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  bool callStaticBooleanMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallStaticBooleanMethodA(_cls, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result != 0;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getStaticMethodID]
  /// and [callStaticBooleanMethod].
  bool callStaticBooleanMethodByName(
      String name, String signature, List<dynamic> args) {
    final mID = getStaticMethodID(name, signature);
    final result = callStaticBooleanMethod(mID, args);
    return result;
  }

  /// Retrieves the value of the field denoted by [fieldID]
  bool getStaticBooleanField(JFieldID fieldID) {
    final result = _env.GetStaticBooleanField(_cls, fieldID);
    _env.checkException();
    return result != 0;
  }

  /// Retrieve field of given [name] and [signature]
  bool getBooleanFieldByName(String name, String signature) {
    final fID = getStaticFieldID(name, signature);
    final result = getStaticBooleanField(fID);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  int callStaticByteMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallStaticByteMethodA(_cls, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getStaticMethodID]
  /// and [callStaticByteMethod].
  int callStaticByteMethodByName(
      String name, String signature, List<dynamic> args) {
    final mID = getStaticMethodID(name, signature);
    final result = callStaticByteMethod(mID, args);
    return result;
  }

  /// Retrieves the value of the field denoted by [fieldID]
  int getStaticByteField(JFieldID fieldID) {
    final result = _env.GetStaticByteField(_cls, fieldID);
    _env.checkException();
    return result;
  }

  /// Retrieve field of given [name] and [signature]
  int getByteFieldByName(String name, String signature) {
    final fID = getStaticFieldID(name, signature);
    final result = getStaticByteField(fID);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  int callStaticCharMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallStaticCharMethodA(_cls, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getStaticMethodID]
  /// and [callStaticCharMethod].
  int callStaticCharMethodByName(
      String name, String signature, List<dynamic> args) {
    final mID = getStaticMethodID(name, signature);
    final result = callStaticCharMethod(mID, args);
    return result;
  }

  /// Retrieves the value of the field denoted by [fieldID]
  int getStaticCharField(JFieldID fieldID) {
    final result = _env.GetStaticCharField(_cls, fieldID);
    _env.checkException();
    return result;
  }

  /// Retrieve field of given [name] and [signature]
  int getCharFieldByName(String name, String signature) {
    final fID = getStaticFieldID(name, signature);
    final result = getStaticCharField(fID);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  int callStaticShortMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallStaticShortMethodA(_cls, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getStaticMethodID]
  /// and [callStaticShortMethod].
  int callStaticShortMethodByName(
      String name, String signature, List<dynamic> args) {
    final mID = getStaticMethodID(name, signature);
    final result = callStaticShortMethod(mID, args);
    return result;
  }

  /// Retrieves the value of the field denoted by [fieldID]
  int getStaticShortField(JFieldID fieldID) {
    final result = _env.GetStaticShortField(_cls, fieldID);
    _env.checkException();
    return result;
  }

  /// Retrieve field of given [name] and [signature]
  int getShortFieldByName(String name, String signature) {
    final fID = getStaticFieldID(name, signature);
    final result = getStaticShortField(fID);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  int callStaticIntMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallStaticIntMethodA(_cls, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getStaticMethodID]
  /// and [callStaticIntMethod].
  int callStaticIntMethodByName(
      String name, String signature, List<dynamic> args) {
    final mID = getStaticMethodID(name, signature);
    final result = callStaticIntMethod(mID, args);
    return result;
  }

  /// Retrieves the value of the field denoted by [fieldID]
  int getStaticIntField(JFieldID fieldID) {
    final result = _env.GetStaticIntField(_cls, fieldID);
    _env.checkException();
    return result;
  }

  /// Retrieve field of given [name] and [signature]
  int getIntFieldByName(String name, String signature) {
    final fID = getStaticFieldID(name, signature);
    final result = getStaticIntField(fID);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  int callStaticLongMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallStaticLongMethodA(_cls, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getStaticMethodID]
  /// and [callStaticLongMethod].
  int callStaticLongMethodByName(
      String name, String signature, List<dynamic> args) {
    final mID = getStaticMethodID(name, signature);
    final result = callStaticLongMethod(mID, args);
    return result;
  }

  /// Retrieves the value of the field denoted by [fieldID]
  int getStaticLongField(JFieldID fieldID) {
    final result = _env.GetStaticLongField(_cls, fieldID);
    _env.checkException();
    return result;
  }

  /// Retrieve field of given [name] and [signature]
  int getLongFieldByName(String name, String signature) {
    final fID = getStaticFieldID(name, signature);
    final result = getStaticLongField(fID);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  double callStaticFloatMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallStaticFloatMethodA(_cls, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getStaticMethodID]
  /// and [callStaticFloatMethod].
  double callStaticFloatMethodByName(
      String name, String signature, List<dynamic> args) {
    final mID = getStaticMethodID(name, signature);
    final result = callStaticFloatMethod(mID, args);
    return result;
  }

  /// Retrieves the value of the field denoted by [fieldID]
  double getStaticFloatField(JFieldID fieldID) {
    final result = _env.GetStaticFloatField(_cls, fieldID);
    _env.checkException();
    return result;
  }

  /// Retrieve field of given [name] and [signature]
  double getFloatFieldByName(String name, String signature) {
    final fID = getStaticFieldID(name, signature);
    final result = getStaticFloatField(fID);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  double callStaticDoubleMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallStaticDoubleMethodA(_cls, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getStaticMethodID]
  /// and [callStaticDoubleMethod].
  double callStaticDoubleMethodByName(
      String name, String signature, List<dynamic> args) {
    final mID = getStaticMethodID(name, signature);
    final result = callStaticDoubleMethod(mID, args);
    return result;
  }

  /// Retrieves the value of the field denoted by [fieldID]
  double getStaticDoubleField(JFieldID fieldID) {
    final result = _env.GetStaticDoubleField(_cls, fieldID);
    _env.checkException();
    return result;
  }

  /// Retrieve field of given [name] and [signature]
  double getDoubleFieldByName(String name, String signature) {
    final fID = getStaticFieldID(name, signature);
    final result = getStaticDoubleField(fID);
    return result;
  }

  /// Calls method pointed to by [methodID] with [args] as arguments
  void callStaticVoidMethod(JMethodID methodID, List<dynamic> args) {
    final jvArgs = Jni.jvalues(args);
    final result = _env.CallStaticVoidMethodA(_cls, methodID, jvArgs);
    _env.checkException();
    calloc.free(jvArgs);
    return result;
  }

  /// Looks up method with [name] and [signature], calls it with [args] as arguments.
  /// If calling the same method multiple times, consider using [getStaticMethodID]
  /// and [callStaticVoidMethod].
  void callStaticVoidMethodByName(
      String name, String signature, List<dynamic> args) {
    final mID = getStaticMethodID(name, signature);
    final result = callStaticVoidMethod(mID, args);
    return result;
  }
}
