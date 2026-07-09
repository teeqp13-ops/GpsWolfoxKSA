#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>

#define GPSPLUS_APP_NAME @"GPS Plus"
#define GPSPLUS_APP_VERSION @"1.1"
#define GPSPLUS_MIN_IOS @"16.0"
#define GPSPLUS_ACTIVATION_URL @"https://p3nd.fun/gps/api/activate.php"

static NSString *GPSPlusDeviceID(void) {
    NSString *vendorID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    if (vendorID.length > 0) return vendorID;
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    NSString *saved = [u stringForKey:@"GPSPlusFallbackUDID"];
    if (saved.length == 0) {
        saved = [[NSUUID UUID] UUIDString];
        [u setObject:saved forKey:@"GPSPlusFallbackUDID"];
        [u synchronize];
    }
    return saved;
}

static UIColor *GPSColor(NSInteger r, NSInteger g, NSInteger b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}

static UIButton *GPSButton(NSString *title, UIColor *color) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = color;
    button.layer.cornerRadius = 14;
    button.layer.masksToBounds = YES;
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 10, 12, 10);
    return button;
}

@interface GPSPlusController : UIViewController <UITextFieldDelegate, UISearchBarDelegate, MKMapViewDelegate>
@property (nonatomic,strong) UIView *rootCard;
@property (nonatomic,strong) MKMapView *mapView;
@property (nonatomic,strong) UISegmentedControl *mapTypeControl;
@property (nonatomic,strong) UISearchBar *searchBar;
@property (nonatomic,strong) UITextField *codeField;
@property (nonatomic,strong) UILabel *statusLabel;
@property (nonatomic,strong) UILabel *versionLabel;
@property (nonatomic,strong) UISwitch *spoofSwitch;
@property (nonatomic,assign) BOOL activated;
@end

@implementation GPSPlusController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.18];
    self.activated = [[NSUserDefaults standardUserDefaults] boolForKey:@"GPSPlusActivated"];
    [self buildInterface];
}

