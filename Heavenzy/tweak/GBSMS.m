#import "GBSMS.h"
#import "GBStore.h"

static NSString *const kDiddyBase   = @"https://api.diddysms.com/v1";
static NSString *const kGrizzlyBase = @"https://api.grizzlysms.com/stubs/handler_api.php";
// sms-activate numeric country ids GrizzlySMS uses for its two US pools (same as Sessions X):
//   187 = USA (real carrier numbers)     12 = USA (virtual) — cheaper, huge stock
static NSString *const kUSACountry        = @"187";
static NSString *const kUSAVirtualCountry = @"12";

// Brand → GrizzlySMS (sms-activate) short service code — same table Sessions X uses.
static NSDictionary *GBGrizzlyServiceMap(void) {
    return @{ @"instagram": @"ig", @"threads": @"ig", @"facebook": @"fb", @"fb": @"fb",
              @"google": @"go", @"gmail": @"go", @"youtube": @"go",
              @"tiktok": @"lf", @"discord": @"ds", @"telegram": @"tg", @"whatsapp": @"wa",
              @"twitter": @"tw", @"x": @"tw", @"snapchat": @"fu", @"reddit": @"re",
              @"microsoft": @"mm", @"outlook": @"mm", @"hotmail": @"mm", @"yahoo": @"mb",
              @"amazon": @"am", @"apple": @"wx", @"tinder": @"oi", @"bumble": @"mo", @"signal": @"bw",
              @"linkedin": @"tn", @"pinterest": @"mj", @"twitch": @"ze", @"paypal": @"ts", @"netflix": @"nf" };
}

static NSString *GBDigits(NSString *s) {
    if (![s isKindOfClass:NSString.class]) return @"";
    NSMutableString *o = [NSMutableString string];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= '0' && c <= '9') [o appendFormat:@"%C", c];
    }
    return o;
}

@implementation GBSMS

+ (NSString *)appBrand {
    NSString *name = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if (name.length == 0) name = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
    if (name.length == 0) name = [[NSBundle mainBundle] bundleIdentifier];
    NSMutableString *o = [NSMutableString string];
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar c = [name.lowercaseString characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) [o appendFormat:@"%C", c];
    }
    return o;
}

+ (BOOL)useGrizzly { return [[GBStore shared].smsProvider isEqualToString:@"grizzly"]; }
+ (NSString *)currentProvider { return [self useGrizzly] ? @"grizzly" : @"diddy"; }
+ (NSString *)providerLabel { return [self useGrizzly] ? @"GrizzlySMS" : @"DiddySMS"; }

+ (NSString *)grizzlyServiceCode {
    NSString *brand = [self appBrand];
    NSString *code = GBGrizzlyServiceMap()[brand];
    if (code.length) return code;
    if (brand.length && brand.length <= 4) return brand;   // allow a raw short code
    return @"";
}

+ (NSString *)serviceLabel {
    if ([self useGrizzly]) { NSString *c = [self grizzlyServiceCode]; return c.length ? c : @"?"; }
    NSString *b = [self appBrand]; return b.length ? b : @"?";
}

// Which GrizzlySMS US pool the user picked in Settings ("virtual" → 12, anything else → 187).
+ (BOOL)grizzlyUsesVirtual { return [self useGrizzly] && [[GBStore shared].grizzlyCountry isEqualToString:@"virtual"]; }
+ (NSString *)grizzlyCountryCode { return [self grizzlyUsesVirtual] ? kUSAVirtualCountry : kUSACountry; }
+ (NSString *)grizzlyCountryName:(NSString *)code { return [code isEqualToString:kUSAVirtualCountry] ? @"USA (virtual)" : @"USA"; }

+ (NSString *)countryLabel {
    if ([self useGrizzly]) return [self grizzlyCountryName:[self grizzlyCountryCode]];
    return @"USA";
}

#pragma mark - HTTP helpers

+ (void)mainCompletion:(void (^)(id, id, id, id))block a:(id)a b:(id)b c:(id)c d:(id)d {
    dispatch_async(dispatch_get_main_queue(), ^{ block(a, b, c, d); });
}

