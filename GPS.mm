// GPS.mm
// Final cleaned Objective-C++ rebuild for the GPS project.
// Source basis: uploaded GPSPlus.dylib analysis + provided UI screenshots.
// UI name: GPS
// Build system: Theos tweak
//
// Safety note:
// This rebuild keeps the useful map/search/favorites/UI/testing behavior only.
// It intentionally does not copy app-bypass, anti-detection, or third-party identity-bypass logic
// found in the analyzed binary.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

extern "C" void MSHookMessageEx(Class cls, SEL sel, IMP replacement, IMP *result);

#pragma mark - Constants

static NSString * const kGPSSuite                 = @"com.khalid.gps";
static NSString * const kGPSSelectedLocationKey   = @"gps_selected_location";
static NSString * const kGPSFavoritesKey          = @"gps_favorites";
static NSString * const kGPSEnabledKey            = @"gps_enabled";
static NSString * const kGPSMotionEnabledKey      = @"gps_motion_enabled";
static NSString * const kGPSToolHiddenKey         = @"gps_tool_hidden";
static NSString * const kGPSRevealTapCountKey     = @"gps_reveal_tap_count";
static NSString * const kGPSCustomIDKey           = @"gps_custom_identifier_local";
static NSString * const kGPSImagePathKey          = @"gps_uploaded_image_path";
static NSString * const kGPSMapTypeKey            = @"gps_map_type";
static NSString * const kGPSStatusChangedNote     = @"GPSStatusChanged";
static NSString * const kGPSToolVisibilityNote    = @"GPSToolVisibilityChanged";

static CGFloat const kGPSMotionRadiusMeters = 10.0;

#pragma mark - Helpers

static inline BOOL GPSValidCoordinate(CLLocationCoordinate2D c) {
    return CLLocationCoordinate2DIsValid(c) && fabs(c.latitude) <= 90.0 && fabs(c.longitude) <= 180.0;
}

static inline NSString *GPSCoordText(CLLocationCoordinate2D c) {
    if (!GPSValidCoordinate(c)) return @"--";
    return [NSString stringWithFormat:@"%.6f, %.6f", c.latitude, c.longitude];
}

static UIWindow *GPSActiveWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    UIWindow *candidate = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *window in ws.windows) {
                if (window.isKeyWindow) return window;
                if (!candidate && !window.hidden && window.alpha > 0.01) candidate = window;
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (!candidate) candidate = app.keyWindow;
    if (!candidate) candidate = app.windows.firstObject;
#pragma clang diagnostic pop
    return candidate;
}

static UIViewController *GPSTopController(void) {
    UIViewController *vc = GPSActiveWindow().rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) vc = ((UINavigationController *)vc).topViewController;
    if ([vc isKindOfClass:UITabBarController.class]) vc = ((UITabBarController *)vc).selectedViewController;
    return vc;
}

static UIColor *GPSRGB(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}
static UIColor *GPSGreen(void)  { return GPSRGB(34, 197, 94); }      // يعمل
static UIColor *GPSBlack(void)  { return GPSRGB(18, 18, 18); }      // مغلق
static UIColor *GPSPanelBG(void){ return GPSRGB(22, 22, 24); }
static UIColor *GPSHeaderBG(void){ return GPSRGB(29, 29, 33); }
static UIColor *GPSCard(void)   { return GPSRGB(47, 47, 54); }
static UIColor *GPSBlue(void)   { return GPSRGB(0, 122, 255); }
static UIColor *GPSPurple(void) { return GPSRGB(181, 82, 232); }
static UIColor *GPSRed(void)    { return GPSRGB(255, 65, 58); }

static void GPSRound(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    view.layer.masksToBounds = YES;
}

static UILabel *GPSLabel(NSString *text, CGFloat size, UIColor *color, NSTextAlignment alignment, BOOL bold) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.textColor = color;
    label.textAlignment = alignment;
    label.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    label.numberOfLines = 1;
    return label;
}

#pragma mark - Model

@interface GPSLocationItem : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *shortAddress;
@property (nonatomic, copy) NSString *fullAddress;
@property (nonatomic) double latitude;
@property (nonatomic) double longitude;
- (instancetype)initWithName:(NSString *)name coordinate:(CLLocationCoordinate2D)c;
- (CLLocationCoordinate2D)coordinate;
- (NSDictionary *)dictionaryValue;
+ (instancetype)itemFromDictionary:(NSDictionary *)dict;
@end

@implementation GPSLocationItem
+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithName:(NSString *)name coordinate:(CLLocationCoordinate2D)c {
    self = [super init];
    if (self) {
        _name = name.length ? [name copy] : @"الموقع المحدد";
        _shortAddress = GPSCoordText(c);
        _fullAddress = @"";
        _latitude = c.latitude;
        _longitude = c.longitude;
    }
    return self;
}

- (CLLocationCoordinate2D)coordinate {
    return CLLocationCoordinate2DMake(self.latitude, self.longitude);
}

- (NSDictionary *)dictionaryValue {
    return @{
        @"name": self.name ?: @"الموقع المحدد",
        @"shortAddress": self.shortAddress ?: @"",
        @"fullAddress": self.fullAddress ?: @"",
        @"latitude": @(self.latitude),
        @"longitude": @(self.longitude)
    };
}

