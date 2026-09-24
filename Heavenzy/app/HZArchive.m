#import "HZArchive.h"
#import <zlib.h>
#import <sys/stat.h>

static NSString *const HZArchiveErrorDomain = @"com.heavenzy.archive";
static NSError *HZArchiveError(NSString *msg) {
    return [NSError errorWithDomain:HZArchiveErrorDomain code:1 userInfo:@{ NSLocalizedDescriptionKey: msg }];
}

#define TAR_BLOCK 512
#define IO_CHUNK  (256 * 1024)

#pragma mark - gzip writer (deflate stream → FILE*)

typedef struct {
    z_stream z;
    FILE *out;
    unsigned char buf[IO_CHUNK];
    BOOL failed;
} HZGzWriter;

static BOOL HZGzOpen(HZGzWriter *w, NSString *path) {
    memset(w, 0, sizeof(*w));
    w->out = fopen(path.fileSystemRepresentation, "wb");
    if (!w->out) return NO;
    // 15 + 16 = 32 KB window, gzip wrapper.
    if (deflateInit2(&w->z, 6, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY) != Z_OK) { fclose(w->out); w->out = NULL; return NO; }
    return YES;
}

static BOOL HZGzWrite(HZGzWriter *w, const void *data, size_t len, int flush) {
    if (w->failed) return NO;
    w->z.next_in = (Bytef *)data;
    w->z.avail_in = (uInt)len;
    do {
        w->z.next_out = w->buf;
        w->z.avail_out = sizeof(w->buf);
        int rc = deflate(&w->z, flush);
        if (rc == Z_STREAM_ERROR) { w->failed = YES; return NO; }
        size_t have = sizeof(w->buf) - w->z.avail_out;
        if (have && fwrite(w->buf, 1, have, w->out) != have) { w->failed = YES; return NO; }
    } while (w->z.avail_out == 0);
    return YES;
}

static BOOL HZGzClose(HZGzWriter *w) {
    BOOL ok = !w->failed && HZGzWrite(w, "", 0, Z_FINISH);
    deflateEnd(&w->z);
    if (w->out) { if (fclose(w->out) != 0) ok = NO; w->out = NULL; }
    return ok;
}

#pragma mark - tar header

// POSIX ustar header layout.
typedef struct {
    char name[100];
    char mode[8];
    char uid[8];
    char gid[8];
    char size[12];
    char mtime[12];
    char chksum[8];
    char typeflag;
    char linkname[100];
    char magic[6];
    char version[2];
    char uname[32];
    char gname[32];
    char devmajor[8];
    char devminor[8];
    char prefix[155];
    char pad[12];
} HZTarHeader;

static void HZOctal(char *field, size_t len, unsigned long long v) {
    // Zero-padded octal, NUL-terminated (len-1 digits).
    snprintf(field, len, "%0*llo", (int)(len - 1), v);
}

static void HZFinishHeader(HZTarHeader *h) {
    memcpy(h->magic, "ustar", 6);           // "ustar\0"
    memcpy(h->version, "00", 2);
    memset(h->chksum, ' ', sizeof(h->chksum));
    unsigned sum = 0;
    const unsigned char *p = (const unsigned char *)h;
    for (size_t i = 0; i < TAR_BLOCK; i++) sum += p[i];
    snprintf(h->chksum, sizeof(h->chksum), "%06o", sum);
    h->chksum[6] = '\0';
    h->chksum[7] = ' ';
}

static BOOL HZWritePadded(HZGzWriter *w, const void *data, size_t len) {
    if (!HZGzWrite(w, data, len, Z_NO_FLUSH)) return NO;
    size_t rem = len % TAR_BLOCK;
    if (rem) {
        static const char zeros[TAR_BLOCK] = {0};
        return HZGzWrite(w, zeros, TAR_BLOCK - rem, Z_NO_FLUSH);
    }
    return YES;
}

// GNU long-name / long-link pseudo entry ('L' / 'K').
static BOOL HZWriteLongEntry(HZGzWriter *w, char type, const char *value) {
    size_t len = strlen(value) + 1;
    HZTarHeader h; memset(&h, 0, sizeof(h));
    strncpy(h.name, "././@LongLink", sizeof(h.name) - 1);
    HZOctal(h.mode, sizeof(h.mode), 0644);
    HZOctal(h.uid, sizeof(h.uid), 0);
    HZOctal(h.gid, sizeof(h.gid), 0);
    HZOctal(h.size, sizeof(h.size), len);
    HZOctal(h.mtime, sizeof(h.mtime), 0);
    h.typeflag = type;
    HZFinishHeader(&h);
    return HZGzWrite(w, &h, TAR_BLOCK, Z_NO_FLUSH) && HZWritePadded(w, value, len);
}

