#import "GBScanner.h"
#import <Vision/Vision.h>

#pragma mark - Username filter

// Words Instagram (and iOS) paints on screen in lowercase that are not handles.
static NSSet<NSString *> *GBStopWords(void) {
    static NSSet *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [NSSet setWithArray:@[
            @"follow", @"following", @"followers", @"follower", @"suggested", @"message", @"remove",
            @"search", @"posts", @"reels", @"tagged", @"more", @"edit", @"profile", @"share", @"home",
            @"explore", @"likes", @"like", @"liked", @"reply", @"replies", @"comments", @"comment",
            @"view", @"all", @"see", @"translation", @"sponsored", @"verified", @"notifications",
            @"settings", @"story", @"stories", @"add", @"cancel", @"done", @"ok", @"send", @"sms",
            @"code", @"number", @"heavenzy", @"usa", @"and", @"others", @"you", @"me", @"new", @"live",
            @"mutual", @"requested", @"unfollow", @"block", @"restrict", @"report", @"hide", @"save",
            @"saved", @"seen", @"ago", @"now", @"today", @"yesterday", @"online", @"active", @"typing",
            @"instagram", @"threads", @"facebook", @"meta", @"login", @"log", @"in", @"sign", @"up",
            @"next", @"back", @"skip", @"continue", @"close", @"open", @"copy", @"paste", @"select",
            @"delete", @"archive", @"pin", @"unpin", @"mute", @"unmute", @"notes", @"note", @"music",
            @"audio", @"original", @"filters", @"effects", @"location", @"people", @"places", @"tags",
            @"top", @"recent", @"accounts", @"account", @"for", @"the", @"with", @"from", @"to", @"of",
            @"on", @"at", @"by", @"is", @"it", @"or", @"a", @"an", @"no", @"yes", @"not", @"found",
            @"loading", @"error", @"retry", @"refresh", @"suggestions", @"discover", @"contacts",
            @"invite", @"friends", @"friend", @"favorites", @"favorite", @"subscribe", @"subscribed",
            @"shop", @"cart", @"buy", @"map", @"guide", @"guides", @"channel", @"channels", @"broadcast",
            @"collab", @"remix", @"template", @"draft", @"drafts", @"trash", @"caption", @"usernames",
            @"username", @"scan", @"scanning", @"sim", @"vpn", @"wifi",
        ]];
    });
    return s;
}

// Whole string must be a plausible Instagram handle. Returns the normalized handle or nil.
static NSString *GBHandle(NSString *raw) {
    if (!raw.length) return nil;
    // Instagram always paints handles in lowercase, so case is kept: it is what separates "teddy"
    // (a handle) from "Teddy" (a display name).
    NSString *s = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([s hasPrefix:@"@"]) s = [s substringFromIndex:1];
    if (s.length < 1 || s.length > 30) return nil;

    static NSRegularExpression *re, *count; static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"^[a-z0-9._]{1,30}$" options:0 error:nil];
        count = [NSRegularExpression regularExpressionWithPattern:@"^[0-9.]+[kmb]$|^[0-9]+[smhdwy]$" options:0 error:nil];
    });
    if (![re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)]) return nil;
    if ([s hasPrefix:@"."] || [s hasSuffix:@"."] || [s containsString:@".."]) return nil;
    // Needs a letter (drops "194", "1.1"); drops counts/durations like "1.1m", "12k", "2h", "3d".
    if ([s rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location == NSNotFound) return nil;
    if ([count firstMatchInString:s options:0 range:NSMakeRange(0, s.length)]) return nil;
    if ([GBStopWords() containsObject:s]) return nil;
    return s;
}

// Accessibility labels are often composites ("calvin_harryy, Follow"); split on separators and
// test each segment as a whole. Never split on spaces: "remi ryle" is a display name, not two handles.
static NSArray<NSString *> *GBSegments(NSString *s) {
    NSCharacterSet *sep = [NSCharacterSet characterSetWithCharactersInString:@",;\n\r\t·•|"];
    return [s componentsSeparatedByCharactersInSet:sep];
}

#pragma mark - Candidates

@interface GBCandidate : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) CGFloat y;
@property (nonatomic, assign) BOOL strong;   // bold/semibold text (how Instagram paints handles)
@end
@implementation GBCandidate @end