+ (instancetype)itemFromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:NSDictionary.class]) return nil;
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake([dict[@"latitude"] doubleValue], [dict[@"longitude"] doubleValue]);
    if (!GPSValidCoordinate(c)) return nil;
    GPSLocationItem *item = [[GPSLocationItem alloc] initWithName:[dict[@"name"] isKindOfClass:NSString.class] ? dict[@"name"] : @"الموقع المحدد" coordinate:c];
    item.shortAddress = [dict[@"shortAddress"] isKindOfClass:NSString.class] ? dict[@"shortAddress"] : GPSCoordText(c);
    item.fullAddress = [dict[@"fullAddress"] isKindOfClass:NSString.class] ? dict[@"fullAddress"] : @"";
    return item;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake([coder decodeDoubleForKey:@"latitude"], [coder decodeDoubleForKey:@"longitude"]);
    self = [self initWithName:[coder decodeObjectOfClass:NSString.class forKey:@"name"] coordinate:c];
    if (self) {
        _shortAddress = [[coder decodeObjectOfClass:NSString.class forKey:@"shortAddress"] copy] ?: GPSCoordText(c);
        _fullAddress = [[coder decodeObjectOfClass:NSString.class forKey:@"fullAddress"] copy] ?: @"";
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.name forKey:@"name"];
    [coder encodeObject:self.shortAddress forKey:@"shortAddress"];
    [coder encodeObject:self.fullAddress forKey:@"fullAddress"];
    [coder encodeDouble:self.latitude forKey:@"latitude"];
    [coder encodeDouble:self.longitude forKey:@"longitude"];
}
@end

#pragma mark - Parser

@interface GPSParseResult : NSObject
@property (nonatomic) BOOL hasCoordinate;
@property (nonatomic) CLLocationCoordinate2D coordinate;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *displayName;
@end
@implementation GPSParseResult @end

@interface GPSLocationParser : NSObject
+ (GPSParseResult *)parseInput:(NSString *)input;
@end

@implementation GPSLocationParser

+ (NSRegularExpression *)coordinateRegex {
    static NSRegularExpression *rx;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rx = [NSRegularExpression regularExpressionWithPattern:@"(-?\\d{1,2}(?:\\.\\d+)?)\\s*[,، ]\\s*(-?\\d{1,3}(?:\\.\\d+)?)" options:0 error:nil];
    });
    return rx;
}

