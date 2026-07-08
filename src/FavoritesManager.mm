// GPS Plus Pro - FavoritesManager.mm
#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
@interface GPSPlusFavoritesManager : NSObject
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *favorites;
+ (instancetype)shared;
- (void)load;
- (void)save;
- (void)addName:(NSString *)name coordinate:(CLLocationCoordinate2D)c;
- (void)removeAtIndex:(NSUInteger)index;
@end
@implementation GPSPlusFavoritesManager
+ (instancetype)shared { static GPSPlusFavoritesManager *m; static dispatch_once_t once; dispatch_once(&once, ^{ m=[GPSPlusFavoritesManager new]; [m load]; }); return m; }
- (void)load { self.favorites = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"GPSPlus_Favorites"] mutableCopy] ?: [NSMutableArray new]; }
- (void)save { [[NSUserDefaults standardUserDefaults] setObject:self.favorites forKey:@"GPSPlus_Favorites"]; }
- (void)addName:(NSString *)name coordinate:(CLLocationCoordinate2D)c { [self.favorites addObject:@{@"name":name?:@"موقع",@"lat":@(c.latitude),@"lon":@(c.longitude)}]; [self save]; }
- (void)removeAtIndex:(NSUInteger)index { if(index<self.favorites.count){ [self.favorites removeObjectAtIndex:index]; [self save]; } }
@end
