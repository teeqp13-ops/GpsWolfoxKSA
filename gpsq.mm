#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>
#import <QuartzCore/QuartzCore.h>

#define GPSQ_APP_NAME @"GPS Plus"
#define GPSQ_APP_VERSION @"1.1"
#define GPSQ_MIN_IOS @"16.0"
#define GPSQ_ACTIVATION_URL @"https://p3nd.fun/gps/api/activate.php"

static NSString *GPSQDeviceID(void) {
    NSString *vendorID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    if (vendorID.length > 0) return vendorID;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *savedID = [defaults stringForKey:@"GPSQ_FallbackUDID"];
    if (savedID.length == 0) {
        savedID = [[NSUUID UUID] UUIDString];
        [defaults setObject:savedID forKey:@"GPSQ_FallbackUDID"];
        [defaults synchronize];
    }
    return savedID;
}

static UIColor *GPSQColor(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1.0];
}

static UIButton *GPSQButton(NSString *title, UIColor *color) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = color;
    button.layer.cornerRadius = 14.0;
    button.layer.masksToBounds = YES;
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.75;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    return button;
}

@interface GPSQController : UIViewController <UITextFieldDelegate, UISearchBarDelegate, MKMapViewDelegate>
@property (nonatomic, strong) UIView *rootCard;
@property (nonatomic, strong) UIView *activationBox;
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UISegmentedControl *mapTypeControl;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITextField *codeField;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UISwitch *spoofSwitch;
@property (nonatomic, assign) BOOL activated;
@end

@implementation GPSQController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.18];
    self.activated = [[NSUserDefaults standardUserDefaults] boolForKey:@"GPSQ_Activated"];
    [self buildInterface];
}

- (void)buildInterface {
    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
    CGFloat cardWidth = MAX(320.0, screenWidth - 20.0);
    CGFloat cardHeight = self.activated ? 510.0 : 640.0;
    CGFloat topInset = 24.0;
    if (@available(iOS 11.0, *)) {
        topInset = UIApplication.sharedApplication.keyWindow.safeAreaInsets.top + 18.0;
        if (topInset < 24.0) topInset = 24.0;
    }

    self.rootCard = [[UIView alloc] initWithFrame:CGRectMake(10.0, topInset, cardWidth, cardHeight)];
    self.rootCard.backgroundColor = GPSQColor(20, 22, 28);
    self.rootCard.layer.cornerRadius = 24.0;
    self.rootCard.layer.shadowColor = UIColor.blackColor.CGColor;
    self.rootCard.layer.shadowOpacity = 0.35;
    self.rootCard.layer.shadowRadius = 16.0;
    self.rootCard.layer.shadowOffset = CGSizeMake(0, 8);
    [self.view addSubview:self.rootCard];

    UIButton *closeButton = GPSQButton(@"إغلاق", GPSQColor(0, 122, 255));
    closeButton.frame = CGRectMake(cardWidth - 86.0, 14.0, 72.0, 42.0);
    [closeButton addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.rootCard addSubview:closeButton];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(92.0, 14.0, cardWidth - 184.0, 42.0)];
    titleLabel.text = GPSQ_APP_NAME;
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:22.0];
    [self.rootCard addSubview:titleLabel];

    self.versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(14.0, 16.0, 92.0, 38.0)];
    self.versionLabel.text = [NSString stringWithFormat:@"%@ v%@", self.activated ? @"✅" : @"🔒", GPSQ_APP_VERSION];
    self.versionLabel.textColor = GPSQColor(220, 225, 235);
    self.versionLabel.font = [UIFont boldSystemFontOfSize:14.0];
    [self.rootCard addSubview:self.versionLabel];

    CGFloat y = 66.0;
    if (!self.activated) {
        [self buildActivationBoxAtY:y cardWidth:cardWidth];
        y += 132.0;
    }

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(14.0, y, cardWidth - 28.0, 46.0)];
    self.searchBar.placeholder = @"ابحث عن موقع أو أدخل إحداثيات";
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [self.rootCard addSubview:self.searchBar];
    y += 54.0;

    self.mapTypeControl = [[UISegmentedControl alloc] initWithItems:@[@"خريطة", @"قمر صناعي", @"هجينة"]];
    self.mapTypeControl.frame = CGRectMake(14.0, y, cardWidth - 28.0, 36.0);
    self.mapTypeControl.selectedSegmentIndex = 0;
    [self.mapTypeControl addTarget:self action:@selector(changeMapType) forControlEvents:UIControlEventValueChanged];
    [self.rootCard addSubview:self.mapTypeControl];
    y += 44.0;

    self.mapView = [[MKMapView alloc] initWithFrame:CGRectMake(14.0, y, cardWidth - 28.0, 230.0)];
    self.mapView.layer.cornerRadius = 18.0;
    self.mapView.layer.masksToBounds = YES;
    self.mapView.delegate = self;
    CLLocationCoordinate2D startCoord = CLLocationCoordinate2DMake(24.7136, 46.6753);
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(startCoord, 8000.0, 8000.0) animated:NO];
    [self.rootCard addSubview:self.mapView];

    UIButton *gpsButton = GPSQButton(@"GPS", GPSQColor(20, 180, 85));
    gpsButton.frame = CGRectMake(cardWidth - 86.0, y + 14.0, 58.0, 42.0);
    [gpsButton addTarget:self action:@selector(centerMap) forControlEvents:UIControlEventTouchUpInside];
    [self.rootCard addSubview:gpsButton];

    UIButton *photoButton = GPSQButton(@"📷", GPSQColor(36, 130, 255));
    photoButton.frame = CGRectMake(26.0, y + 14.0, 48.0, 42.0);
    [photoButton addTarget:self action:@selector(showComingSoon) forControlEvents:UIControlEventTouchUpInside];
    [self.rootCard addSubview:photoButton];

    UIButton *targetButton = GPSQButton(@"⌖", GPSQColor(80, 90, 105));
    targetButton.frame = CGRectMake(26.0, y + 66.0, 48.0, 42.0);
    [targetButton addTarget:self action:@selector(centerMap) forControlEvents:UIControlEventTouchUpInside];
    [self.rootCard addSubview:targetButton];
    y += 244.0;

    [self buildControlPanelAtY:y cardWidth:cardWidth];
}