static BOOL GBFontIsStrong(UIFont *f) {
    if (!f) return NO;
    if (f.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) return YES;
    NSDictionary *traits = [f.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute];
    if ([traits[UIFontWeightTrait] doubleValue] >= 0.2) return YES;   // >= medium
    NSString *n = f.fontName.lowercaseString;
    return [n containsString:@"bold"] || [n containsString:@"medium"] || [n containsString:@"heavy"] || [n containsString:@"black"];
}

static BOOL GBAttrIsStrong(NSAttributedString *a) {
    if (!a.length) return NO;
    return GBFontIsStrong([a attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL]);
}

static void GBAdd(NSMutableArray<GBCandidate *> *out, NSString *text, CGFloat y, BOOL strong) {
    if (!text.length || text.length > 400) return;
    for (NSString *seg in GBSegments(text)) {
        NSString *h = GBHandle(seg);
        if (!h) continue;
        GBCandidate *c = [GBCandidate new]; c.name = h; c.y = y; c.strong = strong;
        [out addObject:c];
    }
}

// Safely pull a string-ish value out of an arbitrary object via a selector it claims to respond to.
static id GBGet(id obj, NSString *sel) {
    SEL s = NSSelectorFromString(sel);
    if (!obj || ![obj respondsToSelector:s]) return nil;
    @try {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        return [obj performSelector:s];
        #pragma clang diagnostic pop
    } @catch (...) { return nil; }
}

// Collect text carried by any object (view, layer, node, accessibility element).
static void GBHarvest(id obj, CGFloat y, NSMutableArray<GBCandidate *> *out) {
    id attr = GBGet(obj, @"attributedText") ?: GBGet(obj, @"attributedString");
    if ([attr isKindOfClass:NSAttributedString.class]) {
        GBAdd(out, [(NSAttributedString *)attr string], y, GBAttrIsStrong(attr));
    } else {
        id text = GBGet(obj, @"text");
        if ([text isKindOfClass:NSString.class]) {
            id font = GBGet(obj, @"font");
            GBAdd(out, text, y, [font isKindOfClass:UIFont.class] ? GBFontIsStrong(font) : NO);
        }
    }
    id al = GBGet(obj, @"accessibilityLabel");
    if ([al isKindOfClass:NSString.class]) GBAdd(out, al, y, NO);
    id av = GBGet(obj, @"accessibilityValue");
    if ([av isKindOfClass:NSString.class]) GBAdd(out, av, y, NO);
    // View-backed Texture nodes keep their attributedText on the node, not the _ASDisplayView.
    if ([obj isKindOfClass:UIView.class] || [obj isKindOfClass:CALayer.class]) {
        id node = GBGet(obj, @"asyncdisplaykit_node");
        if (node && node != obj) GBHarvest(node, y, out);
    }
}

#pragma mark - Pass A: visible view hierarchy

static BOOL GBInsideScrollContext(UIView *v) {
    for (UIView *p = v; p; p = p.superview) {
        if ([p isKindOfClass:UIScrollView.class] || [p isKindOfClass:UITableView.class] ||
            [p isKindOfClass:UICollectionView.class])
            return YES;
    }
    return NO;
}

static void GBWalkLayers(CALayer *layer, UIWindow *win, NSMutableArray<GBCandidate *> *out, NSUInteger depth) {
    if (depth > 40 || layer.hidden || layer.opacity < 0.01) return;
    for (CALayer *sub in layer.sublayers) {
        if ([sub.delegate isKindOfClass:UIView.class]) continue;
        id node = GBGet(sub, @"asyncdisplaykit_node");
        if (node) {
            CGRect r = [sub convertRect:sub.bounds toLayer:win.layer];
            GBHarvest(sub, CGRectGetMinY(r), out);   // harvests the node via asyncdisplaykit_node
        }
        GBWalkLayers(sub, win, out, depth + 1);
    }
}

