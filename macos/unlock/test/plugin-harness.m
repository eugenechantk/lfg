// Loads LFGUnlockPlugin.bundle the way SecurityAgent does and runs its `allow`
// mechanism once with stub engine callbacks. Prints the result it set:
//   plugin-harness <bundle>   →   "result=allow" | "result=deny"
// Used by test/run.sh to check the plug-in's half of the handshake without
// installing it into the real unlock path.
#import <Foundation/Foundation.h>
#import <Security/AuthorizationPlugin.h>
#import <dlfcn.h>

static AuthorizationResult gResult = 99;

static OSStatus SetResult(AuthorizationEngineRef engine, AuthorizationResult result) {
  gResult = result;
  return errAuthorizationSuccess;
}
static OSStatus DidDeactivate(AuthorizationEngineRef engine) { return errAuthorizationSuccess; }
static OSStatus GetContextValue(AuthorizationEngineRef e, AuthorizationString k, AuthorizationContextFlags *f,
                                const AuthorizationValue **v) { return errAuthorizationInternal; }
static OSStatus GetHintValue(AuthorizationEngineRef e, AuthorizationString k, const AuthorizationValue **v) {
  return errAuthorizationInternal;
}

typedef OSStatus (*CreateFn)(const AuthorizationCallbacks *, AuthorizationPluginRef *,
                             const AuthorizationPluginInterface **);

int main(int argc, char **argv) {
  if (argc < 2) return 64;
  NSString *exe = [NSString stringWithFormat:@"%s/Contents/MacOS/LFGUnlockPlugin", argv[1]];
  void *h = dlopen(exe.fileSystemRepresentation, RTLD_NOW);
  if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 1; }
  CreateFn create = (CreateFn)dlsym(h, "AuthorizationPluginCreate");
  if (!create) { fprintf(stderr, "no AuthorizationPluginCreate\n"); return 1; }

  AuthorizationCallbacks callbacks = {0};
  callbacks.version = kAuthorizationCallbacksVersion;
  callbacks.SetResult = SetResult;
  callbacks.DidDeactivate = DidDeactivate;
  callbacks.GetContextValue = GetContextValue;
  callbacks.GetHintValue = GetHintValue;

  AuthorizationPluginRef plugin = NULL;
  const AuthorizationPluginInterface *iface = NULL;
  if (create(&callbacks, &plugin, &iface) != errAuthorizationSuccess) return 2;
  AuthorizationMechanismRef mech = NULL;
  if (iface->MechanismCreate(plugin, (AuthorizationEngineRef)0x1, "allow", &mech) != errAuthorizationSuccess) return 3;
  iface->MechanismInvoke(mech);
  iface->MechanismDestroy(mech);
  iface->PluginDestroy(plugin);
  printf("result=%s\n", gResult == kAuthorizationResultAllow ? "allow" : gResult == kAuthorizationResultDeny ? "deny" : "unset");
  return 0;
}
