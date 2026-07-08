// GPS Plus Pro - MapManager.mm
// مسؤول عن الخريطة، البحث، الدبابيس، أنواع الخريطة، والمساجد.

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>

@interface GPSPlusMapManager : NSObject <MKMapViewDelegate>
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) MKPointAnnotation *selectedPin;
- (void)moveToCoordinate:(CLLocationCoordinate2D)coordinate animated:(BOOL)animated;
- (void)searchForText:(NSString *)text completion:(void (^)(NSArray<MKMapItem *> *items))completion;
- (void)findNearbyMosquesFromCoordinate:(CLLocationCoordinate2D)coordinate completion:(void (^)(NSArray<MKMapItem *> *items))completion;
@end

@implementation GPSPlusMapManager
- (void)moveToCoordinate:(CLLocationCoordinate2D)coordinate animated:(BOOL)animated {}
- (void)searchForText:(NSString *)text completion:(void (^)(NSArray<MKMapItem *> *items))completion { if (completion) completion(@[]); }
- (void)findNearbyMosquesFromCoordinate:(CLLocationCoordinate2D)coordinate completion:(void (^)(NSArray<MKMapItem *> *items))completion { if (completion) completion(@[]); }
@end