// Normalise a DiddySMS key: strip an accidental leading "Bearer ".
+ (NSString *)diddyKeyNormalized {
    NSString *k = [[GBStore shared].diddyKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if ([k.lowercaseString hasPrefix:@"bearer "]) k = [[k substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return k;
}

+ (NSMutableURLRequest *)diddyRequest:(NSString *)path method:(NSString *)method key:(NSString *)key body:(NSDictionary *)body {
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[kDiddyBase stringByAppendingString:path]]];
    r.HTTPMethod = method;
    [r setValue:[NSString stringWithFormat:@"Bearer %@", key] forHTTPHeaderField:@"Authorization"];
    [r setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    r.timeoutInterval = 25;
    if (body) {
        [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        r.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    }
    return r;
}

#pragma mark - Request number

+ (void)requestNumberWithCompletion:(void (^)(NSString *, NSString *, NSString *, NSString *))completion {
    [[GBStore shared] reloadSmsSettings];   // honour a provider/key switch made in the Heavenzy app
    if ([self useGrizzly]) [self grizzlyRequest:completion];
    else                   [self diddyRequest:completion];
}

// GrizzlySMS getNumber → "ACCESS_NUMBER:<id>:<phone>"
+ (void)grizzlyRequest:(void (^)(NSString *, NSString *, NSString *, NSString *))completion {
    NSString *key = [[GBStore shared].grizzlyKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if (key.length == 0) { [self mainCompletion:completion a:nil b:nil c:nil d:@"Add your GrizzlySMS API key in the Heavenzy app → Settings."]; return; }
    NSString *service = [self grizzlyServiceCode];
    if (service.length == 0) { [self mainCompletion:completion a:nil b:nil c:nil d:[NSString stringWithFormat:@"No GrizzlySMS service code for “%@”.", [self appBrand]]]; return; }

    // Try the pool chosen in Settings first; if it's sold out, fall back to the other US pool
    // (Sessions X does the same: 187 → 12, 12 → 187).
    NSString *primary = [self grizzlyCountryCode];
    NSString *other   = [primary isEqualToString:kUSAVirtualCountry] ? kUSACountry : kUSAVirtualCountry;
    [self grizzlyGetNumber:key service:service countries:@[ primary, other ] index:0 completion:completion];
}

+ (void)grizzlyGetNumber:(NSString *)key service:(NSString *)service countries:(NSArray<NSString *> *)countries
                   index:(NSUInteger)idx completion:(void (^)(NSString *, NSString *, NSString *, NSString *))completion {
    NSString *country = countries[idx];
    NSURLComponents *comp = [NSURLComponents componentsWithString:kGrizzlyBase];
    NSMutableArray *q = [@[ [NSURLQueryItem queryItemWithName:@"api_key" value:key],
                           [NSURLQueryItem queryItemWithName:@"action" value:@"getNumber"],
                           [NSURLQueryItem queryItemWithName:@"service" value:service],
                           [NSURLQueryItem queryItemWithName:@"country" value:country] ] mutableCopy];
    NSString *maxPrice = [[GBStore shared].grizzlyMaxPrice stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (maxPrice.length) [q addObject:[NSURLQueryItem queryItemWithName:@"maxPrice" value:maxPrice]];
    comp.queryItems = q;

    NSURLRequest *r = [NSURLRequest requestWithURL:comp.URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:25];
    [[[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) { [self mainCompletion:completion a:nil b:nil c:nil d:[NSString stringWithFormat:@"Network error: %@", err.localizedDescription]]; return; }
        NSString *text = [[[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
        if ([text hasPrefix:@"ACCESS_NUMBER:"]) {
            NSArray *parts = [text componentsSeparatedByString:@":"];
            if (parts.count >= 3) {
                NSString *orderId = parts[1];
                NSString *phone = GBDigits(parts[2]);
                NSLog(@"[Heavenzy][SMS] GrizzlySMS number %@ from %@%@", phone, [self grizzlyCountryName:country],
                      idx ? @" (fallback pool)" : @"");
                [self mainCompletion:completion a:phone b:orderId c:service d:nil];
                return;
            }
        }
        // Sold out in this pool → try the next one before giving up.
        if ([text isEqualToString:@"NO_NUMBERS"] && idx + 1 < countries.count) {
            NSLog(@"[Heavenzy][SMS] GrizzlySMS %@ has no numbers — trying %@", [self grizzlyCountryName:country],
                  [self grizzlyCountryName:countries[idx + 1]]);
            [self grizzlyGetNumber:key service:service countries:countries index:idx + 1 completion:completion];
            return;
        }
        [self mainCompletion:completion a:nil b:nil c:nil d:[NSString stringWithFormat:@"GrizzlySMS: %@", [self grizzlyMessage:text]]];
    }] resume];
}

+ (NSString *)grizzlyMessage:(NSString *)resp {
    NSDictionary *m = @{ @"BAD_KEY": @"Invalid GrizzlySMS API key — check it in Settings.",
                         @"NO_BALANCE": @"GrizzlySMS balance is empty — top up your account.",
                         @"NO_NUMBERS": @"No numbers available in either US pool right now — try again.",
                         @"BAD_SERVICE": @"Unknown service code for this app.",
                         @"SERVICE_UNAVAILABLE_REGION": @"GrizzlySMS is blocked from this IP/region.",
                         @"BAD_ACTION": @"Request rejected (bad action)." };
    NSString *t = [resp stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    return m[t] ?: (t.length ? t : @"request failed");
}

// DiddySMS: resolve the service by name, then POST /orders (retrying across carriers).
+ (void)diddyRequest:(void (^)(NSString *, NSString *, NSString *, NSString *))completion {
    NSString *key = [self diddyKeyNormalized];
    if (key.length == 0) { [self mainCompletion:completion a:nil b:nil c:nil d:@"Add your DiddySMS API key in the Heavenzy app → Settings."]; return; }
    NSString *brand = [self appBrand];
    // Search the catalog for the best-matching service name, then order it.
    NSString *searchPath = [NSString stringWithFormat:@"/services?search=%@&per_page=100",
                            [brand stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    NSURLRequest *sr = [self diddyRequest:searchPath method:@"GET" key:key body:nil];
    [[[NSURLSession sharedSession] dataTaskWithRequest:sr completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSString *service = brand;   // fall back to the brand term if the search yields nothing
        if (!err && data) {
            NSDictionary *j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *services = [j isKindOfClass:NSDictionary.class] ? j[@"services"] : nil;
            NSString *best = nil; NSInteger bestScore = 0;
            if ([services isKindOfClass:NSArray.class]) {
                for (NSDictionary *svc in services) {
                    if (![svc isKindOfClass:NSDictionary.class]) continue;
                    NSString *name = [svc[@"name"] isKindOfClass:NSString.class] ? [svc[@"name"] lowercaseString] : @"";
                    NSString *disp = [svc[@"display_name"] isKindOfClass:NSString.class] ? [svc[@"display_name"] lowercaseString] : @"";
                    NSInteger sc = 0;
                    if ([name isEqualToString:brand]) sc += 150;
                    else if ([name hasPrefix:[brand stringByAppendingString:@"_"]]) sc += 85;
                    else if (brand.length >= 4 && [name containsString:brand]) sc += 62;
                    else if (brand.length >= 2 && [name containsString:brand]) sc += 38;
                    if ([disp containsString:brand]) sc += 42;
                    if (sc > bestScore) { bestScore = sc; best = svc[@"name"]; }
                }
            }
            if (best && bestScore >= 28) service = best;
        }
        [self diddyOrder:service key:key carriers:@[ @"", @"tmobile", @"att", @"verizon", @"metropcs", @"boost", @"cricket" ] index:0 completion:completion];
    }] resume];
}

// Try ordering, walking through carriers until one yields a number.
+ (void)diddyOrder:(NSString *)service key:(NSString *)key carriers:(NSArray<NSString *> *)carriers index:(NSUInteger)index
        completion:(void (^)(NSString *, NSString *, NSString *, NSString *))completion {
    if (index >= carriers.count) { [self mainCompletion:completion a:nil b:nil c:nil d:@"DiddySMS: no number available for this app."]; return; }
    NSMutableDictionary *body = [@{ @"service": service } mutableCopy];
    NSString *carrier = carriers[index];
    if (carrier.length) body[@"carrier"] = carrier;
    NSURLRequest *r = [self diddyRequest:@"/orders" method:@"POST" key:key body:body];
    [[[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSDictionary *j = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *order = [j isKindOfClass:NSDictionary.class] && [j[@"order"] isKindOfClass:NSDictionary.class] ? j[@"order"] : nil;
        id oid = order[@"id"];
        if (order && oid && oid != [NSNull null]) {
            NSString *orderId = [oid isKindOfClass:NSString.class] ? oid : [NSString stringWithFormat:@"%@", oid];
            NSString *phone = GBDigits(order[@"phone_number"]);
            [self mainCompletion:completion a:phone b:orderId c:service d:nil];
            return;
        }
        [self diddyOrder:service key:key carriers:carriers index:index + 1 completion:completion];   // try next carrier
    }] resume];
}

#pragma mark - Poll

+ (void)pollOrder:(NSString *)orderId provider:(NSString *)provider completion:(void (^)(NSString *, NSString *))completion {
    if (orderId.length == 0) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, @"no order"); }); return; }
    if ([provider isEqualToString:@"grizzly"]) {
        NSString *key = [[GBStore shared].grizzlyKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
        NSURLComponents *comp = [NSURLComponents componentsWithString:kGrizzlyBase];
        comp.queryItems = @[ [NSURLQueryItem queryItemWithName:@"api_key" value:key],
                             [NSURLQueryItem queryItemWithName:@"action" value:@"getStatus"],
                             [NSURLQueryItem queryItemWithName:@"id" value:orderId] ];
        NSURLRequest *r = [NSURLRequest requestWithURL:comp.URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:25];
        [[[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            NSString *text = [[[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
            if ([text hasPrefix:@"STATUS_OK:"]) {
                NSString *code = GBDigits([text substringFromIndex:[@"STATUS_OK:" length]]);
                [self cancelOrGrizzlyFinish:orderId status:6 key:key];   // mark used
                dispatch_async(dispatch_get_main_queue(), ^{ completion(code, nil); });
            } else if ([text hasPrefix:@"STATUS_"]) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(@"", nil); });   // still waiting
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSString stringWithFormat:@"GrizzlySMS: %@", [self grizzlyMessage:text]]); });
            }
        }] resume];
        return;
    }
    NSString *key = [self diddyKeyNormalized];
    NSURLRequest *r = [self diddyRequest:[NSString stringWithFormat:@"/orders/%@", orderId] method:@"GET" key:key body:nil];
    [[[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, @"poll failed"); }); return; }
        NSDictionary *j = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *order = [j isKindOfClass:NSDictionary.class] && [j[@"order"] isKindOfClass:NSDictionary.class] ? j[@"order"] : nil;
        NSString *code = order[@"sms_code"] ? GBDigits(order[@"sms_code"]) : @"";
        dispatch_async(dispatch_get_main_queue(), ^{ completion(code, nil); });
    }] resume];
}

#pragma mark - Cancel

+ (void)cancelOrGrizzlyFinish:(NSString *)orderId status:(int)status key:(NSString *)key {
    if (key.length == 0 || orderId.length == 0) return;
    NSURLComponents *comp = [NSURLComponents componentsWithString:kGrizzlyBase];
    comp.queryItems = @[ [NSURLQueryItem queryItemWithName:@"api_key" value:key],
                         [NSURLQueryItem queryItemWithName:@"action" value:@"setStatus"],
                         [NSURLQueryItem queryItemWithName:@"id" value:orderId],
                         [NSURLQueryItem queryItemWithName:@"status" value:[NSString stringWithFormat:@"%d", status]] ];
    [[[NSURLSession sharedSession] dataTaskWithURL:comp.URL] resume];
}

+ (void)cancelOrder:(NSString *)orderId provider:(NSString *)provider {
    if (![provider isEqualToString:@"grizzly"] || orderId.length == 0) return;   // DiddySMS orders expire on their own
    NSString *key = [[GBStore shared].grizzlyKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    [self cancelOrGrizzlyFinish:orderId status:8 key:key];   // 8 = cancel + refund
}

@end
