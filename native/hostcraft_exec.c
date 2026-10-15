// APK-packaged executable: writable app data is never directly exec'd.
#include <jni.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <sys/prctl.h>
#include <unistd.h>

int main(int argc, char **argv) {
    pid_t parent = getppid();
    prctl(PR_SET_PDEATHSIG, SIGTERM);
    if (getppid() != parent) return 125;
    if (argc > 2 && strcmp(argv[1], "--exec") == 0) {
        execv(argv[2], &argv[2]);
        perror("Cannot start packaged agent"); return 126;
    }
    const char *home = getenv("JAVA_HOME");
    if (!home) { fputs("JAVA_HOME is missing\n", stderr); return 2; }
    char path[4096];
    snprintf(path, sizeof(path), "%s/lib/server/libjvm.so", home);
    void *lib = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
    if (!lib) { fprintf(stderr, "Cannot load Android JVM: %s\n", dlerror()); return 3; }
    typedef jint (*CreateVM)(JavaVM **, void **, void *);
    CreateVM create = (CreateVM)dlsym(lib, "JNI_CreateJavaVM");
    if (!create) { fputs("JNI_CreateJavaVM missing\n", stderr); return 4; }
    int split = 1;
    while (split < argc && strcmp(argv[split], "--") != 0) split++;
    JavaVMOption *options = calloc((size_t)argc, sizeof(JavaVMOption));
    for (int i=1; i<split; i++) options[i-1].optionString = argv[i];
    JavaVMInitArgs args = {0x00010008, split-1, options, JNI_FALSE};
    JavaVM *vm; JNIEnv *env;
    jint rc = create(&vm, (void **)&env, &args);
    free(options);
    if (rc != JNI_OK) { fprintf(stderr, "JVM initialization failed: %d\n", rc); return 5; }
    jclass cls = (*env)->FindClass(env, "dev/hostcraft/bootstrap/Main");
    if (!cls) { (*env)->ExceptionDescribe(env); return 6; }
    jmethodID mainMethod = (*env)->GetStaticMethodID(env, cls, "main", "([Ljava/lang/String;)V");
    jclass str = (*env)->FindClass(env, "java/lang/String");
    int count = split < argc ? argc - split - 1 : 0;
    jobjectArray params = (*env)->NewObjectArray(env, count, str, NULL);
    for (int i=0; i<count; i++) {
        jstring arg = (*env)->NewStringUTF(env, argv[split+i+1]);
        (*env)->SetObjectArrayElement(env, params, i, arg);
        (*env)->DeleteLocalRef(env, arg);
    }
    (*env)->CallStaticVoidMethod(env, cls, mainMethod, params);
    int failed = (*env)->ExceptionCheck(env);
    if (failed) { (*env)->ExceptionDescribe(env); (*env)->ExceptionClear(env); }
    (*vm)->DestroyJavaVM(vm);
    return failed ? 7 : 0;
}