- (void)buildActivationBoxAtY:(CGFloat)y cardWidth:(CGFloat)cardWidth {
    self.activationBox = [[UIView alloc] initWithFrame:CGRectMake(14.0, y, cardWidth - 28.0, 122.0)];
    self.activationBox.backgroundColor = GPSQColor(30, 34, 44);
    self.activationBox.layer.cornerRadius = 18.0;
    [self.rootCard addSubview:self.activationBox];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(14.0, 10.0, self.activationBox.bounds.size.width - 28.0, 24.0)];
    label.text = @"تفعيل GPS Plus";
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont boldSystemFontOfSize:17.0];
    label.textAlignment = NSTextAlignmentRight;
    [self.activationBox addSubview:label];

    self.codeField = [[UITextField alloc] initWithFrame:CGRectMake(14.0, 42.0, self.activationBox.bounds.size.width - 118.0, 44.0)];
    self.codeField.placeholder = @"أدخل كود 8 خانات";
    self.codeField.textAlignment = NSTextAlignmentCenter;
    self.codeField.font = [UIFont boldSystemFontOfSize:20.0];
    self.codeField.backgroundColor = UIColor.whiteColor;
    self.codeField.textColor = UIColor.blackColor;
    self.codeField.layer.cornerRadius = 12.0;
    self.codeField.layer.masksToBounds = YES;
    self.codeField.delegate = self;
    self.codeField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    [self.activationBox addSubview:self.codeField];

    UIButton *activateButton = GPSQButton(@"تفعيل", GPSQColor(20, 180, 85));
    activateButton.frame = CGRectMake(self.activationBox.bounds.size.width - 94.0, 42.0, 80.0, 44.0);
    [activateButton addTarget:self action:@selector(activateCode) forControlEvents:UIControlEventTouchUpInside];
    [self.activationBox addSubview:activateButton];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(14.0, 92.0, self.activationBox.bounds.size.width - 28.0, 20.0)];
    self.statusLabel.text = @"UDID يستخرج تلقائيًا";
    self.statusLabel.textColor = GPSQColor(190, 198, 210);
    self.statusLabel.font = [UIFont systemFontOfSize:13.0];
    self.statusLabel.textAlignment = NSTextAlignmentRight;
    [self.activationBox addSubview:self.statusLabel];
}

