// GPS Plus Pro - SettingsManager.mm
#import <Foundation/Foundation.h>
@interface GPSPlusSettingsManager : NSObject
@property(nonatomic,assign) BOOL darkMode;
@property(nonatomic,assign) BOOL haptics;
@property(nonatomic,assign) NSInteger tapCount;
+ (instancetype)shared;
- (void)load;
- (void)save;
@end
@implementation GPSPlusSettingsManager
+ (instancetype)shared { static GPSPlusSettingsManager *m; static dispatch_once_t once; dispatch_once(&once, ^{ m=[GPSPlusSettingsManager new]; [m load]; }); return m; }
- (void)load { NSUserDefaults *u=[NSUserDefaults standardUserDefaults]; self.darkMode=[u boolForKey:@"GPSPlus_Dark"]; self.haptics=[u objectForKey:@"GPSPlus_Haptics"] ? [u boolForKey:@"GPSPlus_Haptics"] : YES; self.tapCount=[u integerForKey:@"GPSPlus_TapCount"] ?: 3; }
- (void)save { NSUserDefaults *u=[NSUserDefaults standardUserDefaults]; [u setBool:self.darkMode forKey:@"GPSPlus_Dark"]; [u setBool:self.haptics forKey:@"GPSPlus_Haptics"]; [u setInteger:self.tapCount forKey:@"GPSPlus_TapCount"]; [u synchronize]; }
@end