+ (BOOL)extractCoordinateFromString:(NSString *)s into:(CLLocationCoordinate2D *)outCoord {
    if (!s.length) return NO;
    NSTextCheckingResult *m = [[self coordinateRegex] firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (m.numberOfRanges < 3) return NO;
    double lat = [[s substringWithRange:[m rangeAtIndex:1]] doubleValue];
    double lon = [[s substringWithRange:[m rangeAtIndex:2]] doubleValue];
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake(lat, lon);
    if (!GPSValidCoordinate(c)) return NO;
    if (outCoord) *outCoord = c;
    return YES;
}

+ (GPSParseResult *)parseInput:(NSString *)input {
    GPSParseResult *result = [GPSParseResult new];
    NSString *s = [[input ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] copy];
    result.query = s;
    result.source = @"text";
    if (!s.length) return result;

    CLLocationCoordinate2D direct;
    if ([self extractCoordinateFromString:s into:&direct]) {
        result.hasCoordinate = YES;
        result.coordinate = direct;
        result.source = @"coordinates";
        result.displayName = @"إحداثيات مباشرة";
        return result;
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:s];
    NSString *host = components.host.lowercaseString ?: @"";
    NSString *path = [components.path stringByRemovingPercentEncoding] ?: @"";
    NSString *lowerURL = s.lowercaseString;
    BOOL isGoogle = [host containsString:@"google"] || [host containsString:@"goo.gl"] || [host containsString:@"maps.app.goo.gl"] || [lowerURL containsString:@"google.com/maps"];
    BOOL isApple  = [host containsString:@"apple"] || [host containsString:@"maps.apple"] || [lowerURL containsString:@"maps.apple.com"];

    if (isGoogle) result.source = @"google_maps";
    if (isApple) result.source = @"apple_maps";

    // Google URL form: /@lat,long,zoom
    if (isGoogle) {
        NSRegularExpression *atRx = [NSRegularExpression regularExpressionWithPattern:@"@(-?\\d{1,2}(?:\\.\\d+)?),(-?\\d{1,3}(?:\\.\\d+)?)" options:0 error:nil];
        NSTextCheckingResult *m = [atRx firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        if (m.numberOfRanges >= 3) {
            CLLocationCoordinate2D c = CLLocationCoordinate2DMake([[s substringWithRange:[m rangeAtIndex:1]] doubleValue], [[s substringWithRange:[m rangeAtIndex:2]] doubleValue]);
            if (GPSValidCoordinate(c)) {
                result.hasCoordinate = YES;
                result.coordinate = c;
                result.displayName = @"Google Maps";
                return result;
            }
        }

        // Google internal share form: !3dlat!4dlon
        NSRegularExpression *bangRx = [NSRegularExpression regularExpressionWithPattern:@"!3d(-?\\d{1,2}(?:\\.\\d+)?)!4d(-?\\d{1,3}(?:\\.\\d+)?)" options:0 error:nil];
        NSTextCheckingResult *bm = [bangRx firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        if (bm.numberOfRanges >= 3) {
            CLLocationCoordinate2D c = CLLocationCoordinate2DMake([[s substringWithRange:[bm rangeAtIndex:1]] doubleValue], [[s substringWithRange:[bm rangeAtIndex:2]] doubleValue]);
            if (GPSValidCoordinate(c)) {
                result.hasCoordinate = YES;
                result.coordinate = c;
                result.displayName = @"Google Maps";
                return result;
            }
        }
    }

    // Query items: q, query, ll, address, daddr, saddr
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        NSString *name = item.name.lowercaseString ?: @"";
        NSString *value = [[item.value ?: @"" stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding] ?: item.value ?: @"";
        if (!value.length) continue;
        BOOL relevant = [@[@"q", @"query", @"ll", @"address", @"daddr", @"saddr"] containsObject:name];
        if (!relevant) continue;

        CLLocationCoordinate2D c;
        if ([self extractCoordinateFromString:value into:&c]) {
            result.hasCoordinate = YES;
            result.coordinate = c;
            result.displayName = isApple ? @"Apple Maps" : (isGoogle ? @"Google Maps" : @"رابط خرائط");
            return result;
        }
        result.query = value;
        result.source = isApple ? @"apple_maps_query" : (isGoogle ? @"google_maps_query" : @"url_query");
        result.displayName = value;
    }

    // Google /place/name
    if (isGoogle && [path containsString:@"/place/"]) {
        NSArray *parts = [path componentsSeparatedByString:@"/place/"];
        if (parts.count > 1) {
            NSString *place = [[parts[1] componentsSeparatedByString:@"/"] firstObject];
            place = [[place stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding];
            if (place.length) {
                result.query = place;
                result.displayName = place;
                result.source = @"google_maps_place";
            }
        }
    }

    return result;
}
@end

#pragma mark - Manager

@interface GPSManager : NSObject <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLLocation *lastRealLocation;
@property (nonatomic, strong) GPSLocationItem *selectedLocation;
@property (nonatomic, strong) NSMutableArray<GPSLocationItem *> *favorites;
@property (nonatomic, copy) NSString *customIdentifier;
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic) BOOL enabled;
@property (nonatomic) BOOL motionEnabled;
@property (nonatomic) BOOL toolHidden;
@property (nonatomic) NSInteger revealTapCount;
@property (nonatomic) NSInteger mapTypeIndex;
+ (instancetype)shared;
- (void)save;
- (void)selectLocation:(GPSLocationItem *)item;
- (void)addFavorite:(GPSLocationItem *)item;
- (void)clearFavorites;
- (CLLocation *)spoofedLocation;
- (NSString *)statusText;
@end

@implementation GPSManager
+ (instancetype)shared {
    static GPSManager *manager = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ manager = [[GPSManager alloc] init]; });
    return manager;
}

- (NSUserDefaults *)defaults {
    return [[NSUserDefaults alloc] initWithSuiteName:kGPSSuite] ?: NSUserDefaults.standardUserDefaults;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *d = [self defaults];
        _enabled = [d objectForKey:kGPSEnabledKey] ? [d boolForKey:kGPSEnabledKey] : NO;
        _motionEnabled = [d objectForKey:kGPSMotionEnabledKey] ? [d boolForKey:kGPSMotionEnabledKey] : NO;
        _toolHidden = [d boolForKey:kGPSToolHiddenKey];
        _revealTapCount = [d objectForKey:kGPSRevealTapCountKey] ? [d integerForKey:kGPSRevealTapCountKey] : 3;
        if (_revealTapCount < 2) _revealTapCount = 3;
        _customIdentifier = [d stringForKey:kGPSCustomIDKey] ?: UIDevice.currentDevice.identifierForVendor.UUIDString;
        _imagePath = [d stringForKey:kGPSImagePathKey];
        _mapTypeIndex = [d objectForKey:kGPSMapTypeKey] ? [d integerForKey:kGPSMapTypeKey] : 0;
        NSDictionary *storedLocation = [d dictionaryForKey:kGPSSelectedLocationKey];
        _selectedLocation = [GPSLocationItem itemFromDictionary:storedLocation];
        _favorites = [NSMutableArray array];
        for (NSDictionary *dict in [d arrayForKey:kGPSFavoritesKey] ?: @[]) {
            GPSLocationItem *item = [GPSLocationItem itemFromDictionary:dict];
            if (item) [_favorites addObject:item];
        }

        _locationManager = [CLLocationManager new];
        _locationManager.delegate = self;
        _locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        if ([_locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) [_locationManager requestWhenInUseAuthorization];
        [_locationManager startUpdatingLocation];
    }
    return self;
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [[self defaults] setBool:enabled forKey:kGPSEnabledKey];
    [self save];
    [[NSNotificationCenter defaultCenter] postNotificationName:kGPSStatusChangedNote object:self];
}

- (void)setMotionEnabled:(BOOL)motionEnabled {
    _motionEnabled = motionEnabled;
    [[self defaults] setBool:motionEnabled forKey:kGPSMotionEnabledKey];
    [self save];
    [[NSNotificationCenter defaultCenter] postNotificationName:kGPSStatusChangedNote object:self];
}

- (void)setToolHidden:(BOOL)toolHidden {
    _toolHidden = toolHidden;
    [[self defaults] setBool:toolHidden forKey:kGPSToolHiddenKey];
    [self save];
    [[NSNotificationCenter defaultCenter] postNotificationName:kGPSToolVisibilityNote object:self];
}

- (void)setRevealTapCount:(NSInteger)revealTapCount {
    _revealTapCount = MAX(2, revealTapCount);
    [[self defaults] setInteger:_revealTapCount forKey:kGPSRevealTapCountKey];
    [self save];
}

- (void)setCustomIdentifier:(NSString *)customIdentifier {
    _customIdentifier = customIdentifier.length ? [customIdentifier copy] : UIDevice.currentDevice.identifierForVendor.UUIDString;
    [[self defaults] setObject:_customIdentifier forKey:kGPSCustomIDKey];
    [self save];
}

- (void)setImagePath:(NSString *)imagePath {
    _imagePath = [imagePath copy];
    if (_imagePath.length) [[self defaults] setObject:_imagePath forKey:kGPSImagePathKey];
    else [[self defaults] removeObjectForKey:kGPSImagePathKey];
    [self save];
}

- (void)setMapTypeIndex:(NSInteger)mapTypeIndex {
    _mapTypeIndex = MAX(0, MIN(2, mapTypeIndex));
    [[self defaults] setInteger:_mapTypeIndex forKey:kGPSMapTypeKey];
    [self save];
}

- (void)save {
    NSUserDefaults *d = [self defaults];
    if (self.selectedLocation) [d setObject:self.selectedLocation.dictionaryValue forKey:kGPSSelectedLocationKey];
    NSMutableArray *arr = [NSMutableArray array];
    for (GPSLocationItem *item in self.favorites) [arr addObject:item.dictionaryValue];
    [d setObject:arr forKey:kGPSFavoritesKey];
    [d synchronize];
}

- (void)selectLocation:(GPSLocationItem *)item {
    if (!item || !GPSValidCoordinate(item.coordinate)) return;
    self.selectedLocation = item;
    [self save];
    [[NSNotificationCenter defaultCenter] postNotificationName:kGPSStatusChangedNote object:self];
}

- (void)addFavorite:(GPSLocationItem *)item {
    if (!item || !GPSValidCoordinate(item.coordinate)) return;
    for (GPSLocationItem *existing in self.favorites) {
        if (fabs(existing.latitude - item.latitude) < 0.000001 && fabs(existing.longitude - item.longitude) < 0.000001) return;
    }
    [self.favorites addObject:item];
    [self save];
}

- (void)clearFavorites {
    [self.favorites removeAllObjects];
    [self save];
    [[NSNotificationCenter defaultCenter] postNotificationName:kGPSStatusChangedNote object:self];
}

- (CLLocation *)spoofedLocation {
    if (!self.enabled || !self.selectedLocation) return nil;
    CLLocationCoordinate2D c = self.selectedLocation.coordinate;
    if (self.motionEnabled) {
        double angle = fmod(CFAbsoluteTimeGetCurrent() / 4.0, M_PI * 2.0);
        double meters = kGPSMotionRadiusMeters;
        double latDelta = (meters * cos(angle)) / 111111.0;
        double lonDelta = (meters * sin(angle)) / (111111.0 * cos(c.latitude * M_PI / 180.0));
        c.latitude += latDelta;
        c.longitude += lonDelta;
    }
    return [[CLLocation alloc] initWithCoordinate:c altitude:0 horizontalAccuracy:5 verticalAccuracy:5 timestamp:NSDate.date];
}

- (NSString *)statusText {
    return self.enabled ? @"يعمل" : @"مغلق";
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *last = locations.lastObject;
    if (last && !self.enabled) self.lastRealLocation = last;
}
@end

#pragma mark - Main UI

@interface GPSPanelController : UIViewController <MKMapViewDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *infoButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UISegmentedControl *mapTypeSegment;
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UIButton *gpsBadge;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UILabel *statusChip;
@property (nonatomic, strong) UILabel *placeLabel;
@property (nonatomic, strong) UILabel *coordLabel;
@property (nonatomic, strong) UILabel *addressLabel;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UISwitch *motionSwitch;
@property (nonatomic, strong) UIImageView *previewImageView;
@property (nonatomic, strong) MKPointAnnotation *pin;
@end

@implementation GPSPanelController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = GPSPanelBG();
    [self buildUI];
    [self refreshUI];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshUI) name:kGPSStatusChangedNote object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutUI];
}