- (void)buildInterface {
    CGFloat width = UIScreen.mainScreen.bounds.size.width;
    CGFloat safeTop = self.view.safeAreaInsets.top;
    self.rootCard = [[UIView alloc] initWithFrame:CGRectMake(10, safeTop + 18, width - 20, 620)];
    self.rootCard.backgroundColor = GPSColor(20, 22, 28);
    self.rootCard.layer.cornerRadius = 24;
    self.rootCard.layer.shadowColor = UIColor.blackColor.CGColor;
    self.rootCard.layer.shadowOpacity = 0.35;
    self.rootCard.layer.shadowRadius = 16;
    self.rootCard.layer.shadowOffset = CGSizeMake(0, 8);
    [self.view addSubview:self.rootCard];

    UIButton *close = GPSButton(@"إغلاق", GPSColor(0, 122, 255));
    close.frame = CGRectMake(self.rootCard.bounds.size.width - 86, 14, 72, 42);
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.rootCard addSubview:close];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(92, 14, self.rootCard.bounds.size.width - 184, 42)];
    title.text = GPSPLUS_APP_NAME;
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:22];
    [self.rootCard addSubview:title];

    self.versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 16, 92, 38)];
    self.versionLabel.text = [NSString stringWithFormat:@"%@ v%@", self.activated ? @"✅" : @"🔒", GPSPLUS_APP_VERSION];
    self.versionLabel.textColor = GPSColor(220, 225, 235);
    self.versionLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.rootCard addSubview:self.versionLabel];

    CGFloat y = 66;
    if (!self.activated) {
        [self buildActivationAtY:y];
        y += 132;
    }

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(14, y, self.rootCard.bounds.size.width - 28, 46)];
    self.searchBar.placeholder = @"ابحث عن موقع أو أدخل إحداثيات";
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [self.rootCard addSubview:self.searchBar];
    y += 54;

    self.mapTypeControl = [[UISegmentedControl alloc] initWithItems:@[@"خريطة", @"قمر صناعي", @"هجينة"]];
    self.mapTypeControl.frame = CGRectMake(14, y, self.rootCard.bounds.size.width - 28, 36);
    self.mapTypeControl.selectedSegmentIndex = 0;
    [self.mapTypeControl addTarget:self action:@selector(changeMapType) forControlEvents:UIControlEventValueChanged];
    [self.rootCard addSubview:self.mapTypeControl];
    y += 44;

    self.mapView = [[MKMapView alloc] initWithFrame:CGRectMake(14, y, self.rootCard.bounds.size.width - 28, 230)];
    self.mapView.layer.cornerRadius = 18;
    self.mapView.layer.masksToBounds = YES;
    self.mapView.delegate = self;
    CLLocationCoordinate2D riyadh = CLLocationCoordinate2DMake(24.7136, 46.6753);
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(riyadh, 8000, 8000) animated:NO];
    [self.rootCard addSubview:self.mapView];

    UIButton *gps = GPSButton(@"GPS", GPSColor(20, 180, 85));
    gps.frame = CGRectMake(self.mapView.frame.origin.x + self.mapView.frame.size.width - 72, y + 14, 58, 42);
    [gps addTarget:self action:@selector(centerMap) forControlEvents:UIControlEventTouchUpInside];
    [self.rootCard addSubview:gps];

    UIButton *photo = GPSButton(@"📷", GPSColor(36, 130, 255));
    photo.frame = CGRectMake(26, y + 14, 48, 42);
    [self.rootCard addSubview:photo];

    UIButton *loc = GPSButton(@"⌖", GPSColor(80, 90, 105));
    loc.frame = CGRectMake(26, y + 66, 48, 42);
    [loc addTarget:self action:@selector(centerMap) forControlEvents:UIControlEventTouchUpInside];
    [self.rootCard addSubview:loc];
    y += 244;

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(14, y, self.rootCard.bounds.size.width - 28, 160)];
    panel.backgroundColor = GPSColor(28, 31, 39);
    panel.layer.cornerRadius = 18;
    [self.rootCard addSubview:panel];

    CGFloat bw = (panel.bounds.size.width - 30) / 2.0;
    UIButton *search = GPSButton(@"إبحث عن موقع", GPSColor(40, 120, 255));
    search.frame = CGRectMake(10, 12, bw, 42);
    [panel addSubview:search];

    UIButton *fav = GPSButton(@"المفضله", GPSColor(142, 68, 173));
    fav.frame = CGRectMake(20 + bw, 12, bw, 42);
    [panel addSubview:fav];

    UIButton *hide = GPSButton(@"إخفاء زر الأداة", GPSColor(224, 65, 65));
    hide.frame = CGRectMake(10, 64, bw, 42);
    [hide addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:hide];

    UIButton *uuid = GPSButton(@"معرف الجهاز UUID", GPSColor(230, 145, 45));
    uuid.frame = CGRectMake(20 + bw, 64, bw, 42);
    [uuid addTarget:self action:@selector(copyUDID) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:uuid];

    UILabel *switchLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 116, 170, 34)];
    switchLabel.text = @"تفعيل تغيير الموقع";
    switchLabel.textColor = UIColor.whiteColor;
    switchLabel.font = [UIFont boldSystemFontOfSize:15];
    switchLabel.textAlignment = NSTextAlignmentRight;
    [panel addSubview:switchLabel];

    self.spoofSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(panel.bounds.size.width - 68, 117, 52, 32)];
    [panel addSubview:self.spoofSwitch];

    UIButton *choose = GPSButton(@"اختر هذا الموقع", GPSColor(0, 122, 255));
    choose.frame = CGRectMake(188, 112, panel.bounds.size.width - 268, 42);
    [panel addSubview:choose];
}

- (void)buildActivationAtY:(CGFloat)y {
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(14, y, self.rootCard.bounds.size.width - 28, 122)];
    box.backgroundColor = GPSColor(30, 34, 44);
    box.layer.cornerRadius = 18;
    [self.rootCard addSubview:box];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(14, 10, box.bounds.size.width - 28, 24)];
    label.text = @"تفعيل GPS Plus";
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont boldSystemFontOfSize:17];
    label.textAlignment = NSTextAlignmentRight;
    [box addSubview:label];

    self.codeField = [[UITextField alloc] initWithFrame:CGRectMake(14, 42, box.bounds.size.width - 118, 44)];
    self.codeField.placeholder = @"أدخل كود 8 خانات";
    self.codeField.textAlignment = NSTextAlignmentCenter;
    self.codeField.font = [UIFont boldSystemFontOfSize:20];
    self.codeField.backgroundColor = UIColor.whiteColor;
    self.codeField.textColor = UIColor.blackColor;
    self.codeField.layer.cornerRadius = 12;
    self.codeField.delegate = self;
    self.codeField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    [box addSubview:self.codeField];

    UIButton *activate = GPSButton(@"تفعيل", GPSColor(20, 180, 85));
    activate.frame = CGRectMake(box.bounds.size.width - 94, 42, 80, 44);
    [activate addTarget:self action:@selector(activateCode) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:activate];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 92, box.bounds.size.width - 28, 20)];
    self.statusLabel.text = @"UDID يستخرج تلقائيًا";
    self.statusLabel.textColor = GPSColor(190, 198, 210);
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textAlignment = NSTextAlignmentRight;
    [box addSubview:self.statusLabel];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *newText = [[textField.text stringByReplacingCharactersInRange:range withString:string] uppercaseString];
    newText = [[newText componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@""];
    if (newText.length > 8) newText = [newText substringToIndex:8];
    textField.text = newText;
    return NO;
}

