// GPS Plus Pro - GPSPlusPro.mm
// ملف واحد بامتداد .mm يحتوي التنظيم الداخلي بدل تقسيم المشروع إلى عدة ملفات.
// الأقسام الداخلية:
// 1) Constants
// 2) Utilities
// 3) SettingsManager
// 4) LicenseManager
// 5) FavoritesManager
// 6) LocationManager
// 7) MapManager
// 8) BluetoothManager
// 9) UIComponents
// 10) OverlayView
// 11) Hooks Entry

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <MapKit/MapKit.h>
#import <AdSupport/AdSupport.h>
#import <objc/runtime.h>

#pragma mark - Constants

#define GPSPLUS_NAME @"GPS Plus Pro"
#define GPSPLUS_DEFAULT_LAT 24.7136
#define GPSPLUS_DEFAULT_LON 46.6753
#define GPSPLUS_BLUE [UIColor colorWithRed:0.18 green:0.49 blue:1.0 alpha:1.0]
#define GPSPLUS_GOLD [UIColor colorWithRed:0.97 green:0.79 blue:0.28 alpha:1.0]

#pragma mark - Utilities

@interface GPSPlusUtilities : NSObject
+ (void)haptic;
+ (void)runOnMain:(dispatch_block_t)block;
+ (NSString *)formatCoordinateLat:(double)lat lon:(double)lon;
+ (UIViewController *)topViewController;
@end

@implementation GPSPlusUtilities
+ (void)haptic {
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
}
+ (void)runOnMain:(dispatch_block_t)block {
    if (!block) return;
    dispatch_async(dispatch_get_main_queue(), block);
}
+ (NSString *)formatCoordinateLat:(double)lat lon:(double)lon {
    return [NSString stringWithFormat:@"%.6f, %.6f", lat, lon];
}
+ (UIViewController *)topViewController {
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}
@end

#pragma mark - SettingsManager

@interface GPSPlusSettingsManager : NSObject
@property(nonatomic, assign) BOOL darkMode;
@property(nonatomic, assign) BOOL haptics;
@property(nonatomic, assign) NSInteger tapCount;
@property(nonatomic, assign) CGFloat panelAlpha;
+ (instancetype)shared;
- (void)load;
- (void)save;
@end

@implementation GPSPlusSettingsManager
+ (instancetype)shared {
    static GPSPlusSettingsManager *s = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [GPSPlusSettingsManager new]; [s load]; });
    return s;
}
- (void)load {
    NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
    self.darkMode = [u objectForKey:@"GPSPlus_darkMode"] ? [u boolForKey:@"GPSPlus_darkMode"] : YES;
    self.haptics = [u objectForKey:@"GPSPlus_haptics"] ? [u boolForKey:@"GPSPlus_haptics"] : YES;
    self.tapCount = [u objectForKey:@"GPSPlus_tapCount"] ? [u integerForKey:@"GPSPlus_tapCount"] : 3;
    self.panelAlpha = [u objectForKey:@"GPSPlus_panelAlpha"] ? [u doubleForKey:@"GPSPlus_panelAlpha"] : 0.96;
}
- (void)save {
    NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
    [u setBool:self.darkMode forKey:@"GPSPlus_darkMode"];
    [u setBool:self.haptics forKey:@"GPSPlus_haptics"];
    [u setInteger:self.tapCount forKey:@"GPSPlus_tapCount"];
    [u setDouble:self.panelAlpha forKey:@"GPSPlus_panelAlpha"];
    [u synchronize];
}
@end

#pragma mark - LicenseManager

@interface GPSPlusLicenseManager : NSObject
@property(nonatomic, copy) NSString *licenseKey;
@property(nonatomic, strong) NSDate *expiryDate;
+ (instancetype)shared;
- (NSString *)deviceID;
- (BOOL)isActive;
- (NSInteger)daysRemaining;
@end