- (void)buildUI {
    self.topBar = [UIView new];
    self.topBar.backgroundColor = GPSHeaderBG();
    [self.view addSubview:self.topBar];

    self.infoButton = [self iconButton:@"info.circle" fallback:@"i" color:GPSBlue()];
    [self.infoButton addTarget:self action:@selector(showCodeInfo) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.infoButton];

    self.closeButton = [self iconButton:@"xmark" fallback:@"×" color:GPSBlue()];
    [self.closeButton addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.closeButton];

    self.titleLabel = GPSLabel(@"GPS", 28, UIColor.whiteColor, NSTextAlignmentCenter, YES);
    [self.topBar addSubview:self.titleLabel];

    self.mapTypeSegment = [[UISegmentedControl alloc] initWithItems:@[@"خريطة", @"قمر صناعي", @"مخطط"]];
    self.mapTypeSegment.selectedSegmentIndex = GPSManager.shared.mapTypeIndex;
    [self.mapTypeSegment addTarget:self action:@selector(changeMapType:) forControlEvents:UIControlEventValueChanged];
    [self.topBar addSubview:self.mapTypeSegment];

    self.mapView = [MKMapView new];
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = YES;
    self.mapView.mapType = [self mapTypeForIndex:GPSManager.shared.mapTypeIndex];
    [self.view addSubview:self.mapView];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressMap:)];
    [self.mapView addGestureRecognizer:longPress];

    self.gpsBadge = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.gpsBadge setTitle:@"GPS" forState:UIControlStateNormal];
    self.gpsBadge.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [self.gpsBadge addTarget:self action:@selector(centerMap) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.gpsBadge];

    self.scrollView = [UIScrollView new];
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.scrollView];

    self.contentView = [UIView new];
    [self.scrollView addSubview:self.contentView];

    self.statusChip = GPSLabel(@"مغلق", 14, UIColor.whiteColor, NSTextAlignmentCenter, YES);
    GPSRound(self.statusChip, 12);
    [self.contentView addSubview:self.statusChip];

    self.placeLabel = GPSLabel(@"لا يوجد موقع", 19, UIColor.whiteColor, NSTextAlignmentRight, YES);
    [self.contentView addSubview:self.placeLabel];

    self.coordLabel = GPSLabel(@"اضغط مطولًا على الخريطة أو استخدم البحث", 14, [UIColor colorWithWhite:0.75 alpha:1], NSTextAlignmentRight, NO);
    [self.contentView addSubview:self.coordLabel];

    self.addressLabel = GPSLabel(@"", 13, [UIColor colorWithWhite:0.62 alpha:1], NSTextAlignmentRight, NO);
    self.addressLabel.numberOfLines = 2;
    [self.contentView addSubview:self.addressLabel];

    UIButton *search = [self actionButton:@"بحث" color:GPSCard()];
    search.tag = 101;
    [search addTarget:self action:@selector(showSearch) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:search];

    UIButton *favorites = [self actionButton:@"المفضلة" color:GPSPurple()];
    favorites.tag = 102;
    [favorites addTarget:self action:@selector(showFavorites) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:favorites];

    UIButton *identity = [self actionButton:@"إعدادات المعرف" color:GPSCard()];
    identity.tag = 103;
    [identity addTarget:self action:@selector(showIdentifierSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:identity];

    UIButton *upload = [self actionButton:@"رفع الصورة" color:GPSCard()];
    upload.tag = 104;
    [upload addTarget:self action:@selector(uploadImage) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:upload];

    self.previewImageView = [UIImageView new];
    self.previewImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.previewImageView.hidden = YES;
    GPSRound(self.previewImageView, 14);
    [self.contentView addSubview:self.previewImageView];

    UIButton *hide = [self actionButton:@"إخفاء الأداة" color:GPSRed()];
    hide.tag = 105;
    [hide addTarget:self action:@selector(hideToolTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:hide];

    [self addSwitchRow:@"تفعيل تغيير الموقع" selector:@selector(switchChanged:) assign:^(UISwitch *sw) { self.enabledSwitch = sw; } tag:201];
    [self addSwitchRow:@"تفعيل الحركة للموقع" selector:@selector(switchChanged:) assign:^(UISwitch *sw) { self.motionSwitch = sw; } tag:202];

    UIButton *choose = [self actionButton:@"اختر هذا الموقع" color:GPSBlue()];
    choose.tag = 106;
    [choose addTarget:self action:@selector(applyLocation) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:choose];
}

- (void)layoutUI {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;

    CGFloat topBarH = safeTop + 96;
    self.topBar.frame = CGRectMake(0, 0, w, topBarH);
    self.infoButton.frame = CGRectMake(16, safeTop + 10, 46, 46);
    self.closeButton.frame = CGRectMake(w - 62, safeTop + 10, 46, 46);
    self.titleLabel.frame = CGRectMake(80, safeTop + 10, w - 160, 46);
    self.mapTypeSegment.frame = CGRectMake(18, safeTop + 62, w - 36, 34);

    CGFloat mapH = MIN(390.0, MAX(275.0, h * 0.40));
    self.mapView.frame = CGRectMake(0, topBarH, w, mapH);
    self.gpsBadge.frame = CGRectMake(22, topBarH + 18, 68, 68);
    GPSRound(self.gpsBadge, 34);

    CGFloat scrollY = CGRectGetMaxY(self.mapView.frame);
    self.scrollView.frame = CGRectMake(0, scrollY, w, h - scrollY);
    self.contentView.frame = CGRectMake(0, 0, w, 0);

    CGFloat y = 18;
    self.statusChip.frame = CGRectMake(20, y, 84, 28);
    self.placeLabel.frame = CGRectMake(112, y - 2, w - 132, 30);
    y += 32;
    self.coordLabel.frame = CGRectMake(20, y, w - 40, 22);
    y += 24;
    self.addressLabel.frame = CGRectMake(20, y, w - 40, 38);
    y += 48;

    CGFloat gap = 14;
    CGFloat bw = (w - 40 - gap) / 2.0;
    [self buttonWithTag:101].frame = CGRectMake(20, y, bw, 48);
    [self buttonWithTag:102].frame = CGRectMake(20 + bw + gap, y, bw, 48);
    y += 60;
    [self buttonWithTag:103].frame = CGRectMake(20, y, bw, 48);
    [self buttonWithTag:104].frame = CGRectMake(20 + bw + gap, y, bw, 48);
    self.previewImageView.frame = CGRectMake(24, y + 60, 52, 52);
    y += 60;

    [self buttonWithTag:105].frame = CGRectMake(20, y, w - 40, 50);
    y += 66;

    [self layoutSwitchRow:201 y:y width:w];
    y += 54;
    [self layoutSwitchRow:202 y:y width:w];
    y += 70;

    [self buttonWithTag:106].frame = CGRectMake(20, y, w - 40, 56);
    y += 72 + safeBottom;

    self.contentView.frame = CGRectMake(0, 0, w, y);
    self.scrollView.contentSize = CGSizeMake(w, y);
}

- (UIButton *)buttonWithTag:(NSInteger)tag {
    return (UIButton *)[self.contentView viewWithTag:tag];
}

- (UIButton *)iconButton:(NSString *)symbol fallback:(NSString *)fallback color:(UIColor *)color {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 13.0, *)) [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    else [button setTitle:fallback forState:UIControlStateNormal];
    button.tintColor = color;
    button.titleLabel.font = [UIFont boldSystemFontOfSize:30];
    return button;
}

