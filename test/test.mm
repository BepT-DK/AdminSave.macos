// Self-check for AdminSave. A fake EditorView saves the way Nextpad++ does
// (atomic write), the plugin is loaded on top of it.
//   adminsave-test AdminSave.dylib          no prompt
//   adminsave-test AdminSave.dylib --auth   three admin prompts: Touch ID when it
//                                           is enabled for sudo, the password otherwise
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <initializer_list>
#include <sys/stat.h>
#include "NppPluginInterfaceMac.h"

static NSData *gContent;

@interface EditorView : NSObject
@end
@implementation EditorView
- (BOOL)_writeContentsToPath:(NSString *)path error:(NSError **)error {
    if ([gContent writeToFile:path atomically:YES]) return YES;
    if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
    return NO;
}
@end

static BOOL save(NSString *path, const char *text) {
    gContent = [NSData dataWithBytes:text length:strlen(text)];
    return [[EditorView new] _writeContentsToPath:path error:nil];
}

static BOOL holds(NSString *path, const char *text) {
    return [[NSData dataWithContentsOfFile:path] isEqualToData:[NSData dataWithBytes:text length:strlen(text)]];
}

// Runs `block` with stderr sent to a file and returns what the plugin logged
// meanwhile; nil when stderr could not be redirected.
static NSString *logOf(void (^block)(void)) {
    NSString *file = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    fflush(stderr);
    int realStderr = dup(STDERR_FILENO);
    if (realStderr < 0) return nil;
    if (!freopen(file.fileSystemRepresentation, "w", stderr)) {
        close(realStderr);
        return nil;
    }
    block();
    fflush(stderr);
    dup2(realStderr, STDERR_FILENO);
    close(realStderr);
    NSString *log = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
    [NSFileManager.defaultManager removeItemAtPath:file error:nil];
    return log;
}

#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); return 1; } } while (0)

int main(int argc, char **argv) {
    @autoreleasepool {
        CHECK(argc > 1);
        void *plugin = dlopen(argv[1], RTLD_NOW);
        CHECK(plugin);
        for (const char *name : {"setInfo", "getName", "getFuncsArray", "beNotified", "messageProc"})
            CHECK(dlsym(plugin, name));

        // setInfo must replace the editor's write method.
        SEL writeSel = @selector(_writeContentsToPath:error:);
        IMP original = class_getMethodImplementation([EditorView class], writeSel);
        ((PFUNCSETINFO)dlsym(plugin, "setInfo"))((struct NppData){});
        CHECK(class_getMethodImplementation([EditorView class], writeSel) != original);

        // The plugin menu holds exactly one command, About (not called: it is a modal alert).
        int count = 0;
        struct FuncItem *items = ((PFUNCGETFUNCSARRAY)dlsym(plugin, "getFuncsArray"))(&count);
        CHECK(count == 1 && strcmp(items[0]._itemName, "About") == 0 && items[0]._pFunc);

        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *file = [dir stringByAppendingPathComponent:@"hosts"];
        NSString *link = [dir stringByAppendingPathComponent:@"hosts-link"];
        CHECK([fm createDirectoryAtPath:dir withIntermediateDirectories:NO attributes:nil error:nil]);
        CHECK([fm createSymbolicLinkAtPath:link withDestinationPath:@"hosts" error:nil]);

        // 1. Writable file: plain save.
        // 2. Failure that is not about permissions: stock failure.
        // In both the plugin must stay out of the way: no log line, so no prompt.
        __block BOOL plain = NO, missing = YES;
        NSString *quietLog = logOf(^{
            plain = save(file, "one\n") && holds(file, "one\n");
            missing = save([dir stringByAppendingPathComponent:@"missing/hosts"], "x");
        });

        __block BOOL admin = YES, viaLink = YES, locked = YES;
        BOOL inPlace = YES, linkKept = YES, lockedTried = YES, extraPassword = NO;
        if (argc > 2) {
            chmod(file.fileSystemRepresentation, 0444);
            chmod(dir.fileSystemRepresentation, 0555);

            // 3. Read-only file in a read-only folder: prompt, then rewrite in place.
            struct stat before, after;
            stat(file.fileSystemRepresentation, &before);
            NSString *adminLog = logOf(^{ admin = save(file, "two\n") && holds(file, "two\n"); });
            stat(file.fileSystemRepresentation, &after);
            inPlace = before.st_ino == after.st_ino && before.st_uid == after.st_uid &&
                      before.st_mode == after.st_mode;
            // Without Touch ID for sudo every admin save goes through the password dialog.
            BOOL passwordOnly = [adminLog containsString:@"asking for the password"];

            // 4. The same file reached through a symlink: the target is rewritten
            // and the link stays a link.
            logOf(^{ viaLink = save(link, "three\n") && holds(file, "three\n"); });
            struct stat linkStat;
            linkKept = lstat(link.fileSystemRepresentation, &linkStat) == 0 && S_ISLNK(linkStat.st_mode);

            // 5. Locked file, which even root cannot write: one prompt, the save
            // fails, and the password dialog is not shown on top of Touch ID.
            chflags(file.fileSystemRepresentation, UF_IMMUTABLE);
            NSString *lockedLog = logOf(^{ locked = !save(file, "four\n") && holds(file, "three\n"); });
            lockedTried = [lockedLog containsString:@"admin save failed"];
            extraPassword = !passwordOnly && [lockedLog containsString:@"asking for the password"];

            chflags(file.fileSystemRepresentation, 0);
            chmod(dir.fileSystemRepresentation, 0755);
        }
        [fm removeItemAtPath:dir error:nil];

        CHECK(plain);
        CHECK(!missing);
        CHECK(quietLog && ![quietLog containsString:@"[AdminSave]"]);
        CHECK(admin);
        CHECK(inPlace);
        CHECK(viaLink);
        CHECK(linkKept);
        CHECK(locked);
        CHECK(lockedTried);
        CHECK(!extraPassword);
        puts(argc > 2 ? "ok: plain save, non-permission failure, admin save in place, save through a symlink, "
                        "locked file refused without an extra password prompt"
                      : "ok: hook installed, plain save, non-permission failure (admin save needs: make test-auth)");
    }
    return 0;
}
