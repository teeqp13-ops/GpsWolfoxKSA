//
//  WFBottomSheetViewController.h
//  WFLocationKit
//
//  لوحة تحكم بالموقع التجريبي: خريطة، بحث، مفضلة، Jitter.
//  UIViewController كامل (وليس UIView عائم) لتسهيل عرض Alerts والتنقل.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WFBottomSheetViewController : UIViewController

/// اعرضها فوق أي شاشة في تطبيقك:
/// [self presentViewController:[WFBottomSheetViewController new] animated:YES completion:nil];
+ (instancetype)sheet;

@end

NS_ASSUME_NONNULL_END