- (UIButton *)actionButton:(NSString *)title color:(UIColor *)color {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = color;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    GPSRound(button, 12);
    return button;
}

- (void)addSwitchRow:(NSString *)title selector:(SEL)selector assign:(void(^)(UISwitch *sw))assign tag:(NSInteger)tag {
    UIView *row = [UIView new];
    row.tag = tag;
    [self.contentView addSubview:row];

    UILabel *label = GPSLabel(title, 22, UIColor.whiteColor, NSTextAlignmentRight, YES);
    label.tag = 1;
    [row addSubview:label];

    UISwitch *sw = [UISwitch new];
    sw.tag = 2;
    sw.onTintColor = GPSGreen();
    sw.tintColor = GPSBlack();
    sw.backgroundColor = GPSBlack();
    GPSRound(sw, 16);
    [sw addTarget:self action:selector forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];
    if (assign) assign(sw);
}

- (void)layoutSwitchRow:(NSInteger)tag y:(CGFloat)y width:(CGFloat)w {
    UIView *row = [self.contentView viewWithTag:tag];
    row.frame = CGRectMake(20, y, w - 40, 44);
    UILabel *label = [row viewWithTag:1];
    UISwitch *sw = [row viewWithTag:2];
    sw.frame = CGRectMake(row.bounds.size.width - 72, 2, 64, 40);
    label.frame = CGRectMake(0, 0, row.bounds.size.width - 90, 44);
}

