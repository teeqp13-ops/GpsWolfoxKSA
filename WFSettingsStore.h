//
//  WFSettingsStore.h
//  WFLocationKit - لوحة تجربة موقع داخل التطبيق فقط
//
//  يخزن كل الإعدادات في NSUserDefaults تحت مفتاح واحد (JSON)
//  بدل أي تعديل على سلوك النظام.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WFFavoriteLocation : NSObject <NSCoding>
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) CLLocationCoordinate2D coordinate;
- (instancetype)initWithName:(NSString *)name coordinate:(CLLocationCoordinate2D)coordinate;
@end

@interface WFSettingsStore : NSObject

+ (instancetype)shared;

// تفعيل/تعطيل الموقع التجريبي (داخل التطبيق فقط)
@property (nonatomic, assign) BOOL mockEnabled;

// الإحداثيات المختارة حاليًا
@property (nonatomic, assign) CLLocationCoordinate2D selectedCoordinate;

// Jitter تجريبي (بالمتر) لإضافة عشوائية بسيطة على الإحداثيات
@property (nonatomic, assign) double jitterMeters;
@property (nonatomic, assign) BOOL jitterEnabled;

// عدد الضغطات المطلوب لإظهار/إخفاء الزر العائم
@property (nonatomic, assign) NSInteger tapsToToggleButton;

// هل الزر العائم ظاهر حاليًا
@property (nonatomic, assign) BOOL floatingButtonVisible;

// قائمة المواقع المفضلة
@property (nonatomic, strong, readonly) NSArray<WFFavoriteLocation *> *favorites;

- (void)addFavoriteWithName:(NSString *)name coordinate:(CLLocationCoordinate2D)coordinate;
- (void)removeFavoriteAtIndex:(NSInteger)index;

- (void)save;
- (void)load;

@end

NS_ASSUME_NONNULL_END
