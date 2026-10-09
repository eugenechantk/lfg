// LFGUnlockPlugin — an authorization plug-in mechanism for `system.login.screensaver`.
//
// When the lock screen's form is submitted, loginwindow asks authd for the
// `system.login.screensaver` right, and authd runs this mechanism (inside
// SecurityAgentHelper, sandboxed, as a different user) before the normal
// password check. We allow the unlock only when the console user is running
// `lfg-unlock unlock` right now and it answers ALLOW on its socket. Every other
// outcome — no socket, a socket or peer owned by anyone else, timeout, any
// error — is a deny, so authd falls through to the real password screen.
//
// Why ownership and not the helper's code signature: the sandbox denies
// SecCodeCopyGuestWithAttributes (status 100013, measured on the first live
// unlock), and a signature check adds nothing anyway — any process running as
// the console user can run the signed helper. The trust boundary is "code
// running as the user whose screen this is".
//
// See .claude/feature/mac-unlock.md.
#import <Foundation/Foundation.h>
#import <Security/AuthorizationPlugin.h>
#import <Security/Security.h>
#import <os/log.h>
#import <pwd.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/un.h>
#import <unistd.h>

static NSString *const kSocketPath = @"/tmp/dev.omg.lfg-unlock/unlock.sock";

static os_log_t Log(void) {
  static os_log_t log;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ log = os_log_create("dev.omg.lfg-unlock", "plugin"); });
  return log;
}

typedef struct {
  AuthorizationPluginInterface interface;
  const AuthorizationCallbacks *callbacks;
} Plugin;

typedef struct {
  const Plugin *plugin;
  AuthorizationEngineRef engine;
} Mechanism;

// The username loginwindow passed for this unlock (the hint or context value
// "username"), resolved to a uid. 0 = unknown.
static uid_t UnlockingUserUID(const AuthorizationCallbacks *cb, AuthorizationEngineRef engine) {
  const AuthorizationValue *value = NULL;
  AuthorizationContextFlags flags = 0;
  if (cb->GetContextValue(engine, kAuthorizationEnvironmentUsername, &flags, &value) != errAuthorizationSuccess ||
      !value || !value->data || value->length == 0) {
    value = NULL;
    if (cb->GetHintValue(engine, kAuthorizationEnvironmentUsername, &value) != errAuthorizationSuccess) value = NULL;
  }
  if (!value || !value->data || value->length == 0 || value->length > 255) return 0;
  char name[256] = {0};
  memcpy(name, value->data, value->length);
  struct passwd *pw = getpwnam(name);
  return pw ? pw->pw_uid : 0;
}

// The user whose screen is locked. Three sources, best first, because this
// runs sandboxed and we cannot test which lookups the sandbox allows without
// a root reinstall: the owner of /dev/console, then the username loginwindow
// passed, then (single-user fallback, logged) the socket's owner if it is a
// regular account. 0 = unknown → deny.
static uid_t ExpectedUID(const AuthorizationCallbacks *cb, AuthorizationEngineRef engine) {
  struct stat st;
  if (stat("/dev/console", &st) == 0 && st.st_uid != 0) return st.st_uid;
  os_log_error(Log(), "cannot use /dev/console owner errno=%{public}d", errno);
  uid_t uid = UnlockingUserUID(cb, engine);
  if (uid != 0) return uid;
  os_log_error(Log(), "no username for this unlock; falling back to the socket owner");
  struct stat sock;
  if (lstat(kSocketPath.fileSystemRepresentation, &sock) == 0 && sock.st_uid >= 501) return sock.st_uid;
  return 0;
}

// The socket, its directory, and the process serving it must all belong to
// the console user. /tmp is sticky, so no other user can swap them.
static BOOL PeerIsConsoleUser(int fd, uid_t console) {
  if (console == 0) return NO;
  struct stat dir, sock;
  NSString *dirPath = kSocketPath.stringByDeletingLastPathComponent;
  if (lstat(dirPath.fileSystemRepresentation, &dir) != 0 || !S_ISDIR(dir.st_mode) || dir.st_uid != console) {
    os_log_error(Log(), "socket directory is missing or not owned by uid %{public}u", console);
    return NO;
  }
  if (lstat(kSocketPath.fileSystemRepresentation, &sock) != 0 || !S_ISSOCK(sock.st_mode) || sock.st_uid != console) {
    os_log_error(Log(), "socket is missing or not owned by uid %{public}u", console);
    return NO;
  }
  uid_t peerUID = (uid_t)-1;
  gid_t peerGID = (gid_t)-1;
  if (getpeereid(fd, &peerUID, &peerGID) != 0 || peerUID != console) {
    os_log_error(Log(), "socket peer uid %{public}d is not console uid %{public}u", (int)peerUID, console);
    return NO;
  }
  return YES;
}

