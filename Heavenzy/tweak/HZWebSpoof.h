#import <Foundation/Foundation.h>

/// Prefix of every Heavenzy web-container user script (used to find and replace our own script).
FOUNDATION_EXTERN NSString *const HZWebSpoofMarker;

/// JavaScript (document-start, all frames) presenting the container's web identity to pages.
FOUNDATION_EXTERN NSString *HZWebSpoofSource(NSDictionary *container);