- (void)buildControlPanelAtY:(CGFloat)y cardWidth:(CGFloat)cardWidth {
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(14.0, y, cardWidth - 28.0, 160.0)];
    panel.backgroundColor = GPSQColor(28, 31, 39);
    panel.layer.cornerRadius = 18.0;
    [self.rootCard addSubview:panel];

    CGFloat buttonWidth = (panel.bounds.size.width - 30.0) / 2.0;

    UIButton *searchButton = GPSQButton(@"إبحث عن موقع", GPSQColor(40, 120, 255));
    searchButton.frame = CGRectMake(10.0, 12.0, buttonWidth, 42.0);
    [searchButton addTarget:self action:@selector(focusSearch) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:searchButton];

    UIButton *favoriteButton = GPSQButton(@"المفضله", GPSQColor(142, 68, 173));
    favoriteButton.frame = CGRectMake(20.0 + buttonWidth, 12.0, buttonWidth, 42.0);
    [favoriteButton addTarget:self action:@selector(showComingSoon) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:favoriteButton];

    UIButton *hideButton = GPSQButton(@"إخفاء زر الأداة", GPSQColor(224, 65, 65));
    hideButton.frame = CGRectMake(10.0, 64.0, buttonWidth, 42.0);
    [hideButton addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:hideButton];

    UIButton *uuidButton = GPSQButton(@"معرف الجهاز UUID", GPSQColor(230, 145, 45));
    uuidButton.frame = CGRectMake(20.0 + buttonWidth, 64.0, buttonWidth, 42.0);
    [uuidButton addTarget:self action:@selector(copyUDID) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:uuidButton];

    UILabel *switchLabel = [[UILabel alloc] initWithFrame:CGRectMake(10.0, 116.0, 170.0, 34.0)];
    switchLabel.text = @"تفعيل تغيير الموقع";
    switchLabel.textColor = UIColor.whiteColor;
    switchLabel.font = [UIFont boldSystemFontOfSize:15.0];
    switchLabel.textAlignment = NSTextAlignmentRight;
    [panel addSubview:switchLabel];

    self.spoofSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(panel.bounds.size.width - 68.0, 117.0, 52.0, 32.0)];
    [panel addSubview:self.spoofSwitch];

    CGFloat chooseX = 188.0;
    CGFloat chooseW = panel.bounds.size.width - 268.0;
    if (chooseW < 72.0) {
        chooseX = 10.0;
        chooseW = panel.bounds.size.width - 90.0;
    }
    UIButton *chooseButton = GPSQButton(@"اختر هذا الموقع", GPSQColor(0, 122, 255));
    chooseButton.frame = CGRectMake(chooseX, 112.0, chooseW, 42.0);
    [chooseButton addTarget:self action:@selector(chooseCurrentLocation) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:chooseButton];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *source = textField.text ?: @"";
    NSString *newText = [[source stringByReplacingCharactersInRange:range withString:string] uppercaseString];
    NSCharacterSet *invalid = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    newText = [[newText componentsSeparatedByCharactersInSet:invalid] componentsJoinedByString:@""];
    if (newText.length > 8) newText = [newText substringToIndex:8];
    textField.text = newText;
    return NO;
}

- (void)activateCode {
    NSString *code = self.codeField.text.uppercaseString ?: @"";
    if (code.length != 8) {
        [self setActivationStatus:@"❌ الكود يجب أن يكون 8 خانات" color:GPSQColor(255, 100, 100)];
        return;
    }

    [self setActivationStatus:@"⏳ جاري التحقق..." color:GPSQColor(230, 230, 230)];

    NSDictionary *payload = @{
        @"code": code,
        @"udid": GPSQDeviceID(),
        @"ios_version": UIDevice.currentDevice.systemVersion ?: @"",
        @"app_version": GPSQ_APP_VERSION
    };

    NSError *jsonError = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    NSURL *url = [NSURL URLWithString:GPSQ_ACTIVATION_URL];
    if (!url || !json || jsonError) {
        [self setActivationStatus:@"❌ خطأ في تجهيز طلب التفعيل" color:GPSQColor(255, 100, 100)];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 15.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = json;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || data.length == 0) {
                [self setActivationStatus:@"❌ تعذر الاتصال بالسيرفر" color:GPSQColor(255, 100, 100)];
                return;
            }

            NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            BOOL ok = [result[@"success"] boolValue] || [result[@"status"] isEqual:@"ok"] || [result[@"status"] isEqual:@"success"];
            if (ok) {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"GPSQ_Activated"];
                [[NSUserDefaults standardUserDefaults] synchronize];
                self.activated = YES;
                self.versionLabel.text = [NSString stringWithFormat:@"✅ v%@", GPSQ_APP_VERSION];
                [self setActivationStatus:@"✅ تم التفعيل بنجاح" color:GPSQColor(80, 220, 120)];
                [UIView animateWithDuration:0.25 animations:^{
                    self.activationBox.alpha = 0.0;
                } completion:^(__unused BOOL finished) {
                    [self.activationBox removeFromSuperview];
                }];
                return;
            }

            NSString *message = [result[@"message"] isKindOfClass:NSString.class] ? result[@"message"] : @"فشل التفعيل";
            [self setActivationStatus:[NSString stringWithFormat:@"❌ %@", message] color:GPSQColor(255, 100, 100)];
        });
    }];
    [task resume];
}

