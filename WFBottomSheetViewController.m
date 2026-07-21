//
//  WFBottomSheetViewController.m
//

#import "WFBottomSheetViewController.h"
#import <MapKit/MapKit.h>
#import "WFSettingsStore.h"
#import "WFLocationProvider.h"

static UIColor *WFNavyColor(void) {
    return [UIColor colorWithRed:0x07/255.0 green:0x0b/255.0 blue:0x18/255.0 alpha:1.0];
}
static UIColor *WFGoldColor(void) {
    return [UIColor colorWithRed:0xc9/255.0 green:0xa2/255.0 blue:0x27/255.0 alpha:1.0];
}

@interface WFBottomSheetViewController () <MKMapViewDelegate, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate, MKLocalSearchCompleterDelegate>

@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *resultsTable;
@property (nonatomic, strong) UITableView *favoritesTable;
@property (nonatomic, strong) UISwitch *mockSwitch;
@property (nonatomic, strong) UISwitch *jitterSwitch;
@property (nonatomic, strong) UISlider *jitterSlider;
@property (nonatomic, strong) UILabel *jitterValueLabel;
@property (nonatomic, strong) UILabel *coordsLabel;
@property (nonatomic, strong) UIButton *copyButton;
@property (nonatomic, strong) UIButton *saveFavoriteButton;

@property (nonatomic, strong) MKLocalSearchCompleter *completer;
@property (nonatomic, strong) NSArray<MKLocalSearchCompletion *> *searchResults;

@property (nonatomic, strong) MKPointAnnotation *pin;

@end

@implementation WFBottomSheetViewController

+ (instancetype)sheet {
    WFBottomSheetViewController *vc = [[WFBottomSheetViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = vc.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                           UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
    }
    return vc;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = WFNavyColor();
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;

    self.completer = [[MKLocalSearchCompleter alloc] init];
    self.completer.delegate = self;
    self.searchResults = @[];

    [self buildUI];
    [self loadCurrentSettingsIntoUI];
}

#pragma mark - بناء الواجهة

- (void)buildUI {
    // شريط البحث
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.placeholder = @"ابحث عن موقع...";
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    // نتائج البحث (تظهر فوق الخريطة عند الكتابة)
    self.resultsTable = [[UITableView alloc] init];
    self.resultsTable.dataSource = self;
    self.resultsTable.delegate = self;
    self.resultsTable.backgroundColor = WFNavyColor();
    self.resultsTable.hidden = YES;
    self.resultsTable.translatesAutoresizingMaskIntoConstraints = NO;
    self.resultsTable.tag = 100; // نتائج البحث
    [self.view addSubview:self.resultsTable];

    // الخريطة
    self.mapView = [[MKMapView alloc] init];
    self.mapView.delegate = self;
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapView.layer.cornerRadius = 14;
    self.mapView.clipsToBounds = YES;
    [self.view addSubview:self.mapView];

    UITapGestureRecognizer *mapTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapTap:)];
    [self.mapView addGestureRecognizer:mapTap];

    // إحداثيات + نسخ
    self.coordsLabel = [[UILabel alloc] init];
    self.coordsLabel.textColor = [UIColor whiteColor];
    self.coordsLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.coordsLabel.textAlignment = NSTextAlignmentCenter;
    self.coordsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.coordsLabel];

    self.copyButton = [self styledButtonWithTitle:@"نسخ الإحداثيات"];
    [self.copyButton addTarget:self action:@selector(copyCoordinates) forControlEvents:UIControlEventTouchUpInside];

    self.saveFavoriteButton = [self styledButtonWithTitle:@"حفظ كمفضلة"];
    [self.saveFavoriteButton addTarget:self action:@selector(saveFavorite) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *actionsRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.copyButton, self.saveFavoriteButton]];
    actionsRow.axis = UILayoutConstraintAxisHorizontal;
    actionsRow.distribution = UIStackViewDistributionFillEqually;
    actionsRow.spacing = 10;
    actionsRow.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    actionsRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:actionsRow];

    // تفعيل الموقع التجريبي
    UILabel *mockLabel = [self sectionLabelWithText:@"تفعيل الموقع التجريبي (داخل التطبيق فقط)"];
    self.mockSwitch = [[UISwitch alloc] init];
    self.mockSwitch.onTintColor = WFGoldColor();
    [self.mockSwitch addTarget:self action:@selector(mockSwitchChanged) forControlEvents:UIControlEventValueChanged];

    UIStackView *mockRow = [self rowWithLabel:mockLabel control:self.mockSwitch];

    // Jitter
    UILabel *jitterLabel = [self sectionLabelWithText:@"تفعيل Jitter (عشوائية بسيطة)"];
    self.jitterSwitch = [[UISwitch alloc] init];
    self.jitterSwitch.onTintColor = WFGoldColor();
    [self.jitterSwitch addTarget:self action:@selector(jitterSwitchChanged) forControlEvents:UIControlEventValueChanged];
    UIStackView *jitterRow = [self rowWithLabel:jitterLabel control:self.jitterSwitch];

    self.jitterSlider = [[UISlider alloc] init];
    self.jitterSlider.minimumValue = 0;
    self.jitterSlider.maximumValue = 200; // متر
    self.jitterSlider.tintColor = WFGoldColor();
    [self.jitterSlider addTarget:self action:@selector(jitterSliderChanged) forControlEvents:UIControlEventValueChanged];
    self.jitterSlider.translatesAutoresizingMaskIntoConstraints = NO;

    self.jitterValueLabel = [[UILabel alloc] init];
    self.jitterValueLabel.textColor = [UIColor lightGrayColor];
    self.jitterValueLabel.font = [UIFont systemFontOfSize:12];
    self.jitterValueLabel.text = @"0 م";
    self.jitterValueLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *jitterSliderRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.jitterValueLabel, self.jitterSlider]];
    jitterSliderRow.axis = UILayoutConstraintAxisHorizontal;
    jitterSliderRow.spacing = 8;
    jitterSliderRow.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    jitterSliderRow.translatesAutoresizingMaskIntoConstraints = NO;

    // المفضلة
    UILabel *favLabel = [self sectionLabelWithText:@"المواقع المفضلة"];
    self.favoritesTable = [[UITableView alloc] init];
    self.favoritesTable.dataSource = self;
    self.favoritesTable.delegate = self;
    self.favoritesTable.backgroundColor = [UIColor colorWithWhite:1 alpha:0.03];
    self.favoritesTable.layer.cornerRadius = 10;
    self.favoritesTable.tag = 200; // جدول المفضلة
    self.favoritesTable.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *mainStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        mockRow, jitterRow, jitterSliderRow, favLabel, self.favoritesTable
    ]];
    mainStack.axis = UILayoutConstraintAxisVertical;
    mainStack.spacing = 10;
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:mainStack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:4],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],

        [self.resultsTable.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.resultsTable.leadingAnchor constraintEqualToAnchor:self.searchBar.leadingAnchor],
        [self.resultsTable.trailingAnchor constraintEqualToAnchor:self.searchBar.trailingAnchor],
        [self.resultsTable.heightAnchor constraintEqualToConstant:180],

        [self.mapView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:6],
        [self.mapView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
        [self.mapView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
        [self.mapView.heightAnchor constraintEqualToConstant:200],

        [self.coordsLabel.topAnchor constraintEqualToAnchor:self.mapView.bottomAnchor constant:8],
        [self.coordsLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
        [self.coordsLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],

        [actionsRow.topAnchor constraintEqualToAnchor:self.coordsLabel.bottomAnchor constant:8],
        [actionsRow.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
        [actionsRow.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
        [actionsRow.heightAnchor constraintEqualToConstant:40],

        [mainStack.topAnchor constraintEqualToAnchor:actionsRow.bottomAnchor constant:14],
        [mainStack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
        [mainStack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
        [mainStack.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],

        [self.favoritesTable.heightAnchor constraintGreaterThanOrEqualToConstant:120],
    ]];
}

- (UILabel *)sectionLabelWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont boldSystemFontOfSize:14];
    label.textAlignment = NSTextAlignmentRight;
    return label;
}

- (UIStackView *)rowWithLabel:(UILabel *)label control:(UIView *)control {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, control]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionEqualSpacing;
    row.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    return row;
}

- (UIButton *)styledButtonWithTitle:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:WFNavyColor() forState:UIControlStateNormal];
    button.backgroundColor = WFGoldColor();
    button.layer.cornerRadius = 8;
    button.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    return button;
}

