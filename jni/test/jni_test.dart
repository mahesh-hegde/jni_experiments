import 'dart:io';
import 'dart:ffi';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:ffi/ffi.dart';
import 'package:jni/jni.dart';

late Jni jni;

void main() {
  // Running on Android through flutter, this plugin
  // will bind to Android runtime's JVM.
  // On other platforms eg Flutter desktop or Dart standalone
  // You need to manually create a JVM at beginning.
  //
  // On flutter desktop, the C wrappers are bundled, and helperPath param
  // is not required.
  //
  // On dart standalone, however, there's no way to bundle the wrappers.
  // You have to manually pass the path to the `dartjni` dynamic library.

  if (!Platform.isAndroid) {
    Jni.spawn(helperDir: "src/");
  }

  jni = Jni.getInstance();

  test('get JNI Version', () {
    // get a dart binding of JNIEnv object
    // It's a thin wrapper over C's JNIEnv*, and provides
    // all methods of it (without need to pass the first self parameter),
    // plus few extension methods to make working in dart easier.
    final env = jni.getEnv();
    expect(env.GetVersion(), isNot(equals(0)));
  });

  test('Manually lookup & call Long.toHexString static method', () {
    // create an arena for allocating anything native
    // it's convenient way to release all natively allocated strings
    // and values at once.
    final arena = Arena();
    final env = jni.getEnv();

    // Method names on JniEnv* from C JNI API are capitalized
    // like in original, while other extension methods
    // follow Dart naming conventions.
    final longClass = env.FindClass("java/lang/Long".toNativeChars(arena));
    // Refer JNI spec on how to construct method signatures
    // Passing wrong signature leads to a segfault
    final hexMethod = env.GetStaticMethodID(
        longClass,
        "toHexString".toNativeChars(arena),
        "(J)Ljava/lang/String;".toNativeChars(arena));

    for (var i in [1, 80, 13, 76, 1134453224145]) {
      // Use Jni.jvalues method to easily construct native argument arrays
      // if your argument is int, bool, or JObject (`Pointer<Void>`)
      // it can be directly placed in the list. To convert into different primitive
      // types, use JValue<Type> wrappers.
      final jres = env.CallStaticObjectMethodA(
          longClass, hexMethod, Jni.jvalues([JValueLong(i)], allocator: arena));

      // use asDartString extension method on Pointer<JniEnv>
      // to convert a String jobject result to string
      final res = env.asDartString(jres);
      expect(res, equals(i.toRadixString(16)));

      // Any object or class result from java is a local reference
      // and needs to be deleted explicitly.
      // Note that method and field IDs aren't local references.
      // But they are valid only until a reference to corresponding
      // java class exists.
      env.DeleteLocalRef(jres);
    }
    env.DeleteLocalRef(longClass);
    arena.releaseAll();
  });

  test("asJString extension method", () {
    final env = jni.getEnv();
    const str = "QWERTY QWERTY";
    // convenience method that wraps
    // converting dart string to native string,
    // instantiating java string, and freeing the native string
    final jstr = env.asJString(str);
    expect(str, equals(env.asDartString(jstr)));
    env.DeleteLocalRef(jstr);
  });

  test("Convert back and forth between dart and java string", () {
    final arena = Arena();
    final env = jni.getEnv();
    const str = "ABCD EFGH";
    // This is what asJString and asDartString do internally
    final jstr = env.NewStringUTF(str.toNativeChars(arena));
    final jchars = env.GetStringUTFChars(jstr, nullptr);
    final dstr = jchars.toDartString();
    env.ReleaseStringUTFChars(jstr, jchars);
    expect(str, equals(dstr));

    // delete multiple local references using this method
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

  // The API based on JniEnv is intended to closely mimic C API
  // And thus can be too verbose for simple experimenting and one-off uses
  // JniObject API provides an easier way to perform some common operations.
  //
  // However, this is only meant for experimenting and very simple uses.
  // For anything complicated, use JNIGen (The main part of this GSoC project, WIP)
  // which will be both more efficient and ergonomic.
  test("Long.intValue() using JniObject", () {
    // findClass on a Jni object returns a JniClass
    // which wraps a local class reference and env, and
    // provides convenience functions.
    final longClass = jni.findClass("java/lang/Long");

    // looks for a constructor with given signature.
    // equivalently you can lookup a method with name <init>
    final longCtor = longClass.getConstructorID("(J)V");

    // note that the arguments are just passed as a list
    final long = longClass.newObject(longCtor, [176]);

    final intValue = long.callIntMethodByName("intValue", "()I", []);
    expect(intValue, equals(176));

    // delete any JniObject and JniClass instances using .delete() after use.
    long.delete();
    longClass.delete();
  });

  test("call a static method using JniClass APIs", () {
    final integerClass = jni.findClass("java/lang/Integer");
    final result = integerClass.callStaticObjectMethodByName(
        "toHexString", "(I)Ljava/lang/String;", [31]);

    // if the object is supposed to be a Java string
    // you can call asDartString on it.
    final resultString = result.asDartString();

    // Dart string is a copy, original object can be deleted.
    result.delete();
    expect(resultString, equals("1f"));

    // Also don't forget to delete the class
    integerClass.delete();
  });

  test("Call method with null argument, expect exception", () {
    final integerClass = jni.findClass("java/lang/Integer");
    expect(
        () => integerClass.callStaticIntMethodByName(
            "parseInt", "(Ljava/lang/String;)I", [nullptr]),
        throwsException);
    integerClass.delete();
  });

  test("Try to find a non-exisiting class, expect exception", () {
    expect(() => jni.findClass("java/lang/NotExists"), throwsException);
  });

  /// call<Type>MethodByName will be expensive if making same call many times
  /// Use getMethodID to get a method ID and use it in subsequent calls
  test("Example for using getMethodID", () {
    final longClass = jni.findClass("java/lang/Long");
    final bitCountMethod = longClass.getStaticMethodID("bitCount", "(J)I");

    // Use newInstance if you want only one instance.
    // It finds the class, gets constructor ID and constructs an instance.
    final random = jni.newInstance("java/util/Random", "()V", []);

    // You don't need a JniClass reference to get instance method IDs
    final nextIntMethod = random.getMethodID("nextInt", "(I)I");

    for (int i = 0; i < 100; i++) {
      int r = random.callIntMethod(nextIntMethod, [256 * 256]);
      int bits = 0;
      int jbc = longClass.callStaticIntMethod(bitCountMethod, [JValueLong(r)]);
      while (r != 0) {
        bits += r % 2;
        r = (r / 2).floor();
      }
      expect(jbc, equals(bits));
    }

    random.delete();
    longClass.delete();
  });

  // Actually it's not even required to get a reference to class
  test("invoke_", () {
    var m = jni.invokeLongMethod(
        "java/lang/Long", "min", "(JJ)J", [JValueLong(1234), JValueLong(1324)]);
    expect(m, equals(1234));
  });

  test("retrieve_", () {
    var maxLong = jni.retrieveShortField("java/lang/Short", "MAX_VALUE", "S");
    expect(maxLong, equals(32767));
  });

  // Use callStringMethod if all you care about is a string result
  test("callStaticStringMethod", () {
    final longClass = jni.findClass("java/lang/Long");
    const n = 1223334444;
    final strFromJava = longClass.callStaticStringMethodByName(
        "toOctalString", "(J)Ljava/lang/String;", [JValueLong(n)]);
    expect(strFromJava, equals(n.toRadixString(8)));
    longClass.delete();
  });

  // In JniObject, JniClass, and retrieve_/invoke_ methods
  // you can also pass Dart strings, apart from range of types
  // allowed by Jni.jvalues
  // They will be converted automatically.
  test("Passing strings in arguments", () {
    final out = jni.retrieveObjectField(
        "java/lang/System", "out", "Ljava/io/PrintStream;");
    // uncomment next line to see output
    // (\n because test runner prints first char at end of the line)
    //out.callVoidMethodByName(
    //    "println", "(Ljava/lang/Object;)V", ["\nWorks (Apparently)"]);
    out.delete();
  });

  test("Passing strings in arguments 2", () {
    var twelve = jni.invokeByteMethod(
        "java/lang/Byte", "parseByte", "(Ljava/lang/String;)B", ["12"]);
    expect(twelve, equals(12));
  });

  // You can use() method on JniObject for using once and deleting
  test("use() method", () {
    var randomInt = jni.newInstance("java/util/Random", "()V", []).use(
        (random) => random.callIntMethodByName("nextInt", "(I)I", [15]));
    expect(randomInt, lessThan(15));
  });

  test("enums", () {
	// Don't forget to escape $ in nested type names
	var ordinal = jni.retrieveObjectField("java/net/Proxy\$Type", "HTTP", "Ljava/net/Proxy\$Type;")
			.use((f) => f.callIntMethodByName("ordinal", "()I", []));
	expect(ordinal, equals(1));
  });

  test("Isolate", () {
    Isolate.spawn(doSomeWorkInIsolate, null);
  });

  // JniObject is valid only in thread it is obtained
  // so it can be safely shared with a function that can run in
  // different thread.
  //
  // Eg: Dart has a thread pool, which means async methods may get scheduled
  // in different thread.
  //
  // In that case, convert the JniObject into `JniGlobalObjectRef` using
  // getGlobalRef() and reconstruct the object in use site using fromJniObject
  // constructor.
  test("JniGlobalRef", () async {
    var uri = jni.invokeObjectMethod(
        "java/net/URI",
        "create",
        "(Ljava/lang/String;)Ljava/net/URI;",
        ["https://www.google.com/search"]);
    var rg = uri.getGlobalRef();
    await Future.delayed(const Duration(seconds: 1), () {
      var env = jni.getEnv();
      // Now comment this line & try to directly use uri local ref
      // in outer scope.
      //
      // You will likely get a segfault, because Future computation is running
      // in different thread.
      //
      // Therefore, don't share JniObjects across functions that can be scheduled
      // across threads, including async callbacks.
      var uri = JniObject.fromGlobalRef(env, rg);
      var scheme =
          uri.callStringMethodByName("getScheme", "()Ljava/lang/String;", []);
      expect(scheme, "https");
      uri.delete();
      rg.deleteIn(env);
    });
    uri.delete();
  });

}

void doSomeWorkInIsolate(Void? _) {
  // On standalone target, make sure to call load
  // when doing getInstance first time in a new isolate.
  //
  // otherwise getInstance will throw a "library not found" exception.
  Jni.load(helperDir: "src/");
  var jni = Jni.getInstance();
  var random = jni.newInstance("java/util/Random", "()V", []);
  var r = random.callIntMethodByName("nextInt", "(I)I", [256]);
  // expect(r, lessThan(256));
  // Expect throws an OutsideTestException
  // but you can uncomment below print and see it works
  // print("\n$r");
  random.delete();
}
