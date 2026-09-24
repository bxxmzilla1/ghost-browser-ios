#import <Foundation/Foundation.h>

/// Supabase-backed account for the control app: email/password auth, a `containers` table for
/// saved-login metadata, and a private `containers` storage bucket for the archives themselves.
/// Everything is plain REST (GoTrue / PostgREST / Storage) over NSURLSession — no SDK.
///
/// The project URL + anon key come from HZConfig (Settings → Account). The signed-in session is kept
/// in the control app's keychain and refreshed automatically before it expires.
///
/// Cloud container rows (NSDictionary) carry the table columns:
///   id, bundle_id, app_name, name, saved_at (ISO-8601), app_version, app_build, bytes,
///   storage_path, identity (dict), device, created_at
@interface HZCloud : NSObject

+ (instancetype)shared;

/// URL + anon key are set.
@property (nonatomic, readonly) BOOL configured;
@property (nonatomic, readonly) BOOL signedIn;
@property (nonatomic, readonly, copy) NSString *email;
@property (nonatomic, readonly, copy) NSString *userId;

/// Posted on the main queue whenever the session changes (sign in / out / refresh failure).
extern NSString *const HZCloudSessionDidChangeNotification;

#pragma mark Auth
/// `needsConfirm` is YES when the project requires email confirmation before the first sign-in.
- (void)signUpWithEmail:(NSString *)email password:(NSString *)password
             completion:(void (^)(BOOL needsConfirm, NSError *error))completion;
- (void)signInWithEmail:(NSString *)email password:(NSString *)password completion:(void (^)(NSError *error))completion;
- (void)signOut:(void (^)(void))completion;
/// Round-trip to the auth server. If the account was deleted/revoked the session is cleared (and
/// HZCloudSessionDidChangeNotification posted); a plain network failure leaves it signed in.
- (void)validateSession:(void (^)(BOOL valid, NSError *error))completion;

#pragma mark Containers
/// Rows for one app (or every app when bundleId is nil), newest first.
- (void)listContainersForApp:(NSString *)bundleId completion:(void (^)(NSArray<NSDictionary *> *rows, NSError *error))completion;

/// Pack a local snapshot folder, upload it, and upsert its metadata row (same app + name replaces
/// the previous upload). `progress` is 0…1 for the upload leg; completion delivers the row.
- (void)uploadSnapshotAtPath:(NSString *)dir
                        meta:(NSDictionary *)meta      // entry from +[HZConfig snapshotsForApp:]
                      forApp:(NSString *)bundleId
                     appName:(NSString *)appName
                    progress:(void (^)(double fraction))progress
                  completion:(void (^)(NSDictionary *row, NSError *error))completion;

/// Download a row's archive and unpack it into `<appDir>/<name>` (replacing anything there).
- (void)downloadContainer:(NSDictionary *)row
           toSnapshotsDir:(NSString *)appDir
                 progress:(void (^)(double fraction))progress
               completion:(void (^)(NSString *localDir, NSError *error))completion;

- (void)renameContainer:(NSDictionary *)row to:(NSString *)name completion:(void (^)(NSError *error))completion;
- (void)deleteContainer:(NSDictionary *)row completion:(void (^)(NSError *error))completion;

@end