#pragma mark - تحميل الحالة الحالية

- (void)loadCurrentSettingsIntoUI {
    WFSettingsStore *settings = [WFSettingsStore shared];

    self.mockSwitch.on = settings.mockEnabled;
    self.jitterSwitch.on = settings.jitterEnabled;
    self.jitterSlider.value = settings.jitterMeters;
    self.jitterValueLabel.text = [NSString stringWithFormat:@"%.0f م", settings.jitterMeters];

    CLLocationCoordinate2D coord = settings.selectedCoordinate;
    [self movePinToCoordinate:coord animated:NO];
    [self updateCoordsLabel:coord];

    [self.favoritesTable reloadData];
}

- (void)movePinToCoordinate:(CLLocationCoordinate2D)coord animated:(BOOL)animated {
    if (!self.pin) {
        self.pin = [[MKPointAnnotation alloc] init];
        [self.mapView addAnnotation:self.pin];
    }
    self.pin.coordinate = coord;

    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coord, 1500, 1500);
    [self.mapView setRegion:region animated:animated];
}

- (void)updateCoordsLabel:(CLLocationCoordinate2D)coord {
    self.coordsLabel.text = [NSString stringWithFormat:@"%.6f, %.6f", coord.latitude, coord.longitude];
}

#pragma mark - أحداث التحكم

- (void)mockSwitchChanged {
    [WFSettingsStore shared].mockEnabled = self.mockSwitch.on;
    [[WFSettingsStore shared] save];
}

- (void)jitterSwitchChanged {
    [WFSettingsStore shared].jitterEnabled = self.jitterSwitch.on;
    [[WFSettingsStore shared] save];
}