@implementation GPSPlusLicenseManager
+ (instancetype)shared {
    static GPSPlusLicenseManager *m = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ m = [GPSPlusLicenseManager new]; });
    return m;
}
- (NSString *)deviceID {
    NSString *vendor = UIDevice.currentDevice.identifierForVendor.UUIDString;
    if (vendor.length) return vendor;
    NSString *custom = [NSUserDefaults.standardUserDefaults stringForKey:@"GPSPlus_DeviceID"];
    if (!custom.length) {
        custom = NSUUID.UUID.UUIDString;
        [NSUserDefaults.standardUserDefaults setObject:custom forKey:@"GPSPlus_DeviceID"];
    }
    return custom;
}
- (BOOL)isActive {
    if (!self.expiryDate) return YES; // مؤقتًا للتطوير، يربط لاحقًا بالسيرفر.
    return [self.expiryDate timeIntervalSinceNow] > 0;
}
- (NSInteger)daysRemaining {
    if (!self.expiryDate) return 999;
    return MAX(0, (NSInteger)([self.expiryDate timeIntervalSinceNow] / 86400.0));
}
@end

#pragma mark - FavoritesManager

@interface GPSPlusFavoritesManager : NSObject
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *favorites;
+ (instancetype)shared;
- (void)load;
- (void)save;
- (void)addName:(NSString *)name coordinate:(CLLocationCoordinate2D)c;
- (void)removeAtIndex:(NSUInteger)index;
@end

@implementation GPSPlusFavoritesManager
+ (instancetype)shared {
    static GPSPlusFavoritesManager *m = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ m = [GPSPlusFavoritesManager new]; [m load]; });
    return m;
}
- (void)load {
    NSArray *a = [NSUserDefaults.standardUserDefaults objectForKey:@"GPSPlus_Favorites"];
    self.favorites = a ? [a mutableCopy] : [NSMutableArray array];
}
- (void)save {
    [NSUserDefaults.standardUserDefaults setObject:self.favorites forKey:@"GPSPlus_Favorites"];
    [NSUserDefaults.standardUserDefaults synchronize];
}
- (void)addName:(NSString *)name coordinate:(CLLocationCoordinate2D)c {
    NSDictionary *item = @{@"name": name ?: @"موقع محفوظ", @"lat": @(c.latitude), @"lon": @(c.longitude)};
    [self.favorites addObject:item];
    [self save];
}
- (void)removeAtIndex:(NSUInteger)index {
    if (index < self.favorites.count) { [self.favorites removeObjectAtIndex:index]; [self save]; }
}
@end

#pragma mark - LocationManager

@interface GPSPlusLocationManager : NSObject
@property(nonatomic, assign) BOOL spoofingEnabled;
@property(nonatomic, assign) BOOL jitterEnabled;
@property(nonatomic, assign) CLLocationDistance jitterDistance;
@property(nonatomic, assign) CLLocationCoordinate2D fakeCoordinate;
@property(nonatomic, assign) CLLocationDegrees driftLatitude;
@property(nonatomic, assign) CLLocationDegrees driftLongitude;
+ (instancetype)shared;
- (void)load;
- (void)save;
- (void)setFakeCoordinateAndSave:(CLLocationCoordinate2D)c;
- (CLLocationCoordinate2D)outputCoordinate;
- (void)startJitter;
- (void)stopJitter;
@end