- (void)activateCode {
    NSString *code = self.codeField.text.uppercaseString ?: @"";
    if (code.length != 8) {
        self.statusLabel.text = @"❌ الكود يجب أن يكون 8 خانات";
        self.statusLabel.textColor = GPSColor(255, 100, 100);
        return;
    }
    self.statusLabel.text = @"⏳ جاري التحقق...";
    self.statusLabel.textColor = GPSColor(230, 230, 230);

    NSDictionary *payload = @{
        @"code": code,
        @"udid": GPSPlusDeviceID(),
        @"ios_version": UIDevice.currentDevice.systemVersion ?: @"",
        @"app_version": GPSPLUS_APP_VERSION
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSURL *url = [NSURL URLWithString:GPSPLUS_ACTIVATION_URL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = json;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!error && data.length > 0) {
                NSDictionary *res = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                BOOL ok = [res[@"status"] isEqual:@"ok"] || [res[@"success"] boolValue];
                if (ok) {
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"GPSPlusActivated"];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    self.statusLabel.text = @"✅ تم التفعيل بنجاح";
                    self.statusLabel.textColor = GPSColor(80, 220, 120);
                    self.versionLabel.text = [NSString stringWithFormat:@"✅ v%@", GPSPLUS_APP_VERSION];
                    return;
                }
            }
            self.statusLabel.text = @"❌ فشل التفعيل أو تعذر الاتصال";
            self.statusLabel.textColor = GPSColor(255, 100, 100);
        });
    }];
    [task resume];
}

- (void)changeMapType {
    if (self.mapTypeControl.selectedSegmentIndex == 0) self.mapView.mapType = MKMapTypeStandard;
    else if (self.mapTypeControl.selectedSegmentIndex == 1) self.mapView.mapType = MKMapTypeSatellite;
    else self.mapView.mapType = MKMapTypeHybrid;
}

- (void)centerMap {
    CLLocationCoordinate2D c = self.mapView.centerCoordinate;
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(c, 1200, 1200) animated:YES];
}

- (void)copyUDID {
    UIPasteboard.generalPasteboard.string = GPSPlusDeviceID();
}

- (void)closePanel {
    self.view.window.hidden = YES;
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    NSString *q = searchBar.text ?: @"";
    NSArray *parts = [q componentsSeparatedByString:@","];
    if (parts.count == 2) {
        double lat = [parts[0] doubleValue];
        double lon = [parts[1] doubleValue];
        if (lat != 0 && lon != 0) {
            CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(lat, lon);
            [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(coord, 1200, 1200) animated:YES];
            return;
        }
    }
    MKLocalSearchRequest *request = [MKLocalSearchRequest new];
    request.naturalLanguageQuery = q;
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    [search startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        MKMapItem *item = response.mapItems.firstObject;
        if (item) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(item.placemark.coordinate, 1500, 1500) animated:YES];
            });
        }
    }];
}
@end

static UIWindow *gpsPlusWindow = nil;
static void GPSPlusShowWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gpsPlusWindow) {
            gpsPlusWindow.hidden = NO;
            return;
        }
        gpsPlusWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        gpsPlusWindow.windowLevel = UIWindowLevelAlert + 30;
        gpsPlusWindow.backgroundColor = UIColor.clearColor;
        gpsPlusWindow.rootViewController = [GPSPlusController new];
        gpsPlusWindow.hidden = NO;
    });
}

__attribute__((constructor)) static void GPSPlusInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            GPSPlusShowWindow();
        }];
        GPSPlusShowWindow();
    });
}