- (MKMapType)mapTypeForIndex:(NSInteger)idx {
    if (idx == 1) return MKMapTypeSatellite;
    if (idx == 2) return MKMapTypeHybrid;
    return MKMapTypeStandard;
}

- (void)refreshUI {
    GPSManager *manager = GPSManager.shared;
    self.enabledSwitch.on = manager.enabled;
    self.motionSwitch.on = manager.motionEnabled;
    self.gpsBadge.backgroundColor = manager.enabled ? GPSGreen() : [UIColor colorWithWhite:0.18 alpha:0.80];
    self.statusChip.text = manager.statusText;
    self.statusChip.backgroundColor = manager.enabled ? GPSGreen() : GPSBlack();

    GPSLocationItem *item = manager.selectedLocation;
    self.placeLabel.text = item ? item.name : @"لا يوجد موقع";
    self.coordLabel.text = item ? GPSCoordText(item.coordinate) : @"اضغط مطولًا على الخريطة أو استخدم البحث";
    self.addressLabel.text = item.fullAddress.length ? item.fullAddress : (item.shortAddress ?: @"");
    if (item) [self updatePin:item.coordinate name:item.name];

    UIImage *image = manager.imagePath.length ? [UIImage imageWithContentsOfFile:manager.imagePath] : nil;
    self.previewImageView.image = image;
    self.previewImageView.hidden = (image == nil);
}

#pragma mark - Map / location

- (void)changeMapType:(UISegmentedControl *)sender {
    GPSManager.shared.mapTypeIndex = sender.selectedSegmentIndex;
    self.mapView.mapType = [self mapTypeForIndex:sender.selectedSegmentIndex];
}

- (void)switchChanged:(UISwitch *)sw {
    if (sw == self.enabledSwitch) GPSManager.shared.enabled = sw.on;
    if (sw == self.motionSwitch) GPSManager.shared.motionEnabled = sw.on;
    [self refreshUI];
}

- (void)longPressMap:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CGPoint point = [gesture locationInView:self.mapView];
    CLLocationCoordinate2D c = [self.mapView convertPoint:point toCoordinateFromView:self.mapView];
    [self selectCoordinate:c name:@"الموقع المحدد" address:nil reverse:YES];
}

- (void)selectCoordinate:(CLLocationCoordinate2D)c name:(NSString *)name address:(NSString *)address reverse:(BOOL)reverse {
    if (!GPSValidCoordinate(c)) return;
    GPSLocationItem *item = [[GPSLocationItem alloc] initWithName:name ?: @"الموقع المحدد" coordinate:c];
    item.fullAddress = address ?: @"";
    [GPSManager.shared selectLocation:item];
    [self updatePin:c name:item.name];
    [self centerOn:c animated:YES];
    [self refreshUI];

    if (reverse) {
        CLLocation *loc = [[CLLocation alloc] initWithLatitude:c.latitude longitude:c.longitude];
        CLGeocoder *geocoder = [CLGeocoder new];
        __weak typeof(self) weakSelf = self;
        [geocoder reverseGeocodeLocation:loc completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
            if (error) return;
            CLPlacemark *pm = placemarks.firstObject;
            if (!pm) return;
            NSString *shortName = pm.name ?: pm.locality ?: item.name;
            NSMutableArray *parts = [NSMutableArray array];
            if (pm.thoroughfare) [parts addObject:pm.thoroughfare];
            if (pm.locality) [parts addObject:pm.locality];
            if (pm.administrativeArea) [parts addObject:pm.administrativeArea];
            if (pm.country) [parts addObject:pm.country];
            item.name = shortName ?: item.name;
            item.fullAddress = [parts componentsJoinedByString:@"، "];
            item.shortAddress = GPSCoordText(c);
            [GPSManager.shared selectLocation:item];
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refreshUI]; });
        }];
    }
}

- (void)updatePin:(CLLocationCoordinate2D)c name:(NSString *)name {
    if (!GPSValidCoordinate(c)) return;
    if (!self.pin) {
        self.pin = [MKPointAnnotation new];
        [self.mapView addAnnotation:self.pin];
    }
    self.pin.coordinate = c;
    self.pin.title = name ?: @"الموقع المحدد";
}

- (void)centerOn:(CLLocationCoordinate2D)c animated:(BOOL)animated {
    if (!GPSValidCoordinate(c)) return;
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(c, 1500, 1500) animated:animated];
}

- (void)centerMap {
    GPSLocationItem *selected = GPSManager.shared.selectedLocation;
    CLLocation *real = GPSManager.shared.lastRealLocation;
    if (selected) [self centerOn:selected.coordinate animated:YES];
    else if (real) [self centerOn:real.coordinate animated:YES];
}

#pragma mark - Actions

