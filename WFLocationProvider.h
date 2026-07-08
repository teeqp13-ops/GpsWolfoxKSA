//
//  WFLocationProvider.h
//  WFLocationKit
//
//  يوفر إحداثيات "تجريبية" داخل تطبيقك فقط.
//  لا يعدّل CLLocationManager ولا أي سلوك في النظام أو تطبيقات أخرى.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WFLocationProvider : NSObject

+ (instancetype)shared;

/// أعطه الموقع الحقيقي (من CLLocationManager الخاص بتطبيقك)
/// ويرجع لك إما نفس الموقع أو الموقع التجريبي حسب الإعدادات.
- (CLLocationCoordinate2D)currentCoordinateFromRealLocation:(nullable CLLocation *)realLocation;

/// نفس الفكرة لكن يرجع CLLocation كامل (مفيد لو تبي altitude/accuracy)
- (CLLocation *)currentLocationFromRealLocation:(nullable CLLocation *)realLocation;

@end

NS_ASSUME_NONNULL_END