// YES only when the helper is listening, is who it should be, and says ALLOW.
static BOOL HelperApprovesUnlock(uid_t console) {
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) return NO;
  struct timeval tv = {.tv_sec = 3, .tv_usec = 0};
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
  setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
  // We run inside SecurityAgent: a write to a socket the helper already closed
  // must fail with EPIPE, not raise SIGPIPE and kill the unlock UI's process.
  int one = 1;
  setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
  struct sockaddr_un addr = {.sun_family = AF_UNIX};
  strlcpy(addr.sun_path, kSocketPath.fileSystemRepresentation, sizeof(addr.sun_path));
  if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
    // The normal case whenever a person unlocks: no lfg-unlock attempt is running.
    os_log_info(Log(), "no unlock request pending (errno=%{public}d)", errno);
    close(fd);
    return NO;
  }
  BOOL allowed = NO;
  if (PeerIsConsoleUser(fd, console)) {
    const char *ask = "UNLOCK 1\n";
    char reply[32] = {0};
    if (write(fd, ask, strlen(ask)) == (ssize_t)strlen(ask)) {
      ssize_t n = read(fd, reply, sizeof(reply) - 1);
      allowed = n >= 5 && strncmp(reply, "ALLOW", 5) == 0;
    }
  }
  close(fd);
  os_log(Log(), "unlock request answered allowed=%{public}d", allowed);
  return allowed;
}

static OSStatus MechanismInvoke(AuthorizationMechanismRef ref) {
  Mechanism *m = (Mechanism *)ref;
  BOOL allow = NO;
  @try {
    allow = HelperApprovesUnlock(ExpectedUID(m->plugin->callbacks, m->engine));
  } @catch (NSException *e) {
    os_log_error(Log(), "exception %{public}@", e.reason);
  }
  return m->plugin->callbacks->SetResult(m->engine, allow ? kAuthorizationResultAllow : kAuthorizationResultDeny);
}

static OSStatus MechanismDeactivate(AuthorizationMechanismRef ref) {
  Mechanism *m = (Mechanism *)ref;
  return m->plugin->callbacks->DidDeactivate(m->engine);
}

static OSStatus MechanismDestroy(AuthorizationMechanismRef ref) {
  free(ref);
  return errAuthorizationSuccess;
}

static OSStatus MechanismCreate(AuthorizationPluginRef plugin, AuthorizationEngineRef engine,
                                AuthorizationMechanismId mechanismId, AuthorizationMechanismRef *out) {
  if (strcmp(mechanismId, "allow") != 0) return errAuthorizationInternal;
  Mechanism *m = calloc(1, sizeof(Mechanism));
  if (!m) return errAuthorizationInternal;
  m->plugin = (const Plugin *)plugin;
  m->engine = engine;
  *out = m;
  return errAuthorizationSuccess;
}

static OSStatus PluginDestroy(AuthorizationPluginRef plugin) {
  free(plugin);
  return errAuthorizationSuccess;
}

OSStatus AuthorizationPluginCreate(const AuthorizationCallbacks *callbacks, AuthorizationPluginRef *outPlugin,
                                   const AuthorizationPluginInterface **outInterface) {
  Plugin *p = calloc(1, sizeof(Plugin));
  if (!p) return errAuthorizationInternal;
  p->interface.version = kAuthorizationPluginInterfaceVersion;
  p->interface.PluginDestroy = PluginDestroy;
  p->interface.MechanismCreate = MechanismCreate;
  p->interface.MechanismInvoke = MechanismInvoke;
  p->interface.MechanismDeactivate = MechanismDeactivate;
  p->interface.MechanismDestroy = MechanismDestroy;
  p->callbacks = callbacks;
  *outPlugin = p;
  *outInterface = &p->interface;
  return errAuthorizationSuccess;
}
