// GPS Plus Pro - UIComponents.mm
#import <UIKit/UIKit.h>
@interface GPSPlusUIComponents : NSObject
+ (UIButton *)primaryButton:(NSString *)title;
+ (UIView *)cardView;
+ (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight;
@end
@implementation GPSPlusUIComponents
+ (UIButton *)primaryButton:(NSString *)title { UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem]; [b setTitle:title forState:UIControlStateNormal]; b.layer.cornerRadius=14; b.backgroundColor=[UIColor systemBlueColor]; [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; b.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]; return b; }
+ (UIView *)cardView { UIView *v=[UIView new]; v.layer.cornerRadius=16; v.backgroundColor=[UIColor colorWithWhite:1 alpha:0.08]; return v; }
+ (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight { UILabel *l=[UILabel new]; l.text=text; l.textColor=UIColor.whiteColor; l.font=[UIFont systemFontOfSize:size weight:weight]; l.textAlignment=NSTextAlignmentRight; return l; }
@end
