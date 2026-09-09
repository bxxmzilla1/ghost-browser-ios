#import "GBBundle.h"

static NSString *const GBBundleBase = @"https://api.bundle.social";
static NSString *const GBBundleErrorDomain = @"Heavenzy.BundleSocial";

// Where bundle.social sends the browser once the OAuth flow ends (must be http/https). The user just
// closes the in-app Safari sheet afterwards.
static NSString *const GBBundleRedirect = @"https://bundle.social/?heavenzy=connected";

@implementation GBBundle

+ (NSError *)error:(NSString *)msg code:(NSInteger)code {
    return [NSError errorWithDomain:GBBundleErrorDomain code:code userInfo:@{ NSLocalizedDescriptionKey: msg }];
}

/// Dedicated session that ignores whatever proxy / cookie state the host app has.
+ (NSURLSession *)session {
    static NSURLSession *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *c = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        c.timeoutIntervalForRequest = 20;
        c.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
        s = [NSURLSession sessionWithConfiguration:c];
    });
    return s;
}

+ (void)request:(NSString *)method path:(NSString *)path key:(NSString *)apiKey body:(NSDictionary *)body
     completion:(void (^)(NSDictionary *json, NSError *error))completion {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[GBBundleBase stringByAppendingString:path]]];
    req.HTTPMethod = method;
    [req setValue:apiKey forHTTPHeaderField:@"x-api-key"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (body) {
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    }
    [[[self session] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSDictionary *json = nil;
        NSError *outErr = err;
        NSInteger status = [(NSHTTPURLResponse *)resp statusCode];
        if (data.length) {
            id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([parsed isKindOfClass:NSDictionary.class]) json = parsed;
        }
        if (!outErr && (status < 200 || status >= 300)) {
            NSString *msg = json[@"message"] ?: [NSString stringWithFormat:@"HTTP %ld", (long)status];
            if (status == 401 || status == 403) msg = [@"API key rejected: " stringByAppendingString:msg];
            outErr = [self error:msg code:status];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(outErr ? nil : json, outErr); });
    }] resume];
}

+ (void)organizationWithKey:(NSString *)apiKey
                 completion:(void (^)(NSString *, NSArray<NSDictionary *> *, NSError *))completion {
    if (apiKey.length == 0) { completion(nil, nil, [self error:@"No Bundle.social API key set. Add it in Settings." code:0]); return; }
    [self request:@"GET" path:@"/api/v1/organization/" key:apiKey body:nil completion:^(NSDictionary *json, NSError *error) {
        if (error) { completion(nil, nil, error); return; }
        NSArray *teams = [json[@"teams"] isKindOfClass:NSArray.class] ? json[@"teams"] : @[];
        completion(json[@"name"] ?: @"Organization", teams, nil);
    }];
}

+ (void)instagramConnectURLWithKey:(NSString *)apiKey
                            teamId:(NSString *)teamId
                        completion:(void (^)(NSURL *, NSString *, NSError *))completion {
    [self organizationWithKey:apiKey completion:^(NSString *orgName, NSArray<NSDictionary *> *teams, NSError *error) {
        if (error) { completion(nil, nil, error); return; }
        NSDictionary *team = nil;
        if (teamId.length) {
            for (NSDictionary *t in teams) { if ([t[@"id"] isEqualToString:teamId]) { team = t; break; } }
            if (!team) team = @{ @"id": teamId, @"name": teamId };   // trust the id the user typed
        } else {
            team = teams.firstObject;
        }
        if (!team) { completion(nil, nil, [self error:@"Your Bundle.social organization has no team yet. Create one in the dashboard." code:0]); return; }

        NSDictionary *body = @{
            @"type": @"INSTAGRAM",
            @"teamId": team[@"id"],
            @"redirectUrl": GBBundleRedirect,
            @"instagramConnectionMethod": @"INSTAGRAM",
            // We are already *inside* the Instagram app; never let the OAuth page deep-link back into it.
            @"forceBrowserOAuth": @YES,
        };
        [self request:@"POST" path:@"/api/v1/social-account/connect" key:apiKey body:body completion:^(NSDictionary *json, NSError *err2) {
            if (err2) { completion(nil, nil, err2); return; }
            NSURL *url = [json[@"url"] isKindOfClass:NSString.class] ? [NSURL URLWithString:json[@"url"]] : nil;
            if (!url) { completion(nil, nil, [self error:@"bundle.social did not return a connect URL." code:0]); return; }
            completion(url, team[@"name"] ?: @"team", nil);
        }];
    }];
}

@end