- (void)showCodeInfo {
    GPSManager *m = GPSManager.shared;
    NSString *location = m.selectedLocation ? GPSCoordText(m.selectedLocation.coordinate) : @"غير محدد";
    NSString *message = [NSString stringWithFormat:@"الحالة: %@\nالمعرف المحلي: %@\nإظهار الأداة بعد: %ld ضغطات\nالموقع: %@\nالصورة: %@", m.statusText, m.customIdentifier ?: @"--", (long)m.revealTapCount, location, m.imagePath.length ? @"مرفوعة" : @"غير مرفوعة"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"معلومات الكود" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"نسخ المعرف" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = m.customIdentifier ?: @"";
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"موافق" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)closePanel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showSearch {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"بحث" message:@"ضع اسم مكان، إحداثيات، رابط Google Maps أو Apple Maps" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"24.7136,46.6753 أو رابط خرائط";
        tf.textAlignment = NSTextAlignmentRight;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"بحث" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf runSearch:alert.textFields.firstObject.text];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)runSearch:(NSString *)text {
    GPSParseResult *result = [GPSLocationParser parseInput:text];
    if (result.hasCoordinate) {
        [self selectCoordinate:result.coordinate name:result.displayName ?: @"الموقع المحدد" address:result.source reverse:YES];
        return;
    }
    if (!result.query.length) {
        [self showAlert:@"لا يوجد مدخل" message:@"اكتب اسم مكان أو رابط خرائط أو إحداثيات."];
        return;
    }

    MKLocalSearchRequest *request = [MKLocalSearchRequest new];
    request.naturalLanguageQuery = result.query;
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    __weak typeof(self) weakSelf = self;
    [search startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            MKMapItem *first = response.mapItems.firstObject;
            if (!first || error) {
                [weakSelf showAlert:@"لم يتم العثور" message:@"جرّب اسمًا أوضح أو استخدم الإحداثيات مباشرة."];
                return;
            }
            NSString *name = first.name ?: result.query;
            NSString *address = first.placemark.title ?: @"";
            [weakSelf selectCoordinate:first.placemark.coordinate name:name address:address reverse:NO];
        });
    }];
}

