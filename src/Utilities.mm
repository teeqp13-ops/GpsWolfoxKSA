// GPS Plus Pro - Utilities.mm
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
@interface GPSPlusUtilities : NSObject
+ (void)haptic;
+ (NSString *)formatCoordinateLat:(double)lat lon:(double)lon;
+ (void)runOnMain:(dispatch_block_t)block;
@end
@implementation GPSPlusUtilities
+ (void)haptic { UIImpactFeedbackGenerator *g=[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight]; [g impactOccurred]; }
+ (NSString *)formatCoordinateLat:(double)lat lon:(double)lon { return [NSString stringWithFormat:@"%.6f, %.6f", lat, lon]; }
+ (void)runOnMain:(dispatch_block_t)block { if(!block)return; dispatch_async(dispatch_get_main_queue(), block); }
@end
