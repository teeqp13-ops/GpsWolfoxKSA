// GPS Plus Pro - OverlayView.mm
// مسؤول عن الواجهة العائمة واللوحة الرئيسية.

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>

@interface GPSPlusOverlayView : UIView
+ (instancetype)shared;
- (void)showPanel;
- (void)hidePanel;
- (void)togglePanel;
- (void)hideToolCompletely;
- (void)showToolGesture;
@end

@implementation GPSPlusOverlayView
+ (instancetype)shared {
    static GPSPlusOverlayView *view = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        view = [[GPSPlusOverlayView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    });
    return view;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = YES;
        // TODO: نقل كود بناء الواجهة من KSA.mm هنا.
    }
    return self;
}

- (void)showPanel {}
- (void)hidePanel {}
- (void)togglePanel {}
- (void)hideToolCompletely {}
- (void)showToolGesture {}
@end
