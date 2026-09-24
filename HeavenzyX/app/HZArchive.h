#import <Foundation/Foundation.h>

/// Minimal, dependency-free .tar.gz packer/unpacker (ustar + GNU long-name entries, gzip via zlib).
/// Used to move a saved-login snapshot folder to and from the cloud as one file. Streams both ways,
/// so a multi-hundred-MB container never has to fit in memory.
@interface HZArchive : NSObject

/// Pack everything under `dir` (relative paths, regular files, folders and symlinks) into `gzPath`.
+ (BOOL)packDirectory:(NSString *)dir toFile:(NSString *)gzPath error:(NSError **)error;

/// Unpack `gzPath` into `dir` (created if missing). Entries that would escape `dir` are refused.
+ (BOOL)unpackFile:(NSString *)gzPath toDirectory:(NSString *)dir error:(NSError **)error;

@end
