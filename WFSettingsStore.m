//
//  WFSettingsStore.m
//

#import "WFSettingsStore.h"

static NSString * const kWFDefaultsKey = @"WFLocationKit.settings.v1";
static NSString * const kWFFavoritesKey = @"WFLocationKit.favorites.v1";

#pragma mark - WFFavoriteLocation

@implementation WFFavoriteLocation

- (instancetype)initWithName:(NSString *)name coordinate:(CLLocationCoordinate2D)coordinate {
    self = [super init];
    if (self) {
        _name = [name copy];
        _coordinate = coordinate;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _name = [coder decodeObjectForKey:@"name"];
        _coordinate = CLLocationCoordinate2DMake(
            [coder decodeDoubleForKey:@"lat"],
            [coder decodeDoubleForKey:@"lng"]
        );
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.name forKey:@"name"];
    [coder encodeDouble:self.coordinate.latitude forKey:@"lat"];
    [coder encodeDouble:self.coordinate.longitude forKey:@"lng"];
}

@end

#pragma mark - WFSettingsStore

@interface WFSettingsStore ()
@property (nonatomic, strong) NSMutableArray<WFFavoriteLocation *> *mutableFavorites;
@end

@implementation WFSettingsStore

+ (instancetype)shared {
    static WFSettingsStore *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WFSettingsStore alloc] init];
        [instance load];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableFavorites = [NSMutableArray array];
        _tapsToToggleButton = 5; // افتراضي: 5 ضغطات لإظهار/إخفاء الزر
        _jitterMeters = 0;
        _jitterEnabled = NO;
        _mockEnabled = NO;
        _selectedCoordinate = kCLLocationCoordinate2DInvalid;
        _floatingButtonVisible = NO;
    }
    return self;
}

- (NSArray<WFFavoriteLocation *> *)favorites {
    return [self.mutableFavorites copy];
}

- (void)addFavoriteWithName:(NSString *)name coordinate:(CLLocationCoordinate2D)coordinate {
    WFFavoriteLocation *fav = [[WFFavoriteLocation alloc] initWithName:name coordinate:coordinate];
    [self.mutableFavorites addObject:fav];
    [self save];
}

- (void)removeFavoriteAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.mutableFavorites.count) return;
    [self.mutableFavorites removeObjectAtIndex:index];
    [self save];
}

- (void)save {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSDictionary *dict = @{
        @"mockEnabled": @(self.mockEnabled),
        @"lat": @(self.selectedCoordinate.latitude),
        @"lng": @(self.selectedCoordinate.longitude),
        @"jitterMeters": @(self.jitterMeters),
        @"jitterEnabled": @(self.jitterEnabled),
        @"tapsToToggleButton": @(self.tapsToToggleButton),
        @"floatingButtonVisible": @(self.floatingButtonVisible),
    };
    [defaults setObject:dict forKey:kWFDefaultsKey];

    // حفظ المفضلة عبر NSKeyedArchiver
    NSError *error = nil;
    NSData *favData = [NSKeyedArchiver archivedDataWithRootObject:self.mutableFavorites
                                              requiringSecureCoding:NO
                                                              error:&error];
    if (favData && !error) {
        [defaults setObject:favData forKey:kWFFavoritesKey];
    }

    [defaults synchronize];
}

- (void)load {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSDictionary *dict = [defaults objectForKey:kWFDefaultsKey];
    if (dict) {
        self.mockEnabled = [dict[@"mockEnabled"] boolValue];
        double lat = [dict[@"lat"] doubleValue];
        double lng = [dict[@"lng"] doubleValue];
        self.selectedCoordinate = CLLocationCoordinate2DMake(lat, lng);
        self.jitterMeters = [dict[@"jitterMeters"] doubleValue];
        self.jitterEnabled = [dict[@"jitterEnabled"] boolValue];
        NSNumber *taps = dict[@"tapsToToggleButton"];
        self.tapsToToggleButton = taps ? [taps integerValue] : 5;
        self.floatingButtonVisible = [dict[@"floatingButtonVisible"] boolValue];
    }

    NSData *favData = [defaults objectForKey:kWFFavoritesKey];
    if (favData) {
        NSError *error = nil;
        NSSet *classes = [NSSet setWithObjects:[NSArray class], [WFFavoriteLocation class], nil];
        NSArray *favs = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes
                                                             fromData:favData
                                                                error:&error];
        if (favs && !error) {
            self.mutableFavorites = [favs mutableCopy];
        }
    }

    // لو الإحداثيات غير صالحة، خلها قيمة افتراضية معقولة بدل 0,0
    if (!CLLocationCoordinate2DIsValid(self.selectedCoordinate) ||
        (self.selectedCoordinate.latitude == 0 && self.selectedCoordinate.longitude == 0)) {
        self.selectedCoordinate = CLLocationCoordinate2DMake(24.7136, 46.6753); // الرياض كافتراضي
    }
}

@end
