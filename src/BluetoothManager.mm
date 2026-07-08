// GPS Plus Pro - BluetoothManager.mm
#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
@interface GPSPlusBluetoothManager : NSObject <CBCentralManagerDelegate>
@property(nonatomic,strong) CBCentralManager *central;
@property(nonatomic,strong) NSMutableArray *devices;
+ (instancetype)shared;
- (void)startScan;
- (void)stopScan;
@end
@implementation GPSPlusBluetoothManager
+ (instancetype)shared { static GPSPlusBluetoothManager *m; static dispatch_once_t once; dispatch_once(&once, ^{ m=[GPSPlusBluetoothManager new]; m.devices=[NSMutableArray new]; }); return m; }
- (void)startScan {}
- (void)stopScan {}
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {}
@end
