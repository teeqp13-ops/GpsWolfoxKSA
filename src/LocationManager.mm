// GPS Plus Pro - LocationManager.mm
// مسؤول عن Hooks الموقع، الإحداثيات الوهمية، الحركة، والجدولة.

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface GPSPlusLocationManager : NSObject
@property (nonatomic, assign) CLLocationCoordinate2D fakeCoordinate;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL jitterEnabled;
@property (nonatomic, assign) double jitterDistance;
+ (instancetype)shared;
- (CLLocation *)fakeLocation;
- (void)installLocationHooks;
- (void)updateJitter;
- (void)resetToRealLocation;
@end

@implementation GPSPlusLocationManager
+ (instancetype)shared { static GPSPlusLocationManager *m; static dispatch_once_t once; dispatch_once(&once, ^{ m = [GPSPlusLocationManager new]; }); return m; }
- (CLLocation *)fakeLocation { return [[CLLocation alloc] initWithLatitude:self.fakeCoordinate.latitude longitude:self.fakeCoordinate.longitude]; }
- (void)installLocationHooks {}
- (void)updateJitter {}
- (void)resetToRealLocation { self.enabled = NO; }
@end
