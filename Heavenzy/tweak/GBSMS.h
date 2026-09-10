#import <Foundation/Foundation.h>

/// On-device port of the Sessions X DiddySMS + GrizzlySMS clients. Provider + API keys come from
/// GBStore (mirrored in from the Heavenzy control app's Settings). The service is auto-detected from
/// the host app's name (e.g. Instagram → "instagram"/"ig") and the country is always USA.
@interface GBSMS : NSObject

/// Lowercased brand derived from the current app's display name, e.g. "instagram".
+ (NSString *)appBrand;
/// "DiddySMS" or "GrizzlySMS" for display.
+ (NSString *)providerLabel;
/// The service label to show the user (Grizzly short code or the resolved Diddy service name).
+ (NSString *)serviceLabel;

/// Order a US number for the detected service. completion runs on the main queue: on success
/// (phone,orderId,service,nil); on failure (nil,nil,nil,error).
+ (void)requestNumberWithCompletion:(void (^)(NSString *phone, NSString *orderId, NSString *service, NSString *error))completion;

/// "diddy" or "grizzly" — the provider currently selected in Settings. Capture it when an order is
/// placed and pass it to poll/cancel so a later provider switch doesn't break an in-flight order.
+ (NSString *)currentProvider;

/// Poll an order for the SMS code. completion runs on the main queue: code is @"" while still
/// waiting, a digit string once it arrives, or (nil,error) on failure.
+ (void)pollOrder:(NSString *)orderId provider:(NSString *)provider completion:(void (^)(NSString *code, NSString *error))completion;

/// Release/cancel an unfinished order (GrizzlySMS refunds it). Fire-and-forget.
+ (void)cancelOrder:(NSString *)orderId provider:(NSString *)provider;

@end