@implementation GPSPlusLocationManager {
    NSTimer *_jitterTimer;
}
+ (instancetype)shared {
    static GPSPlusLocationManager *m = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ m = [GPSPlusLocationManager new]; [m load]; });
    return m;
}
- (void)load {
    NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
    double lat = [u objectForKey:@"GPSPlus_LAT"] ? [u doubleForKey:@"GPSPlus_LAT"] : GPSPLUS_DEFAULT_LAT;
    double lon = [u objectForKey:@"GPSPlus_LON"] ? [u doubleForKey:@"GPSPlus_LON"] : GPSPLUS_DEFAULT_LON;
    self.fakeCoordinate = CLLocationCoordinate2DMake(lat, lon);
    self.spoofingEnabled = [u boolForKey:@"GPSPlus_Enabled"];
    self.jitterEnabled = [u boolForKey:@"GPSPlus_Jitter"];
    self.jitterDistance = [u objectForKey:@"GPSPlus_JitterDistance"] ? [u doubleForKey:@"GPSPlus_JitterDistance"] : 10.0;
}
- (void)save {
    NSUserDefaults *u = NSUserDefaults.standardUserDefaults;
    [u setDouble:self.fakeCoordinate.latitude forKey:@"GPSPlus_LAT"];
    [u setDouble:self.fakeCoordinate.longitude forKey:@"GPSPlus_LON"];
    [u setBool:self.spoofingEnabled forKey:@"GPSPlus_Enabled"];
    [u setBool:self.jitterEnabled forKey:@"GPSPlus_Jitter"];
    [u setDouble:self.jitterDistance forKey:@"GPSPlus_JitterDistance"];
    [u synchronize];
}
- (void)setFakeCoordinateAndSave:(CLLocationCoordinate2D)c { self.fakeCoordinate = c; [self save]; }
- (CLLocationCoordinate2D)outputCoordinate { return CLLocationCoordinate2DMake(self.fakeCoordinate.latitude + self.driftLatitude, self.fakeCoordinate.longitude + self.driftLongitude); }
- (void)startJitter { [self stopJitter]; _jitterTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateJitter) userInfo:nil repeats:YES]; }
- (void)stopJitter { [_jitterTimer invalidate]; _jitterTimer = nil; self.driftLatitude = 0; self.driftLongitude = 0; }
- (void)updateJitter {
    if (!self.spoofingEnabled || !self.jitterEnabled) { self.driftLatitude = 0; self.driftLongitude = 0; return; }
    double distance = 0.1 + ((double)arc4random_uniform((uint32_t)(self.jitterDistance * 1000.0)) / 1000.0);
    double angle = (arc4random_uniform(360)) * M_PI / 180.0;
    self.driftLatitude = (distance * cos(angle)) / 111111.0;
    self.driftLongitude = (distance * sin(angle)) / (111111.0 * cos(self.fakeCoordinate.latitude * M_PI / 180.0));
}
@end

#pragma mark - MapManager

@interface GPSPlusMapManager : NSObject <MKMapViewDelegate>
@property(nonatomic, strong) MKMapView *mapView;
@property(nonatomic, strong) MKPointAnnotation *pin;
- (void)attachMap:(MKMapView *)map;
- (void)moveToCoordinate:(CLLocationCoordinate2D)c animated:(BOOL)animated;
@end

@implementation GPSPlusMapManager
- (void)attachMap:(MKMapView *)map { self.mapView = map; self.mapView.delegate = self; }
- (void)moveToCoordinate:(CLLocationCoordinate2D)c animated:(BOOL)animated {
    if (!self.pin) { self.pin = [MKPointAnnotation new]; [self.mapView addAnnotation:self.pin]; }
    self.pin.coordinate = c;
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(c, 900, 900) animated:animated];
}
@end

#pragma mark - BluetoothManager

@interface GPSPlusBluetoothManager : NSObject <CBCentralManagerDelegate>
@property(nonatomic, strong) CBCentralManager *central;
@property(nonatomic, strong) NSMutableArray *devices;
+ (instancetype)shared;
- (void)startScan;
- (void)stopScan;
@end

@implementation GPSPlusBluetoothManager
+ (instancetype)shared {
    static GPSPlusBluetoothManager *m = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ m = [GPSPlusBluetoothManager new]; m.devices = [NSMutableArray array]; });
    return m;
}
- (void)startScan {
    if (!self.central) { self.central = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()]; return; }
    if (self.central.state == CBManagerStatePoweredOn) [self.central scanForPeripheralsWithServices:nil options:nil];
}
- (void)stopScan { [self.central stopScan]; }
- (void)centralManagerDidUpdateState:(CBCentralManager *)central { if (central.state == CBManagerStatePoweredOn) [self startScan]; }
@end

#pragma mark - UIComponents

