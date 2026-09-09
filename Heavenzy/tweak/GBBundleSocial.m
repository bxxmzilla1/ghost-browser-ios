#import "GBBundleSocial.h"

static NSString *const kBase = @"https://api.bundle.social";

@implementation GBBundleSocial

+ (void)finish:(void (^)(NSURL *, NSString *))completion url:(NSURL *)url error:(NSString *)error {
    dispatch_async(dispatch_get_main_queue(), ^{ completion(url, error); });
}

// Build an x-api-key request for a path under the base URL.
+ (NSMutableURLRequest *)requestFor:(NSString *)path method:(NSString *)method key:(NSString *)key {
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[kBase stringByAppendingString:path]]];
    r.HTTPMethod = method;
    [r setValue:key forHTTPHeaderField:@"x-api-key"];
    [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [r setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    r.timeoutInterval = 25;
    return r;
}

// Turn common HTTP failures into a readable message.
+ (NSString *)messageForStatus:(NSInteger)status data:(NSData *)data {
    if (status == 401) return @"Bundle.social rejected the API key (401). Check it in the Heavenzy app → Settings.";
    if (status == 403) return @"That API key isn't allowed (403). Paste a valid org key in Settings.";
    NSString *body = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
    if (body.length > 300) body = [body substringToIndex:300];
    return [NSString stringWithFormat:@"Bundle.social error (%ld). %@", (long)status, body ?: @""];
}

+ (void)instagramPortalWithKey:(NSString *)key team:(NSString *)team completion:(void (^)(NSURL *, NSString *))completion {
    if (key.length == 0) { [self finish:completion url:nil error:@"No Bundle.social API key yet. Add it in the Heavenzy app → Settings."]; return; }
    if (team.length) { [self createPortalWithKey:key team:team completion:completion]; return; }

    // No team id supplied — discover one from the organization first.
    NSURLRequest *r = [self requestFor:@"/api/v1/organization" method:@"GET" key:key];
    [[[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger status = [(NSHTTPURLResponse *)resp statusCode];
        if (err) { [self finish:completion url:nil error:[NSString stringWithFormat:@"Network error: %@", err.localizedDescription]]; return; }
        if (status < 200 || status >= 300) { [self finish:completion url:nil error:[self messageForStatus:status data:data]]; return; }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
        NSArray *teams = [json isKindOfClass:NSDictionary.class] ? json[@"teams"] : nil;
        NSString *tid = ([teams isKindOfClass:NSArray.class] && teams.count) ? teams.firstObject[@"id"] : nil;
        if (tid.length == 0) { [self finish:completion url:nil error:@"No team found on this Bundle.social account. Create a team first, or set a Team ID in Settings."]; return; }
        [self createPortalWithKey:key team:tid completion:completion];
    }] resume];
}

+ (void)createPortalWithKey:(NSString *)key team:(NSString *)team completion:(void (^)(NSURL *, NSString *))completion {
    NSMutableURLRequest *r = [self requestFor:@"/api/v1/social-account/create-portal-link" method:@"POST" key:key];
    NSDictionary *body = @{ @"teamId": team,
                            @"socialAccountTypes": @[ @"INSTAGRAM" ],
                            @"instagramConnectionMethod": @"INSTAGRAM" };   // direct IG OAuth (no Facebook page picker)
    r.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [[[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger status = [(NSHTTPURLResponse *)resp statusCode];
        if (err) { [self finish:completion url:nil error:[NSString stringWithFormat:@"Network error: %@", err.localizedDescription]]; return; }
        if (status < 200 || status >= 300) { [self finish:completion url:nil error:[self messageForStatus:status data:data]]; return; }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
        NSString *urlStr = [json isKindOfClass:NSDictionary.class] ? json[@"url"] : nil;
        NSURL *url = urlStr.length ? [NSURL URLWithString:urlStr] : nil;
        if (!url) { [self finish:completion url:nil error:@"Bundle.social didn't return a connect link."]; return; }
        [self finish:completion url:url error:nil];
    }] resume];
}

@end
