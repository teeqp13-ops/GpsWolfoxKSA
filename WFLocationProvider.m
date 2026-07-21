//
//  WFLocationProvider.m
//

#import "WFLocationProvider.h"
#import "WFSettingsStore.h"

@implementation WFLocationProvider

+ (instancetype)shared {
    static WFLocationProvider *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WFLocationProvider alloc] init];
    });
    return instance;
}

// يحول متر إلى فرق تقريبي بالدرجات (Jitter بسيط، غير دقيق جغرافيًا لكن كافٍ للتجربة)
- (CLLocationCoordinate2D)jitteredCoordinate:(CLLocationCoordinate2D)coord metersRadius:(double)meters {
    if (meters <= 0) return coord;

    double metersPerDegreeLat = 111320.0;
    double metersPerDegreeLng = 111320.0 * cos(coord.latitude * M_PI / 180.0);
    if (metersPerDegreeLng <= 0) metersPerDegreeLng = metersPerDegreeLat;

    double randomAngle = ((double)arc4random_uniform(3600)) / 10.0 * M_PI / 180.0;
    double randomDistance = ((double)arc4random_uniform(1000)) / 1000.0 * meters;

    double dLat = (randomDistance * cos(randomAngle)) / metersPerDegreeLat;
    double dLng = (randomDistance * sin(randomAngle)) / metersPerDegreeLng;

    return CLLocationCoordinate2DMake(coord.latitude + dLat, coord.longitude + dLng);
}

- (CLLocationCoordinate2D)currentCoordinateFromRealLocation:(CLLocation *)realLocation {
    WFSettingsStore *settings = [WFSettingsStore shared];

    if (!settings.mockEnabled) {
        return realLocation ? realLocation.coordinate : kCLLocationCoordinate2DInvalid;
    }

    CLLocationCoordinate2D coord = settings.selectedCoordinate;

    if (settings.jitterEnabled && settings.jitterMeters > 0) {
        coord = [self jitteredCoordinate:coord metersRadius:settings.jitterMeters];
    }

    return coord;
}

- (CLLocation *)currentLocationFromRealLocation:(CLLocation *)realLocation {
    CLLocationCoordinate2D coord = [self currentCoordinateFromRealLocation:realLocation];
    if (!CLLocationCoordinate2DIsValid(coord)) {
        return realLocation;
    }

    if ([WFSettingsStore shared].mockEnabled) {
        return [[CLLocation alloc] initWithCoordinate:coord
                                              altitude:realLocation.altitude ?: 0
                                    horizontalAccuracy:5
                                      verticalAccuracy:5
                                             timestamp:[NSDate date]];
    }

    return realLocation;
}

@end
