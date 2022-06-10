import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'jni_bindings_generated.dart';

typedef GetVersionDartType = int Function(Pointer<JNIEnv> env);

typedef _GetJvmType = Pointer<JavaVM> Function();
typedef _GetJniEnvType = Pointer<JNIEnv> Function();

typedef _SpawnJvmType = Pointer<JNIEnv> Function(Pointer<JavaVMInitArgs>);

typedef CreateJavaVMNativeType = Int64 Function(Pointer<Pointer<JavaVM>>, Pointer<Pointer<JNIEnv>>, Pointer<Pointer<Utf8>> args);
typedef CreateJavaVMDartType = int Function(Pointer<Pointer<JavaVM>>, Pointer<Pointer<JNIEnv>>, Pointer<Pointer<Utf8>> args);

final _helperNullError = Exception("Helpers library is not loaded!");
final _helperPathNeededError = Exception("JNI Helpers are not loaded! Please provide a helpersLibraryPath argument");

// Functions provided by helper DLL
_GetJvmType? _getJvm;
_GetJniEnvType? _getJniEnv;

// Returns pointer to current JNI JavaVM instance
Pointer<JavaVM> getJavaVM() {
	if (_getJvm == null) {
		if (_helpersDll == null) {
			throw _helperNullError;
		}
		_getJvm = _helpersDll!.lookupFunction<_GetJvmType, _GetJvmType>("GetJvm");
	}
	return _getJvm!();
}

// Returns a JNIEnv, it's valid only in current thread.
// Do not reuse a JNIEnv between callbacks that may be scheduled on different threads.
// Get a new JniEnv instead in such cases.
Pointer<JNIEnv> getJniEnv() {
	if (_getJniEnv == null) {
		if (_helpersDll == null) {
			throw _helperNullError;
		}
		_getJniEnv = _helpersDll!.lookupFunction<_GetJniEnvType, _GetJniEnvType>("GetJniEnv");
	}
	final env = _getJniEnv!();
	if (env == nullptr) {
		throw Exception("GetJNIEnv() returned null! Ensure a JVM is spawned in non-android code.");
	}
	return env;
}

String _getLibraryFilename(String base) {
	if (Platform.isLinux || Platform.isAndroid) {
		return "lib$base.so";
	} else if (Platform.isWindows) {
		return "$base.dll";
	} else if (Platform.isMacOS) {
		// TODO
		return "---";
	} else {
		throw Exception("cannot derive library name: unsupported platform");
	}
}

// DLL for helper library, or null if not loaded yet
//
// We could store DynamicLibrary.executable() instead of null
// but explicitly checking for null makes error messages easier
DynamicLibrary? _helpersDll = () {
	final libPath = Platform.environment["DART_JNI_LIB"] ?? _getLibraryFilename("dartjni");
	try {
		return DynamicLibrary.open(libPath);
	} on Exception catch(_) {
		return null;
	}
}();

bool isInitialized() {
	return _helpersDll == null;
}

Pointer<JNIEnv> spawnJvm({String? helpersLibraryPath, JavaVMInitArgs? args}) {
	if (helpersLibraryPath != null) {
		final dll = DynamicLibrary.open(helpersLibraryPath);
		_helpersDll = dll;
	}
	Pointer<JavaVMInitArgs>? jInitArgs;
	if (args != null) {
		jInitArgs = calloc<JavaVMInitArgs>();
		jInitArgs.ref = args;
	}
	if (_helpersDll == null) {
		throw _helperPathNeededError;
	}
	final spawnJvmFunc = _helpersDll!.lookupFunction<_SpawnJvmType, _SpawnJvmType>('SpawnJvm');
	final res = spawnJvmFunc(jInitArgs ?? nullptr);
	if (args != null) {
		calloc.free(jInitArgs!);
	}
	return res;
}

String getJniVersion() {
	final envPtr = getJniEnv();
	final env = envPtr.value;
	GetVersionDartType getVersion = env.ref.GetVersion.asFunction();
	final version = getVersion(envPtr);
	final majorVersion = version >> 16;
	final minorVersion = version & 0xFFFF;
	return "$majorVersion $minorVersion";
}

