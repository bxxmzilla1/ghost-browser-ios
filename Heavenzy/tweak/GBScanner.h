#import <UIKit/UIKit.h>

/// On-tap username extraction for the host app (tuned for Instagram).
///
/// Two passes, run from inside the app's own process:
///  1. View-hierarchy pass — walks every visible view/layer in the app's windows and reads the real
///     strings out of UILabel/UITextView, Texture/AsyncDisplayKit text nodes, and accessibility
///     labels. Exact text (no OCR errors, no truncation), and bold/semibold text is preferred
///     because Instagram renders handles in semibold and display names in regular weight.
///  2. OCR fallback — if the hierarchy pass finds nothing, snapshot the app's windows and run
///     Vision's on-device text recognizer (language correction off so handles aren't "fixed").
///
/// Candidates must look like an Instagram handle: 1–30 chars of [a-z0-9._], lowercase only, no
/// leading/trailing/consecutive dots, not a pure number/count/duration, not a UI word.
@interface GBScanner : NSObject

/// Scans every window in `scene` except `excluded` (our own overlay). Completion runs on the main
/// queue with usernames ordered top-to-bottom as they appear on screen, and `method` set to
/// "hierarchy" or "ocr" (or nil when nothing was found).
///
/// When `approvedNames` is non-empty, only accounts whose display-name first name (or whole display
/// name), lowercased, is in the set are returned — the rest are dropped. Pass nil/empty for no filter.
+ (void)scanScene:(UIWindowScene *)scene
   excludingWindow:(UIWindow *)excluded
     approvedNames:(NSSet<NSString *> *)approvedNames
        completion:(void (^)(NSArray<NSString *> *usernames, NSString *method))completion;

@end
