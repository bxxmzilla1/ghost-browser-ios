#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "HZConfig.h"
#import "HZWebClips.h"
#import "HZWebSpoof.h"
#import "GBStore.h"

// Spoofed Home Screen web-app containers.
//
// Full-screen web clips ("Add to Home Screen" web apps) run outside Safari with their own website
// data store. This file does for such a web container what Tweak.xm does for a native app: the
// container's identity script is attached to its WKWebView's user content controller so every page it
// loads sees the same per-container canvas / audio fingerprint, LAN-free WebRTC and re-encoded uploads.
//
// Which container we are in (see %ctor):
//   1. Newer iOS registers each Home Screen web app as its own application whose bundle identifier
//      ends with the web clip's identifier ("com.apple.WebKit.…<clipId>") — a direct, reliable match
//      that also makes the container show up in the control app's app list.
//   2. Older iOS hosts all web apps in one process (com.apple.webapp); there the "#hzc=<id>" tag the
//      control app bakes into the icon's URL identifies the container on its first loadRequest: (it is
//      stripped before the page sees it) and the view's data store is linked for later launches.
//
// Only Objective-C method swizzles — same rule as Tweak.xm, no inline C hooks.

/// Container this whole process belongs to (case 1), nil in the shared-host case.
static NSString *gHZBoundContainerId;

static const void *kHZContainerKey = &kHZContainerKey;

