#include "dartjni.h"

#include <jni.h>
#include <stdint.h>
#include <threads.h>

#ifdef __ANDROID__
#include<android/log.h>
#endif


#define JNI_LOG_TAG "Dart-JNI"

static struct {
	JavaVM *jvm;
	jobject classLoader;
	jmethodID loadClassMethod;
	jobject mainActivityObject;
	jobject appContext;
	// TODO: Update mainActivity and context using ActivityAware plugin
} jni = {NULL, NULL, NULL, NULL, NULL};

thread_local JNIEnv *jniEnv = NULL;

int jni_log_level = DART_JNI_INFO;

FFI_PLUGIN_EXPORT
void SetJNILogging(int level) {
	jni_log_level = level;
}

void jni_log(int level, const char *format, ...) {
	if (level >= jni_log_level) {
		va_list args;
        va_start(args, format);
#ifdef __ANDROID__
		__android_log_print(level, JNI_LOG_TAG, format, args);
#else
		printf("%s: ", JNI_LOG_TAG);
		vfprintf(stderr, format, args);
#endif
        va_end(args);
	}
}

/// Get JVM associated with current process.
/// Returns NULL if no JVM is running.
FFI_PLUGIN_EXPORT
JavaVM *GetJavaVM() { return jni.jvm; }

/// Returns Application classLoader (on Android), 
/// which can be used to load application and platform classes.
/// ...
/// On other platforms, NULL is returned.
FFI_PLUGIN_EXPORT
jobject GetClassLoader() {
	return jni.classLoader;
}

/// Returns application context on Android.
///
/// On other platforms, NULL is returned.
FFI_PLUGIN_EXPORT
jobject GetApplicationContext() {
	return jni.appContext;
}

/// Load class through platform-specific mechanism
/// ...
/// Currently uses application classloader on android,
/// and JNIEnv->FindClass on other platforms.
FFI_PLUGIN_EXPORT
jclass LoadClass(const char *name) {
	jclass cls = NULL;
#ifdef __ANDROID__
	jstring className = (*jniEnv)->NewStringUTF(jniEnv, name);
	cls = (*jniEnv)->CallObjectMethod(jniEnv, jni.classLoader,
	                                  jni.loadClassMethod, className);
#else
	cls = (*jniEnv)->FindClass(jniEnv, name);
#endif
	if (cls == NULL) {
		(*jniEnv)->ExceptionDescribe(jniEnv);
	}
	return cls;
};

static inline void load_class(jclass *cls, const char *name) {
	if (*cls == NULL) {
#ifdef __ANDROID__
		jstring className = (*jniEnv)->NewStringUTF(jniEnv, name);
		*cls = (*jniEnv)->CallObjectMethod(
		    jniEnv, jni.classLoader, jni.loadClassMethod, className);
		(*jniEnv)->DeleteLocalRef(jniEnv, className);
#else
		*cls = (*jniEnv)->FindClass(jniEnv, name);
#endif
	}
}

static inline void attach_thread() {
	if (jniEnv == NULL) {
		(*jni.jvm)->AttachCurrentThread(jni.jvm, (void **)&jniEnv,
		                                NULL);
	}
}

FFI_PLUGIN_EXPORT
JNIEnv *GetJniEnv() {
	if (jni.jvm == NULL) {
		return NULL;
	}
	attach_thread();
	return jniEnv;
}

static inline void load_method(jclass cls, jmethodID *res, const char *name,
                               const char *sig) {
	if (*res == NULL) {
		*res = (*jniEnv)->GetMethodID(jniEnv, cls, name, sig);
	}
}

static inline void load_static_method(jclass cls, jmethodID *res,
                                      const char *name, const char *sig) {
	if (*res == NULL) {
		*res = (*jniEnv)->GetStaticMethodID(jniEnv, cls, name, sig);
	}
}

#ifdef __ANDROID__
JNIEXPORT void JNICALL Java_dev_dart_jni_JniPlugin_initializeJni(
    JNIEnv *env, jobject obj, jobject appContext, jobject classLoader) {
	jniEnv = env;
	_log(DART_JNI_DEBUG, "LoL\n");
	(*env)->GetJavaVM(env, &jni.jvm);
	jni.mainActivityObject = (*env)->NewGlobalRef(env, obj);
	jni.classLoader = (*env)->NewGlobalRef(env, classLoader);
	jni.appContext = (*env)->NewGlobalRef(env, appContext);
	jclass classLoaderClass = (*env)->GetObjectClass(env, classLoader);
	jni.loadClassMethod =
	    (*env)->GetMethodID(env, classLoaderClass, "loadClass",
	                        "(Ljava/lang/String;)Ljava/lang/Class;");
}
// Sometimes you may get linker error trying to link JNI_CreateJavaVM APIs
// on Android NDK. So IFDEF is required.
#else
FFI_PLUGIN_EXPORT
__attribute__((visibility("default"))) __attribute__((used)) JNIEnv *
SpawnJvm(JavaVMInitArgs *initArgs) {
	JavaVMOption jvmopt[1];
	char class_path[] = "-Djava.class.path=.";
	jvmopt[0].optionString = class_path;
	JavaVMInitArgs vmArgs;
	if (!initArgs) {
		vmArgs.version = JNI_VERSION_1_2;
		vmArgs.nOptions = 1;
		vmArgs.options = jvmopt;
		vmArgs.ignoreUnrecognized = JNI_TRUE;
		initArgs = &vmArgs;
	}
	jni_log(DART_JNI_DEBUG, "JNI Version: %d\n", initArgs->version);
	const long flag =
	    JNI_CreateJavaVM(&jni.jvm, (void **)&jniEnv, initArgs);
	if (flag == JNI_ERR) {
		return NULL;
	}
	return jniEnv;
}
#endif

