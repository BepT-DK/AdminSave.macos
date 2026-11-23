// AdminSave — Nextpad++ plugin.
// Lets the editor save files the user has no write access to: when a normal
// save is refused, it asks for admin rights and rewrites the file in place.
#import <AppKit/AppKit.h>
#import <Security/Authorization.h>
#import <objc/runtime.h>
#include <crt_externs.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
#include "NppPluginInterfaceMac.h"

// The editor's own -[EditorView _writeContentsToPath:error:], kept to call and to restore.
typedef BOOL (*WriteIMP)(id, SEL, NSString *, NSError **);
static Method gMethod;
static WriteIMP gOrigWrite;

// True when writing to `path` is refused for lack of permission.
static bool denied(NSString *path) {
    return access(path.fileSystemRepresentation, W_OK) != 0 && errno == EACCES;
}

// Exit code of the sudo command when the user authenticated but cp itself failed.
// sudo's own failures (not authenticated) exit with 1, so the two can be told apart.
static const int kCopyFailed = 3;

// Copies src over dst as root through sudo, which authenticates with Touch ID
// when pam_tid is enabled. Returns 0 on success, kCopyFailed when root could
// not write the file, anything else when sudo did not authenticate.
// cp, not mv: it rewrites the file in place, keeping its owner and mode.
//   -k  do not cache the credentials, or anything the editor starts could reuse them
//   -S  read the password from stdin; stdin is /dev/null, so without Touch ID
//       sudo fails at once instead of waiting for input
// The paths reach the shell as positional arguments, never as script text.
static int sudoCopy(const char *src, const char *dst) {
    posix_spawn_file_actions_t io;
    posix_spawn_file_actions_init(&io);
    for (int fd = 0; fd < 3; fd++) posix_spawn_file_actions_addopen(&io, fd, "/dev/null", O_RDWR, 0);
    const char *argv[] = {"sudo", "-k", "-S", "-p", "", "--", "/bin/sh", "-c",
                          "/bin/cp \"$1\" \"$2\" || exit 3", "sh", src, dst, NULL};
    pid_t pid, done = -1;
    int status = -1;
    // Block in waitpid: NSTask would spin the run loop and let editor timers fire mid-save.
    if (posix_spawn(&pid, "/usr/bin/sudo", &io, NULL, (char *const *)argv, *_NSGetEnviron()) == 0)
        while ((done = waitpid(pid, &status, 0)) == -1 && errno == EINTR) {}
    posix_spawn_file_actions_destroy(&io);
    return done != -1 && WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

// Copies src over dst as root after the system password dialog. That dialog
// never offers Touch ID, which is why sudoCopy is tried first.
static BOOL passwordCopy(const char *src, const char *dst) {
    AuthorizationRef auth;
    if (AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults,
                            &auth) != errAuthorizationSuccess)
        return NO;
    char *const args[] = {(char *)src, (char *)dst, NULL};
    FILE *pipe = NULL;
    // Deprecated, but it shows the system password dialog without installing a helper.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OSStatus status = AuthorizationExecuteWithPrivileges(auth, "/bin/cp", kAuthorizationFlagDefaults,
                                                         args, &pipe);
#pragma clang diagnostic pop
    if (status == errAuthorizationSuccess) {  // otherwise cancelled or denied
        for (char buf[256]; fread(buf, 1, sizeof buf, pipe) > 0;) {}  // wait for cp to exit
        fclose(pipe);
    }
    // Give the admin right back at once. Kept, it would let the next saves
    // through without a prompt for five minutes, even after a cancelled Touch ID.
    AuthorizationFree(auth, kAuthorizationFlagDestroyRights);
    return status == errAuthorizationSuccess;
}

// Touch ID first, the password dialog as a fallback.
static BOOL copyAsRoot(NSString *src, NSString *dst) {
    int status = sudoCopy(src.fileSystemRepresentation, dst.fileSystemRepresentation);
    if (status == 0) return YES;
    // Root could not write the file either (locked or system-protected): the
    // password dialog would only fail the same way, so do not show it.
    if (status == kCopyFailed) return NO;
    NSLog(@"[AdminSave] Touch ID via sudo unavailable or cancelled — asking for the password");
    return passwordCopy(src.fileSystemRepresentation, dst.fileSystemRepresentation);
}

// Replaces -[EditorView _writeContentsToPath:error:]. Runs the editor's own
// save first and steps in only when it fails for lack of permission.
static BOOL hookedWrite(id self, SEL _cmd, NSString *path, NSError **error) {
    if (gOrigWrite(self, _cmd, path, error)) return YES;
    // Any other failure is left to the editor and its error message.
    if (!denied(path) && !denied(path.stringByDeletingLastPathComponent)) return NO;

    // Let the editor encode the document into a temp file and copy that over the
    // target as root. The bytes are read back before the copy and compared with
    // the target after it, so a temp file changed while the prompt was up ends
    // as a failed save. Reading the target follows a symlink, as cp does.
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSData *bytes = gOrigWrite(self, _cmd, tmp, NULL) ? [NSData dataWithContentsOfFile:tmp] : nil;
    BOOL ok = bytes && copyAsRoot(tmp, path);
    if (ok) {
        NSData *written = [NSData dataWithContentsOfFile:path];
        ok = written && [bytes isEqualToData:written];
    }
    [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
    NSLog(@"[AdminSave] %@: %@", path, ok ? @"saved with admin rights" : @"admin save failed or cancelled");
    return ok;
}

// Puts the editor's method back when the plugin is unloaded.
__attribute__((destructor)) static void unhook(void) {
    if (gMethod && gOrigWrite) method_setImplementation(gMethod, (IMP)gOrigWrite);
}

extern "C" {

// Called once by the editor at load: installs the save hook.
void setInfo(struct NppData) {
    if (gOrigWrite) return;
    Method m = class_getInstanceMethod(NSClassFromString(@"EditorView"),
                                       NSSelectorFromString(@"_writeContentsToPath:error:"));
    // An editor version without this method: leave saving untouched.
    if (!m || method_getNumberOfArguments(m) != 4) {
        NSLog(@"[AdminSave] EditorView save method not found — plugin inactive");
        return;
    }
    gMethod = m;
    gOrigWrite = (WriteIMP)method_setImplementation(m, (IMP)hookedWrite);
}

const char *getName(void) { return "AdminSave"; }

static void about(void) {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"AdminSave";
    alert.informativeText =
        @"AdminSave for Nextpad++ (macOS)\n"
        @"Version " ADMINSAVE_VERSION "\n\n"
        @"Saves files as administrator, with a Touch ID or password prompt. "
        @"Nextpad++ saves with your own rights, so a file owned by the system ends "
        @"in a save error; with AdminSave you just press Save.\n\n"
        @"Features:\n"
        @"- Works on the normal Save, Save As and Save All\n"
        @"- Asks only when a save is refused for lack of permission\n"
        @"- Touch ID when it is enabled for sudo, admin password otherwise\n"
        @"- Keeps the file's owner and permissions\n"
        @"- Asks again on every protected save\n\n"
        @"Author: Danny Karpilov";
    [alert runModal];
}

// The plugin menu: a single About item.
struct FuncItem *getFuncsArray(int *nbF) {
    static struct FuncItem items[] = {{"About", about, 0, false, NULL}};
    *nbF = 1;
    return items;
}

// Required exports; the plugin has no notifications or messages to handle.
void beNotified(struct SCNotification *) {}

intptr_t messageProc(uint32_t, uintptr_t, intptr_t) { return 0; }

}
