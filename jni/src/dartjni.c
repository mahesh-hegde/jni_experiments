#include "dartjni.h"

#include <jni.h>
#include <threads.h>
#include<stdint.h>

static struct {
	JavaVM *jvm;
	jobject classLoader;
	jmethodID loadClassMethod;
	jobject mainActivityObject;
	jobject appContext;
} jni = {NULL, NULL, NULL, NULL, NULL};

thread_local JNIEnv *jniEnv = NULL;

FFI_PLUGIN_EXPORT
JavaVM *GetJVM() {
	return jni.jvm;
}

// Class and method loading helpers
static inline
void load_class(jclass *cls, const char *name) {
    if (*cls == NULL) {
#ifdef __ANDROID__
		jstring className = (*jniEnv)->NewStringUTF(jniEnv, name);
        *cls = (*jniEnv)->CallObjectMethod(jniEnv, jni.classLoader, jni.loadClassMethod, className);
        (*jniEnv)->DeleteLocalRef(jniEnv, className);
#else
		*cls = (*jniEnv)->FindClass(jniEnv, name);
#endif
    }
}

static inline
void attach_thread() {
    if (jniEnv == NULL) {
        (*jni.jvm)->AttachCurrentThread(jni.jvm, (void **)&jniEnv, NULL);
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

static inline
void load_method(jclass cls, jmethodID *res, const char *name, const char *sig) {
    if (*res == NULL) {
        *res = (*jniEnv)->GetMethodID(jniEnv, cls, name, sig);
    }
}

static inline
void load_static_method(jclass cls, jmethodID *res, const char *name, const char *sig) {
    if (*res == NULL) {
        *res = (*jniEnv)->GetStaticMethodID(jniEnv, cls, name, sig);
    }
}

#ifdef __ANDROID__
JNIEXPORT void JNICALL
Java_dev_dart_jni_JniPlugin_initializeJni(JNIEnv *env, jobject obj, jobject appContext, jobject classLoader) {
    jniEnv = env;
	(*env)->GetJavaVM(env, &jni.jvm);
	jni.mainActivityObject = (*env)->NewGlobalRef(env, obj);
	jni.classLoader = (*env)->NewGlobalRef(env, classLoader);
	jni.appContext = (*env)->NewGlobalRef(env, appContext);
	jclass classLoaderClass = (*env)->GetObjectClass(env, classLoader);
	jni.loadClassMethod = (*env)->GetMethodID(env, classLoaderClass,"loadClass", "(Ljava/lang/String;)Ljava/lang/Class;");
}
#else
FFI_PLUGIN_EXPORT
__attribute__((visibility("default"))) __attribute__((used))
JNIEnv *SpawnJvm(JavaVMInitArgs *initArgs) {
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
  const long flag = JNI_CreateJavaVM(&jni.jvm, (void **)&jniEnv, initArgs);
  if (flag == JNI_ERR) {
    return NULL;
  }
  return jniEnv;
}
#endif