- (void)setActivationStatus:(NSString *)text color:(UIColor *)color {
    self.statusLabel.text = text;
    self.statusLabel.textColor = color;
}

- (void)changeMapType {
    NSInteger index = self.mapTypeControl.selectedSegmentIndex;
    if (index == 0) self.mapView.mapType = MKMapTypeStandard;
    else if (index == 1) self.mapView.mapType = MKMapTypeSatellite;
    else self.mapView.mapType = MKMapTypeHybrid;
}

- (void)centerMap {
    CLLocationCoordinate2D center = self.mapView.centerCoordinate;
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(center, 1200.0, 1200.0) animated:YES];
}

- (void)copyUDID {
    UIPasteboard.generalPasteboard.string = GPSQDeviceID();
    [self showToast:@"تم نسخ UUID"];
}

- (void)focusSearch {
    [self.searchBar becomeFirstResponder];
}

- (void)chooseCurrentLocation {
    CLLocationCoordinate2D center = self.mapView.centerCoordinate;
    UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%.6f,%.6f", center.latitude, center.longitude];
    [self showToast:@"تم اختيار الموقع ونسخ الإحداثيات"];
}

- (void)showComingSoon {
    [self showToast:@"سيتم تفعيل هذه الميزة لاحقًا"];
}

- (void)showToast:(NSString *)message {
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(24.0, self.rootCard.bounds.size.height - 54.0, self.rootCard.bounds.size.width - 48.0, 36.0)];
    toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.76];
    toast.textColor = UIColor.whiteColor;
    toast.text = message;
    toast.textAlignment = NSTextAlignmentCenter;
    toast.font = [UIFont boldSystemFontOfSize:14.0];
    toast.layer.cornerRadius = 12.0;
    toast.layer.masksToBounds = YES;
    [self.rootCard addSubview:toast];

    [UIView animateWithDuration:0.25 delay:1.1 options:0 animations:^{
        toast.alpha = 0.0;
    } completion:^(__unused BOOL finished) {
        [toast removeFromSuperview];
    }];
}

- (void)closePanel {
    self.view.window.hidden = YES;
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    NSString *query = searchBar.text ?: @"";
    if (query.length == 0) return;

    NSArray<NSString *> *parts = [query componentsSeparatedByString:@","];
    if (parts.count == 2) {
        double latitude = [parts[0] doubleValue];
        double longitude = [parts[1] doubleValue];
        if (latitude >= -90.0 && latitude <= 90.0 && longitude >= -180.0 && longitude <= 180.0) {
            CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(latitude, longitude);
            [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(coord, 1200.0, 1200.0) animated:YES];
            return;
        }
    }

    MKLocalSearchRequest *request = [MKLocalSearchRequest new];
    request.naturalLanguageQuery = query;
    MKLocalSearch *localSearch = [[MKLocalSearch alloc] initWithRequest:request];
    [localSearch startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        MKMapItem *item = response.mapItems.firstObject;
        if (!item || error) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(item.placemark.coordinate, 1500.0, 1500.0) animated:YES];
        });
    }];
}

@end

static UIWindow *gpsqWindow = nil;

static void GPSQShowWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gpsqWindow) {
            gpsqWindow.hidden = NO;
            return;
        }

        gpsqWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        gpsqWindow.windowLevel = UIWindowLevelAlert + 30.0;
        gpsqWindow.backgroundColor = UIColor.clearColor;
        gpsqWindow.rootViewController = [GPSQController new];
        gpsqWindow.hidden = NO;
    });
}

__attribute__((constructor)) static void GPSQInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            GPSQShowWindow();
        }];
        GPSQShowWindow();
    });
}