/// Stable key for a web app's website data store across launches (nil for ephemeral stores).
static NSString *HZStoreKey(WKWebsiteDataStore *ds) {
    if (!ds) return nil;
    @try {
        if (!ds.persistent) return nil;
        // iOS 17+: public -identifier (NSUUID). Resolved via KVC so the 16.x SDK still compiles.
        if ([ds respondsToSelector:NSSelectorFromString(@"identifier")]) {
            id u = [ds valueForKey:@"identifier"];
            if ([u isKindOfClass:NSUUID.class]) return [(NSUUID *)u UUIDString];
        }
        // Older: the private configuration's storage directory is unique per web app.
        if ([ds respondsToSelector:NSSelectorFromString(@"_configuration")]) {
            id cfg = [ds valueForKey:@"_configuration"];
            for (NSString *k in @[ @"generalStorageDirectory", @"_webStorageDirectory", @"_indexedDBDatabaseDirectory" ]) {
                if (![cfg respondsToSelector:NSSelectorFromString(k)]) continue;
                id v = [cfg valueForKey:k];
                NSString *path = [v isKindOfClass:NSURL.class] ? [(NSURL *)v path] : ([v isKindOfClass:NSString.class] ? v : nil);
                if (path.length) return path;
            }
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

/// Attach (or swap in) the container's identity script. Removes a previously attached Heavenzy script
/// — and only ours — so a re-identified view never carries two identities.
static void HZAttachContainer(WKWebView *webView, WKWebViewConfiguration *config, NSDictionary *container) {
    if (!container || !config) return;
    NSString *cid = container[@"id"];
    if (webView && [objc_getAssociatedObject(webView, kHZContainerKey) isEqualToString:cid]) return;

    WKUserContentController *ucc = config.userContentController;
    if (!ucc) { ucc = [WKUserContentController new]; config.userContentController = ucc; }

    NSMutableArray<WKUserScript *> *keep = [NSMutableArray array];
    BOOL hadOurs = NO;
    for (WKUserScript *s in ucc.userScripts) {
        if ([s.source hasPrefix:HZWebSpoofMarker]) hadOurs = YES; else [keep addObject:s];
    }
    if (hadOurs) {
        [ucc removeAllUserScripts];
        for (WKUserScript *s in keep) [ucc addUserScript:s];
    }
    WKUserScript *script = [[WKUserScript alloc] initWithSource:HZWebSpoofSource(container)
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                               forMainFrameOnly:NO];
    [ucc addUserScript:script];
    if (webView) objc_setAssociatedObject(webView, kHZContainerKey, cid, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSLog(@"[Heavenzy][WebClip] container %@ (%@) attached, seed %@", cid, container[@"name"], [HZWebClips seedLabel:container]);
}

/// Prepares a top-level load: strips our URL tag, identifies/links the container, and honours a
/// pending wipe. Returns the request to load now, or nil when the load was deferred until the
/// container's website data has been erased (`resume` is then called on the main thread).
static NSURLRequest *HZPrepareLoad(WKWebView *webView, NSURLRequest *request, void (^resume)(NSURLRequest *)) {
    NSString *tagged = [HZWebClips containerIdInURL:request.URL];
    NSString *attached = objc_getAssociatedObject(webView, kHZContainerKey);
    if (!tagged && !attached) return request;

    NSURLRequest *req = request;
    if (tagged) {
        NSMutableURLRequest *m = [request mutableCopy];
        m.URL = [HZWebClips URLByRemovingTag:request.URL];
        req = m;
        if (![tagged isEqualToString:attached]) {
            NSDictionary *c = [HZWebClips containerWithId:tagged];
            if (c) {
                HZAttachContainer(webView, webView.configuration, c);
                attached = tagged;
                NSString *key = HZStoreKey(webView.configuration.websiteDataStore);
                if (key) [HZWebClips linkStoreKey:key toContainer:tagged];
            } else {
                NSLog(@"[Heavenzy][WebClip] URL tagged with unknown container %@", tagged);
            }
        }
    }
    if (!attached) return req;

    NSDictionary *c = [HZWebClips containerWithId:attached];
    if (![c[@"wipePending"] boolValue]) return req;

    // Reset requested from the control app: erase everything this container stored, then load.
    [HZWebClips clearWipePendingForContainer:attached];
    NSLog(@"[Heavenzy][WebClip] wiping website data of container %@", attached);
    WKWebsiteDataStore *ds = webView.configuration.websiteDataStore;
    [ds removeDataOfTypes:[WKWebsiteDataStore allWebsiteDataTypes] modifiedSince:[NSDate distantPast] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{ resume(req); });
    }];
    return nil;
}

%group HZWebClipHooks

%hook WKWebView

- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    NSDictionary *container = nil;
    NSString *key = nil;
    @try {
        key = HZStoreKey(configuration.websiteDataStore);
        container = gHZBoundContainerId ? [HZWebClips containerWithId:gHZBoundContainerId]
                                        : (key ? [HZWebClips containerForStoreKey:key] : nil);
        if (container) HZAttachContainer(nil, configuration, container);
    } @catch (__unused NSException *e) {}
    WKWebView *wv = %orig;
    if (wv && container) {
        objc_setAssociatedObject(wv, kHZContainerKey, container[@"id"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (key && gHZBoundContainerId) [HZWebClips linkStoreKey:key toContainer:gHZBoundContainerId];
    }
    return wv;
}

- (WKNavigation *)loadRequest:(NSURLRequest *)request {
    __weak WKWebView *weakSelf = self;
    NSURLRequest *req = nil;
    @try {
        req = HZPrepareLoad(self, request, ^(NSURLRequest *r) { [weakSelf loadRequest:r]; });
    } @catch (__unused NSException *e) { req = request; }
    if (!req) return nil;   // deferred until the pending wipe finishes
    return %orig(req);
}

%end

%end   // HZWebClipHooks

// -[WKWebView _loadRequest:shouldOpenExternalURLs:] is private and may not exist on every iOS, so it is
// hooked by hand only when present (Logos would log an error for a missing selector).
static WKNavigation *(*orig_loadRequestExternal)(WKWebView *, SEL, NSURLRequest *, BOOL);
static WKNavigation *hz_loadRequestExternal(WKWebView *self, SEL _cmd, NSURLRequest *request, BOOL external) {
    __weak WKWebView *weakSelf = self;
    NSURLRequest *req = nil;
    @try {
        req = HZPrepareLoad(self, request, ^(NSURLRequest *r) {
            WKWebView *s = weakSelf;
            if (s) orig_loadRequestExternal(s, _cmd, r, external);
        });
    } @catch (__unused NSException *e) { req = request; }
    return req ? orig_loadRequestExternal(self, _cmd, req, external) : nil;
}

%ctor {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        BOOL sharedHost = [bundleID isEqualToString:@"com.apple.webapp"] || [bundleID isEqualToString:@"com.apple.webapp1"];
        if (!sharedHost && ![bundleID hasPrefix:@"com.apple."]) return;

        [HZConfig grantSandboxAccess];   // webclips.plist lives in the shared Heavenzy directory
        NSDictionary *bound = [HZWebClips containerForBundleId:bundleID];
        if (!bound && !sharedHost) return;   // some other Apple process (incl. WebKit XPC services)

        if (bound) {
            gHZBoundContainerId = bound[@"id"];
            // The control app's Spoof Chain / "Erase App Data" queue a native wipe for this bundle id
            // (either in our own container or in the central plist). For a web container that means a
            // reset: new fingerprint seed + erase all website data on the first load.
            GBStore *store = [GBStore shared];
            if (store.wipePending || [HZConfig wipePendingForApp:bundleID]) {
                [HZWebClips resetContainer:gHZBoundContainerId];
                store.wipePending = NO;
                [store save];
                [HZConfig setWipePending:NO forApp:bundleID];
                NSLog(@"[Heavenzy][WebClip] Spoof Chain requested → container %@ reset queued", gHZBoundContainerId);
            }
        }
        %init(HZWebClipHooks);

        SEL ext = NSSelectorFromString(@"_loadRequest:shouldOpenExternalURLs:");
        if (class_getInstanceMethod(WKWebView.class, ext)) {
            MSHookMessageEx(WKWebView.class, ext, (IMP)hz_loadRequestExternal, (IMP *)&orig_loadRequestExternal);
        }
        NSLog(@"[Heavenzy][WebClip] active in %@ — bound to %@ (%@), %lu container(s), config %@", bundleID,
              bound[@"name"] ?: @"shared host", bound ? [HZWebClips seedLabel:bound] : @"tag-based",
              (unsigned long)[HZWebClips containers].count, [HZConfig sandboxAccessDescription]);
    }
}
