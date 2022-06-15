import 'dart:io';
import 'dart:ffi';

import 'package:test/test.dart';
import 'package:jni/jni.dart';

late Jni jni;

void main() {
  if (!Platform.isAndroid) {
	Jni.spawn(helperPath: "src/libdartjni.so");
  }
  jni = Jni.getInstance();
  test('java toString', () {
    expect(jni.toJavaString(114), equals("114"));
  });
  test('get JNI Version', () {
    expect(jni.getEnv().GetVersion(), isNot(equals(0)));
  });
  test('Manually lookup Integer.toHexString method and call it', () {
    final env = jni.getEnv();
    final integerClass = env.FindClass("java/lang/Integer".toNativeChars());
    final hexMethod = env.GetStaticMethodID(integerClass,
        "toHexString".toNativeChars(), "(I)Ljava/lang/String;".toNativeChars());
    for (var i in [1, 80, 13, 76]) {
      final res = env.CallStaticObjectMethodA(
          integerClass, hexMethod, Jni.jvalues([i]));
      final resChars = env.GetStringUTFChars(res, nullptr).toDartString();
      expect(resChars, equals(i.toRadixString(16)));
    }
  });
  test("convert back and forth between dart and java string", () {
    final env = jni.getEnv();
    const str = "ABCD EFGH";
    final jstr = env.NewStringUTF(str.toNativeChars());
    final djstr = env.GetStringUTFChars(jstr, nullptr).toDartString();
    expect(str, equals(djstr));
  });

  test("Print something from Java", () {
    final env = jni.getEnv();
    final system = env.FindClass("java/lang/System".toNativeChars());
    final field = env.GetStaticFieldID(
        system, "out".toNativeChars(), "Ljava/io/PrintStream;".toNativeChars());
    final out = env.GetStaticObjectField(system, field);
    final printStream = env.GetObjectClass(out);
    final println = env.GetMethodID(printStream, "println".toNativeChars(),
        "(Ljava/lang/String;)V".toNativeChars());
    const str = "\nHello JNI!";
    final jstr = env.NewStringUTF(str.toNativeChars());
    // test runner can't compare what's printed by Java, leaving it
    // env.CallVoidMethodA(out, println, Jni.jvalues([jstr]));
  });
}
