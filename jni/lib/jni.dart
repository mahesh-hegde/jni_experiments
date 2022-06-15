// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Package jni provides dart bindings for the Java Native Interface (JNI) on android and desktop platforms.
///
/// It's intended as a supplement to the (planned) jnigen tool, a Java wrapper generator using JNI.
/// The goal is to provide sufficiently complete and ergonomic access to underlying JNI APIs.
/// Therefore, some understanding of JNI is required to use this module.
///
/// __Java VM:__
/// On Android, the existing JVM is used, a new JVM needs to be spawned on flutter desktop platforms.
///
/// ```dart
/// if (!Platform.isAndroid) {
///   // Spin up a JVM instance with custom classpath etc..
///   Jni.spawn(/* options */);
/// }
/// Jni jni = Jni.getInstance();
/// ```
///
/// __Dart standalone support:__
/// This module depends on a shared library written in C, when using dart standalone, it's
/// your responsibility to:
///
///    * Build the library `libdartjni.so`
///    * Bundle it appropriately with dart application
///    * Pass the path to library as a parameter to `Jni.spawn()`
///
/// __JNIEnv:__
/// The types `JNIEnv` and `JavaVM` in JNI are available as `JniEnv` and `JavaVM`
/// respectively, with extension methods to conveniently invoke the function pointer
/// members. Therefore the calling syntax will be similar to JNI in C++. The first `JniEnv *` parameter is
/// implicit, a la C++.
///
/// ```dart
/// import 'package:jni/jni.dart'
///
/// final jni = Platform.isAndroid? Jni.getInstance() : Jni.spawn({options})
/// ```
///
/// On dart standalone target, we unfortunately have no mechanism to bundle the wrapper libraries
/// with the executable. Thus it needs to be explicitly placed in a accessable directory and provided
/// as an argument to Jni.spawn().
///
library jni;

export 'src/jni.dart' show Jni;
export 'src/extensions.dart' show StringMethodsForJNI, CharPtrMethodsForJNI;
export 'src/jni_bindings_generated.dart'; // currently just export all

