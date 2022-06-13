import 'package:flutter/material.dart';

import 'dart:io';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:jni/jni.dart';

late Jni jni;

String localToJavaString(int n) {
	final jniEnv = jni.getEnv();
    final cls = jniEnv.FindClass("java/lang/String".toNativeChars());
    jniEnv.ExceptionDescribe();
    final mId = jniEnv.GetStaticMethodID(cls, "valueOf".toNativeChars(),
        "(I)Ljava/lang/String;".toNativeChars());
    final i = calloc<jvalue>();
    i.ref.i = n;
    final res = jniEnv.CallStaticObjectMethodA(cls, mId, i);
    final resChars =
        jniEnv.GetStringUTFChars(res, nullptr).cast<Utf8>().toDartString();
    return resChars;
}

void main() {
  jni = Platform.isAndroid ? Jni.getInstance() 
		  : Jni.spawn();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late String _stringFromJni;

  @override
  void initState() {
    super.initState();
    _stringFromJni = localToJavaString(1450);
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 25);
    const spacerSmall = SizedBox(height: 10);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Native Packages'),
        ),
        body: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                const Text(
                  'This calls a native function through FFI that is shipped as source in the package. '
                  'The native code is built as part of the Flutter Runner build.',
                  style: textStyle,
                  textAlign: TextAlign.center,
                ),
                spacerSmall,
                Text(
                  '"$_stringFromJni"',
                  style: textStyle,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