@interface GPSPlusUIComponents : NSObject
+ (UIButton *)primaryButton:(NSString *)title;
+ (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight;
+ (UIView *)card;
@end

@implementation GPSPlusUIComponents
+ (UIButton *)primaryButton:(NSString *)title {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.backgroundColor = GPSPLUS_BLUE;
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    b.layer.cornerRadius = 16;
    return b;
}
+ (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *l = [UILabel new]; l.text = text; l.textColor = UIColor.whiteColor; l.font = [UIFont systemFontOfSize:size weight:weight]; return l;
}
+ (UIView *)card {
    UIView *v = [UIView new]; v.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08]; v.layer.cornerRadius = 18; return v;
}
@end

#pragma mark - OverlayView

@interface GPSPlusOverlayView : UIView
@property(nonatomic, strong) UIButton *floatButton;
@property(nonatomic, strong) UIVisualEffectView *panel;
@property(nonatomic, strong) MKMapView *map;
@property(nonatomic, strong) GPSPlusMapManager *mapManager;
+ (instancetype)shared;
- (void)togglePanel;
@end

@implementation GPSPlusOverlayView
+ (instancetype)shared {
    static GPSPlusOverlayView *v = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ v = [[GPSPlusOverlayView alloc] initWithFrame:UIScreen.mainScreen.bounds]; });
    return v;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) { self.backgroundColor = UIColor.clearColor; [self buildUI]; }
    return self;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
- (void)buildUI {
    CGFloat w = self.bounds.size.width;
    self.floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatButton.frame = CGRectMake(18, 88, 58, 58);
    self.floatButton.layer.cornerRadius = 29;
    self.floatButton.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
    [self.floatButton setTitle:@"GPS" forState:UIControlStateNormal];
    [self.floatButton setTitleColor:GPSPLUS_GOLD forState:UIControlStateNormal];
    [self.floatButton addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.floatButton];

    CGFloat pw = MIN(w - 24, 420);
    CGFloat ph = MIN(self.bounds.size.height - 80, 760);
    self.panel = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    self.panel.frame = CGRectMake((w - pw) / 2.0, 50, pw, ph);
    self.panel.layer.cornerRadius = 24;
    self.panel.clipsToBounds = YES;
    self.panel.hidden = YES;
    [self addSubview:self.panel];

    UILabel *title = [GPSPlusUIComponents label:GPSPLUS_NAME size:20 weight:UIFontWeightBold];
    title.frame = CGRectMake(20, 16, pw - 40, 30);
    title.textAlignment = NSTextAlignmentCenter;
    [self.panel.contentView addSubview:title];

    self.map = [[MKMapView alloc] initWithFrame:CGRectMake(16, 62, pw - 32, 260)];
    self.map.layer.cornerRadius = 18;
    self.map.clipsToBounds = YES;
    [self.panel.contentView addSubview:self.map];

    self.mapManager = [GPSPlusMapManager new];
    [self.mapManager attachMap:self.map];
    [self.mapManager moveToCoordinate:GPSPlusLocationManager.shared.fakeCoordinate animated:NO];

    UIButton *choose = [GPSPlusUIComponents primaryButton:@"📍 اختر هذا الموقع"];
    choose.frame = CGRectMake(16, ph - 72, pw - 32, 54);
    [choose addTarget:self action:@selector(selectLocation) forControlEvents:UIControlEventTouchUpInside];
    [self.panel.contentView addSubview:choose];
}
- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
    if (GPSPlusSettingsManager.shared.haptics) [GPSPlusUtilities haptic];
}
- (void)selectLocation {
    CLLocationCoordinate2D c = self.map.centerCoordinate;
    [GPSPlusLocationManager.shared setFakeCoordinateAndSave:c];
    [self.mapManager moveToCoordinate:c animated:YES];
    if (GPSPlusSettingsManager.shared.haptics) [GPSPlusUtilities haptic];
}
@end

#pragma mark - Hooks Entry

__attribute__((constructor))
static void GPSPlusProInit(void) {
    [GPSPlusUtilities runOnMain:^{
        UIWindow *window = UIApplication.sharedApplication.keyWindow;
        if (!window) return;
        GPSPlusOverlayView *overlay = [GPSPlusOverlayView shared];
        overlay.frame = UIScreen.mainScreen.bounds;
        [window addSubview:overlay];
        [GPSPlusLocationManager.shared startJitter];
    }];
}
