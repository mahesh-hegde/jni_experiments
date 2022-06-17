import 'dart:io';
import 'dart:ffi';

import 'package:test/test.dart';
import 'package:ffi/ffi.dart';
import 'package:jni/jni.dart';

late Jni jni;

void main() {
  if (!Platform.isAndroid) {
    Jni.spawn(helperPath: "src/");
  }
  jni = Jni.getInstance();

  test('get JNI Version', () {
    expect(jni.getEnv().GetVersion(), isNot(equals(0)));
  });

  test('Manually lookup & call Integer.toHexString static method', () {
    final arena = Arena();
    final env = jni.getEnv();
    final integerClass =
        env.FindClass("java/lang/Integer".toNativeChars(arena));
    final hexMethod = env.GetStaticMethodID(
        integerClass,
        "toHexString".toNativeChars(arena),
        "(I)Ljava/lang/String;".toNativeChars(arena));
    for (var i in [1, 80, 13, 76]) {
      final res = env.CallStaticObjectMethodA(
          integerClass, hexMethod, Jni.jvalues([i], allocator: arena));
      final resChars = env.asDartString(res);
      expect(resChars, equals(i.toRadixString(16)));
      env.DeleteLocalRef(res);
    }
    env.DeleteLocalRef(integerClass);
    arena.releaseAll();
  });

  test("Test asJString", () {
    final env = jni.getEnv();
    const str = "QWERTY QWERTY";
    final jstr = env.asJString(str);
    expect(str, equals(env.asDartString(jstr)));
    env.DeleteLocalRef(jstr);
  });

  test("Convert back and forth between dart and java string", () {
    final arena = Arena();
    final env = jni.getEnv();
    const str = "ABCD EFGH";
    final jstr = env.NewStringUTF(str.toNativeChars(arena));
    final jchars = env.GetStringUTFChars(jstr, nullptr);
    final dstr = jchars.toDartString();
    env.ReleaseStringUTFChars(jstr, jchars);
    expect(str, equals(dstr));
    env.deleteAllLocalRefs([jstr]);
    arena.releaseAll();
  });

  test("Print something from Java", () {
    final arena = Arena();
    final env = jni.getEnv();
    final system = env.FindClass("java/lang/System".toNativeChars(arena));
    final field = env.GetStaticFieldID(system, "out".toNativeChars(arena),
        "Ljava/io/PrintStream;".toNativeChars(arena));
    final out = env.GetStaticObjectField(system, field);
    final printStream = env.GetObjectClass(out);
    final println = env.GetMethodID(printStream, "println".toNativeChars(arena),
        "(Ljava/lang/String;)V".toNativeChars(arena));
    const str = "\nHello JNI!";
    final jstr = env.asJString(str);
    // test runner can't compare what's printed by Java, leaving it
    // env.CallVoidMethodA(out, println, Jni.jvalues([jstr]));
    env.deleteAllLocalRefs([system, printStream, jstr]);
    arena.releaseAll();
  });
  test("Throw an exception", () {});

  test("Long.intValue() using JniObject", () {
    final longClass = jni.findClass("java/lang/Long");
    jni.getEnv().checkException();
    final longCtor = longClass.getConstructorID("(J)V");
    final long = longClass.newObject(longCtor, [176]);
    final intValue = long.callIntMethodByName("intValue", "()I", []);
    expect(intValue, equals(176));
    long.delete();
  });
}
