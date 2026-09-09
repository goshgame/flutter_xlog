#include "xlog_bridge.h"

#include <jni.h>

#include <string>

namespace {

std::string ToUtf8(JNIEnv* env, jstring value) {
    if (value == nullptr) {
        return "";
    }

    const char* chars = env->GetStringUTFChars(value, nullptr);
    if (chars == nullptr) {
        return "";
    }

    std::string result(chars);
    env->ReleaseStringUTFChars(value, chars);
    return result;
}

}  // namespace

extern "C" JNIEXPORT void JNICALL
Java_com_gosh_flutter_1xlog_XLogNative_nativeWrite(
    JNIEnv* env,
    jclass,
    jint level,
    jstring tag,
    jstring file,
    jstring function,
    jint line,
    jstring message) {
    const std::string tag_utf8 = ToUtf8(env, tag);
    const std::string file_utf8 = ToUtf8(env, file);
    const std::string function_utf8 = ToUtf8(env, function);
    const std::string message_utf8 = ToUtf8(env, message);

    xlog_write(level, tag_utf8.c_str(), file_utf8.c_str(), function_utf8.c_str(), line,
               message_utf8.c_str());
}

extern "C" JNIEXPORT void JNICALL
Java_com_gosh_flutter_1xlog_XLogNative_nativeFlush(JNIEnv*, jclass, jboolean sync) {
    xlog_flush(sync == JNI_TRUE ? 1 : 0);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_gosh_flutter_1xlog_XLogNative_nativeIsOpen(JNIEnv*, jclass) {
    return xlog_is_open() == 1 ? JNI_TRUE : JNI_FALSE;
}