- (void)jitterSliderChanged {
    double value = self.jitterSlider.value;
    [WFSettingsStore shared].jitterMeters = value;
    self.jitterValueLabel.text = [NSString stringWithFormat:@"%.0f م", value];
    [[WFSettingsStore shared] save];
}

- (void)copyCoordinates {
    CLLocationCoordinate2D coord = [WFSettingsStore shared].selectedCoordinate;
    UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%.6f,%.6f", coord.latitude, coord.longitude];
    [self showToast:@"تم نسخ الإحداثيات"];
}

- (void)saveFavorite {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"حفظ كمفضلة"
                                                                    message:@"أدخل اسم الموقع"
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"مثال: المنزل";
        textField.textAlignment = NSTextAlignmentRight;
    }];

    __weak typeof(self) weakSelf = self;
    UIAlertAction *save = [UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text;
        if (name.length == 0) name = @"موقع بدون اسم";
        CLLocationCoordinate2D coord = [WFSettingsStore shared].selectedCoordinate;
        [[WFSettingsStore shared] addFavoriteWithName:name coordinate:coord];
        [weakSelf.favoritesTable reloadData];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil];

    [alert addAction:save];
    [alert addAction:cancel];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showToast:(NSString *)message {
    UILabel *toast = [[UILabel alloc] init];
    toast.text = message;
    toast.textColor = WFNavyColor();
    toast.backgroundColor = WFGoldColor();
    toast.textAlignment = NSTextAlignmentCenter;
    toast.font = [UIFont boldSystemFontOfSize:13];
    toast.layer.cornerRadius = 10;
    toast.clipsToBounds = YES;
    toast.alpha = 0;
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:toast];

    [NSLayoutConstraint activateConstraints:@[
        [toast.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [toast.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [toast.widthAnchor constraintGreaterThanOrEqualToConstant:160],
        [toast.heightAnchor constraintEqualToConstant:36],
    ]];

    [UIView animateWithDuration:0.25 animations:^{
        toast.alpha = 1;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.25 delay:1.2 options:0 animations:^{
            toast.alpha = 0;
        } completion:^(BOOL finished) {
            [toast removeFromSuperview];
        }];
    }];
}

#pragma mark - المس على الخريطة لاختيار نقطة

- (void)handleMapTap:(UITapGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.mapView];
    CLLocationCoordinate2D coord = [self.mapView convertPoint:point toCoordinateFromView:self.mapView];

    [WFSettingsStore shared].selectedCoordinate = coord;
    [[WFSettingsStore shared] save];

    [self movePinToCoordinate:coord animated:YES];
    [self updateCoordsLabel:coord];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.resultsTable.hidden = YES;
        return;
    }
    self.completer.queryFragment = searchText;
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - MKLocalSearchCompleterDelegate

- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)completer {
    self.searchResults = completer.results;
    self.resultsTable.hidden = (self.searchResults.count == 0);
    [self.resultsTable reloadData];
}

- (void)completer:(MKLocalSearchCompleter *)completer didFailWithError:(NSError *)error {
    self.resultsTable.hidden = YES;
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView.tag == 100) return self.searchResults.count;
    if (tableView.tag == 200) return [WFSettingsStore shared].favorites.count;
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    cell.textLabel.textAlignment = NSTextAlignmentRight;
    cell.detailTextLabel.textAlignment = NSTextAlignmentRight;

    if (tableView.tag == 100) {
        MKLocalSearchCompletion *result = self.searchResults[indexPath.row];
        cell.textLabel.text = result.title;
        cell.detailTextLabel.text = result.subtitle;
    } else if (tableView.tag == 200) {
        WFFavoriteLocation *fav = [WFSettingsStore shared].favorites[indexPath.row];
        cell.textLabel.text = fav.name;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.5f, %.5f", fav.coordinate.latitude, fav.coordinate.longitude];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (tableView.tag == 100) {
        MKLocalSearchCompletion *completion = self.searchResults[indexPath.row];
        MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:[[MKLocalSearchRequest alloc] initWithCompletion:completion]];
        __weak typeof(self) weakSelf = self;
        [search startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
            if (response.mapItems.count == 0) return;
            CLLocationCoordinate2D coord = response.mapItems.firstObject.placemark.coordinate;
            [WFSettingsStore shared].selectedCoordinate = coord;
            [[WFSettingsStore shared] save];
            [weakSelf movePinToCoordinate:coord animated:YES];
            [weakSelf updateCoordsLabel:coord];
            weakSelf.resultsTable.hidden = YES;
            weakSelf.searchBar.text = completion.title;
            [weakSelf.searchBar resignFirstResponder];
        }];
    } else if (tableView.tag == 200) {
        WFFavoriteLocation *fav = [WFSettingsStore shared].favorites[indexPath.row];
        [WFSettingsStore shared].selectedCoordinate = fav.coordinate;
        [[WFSettingsStore shared] save];
        [self movePinToCoordinate:fav.coordinate animated:YES];
        [self updateCoordsLabel:fav.coordinate];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return tableView.tag == 200;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete && tableView.tag == 200) {
        [[WFSettingsStore shared] removeFavoriteAtIndex:indexPath.row];
        [tableView reloadData];
    }
}

@end
