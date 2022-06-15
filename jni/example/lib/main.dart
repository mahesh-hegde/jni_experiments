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
  final mId = jniEnv.GetStaticMethodID(
      cls, "valueOf".toNativeChars(), "(I)Ljava/lang/String;".toNativeChars());
  final i = calloc<JValue>();
  i.ref.i = n;
  final res = jniEnv.CallStaticObjectMethodA(cls, mId, i);
  final resChars =
      jniEnv.GetStringUTFChars(res, nullptr).cast<Utf8>().toDartString();
  return resChars;
}

void main() {
  jni = Platform.isAndroid ? Jni.getInstance() : Jni.spawn();
  final examples = [
    ["Locally defined toJavaString(1332)", () => localToJavaString(1332)],
    ["JNI library's example", () => jni.toJavaString(720)],
  ];
  runApp(MyApp(examples));
}

class MyApp extends StatefulWidget {
  const MyApp(this.examples, {Key? key}) : super(key: key);
  final List<List<dynamic>> examples;

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('JNI Examples'),
        ),
        body: ListView.builder(
            itemCount: widget.examples.length,
            itemBuilder: (context, i) {
              final eg = widget.examples[i];
              return ExampleCard(eg[0] as String, eg[1] as dynamic Function());
            }),
      ),
    );
  }
}

class ExampleCard extends StatefulWidget {
  const ExampleCard(this.title, this.callback, {Key? key}) : super(key: key);

  final String title;
  final dynamic Function() callback;

  @override
  _ExampleCardState createState() => _ExampleCardState();
}

class _ExampleCardState extends State<ExampleCard> {
  Widget _pad(Widget w, double h, double v) {
    return Padding(
        padding: EdgeInsets.symmetric(horizontal: h, vertical: v), child: w);
  }

  @override
  Widget build(BuildContext context) {
    var result = widget.callback();
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.title,
            softWrap: true,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        _pad(Text(result.toString(),
            softWrap: true, style: const TextStyle(fontFamily: "Monospace")), 8, 16),
        _pad(ElevatedButton(
          child: const Text("Run again"),
          onPressed: () => setState(() {}),
        ), 8, 8),
      ]),
    );
  }
}