// Fill name/prefix for `path`; falls back to a GNU 'L' entry when it can't be split ustar-style.
static BOOL HZWriteEntryHeader(HZGzWriter *w, const char *path, const char *link, unsigned long long size,
                               unsigned mode, time_t mtime, char type) {
    HZTarHeader h; memset(&h, 0, sizeof(h));
    size_t plen = strlen(path);
    if (plen < sizeof(h.name)) {
        memcpy(h.name, path, plen);
    } else {
        // Try ustar prefix/name split at a '/'.
        BOOL split = NO;
        for (size_t i = plen - 1; i > 0; i--) {
            if (path[i] == '/' && i < sizeof(h.prefix) && (plen - i - 1) < sizeof(h.name) && (plen - i - 1) > 0) {
                memcpy(h.prefix, path, i);
                memcpy(h.name, path + i + 1, plen - i - 1);
                split = YES;
                break;
            }
        }
        if (!split) {
            if (!HZWriteLongEntry(w, 'L', path)) return NO;
            memcpy(h.name, path, sizeof(h.name) - 1);
        }
    }
    if (link) {
        size_t llen = strlen(link);
        if (llen >= sizeof(h.linkname)) {
            if (!HZWriteLongEntry(w, 'K', link)) return NO;
            memcpy(h.linkname, link, sizeof(h.linkname) - 1);
        } else {
            memcpy(h.linkname, link, llen);
        }
    }
    HZOctal(h.mode, sizeof(h.mode), mode & 07777);
    HZOctal(h.uid, sizeof(h.uid), 501);
    HZOctal(h.gid, sizeof(h.gid), 501);
    HZOctal(h.size, sizeof(h.size), size);
    HZOctal(h.mtime, sizeof(h.mtime), (unsigned long long)MAX(mtime, 0));
    h.typeflag = type;
    strncpy(h.uname, "mobile", sizeof(h.uname) - 1);
    strncpy(h.gname, "mobile", sizeof(h.gname) - 1);
    HZFinishHeader(&h);
    return HZGzWrite(w, &h, TAR_BLOCK, Z_NO_FLUSH);
}

#pragma mark - Pack

@implementation HZArchive

+ (BOOL)packDirectory:(NSString *)dir toFile:(NSString *)gzPath error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) {
        if (error) *error = HZArchiveError(@"snapshot folder not found");
        return NO;
    }
    [fm removeItemAtPath:gzPath error:nil];
    HZGzWriter w;
    if (!HZGzOpen(&w, gzPath)) { if (error) *error = HZArchiveError(@"couldn't create the archive file"); return NO; }

    // Enumerate without following symlinks so a link is stored as a link, not as its target.
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:dir];
    NSString *rel;
    BOOL ok = YES;
    while (ok && (rel = [en nextObject])) {
        NSString *full = [dir stringByAppendingPathComponent:rel];
        NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];   // does not follow symlinks
        NSString *type = attrs.fileType;
        unsigned mode = (unsigned)[attrs filePosixPermissions];
        time_t mtime = (time_t)[attrs.fileModificationDate timeIntervalSince1970];
        const char *cpath = rel.UTF8String;

        if ([type isEqualToString:NSFileTypeDirectory]) {
            NSString *withSlash = [rel stringByAppendingString:@"/"];
            ok = HZWriteEntryHeader(&w, withSlash.UTF8String, NULL, 0, mode ?: 0755, mtime, '5');
        } else if ([type isEqualToString:NSFileTypeSymbolicLink]) {
            NSString *dest = [fm destinationOfSymbolicLinkAtPath:full error:nil] ?: @"";
            ok = HZWriteEntryHeader(&w, cpath, dest.UTF8String, 0, 0777, mtime, '2');
        } else if ([type isEqualToString:NSFileTypeRegular]) {
            unsigned long long size = attrs.fileSize;
            ok = HZWriteEntryHeader(&w, cpath, NULL, size, mode ?: 0644, mtime, '0');
            if (!ok) break;
            FILE *in = fopen(full.fileSystemRepresentation, "rb");
            if (!in) { ok = NO; break; }
            unsigned long long written = 0;
            unsigned char *buf = malloc(IO_CHUNK);
            while (written < size) {
                size_t want = (size_t)MIN((unsigned long long)IO_CHUNK, size - written);
                size_t got = fread(buf, 1, want, in);
                if (got == 0) break;   // file shrank underneath us — pad the rest with zeros below
                if (!HZGzWrite(&w, buf, got, Z_NO_FLUSH)) { ok = NO; break; }
                written += got;
            }
            fclose(in);
            if (ok && written < size) {
                // Keep the archive consistent with the header we already wrote.
                memset(buf, 0, IO_CHUNK);
                while (ok && written < size) {
                    size_t n = (size_t)MIN((unsigned long long)IO_CHUNK, size - written);
                    ok = HZGzWrite(&w, buf, n, Z_NO_FLUSH);
                    written += n;
                }
            }
            free(buf);
            if (ok) {
                size_t rem = size % TAR_BLOCK;
                if (rem) { static const char zeros[TAR_BLOCK] = {0}; ok = HZGzWrite(&w, zeros, TAR_BLOCK - rem, Z_NO_FLUSH); }
            }
        }
        // Sockets, devices, etc. are skipped.
    }
    if (ok) {
        static const char end[TAR_BLOCK * 2] = {0};   // two zero blocks terminate the archive
        ok = HZGzWrite(&w, end, sizeof(end), Z_NO_FLUSH);
    }
    BOOL closed = HZGzClose(&w);
    if (!ok || !closed) {
        [fm removeItemAtPath:gzPath error:nil];
        if (error) *error = HZArchiveError(@"failed while writing the archive (disk full?)");
        return NO;
    }
    return YES;
}

