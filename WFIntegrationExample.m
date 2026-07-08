//
//  WFIntegrationExample.m
//  مثال فقط - انسخ الجزء المناسب داخل RootViewController أو AppDelegate الخاص بتطبيقك.
//  لا يوجد هنا أي Hook أو حقن تلقائي على تطبيقات أخرى أو على النظام.
//

#import "WFFloatingButton.h"
#import "WFBottomSheetViewController.h"
#import "WFSettingsStore.h"

@interface WFIntegrationExampleController : UIViewController <WFFloatingButtonDelegate>
@property (nonatomic, strong) WFFloatingButton *gpsButton;
@property (nonatomic, strong) WFSecretTapCounter *tapCounter;
@end

@implementation WFIntegrationExampleController

- (void)viewDidLoad {
    [super viewDidLoad];

    // 1) أنشئ الزر العائم مرة وحدة
    self.gpsButton = [[WFFloatingButton alloc] initWithFrame:CGRectMake(0, 0, 56, 56)];
    self.gpsButton.delegate = self;
    [self.gpsButton attachToView:self.view];

    // 2) اعرضه فقط لو كان مفعّل مسبقًا من الإعدادات المحفوظة
    if ([WFSettingsStore shared].floatingButtonVisible) {
        [self.gpsButton show];
    }

    // 3) عدّاد ضغطات سري لإظهار/إخفاء الزر (بدل الظهور التلقائي دائمًا)
    //    مثال: اربط هذا بضغطات على شعار التطبيق أو زاوية معينة في شاشتك الرئيسية فقط.
    NSInteger requiredTaps = [WFSettingsStore shared].tapsToToggleButton;
    self.tapCounter = [[WFSecretTapCounter alloc] initWithRequiredTaps:requiredTaps
                                                             resetAfter:2.0
                                                              onTrigger:^{
        BOOL newState = ![WFSettingsStore shared].floatingButtonVisible;
        [WFSettingsStore shared].floatingButtonVisible = newState;
        [[WFSettingsStore shared] save];
        if (newState) {
            [self.gpsButton show];
        } else {
            [self.gpsButton hide];
        }
    }];
}

// اربط هذا مثلاً بزر شعار أو منطقة صغيرة في واجهتك أنت (وليس عبر Hook على النظام)
- (void)secretAreaTapped {
    [self.tapCounter registerTap];
}

#pragma mark - WFFloatingButtonDelegate

- (void)floatingButtonWasTapped {
    WFBottomSheetViewController *sheet = [WFBottomSheetViewController sheet];
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