- (void)showFavorites {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"المفضلة" message:@"اختر موقعًا أو احفظ الموقع الحالي" preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    GPSManager *m = GPSManager.shared;

    if (m.selectedLocation) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"حفظ الموقع الحالي" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [m addFavorite:m.selectedLocation];
            [weakSelf showAlert:@"تم الحفظ" message:@"تمت إضافة الموقع إلى المفضلة."];
        }]];
    }

    for (GPSLocationItem *item in m.favorites) {
        [sheet addAction:[UIAlertAction actionWithTitle:item.name style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [m selectLocation:item];
            [weakSelf centerOn:item.coordinate animated:YES];
            [weakSelf refreshUI];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"حذف كل المفضلات" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [m clearFavorites];
        [weakSelf refreshUI];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height - 80, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showIdentifierSettings {
    GPSManager *m = GPSManager.shared;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"إعدادات المعرف" message:@"معرف محلي داخل الأداة فقط، وليس لتجاوز حماية التطبيقات." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = m.customIdentifier;
        tf.textAlignment = NSTextAlignmentLeft;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"نسخ" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = m.customIdentifier ?: @"";
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إعادة توليد" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        m.customIdentifier = NSUUID.UUID.UUIDString;
        [weakSelf refreshUI];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        m.customIdentifier = alert.textFields.firstObject.text;
        [weakSelf refreshUI];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)uploadImage {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.image"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)hideToolTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"إخفاء الأداة" message:@"أدخل عدد الضغطات المطلوبة على زر GPS الأسود لإظهار الأداة مرة أخرى." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.text = [NSString stringWithFormat:@"%ld", (long)GPSManager.shared.revealTapCount];
        tf.textAlignment = NSTextAlignmentCenter;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إخفاء" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        NSInteger n = [alert.textFields.firstObject.text integerValue];
        GPSManager.shared.revealTapCount = MAX(2, n);
        GPSManager.shared.toolHidden = YES;
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)applyLocation {
    GPSManager *m = GPSManager.shared;
    if (!m.selectedLocation) {
        [self showAlert:@"لا يوجد موقع" message:@"حدد موقعًا أولًا من الخريطة أو البحث."];
        return;
    }
    m.enabled = YES;
    [self refreshUI];
    [self showAlert:@"تم اختيار الموقع" message:@"تم حفظ الموقع وتفعيل GPS."];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"موافق" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Document picker

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (scoped) [url stopAccessingSecurityScopedResource];

    UIImage *image = data ? [UIImage imageWithData:data] : nil;
    if (!image) {
        [self showAlert:@"ملف غير صالح" message:@"اختر صورة بصيغة مدعومة."];
        return;
    }

    NSData *jpeg = UIImageJPEGRepresentation(image, 0.86);
    NSString *baseDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"GPS"];
    [[NSFileManager defaultManager] createDirectoryAtPath:baseDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [baseDir stringByAppendingPathComponent:@"uploaded.jpg"];
    [jpeg writeToFile:path atomically:YES];
    GPSManager.shared.imagePath = path;
    [self refreshUI];
}
@end

#pragma mark - Floating button / overlay

@interface GPSFloatingButton : UIButton
@property (nonatomic) NSInteger hiddenTapCounter;
@end

@implementation GPSFloatingButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        [self addTarget:self action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [self addGestureRecognizer:pan];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:kGPSStatusChangedNote object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:kGPSToolVisibilityNote object:nil];
        [self refresh];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)refresh {
    GPSManager *m = GPSManager.shared;
    if (m.toolHidden) {
        [self setTitle:@"" forState:UIControlStateNormal];
        self.backgroundColor = [UIColor colorWithWhite:0.02 alpha:0.25];
        GPSRound(self, self.bounds.size.width / 2.0);
        return;
    }
    [self setTitle:@"GPS" forState:UIControlStateNormal];
    self.backgroundColor = m.enabled ? GPSGreen() : [UIColor colorWithWhite:0.18 alpha:0.82];
    GPSRound(self, self.bounds.size.width / 2.0);
}

- (void)tap {
    GPSManager *m = GPSManager.shared;
    if (m.toolHidden) {
        self.hiddenTapCounter += 1;
        if (self.hiddenTapCounter >= m.revealTapCount) {
            self.hiddenTapCounter = 0;
            m.toolHidden = NO;
        }
        return;
    }
    UIViewController *top = GPSTopController();
    if (!top) return;
    GPSPanelController *panel = [GPSPanelController new];
    panel.modalPresentationStyle = UIModalPresentationFullScreen;
    [top presentViewController:panel animated:YES completion:nil];
}

- (void)pan:(UIPanGestureRecognizer *)pan {
    UIView *v = self;
    CGPoint translation = [pan translationInView:v.superview];
    v.center = CGPointMake(v.center.x + translation.x, v.center.y + translation.y);
    [pan setTranslation:CGPointZero inView:v.superview];
}
@end

@interface GPSOverlayWindow : UIWindow
@property (nonatomic, strong) GPSFloatingButton *button;
@end

@implementation GPSOverlayWindow
- (instancetype)init {
    self = [super initWithFrame:UIScreen.mainScreen.bounds];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 50;
        self.backgroundColor = UIColor.clearColor;
        self.hidden = NO;
        self.userInteractionEnabled = YES;
        UIViewController *root = [UIViewController new];
        root.view.backgroundColor = UIColor.clearColor;
        self.rootViewController = root;
        self.button = [[GPSFloatingButton alloc] initWithFrame:CGRectMake(22, 154, 68, 68)];
        [root.view addSubview:self.button];
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self.rootViewController.view) return nil;
    return hit;
}
@end

static GPSOverlayWindow *gGPSWindow = nil;

#pragma mark - CoreLocation hooks

static CLLocation *(*orig_location)(id self, SEL _cmd);
static void (*orig_startUpdatingLocation)(id self, SEL _cmd);
static void (*orig_requestLocation)(id self, SEL _cmd);
static void (*orig_setDelegate)(id self, SEL _cmd, id delegate);

static void GPSDeliverLocationToDelegate(id manager) {
    CLLocation *loc = [GPSManager.shared spoofedLocation];
    if (!loc) return;

    SEL delegateSEL = NSSelectorFromString(@"delegate");
    if (![manager respondsToSelector:delegateSEL]) return;
    id delegate = ((id (*)(id, SEL))objc_msgSend)(manager, delegateSEL);
    if (!delegate) return;

    SEL modernSEL = @selector(locationManager:didUpdateLocations:);
    if ([delegate respondsToSelector:modernSEL]) {
        ((void (*)(id, SEL, id, NSArray *))objc_msgSend)(delegate, modernSEL, manager, @[loc]);
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    SEL legacySEL = @selector(locationManager:didUpdateToLocation:fromLocation:);
#pragma clang diagnostic pop
    if ([delegate respondsToSelector:legacySEL]) {
        ((void (*)(id, SEL, id, CLLocation *, CLLocation *))objc_msgSend)(delegate, legacySEL, manager, loc, nil);
    }
}

static CLLocation *gps_location(id self, SEL _cmd) {
    CLLocation *spoofed = [GPSManager.shared spoofedLocation];
    if (spoofed) return spoofed;
    return orig_location ? orig_location(self, _cmd) : nil;
}

static void gps_startUpdatingLocation(id self, SEL _cmd) {
    if (orig_startUpdatingLocation) orig_startUpdatingLocation(self, _cmd);
    if (GPSManager.shared.enabled) {
        dispatch_async(dispatch_get_main_queue(), ^{ GPSDeliverLocationToDelegate(self); });
    }
}

static void gps_requestLocation(id self, SEL _cmd) {
    if (orig_requestLocation) orig_requestLocation(self, _cmd);
    if (GPSManager.shared.enabled) {
        dispatch_async(dispatch_get_main_queue(), ^{ GPSDeliverLocationToDelegate(self); });
    }
}

static void gps_setDelegate(id self, SEL _cmd, id delegate) {
    if (orig_setDelegate) orig_setDelegate(self, _cmd, delegate);
    if (GPSManager.shared.enabled) {
        dispatch_async(dispatch_get_main_queue(), ^{ GPSDeliverLocationToDelegate(self); });
    }
}

#pragma mark - Constructor

__attribute__((constructor)) static void GPSInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [GPSManager shared];
        if (!gGPSWindow) gGPSWindow = [[GPSOverlayWindow alloc] init];
    });

    Class locationManagerClass = objc_getClass("CLLocationManager");
    if (locationManagerClass) {
        MSHookMessageEx(locationManagerClass, @selector(location), (IMP)gps_location, (IMP *)&orig_location);
        MSHookMessageEx(locationManagerClass, @selector(startUpdatingLocation), (IMP)gps_startUpdatingLocation, (IMP *)&orig_startUpdatingLocation);
        MSHookMessageEx(locationManagerClass, @selector(setDelegate:), (IMP)gps_setDelegate, (IMP *)&orig_setDelegate);
        if ([locationManagerClass instancesRespondToSelector:@selector(requestLocation)]) {
            MSHookMessageEx(locationManagerClass, @selector(requestLocation), (IMP)gps_requestLocation, (IMP *)&orig_requestLocation);
        }
    }
}