#pragma mark - Unpack

// Inflate the whole .gz to a temporary .tar (containers can be large; two simple passes beat a
// fragile single-pass block parser over an inflate stream).
static BOOL HZGunzipToFile(NSString *gzPath, NSString *tarPath) {
    FILE *in = fopen(gzPath.fileSystemRepresentation, "rb");
    if (!in) return NO;
    FILE *out = fopen(tarPath.fileSystemRepresentation, "wb");
    if (!out) { fclose(in); return NO; }
    z_stream z; memset(&z, 0, sizeof(z));
    if (inflateInit2(&z, 15 + 32) != Z_OK) { fclose(in); fclose(out); return NO; }   // auto gzip/zlib
    unsigned char *ibuf = malloc(IO_CHUNK), *obuf = malloc(IO_CHUNK);
    BOOL ok = YES; int rc = Z_OK;
    while (ok && rc != Z_STREAM_END) {
        size_t got = fread(ibuf, 1, IO_CHUNK, in);
        if (got == 0) { ok = NO; break; }   // truncated
        z.next_in = ibuf; z.avail_in = (uInt)got;
        do {
            z.next_out = obuf; z.avail_out = IO_CHUNK;
            rc = inflate(&z, Z_NO_FLUSH);
            if (rc != Z_OK && rc != Z_STREAM_END) { ok = NO; break; }
            size_t have = IO_CHUNK - z.avail_out;
            if (have && fwrite(obuf, 1, have, out) != have) { ok = NO; break; }
        } while (z.avail_out == 0 && rc != Z_STREAM_END);
    }
    inflateEnd(&z);
    free(ibuf); free(obuf);
    fclose(in);
    if (fclose(out) != 0) ok = NO;
    return ok;
}

static unsigned long long HZParseOctal(const char *field, size_t len) {
    unsigned long long v = 0;
    for (size_t i = 0; i < len && field[i]; i++) {
        if (field[i] == ' ') continue;
        if (field[i] < '0' || field[i] > '7') break;
        v = v * 8 + (unsigned)(field[i] - '0');
    }
    return v;
}

static BOOL HZHeaderIsZero(const HZTarHeader *h) {
    const unsigned char *p = (const unsigned char *)h;
    for (size_t i = 0; i < TAR_BLOCK; i++) if (p[i]) return NO;
    return YES;
}

static NSString *HZFieldString(const char *field, size_t len) {
    size_t n = strnlen(field, len);
    return [[NSString alloc] initWithBytes:field length:n encoding:NSUTF8StringEncoding] ?: @"";
}

// Reject anything that could escape the destination.
static NSString *HZSafeRelativePath(NSString *rel) {
    NSString *r = rel;
    while ([r hasPrefix:@"/"]) r = [r substringFromIndex:1];
    if (r.length == 0) return nil;
    for (NSString *comp in [r pathComponents]) if ([comp isEqualToString:@".."]) return nil;
    return r;
}

