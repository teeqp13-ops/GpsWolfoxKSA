// GPS Plus Pro - LicenseManager.mm
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
@interface GPSPlusLicenseManager : NSObject
@property(nonatomic,copy) NSString *licenseKey;
@property(nonatomic,strong) NSDate *expiryDate;
+ (instancetype)shared;
- (NSString *)deviceID;
- (BOOL)isActive;
- (NSInteger)daysRemaining;
@end
@implementation GPSPlusLicenseManager
+ (instancetype)shared { static GPSPlusLicenseManager *m; static dispatch_once_t once; dispatch_once(&once, ^{ m=[GPSPlusLicenseManager new]; }); return m; }
- (NSString *)deviceID { NSString *v=[[[UIDevice currentDevice] identifierForVendor] UUIDString]; return v ?: [[NSUUID UUID] UUIDString]; }
- (BOOL)isActive { return self.expiryDate && [self.expiryDate timeIntervalSinceNow] > 0; }
- (NSInteger)daysRemaining { return MAX(0,(NSInteger)([self.expiryDate timeIntervalSinceNow]/86400.0)); }
@end