static void GBWalkViews(UIView *v, UIWindow *win, NSMutableArray<GBCandidate *> *out, NSUInteger depth) {
    if (depth > 80 || v.hidden || v.alpha < 0.01) return;
    BOOL deep = GBInsideScrollContext(v);
    CGRect r = [v convertRect:v.bounds toView:win];
    if (!deep && !CGRectIntersectsRect(r, win.bounds)) return;
    GBHarvest(v, CGRectGetMinY(r), out);
    for (UIView *sub in v.subviews) GBWalkViews(sub, win, out, depth + 1);
    GBWalkLayers(v.layer, win, out, 0);
}

static NSArray<NSString *> *GBDedupeSort(NSMutableArray<GBCandidate *> *raw) {
    // Instagram paints handles semibold and display names regular. When any bold candidates exist,
    // keep only those so lowercase single-word display names ("teddy") don't slip in. When the app
    // exposes no font info at all (accessibility-only / OCR), fall back to everything.
    BOOL anyStrong = NO;
    for (GBCandidate *c in raw) { if (c.strong) { anyStrong = YES; break; } }
    NSMutableDictionary<NSString *, GBCandidate *> *best = [NSMutableDictionary new];
    for (GBCandidate *c in raw) {
        if (anyStrong && !c.strong) continue;
        GBCandidate *prev = best[c.name];
        if (!prev || (c.strong && !prev.strong) || (c.strong == prev.strong && c.y < prev.y))
            best[c.name] = c;
    }
    NSArray *vals = [[best allValues] sortedArrayUsingComparator:^NSComparisonResult(GBCandidate *a, GBCandidate *b) {
        if (a.y < b.y) return NSOrderedAscending;
        if (a.y > b.y) return NSOrderedDescending;
        return [a.name compare:b.name];
    }];
    NSMutableArray *names = [NSMutableArray arrayWithCapacity:vals.count];
    for (GBCandidate *c in vals) [names addObject:c.name];
    return names;
}

static NSArray<NSString *> *GBHierarchyScan(UIWindowScene *scene, UIWindow *excluded) {
    NSMutableArray<GBCandidate *> *raw = [NSMutableArray new];
    for (UIWindow *win in scene.windows) {
        if (win == excluded || win.hidden || win.alpha < 0.01) continue;
        for (UIView *sub in win.subviews) GBWalkViews(sub, win, raw, 0);
    }
    return GBDedupeSort(raw);
}

@implementation GBScanner

+ (void)scanScene:(UIWindowScene *)scene excludingWindow:(UIWindow *)excluded
       completion:(void (^)(NSArray<NSString *> *, NSString *))completion {
    if (!scene) {
        if (completion) completion(@[], nil);
        return;
    }
    // UIKit hierarchy + snapshots must be read on the main thread.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *hier = GBHierarchyScan(scene, excluded);
        if (hier.count) {
            if (completion) completion(hier, @"hierarchy");
            return;
        }
        UIImage *img = nil;
        CGRect bounds = scene.coordinateSpace.bounds;
        if (CGRectIsEmpty(bounds)) bounds = UIScreen.mainScreen.bounds;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:bounds];
        img = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            for (UIWindow *win in scene.windows) {
                if (win == excluded || win.hidden || win.alpha < 0.01) continue;
                [win drawViewHierarchyInRect:bounds afterScreenUpdates:NO];
            }
        }];
        CGImageRef cg = img.CGImage;
        if (!cg) {
            if (completion) completion(@[], nil);
            return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSMutableArray<GBCandidate *> *raw = [NSMutableArray new];
            VNRecognizeTextRequest *req = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *error) {
                if (error) return;
                for (VNRecognizedTextObservation *obs in request.results) {
                    VNRecognizedText *top = [[obs topCandidates:1] firstObject];
                    if (!top.string.length) continue;
                    CGRect bb = obs.boundingBox;
                    CGFloat y = (1.0 - bb.origin.y - bb.size.height) * bounds.size.height;
                    for (NSString *seg in GBSegments(top.string)) {
                        NSString *h = GBHandle(seg);
                        if (h) {
                            GBCandidate *c = [GBCandidate new]; c.name = h; c.y = y; c.strong = NO;
                            [raw addObject:c];
                        }
                    }
                }
            }];
            req.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
            req.usesLanguageCorrection = NO;
            VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
            [handler performRequests:@[req] error:nil];
            NSArray *ocr = GBDedupeSort(raw);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(ocr, ocr.count ? @"ocr" : nil);
            });
        });
    });
}

@end
