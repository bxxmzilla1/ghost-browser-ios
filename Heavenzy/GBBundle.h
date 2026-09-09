#import <Foundation/Foundation.h>

/// Minimal bundle.social REST client (https://api.bundle.social, `x-api-key` auth).
/// Used to connect the Instagram account of the host app to a bundle.social team.
@interface GBBundle : NSObject

/// GET /api/v1/organization/ — verifies the key and returns the organization name + teams
/// (`@[ @{ @"id": ..., @"name": ... } ]`). Completion is called on the main queue.
+ (void)organizationWithKey:(NSString *)apiKey
                 completion:(void (^)(NSString *orgName, NSArray<NSDictionary *> *teams, NSError *error))completion;

/// Resolves the team (given id, or the organization's first team) and asks bundle.social for the
/// Instagram OAuth URL. Completion (main queue) gets the URL to open and the team name it's for.
+ (void)instagramConnectURLWithKey:(NSString *)apiKey
                            teamId:(NSString *)teamId
                        completion:(void (^)(NSURL *url, NSString *teamName, NSError *error))completion;

@end