+ (BOOL)unpackFile:(NSString *)gzPath toDirectory:(NSString *)dir error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *tarPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"hz-%@.tar", NSUUID.UUID.UUIDString]];
    if (!HZGunzipToFile(gzPath, tarPath)) {
        [fm removeItemAtPath:tarPath error:nil];
        if (error) *error = HZArchiveError(@"the downloaded archive is corrupt or incomplete");
        return NO;
    }
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

    FILE *in = fopen(tarPath.fileSystemRepresentation, "rb");
    if (!in) { [fm removeItemAtPath:tarPath error:nil]; if (error) *error = HZArchiveError(@"couldn't read the archive"); return NO; }

    BOOL ok = YES;
    NSString *pendingLongName = nil, *pendingLongLink = nil;
    unsigned char *buf = malloc(IO_CHUNK);
    HZTarHeader h;
    while (ok) {
        if (fread(&h, 1, TAR_BLOCK, in) != TAR_BLOCK) break;   // EOF without end blocks — tolerate
        if (HZHeaderIsZero(&h)) break;
        unsigned long long size = HZParseOctal(h.size, sizeof(h.size));
        unsigned long long padded = (size + TAR_BLOCK - 1) / TAR_BLOCK * TAR_BLOCK;

        if (h.typeflag == 'L' || h.typeflag == 'K') {
            // GNU long name / long link: payload is the string for the *next* header.
            if (size > 64 * 1024) { ok = NO; break; }
            NSMutableData *d = [NSMutableData dataWithLength:(NSUInteger)padded];
            if (fread(d.mutableBytes, 1, (size_t)padded, in) != padded) { ok = NO; break; }
            NSString *s = [[NSString alloc] initWithBytes:d.bytes length:(NSUInteger)strnlen(d.bytes, (size_t)size) encoding:NSUTF8StringEncoding];
            if (h.typeflag == 'L') pendingLongName = s; else pendingLongLink = s;
            continue;
        }

        NSString *name = pendingLongName;
        if (!name) {
            NSString *prefix = (memcmp(h.magic, "ustar", 5) == 0) ? HZFieldString(h.prefix, sizeof(h.prefix)) : @"";
            NSString *base = HZFieldString(h.name, sizeof(h.name));
            name = prefix.length ? [prefix stringByAppendingPathComponent:base] : base;
        }
        NSString *link = pendingLongLink ?: HZFieldString(h.linkname, sizeof(h.linkname));
        pendingLongName = nil; pendingLongLink = nil;

        NSString *rel = HZSafeRelativePath(name);
        NSString *dest = rel ? [dir stringByAppendingPathComponent:rel] : nil;
        unsigned mode = (unsigned)HZParseOctal(h.mode, sizeof(h.mode));
        char type = h.typeflag;
        if (type == '\0') type = [name hasSuffix:@"/"] ? '5' : '0';

        if (!dest) {
            // Unsafe path: skip payload.
            if (padded && fseeko(in, (off_t)padded, SEEK_CUR) != 0) { ok = NO; break; }
            continue;
        }

        if (type == '5') {
            [fm createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:nil];
            if (padded) fseeko(in, (off_t)padded, SEEK_CUR);
        } else if (type == '2') {
            [fm createDirectoryAtPath:dest.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
            [fm removeItemAtPath:dest error:nil];
            [fm createSymbolicLinkAtPath:dest withDestinationPath:link error:nil];
            if (padded) fseeko(in, (off_t)padded, SEEK_CUR);
        } else if (type == '0' || type == '7') {
            [fm createDirectoryAtPath:dest.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
            [fm removeItemAtPath:dest error:nil];
            FILE *out = fopen(dest.fileSystemRepresentation, "wb");
            if (!out) { ok = NO; break; }
            unsigned long long left = size;
            while (left) {
                size_t want = (size_t)MIN((unsigned long long)IO_CHUNK, left);
                size_t got = fread(buf, 1, want, in);
                if (got == 0 || fwrite(buf, 1, got, out) != got) { ok = NO; break; }
                left -= got;
            }
            fclose(out);
            if (!ok) break;
            if (padded > size) fseeko(in, (off_t)(padded - size), SEEK_CUR);
            if (mode) chmod(dest.fileSystemRepresentation, (mode_t)(mode & 07777));
        } else {
            // Unsupported entry type (hard link, device, etc.) — skip.
            if (padded && fseeko(in, (off_t)padded, SEEK_CUR) != 0) { ok = NO; break; }
        }
    }
    free(buf);
    fclose(in);
    [fm removeItemAtPath:tarPath error:nil];
    if (!ok) {
        if (error) *error = HZArchiveError(@"failed while extracting the archive (disk full or corrupt file)");
        return NO;
    }
    return YES;
}

@end
