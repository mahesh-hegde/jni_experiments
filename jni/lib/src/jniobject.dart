import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'jni_bindings_generated.dart';
import 'extensions.dart';
import 'jniclass.dart';
import 'jvalues.dart';

part 'jniobject_methods_generated.dart';

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
  JniObject.of(this._env, this._obj, this._cls);

  JniObject.fromJObject(Pointer<JniEnv> env, JObject obj)
      : _env = env,
        _obj = obj,
        _cls = nullptr;

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

  /// Returns underlying [JObject] of this [JniObject].
  JObject get jobject => _obj;

  /// Returns underlying [JClass] of this [JniObject].
  JObject get jclass {
    if (_cls == nullptr) {
      _cls = _env.GetObjectClass(_obj);
    }
    return _cls;
  }

  /// Get a JniClass of this object's class.
  JniClass getClass() {
    if (_cls == nullptr) {
      return JniClass.of(_env, _env.GetObjectClass(_obj));
    }
    return JniClass.of(_env, _env.NewLocalRef(_cls));
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

  /// Use this [JniObject] to execute callback, then delete.
  ///
  /// Useful in expression chains.
  T use<T>(T Function(JniObject) callback) {
    var result = callback(this);
    delete();
    return result;
  }
}

/// High level wrapper to a JNI global reference.
/// which is safe to be passed through threads.
///
/// In a different thread, actual object can be reconstructed
/// using [JniObject.fromGlobalRef]
///
/// It should be explicitly deleted after done, using
/// [deleteIn] method, passing some env, eg: obtained using [Jni.getEnv].
class JniGlobalObjectRef {
  final JObject _obj;
  final JClass _cls;
  JniGlobalObjectRef._(this._obj, this._cls);

  JObject get jobject => _obj;
  JObject get jclass => _cls;

  void deleteIn(Pointer<JniEnv> env) {
    env.DeleteGlobalRef(_obj);
    env.DeleteGlobalRef(_cls);
  }
}
