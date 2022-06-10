#include <stdint.h>
#include <stdio.h>
#include <jni.h>
#include <stdlib.h>

#if _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

FFI_PLUGIN_EXPORT JavaVM *GetJVM();

FFI_PLUGIN_EXPORT JNIEnv *GetJniEnv();

FFI_PLUGIN_EXPORT JNIEnv *spawnJvm(JavaVMInitArgs *args);

