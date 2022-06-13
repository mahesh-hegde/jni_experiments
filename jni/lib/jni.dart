// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Package jni provides dart bindings for JNI on android and desktop platforms.
/// 
/// On Android, the existing JVM is used, a new JVM needs to be spawned on desktop platforms.
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

