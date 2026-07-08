//
//  WFFloatingButton.h
//  WFLocationKit
//
//  زر GPS عائم يمكن سحبه، ويُخفى/يُظهر عبر ضغط سري على منطقة معينة
//  (مثلًا الضغط N مرة في زاوية الشاشة) بدل الحقن التلقائي في كل التطبيق.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol WFFloatingButtonDelegate <NSObject>
- (void)floatingButtonWasTapped;
@end

@interface WFFloatingButton : UIView

@property (nonatomic, weak, nullable) id<WFFloatingButtonDelegate> delegate;

/// أضف الزر داخل أي view (مثلًا window التطبيق الخاص بك فقط - ليس عبر Hook على النظام)
- (void)attachToView:(UIView *)containerView;

- (void)show;
- (void)hide;

@end

/// كائن مسؤول عن عدّ الضغطات السرية لإظهار/إخفاء الزر
@interface WFSecretTapCounter : NSObject
- (instancetype)initWithRequiredTaps:(NSInteger)requiredTaps
                          resetAfter:(NSTimeInterval)seconds
                           onTrigger:(void (^)(void))triggerBlock;
- (void)registerTap;
@end

NS_ASSUME_NONNULL_END
