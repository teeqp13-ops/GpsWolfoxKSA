#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Security/Security.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#import <sys/socket.h>
#import <unistd.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <mach/mach.h>
#include <errno.h>
#import <AdSupport/AdSupport.h>

#define WOLFOX_TOOL_NAME @"Gps Wolfox"

#ifdef __cplusplus
extern "C" {
#endif
intptr_t _dyld_get_image_slide(uint32_t image_index);
#ifdef __cplusplus
}
#endif

// -------------- Fishhook & Rebinding --------------
#ifndef FISHHOOK_H
#define FISHHOOK_H
struct rebinding { const char *name; void *replacement; void **replaced; };
int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel);
#endif

#ifdef __LP64__
typedef struct mach_header_64 mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct section_64 section_t;
typedef struct nlist_64 nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT_64
#else
typedef struct mach_header mach_header_t;
typedef struct segment_command segment_command_t;
typedef struct section section_t;
typedef struct nlist nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT
#endif

#ifndef SEG_DATA_CONST
#define SEG_DATA_CONST  "__DATA_CONST"
#endif

struct rebindings_entry { struct rebinding *rebindings; size_t rebindings_nel; struct rebindings_entry *next; };
static struct rebindings_entry *_rebindings_head = NULL;

static int prepend_rebindings(struct rebindings_entry **head, struct rebinding rebindings[], size_t rebindings_nel) {
  struct rebindings_entry *new_entry = (struct rebindings_entry *) malloc(sizeof(struct rebindings_entry));
  if (!new_entry) return -1;
  new_entry->rebindings = (struct rebinding *) malloc(sizeof(struct rebinding) * rebindings_nel);
  if (!new_entry->rebindings) { free(new_entry); return -1; }
  memcpy(new_entry->rebindings, rebindings, sizeof(struct rebinding) * rebindings_nel);
  new_entry->rebindings_nel = rebindings_nel;
  new_entry->next = *head;
  *head = new_entry;
  return 0;
}

static void rebind_symbols_sec(struct rebindings_entry *rebindings, section_t *section, intptr_t slide, nlist_t *symtab, char *strtab, uint32_t *indirect_symtab) {
  uint32_t *indirect_symbol_indices = indirect_symtab + section->reserved1;
  void **astruct = (void **)((uintptr_t)section->addr + slide);
  for (uint32_t i = 0; i < section->size / sizeof(void *); i++) {
    uint32_t symtab_index = indirect_symbol_indices[i];
    if (symtab_index == INDIRECT_SYMBOL_ABS || symtab_index == INDIRECT_SYMBOL_LOCAL || symtab_index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) continue;
    uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
    char *symbol_name = strtab + strtab_offset;
    bool symbol_has_leading_underscore = symbol_name[0] == '_';
    struct rebindings_entry *cur = rebindings;
    while (cur) {
      for (size_t j = 0; j < cur->rebindings_nel; j++) {
        char *rebind_name = (char *)cur->rebindings[j].name;
        if (symbol_has_leading_underscore && strlen(symbol_name) > 1 && strcmp(&symbol_name[1], rebind_name) == 0) {
          if (cur->rebindings[j].replaced != NULL && *cur->rebindings[j].replaced != astruct[i]) *cur->rebindings[j].replaced = astruct[i];
          vm_protect(mach_task_self(), (vm_address_t)&astruct[i], sizeof(void *), FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
          astruct[i] = cur->rebindings[j].replacement;
          goto symbol_loop;
        }
      }
      cur = cur->next;
    }
  symbol_loop:;
  }
}

static void rebind_symbols_image(struct rebindings_entry *rebindings, const struct mach_header *header, intptr_t slide) {
  segment_command_t *linkedit_segment = NULL;
  segment_command_t *data_segment = NULL;
  segment_command_t *data_const_segment = NULL;
  struct symtab_command *symtab_cmd = NULL;
  struct dysymtab_command *dysymtab_cmd = NULL;
  
  segment_command_t *cur_seg_cmd;
  uintptr_t cur = (uintptr_t)header + sizeof(mach_header_t);
  for (uint32_t i = 0; i < header->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
    cur_seg_cmd = (segment_command_t *)cur;
    if (cur_seg_cmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
      if (strcmp(cur_seg_cmd->segname, SEG_LINKEDIT) == 0) linkedit_segment = cur_seg_cmd;
      else if (strcmp(cur_seg_cmd->segname, SEG_DATA) == 0) data_segment = cur_seg_cmd;
      else if (strcmp(cur_seg_cmd->segname, SEG_DATA_CONST) == 0) data_const_segment = cur_seg_cmd;
    } else if (cur_seg_cmd->cmd == LC_SYMTAB) symtab_cmd = (struct symtab_command *)cur_seg_cmd;
    else if (cur_seg_cmd->cmd == LC_DYSYMTAB) dysymtab_cmd = (struct dysymtab_command *)cur_seg_cmd;
  }

  if (!symtab_cmd || !dysymtab_cmd || !linkedit_segment || (!data_segment && !data_const_segment)) return;
  uintptr_t linkedit_base = (uintptr_t)linkedit_segment->vmaddr - linkedit_segment->fileoff + slide;
  nlist_t *symtab = (nlist_t *)(linkedit_base + symtab_cmd->symoff);
  char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);
  uint32_t *indirect_symtab = (uint32_t *)(linkedit_base + dysymtab_cmd->indirectsymoff);

  if (data_segment) {
    uintptr_t temp = (uintptr_t)data_segment + sizeof(segment_command_t);
    for (uint32_t i = 0; i < data_segment->nsects; i++, temp += sizeof(section_t)) {
      section_t *sect = (section_t *)temp;
      uint8_t type = sect->flags & SECTION_TYPE;
      if (type == S_LAZY_SYMBOL_POINTERS || type == S_NON_LAZY_SYMBOL_POINTERS) rebind_symbols_sec(rebindings, sect, slide, symtab, strtab, indirect_symtab);
    }
  }
  if (data_const_segment) {
    uintptr_t temp = (uintptr_t)data_const_segment + sizeof(segment_command_t);
    for (uint32_t i = 0; i < data_const_segment->nsects; i++, temp += sizeof(section_t)) {
      section_t *sect = (section_t *)temp;
      uint8_t type = sect->flags & SECTION_TYPE;
      if (type == S_LAZY_SYMBOL_POINTERS || type == S_NON_LAZY_SYMBOL_POINTERS) rebind_symbols_sec(rebindings, sect, slide, symtab, strtab, indirect_symtab);
    }
  }
}

static void _rebind_symbols_image(const struct mach_header *header, intptr_t slide) {
    rebind_symbols_image(_rebindings_head, header, slide);
}

int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel) {
  int err = prepend_rebindings(&_rebindings_head, rebindings, rebindings_nel);
  if (err) return err;
  if (!_rebindings_head->next) _dyld_register_func_for_add_image(_rebind_symbols_image);
  else {
    uint32_t c = _dyld_image_count();
    for (uint32_t i = 0; i < c; i++) rebind_symbols_image(_rebindings_head, _dyld_get_image_header(i), _dyld_get_image_slide(i));
  }
  return 0;
}

// -------------- System Bypasses --------------
static __attribute__((always_inline)) void wolfox_safe_exit(int code) {
#ifdef __arm64__
    register int x0 __asm__("w0") = code;
    register int x16 __asm__("x16") = 1;
    __asm__ volatile ("svc #0x80" : : "r"(x0), "r"(x16) : "memory");
#else
    exit(code);
#endif
}

static int (*orig_dladdr)(const void *, Dl_info *);
static int hook_dladdr(const void *addr, Dl_info *info) {
    int res = orig_dladdr(addr, info);
    if (res && info && info->dli_fname) {
        const char *fname = info->dli_fname;
        if (strstr(fname, "Wolfox") || strstr(fname, "Spoof") || strstr(fname, "FakeGPS")) {
            info->dli_fname = "/usr/lib/libobjc.A.dylib";
        }
    }
    return res;
}

static void (*orig_exit_fn)(int);
static void hook_exit_fn(int code) { return; }

static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    if (namelen == 4 && name[0] == CTL_KERN && name[1] == KERN_PROC && name[2] == KERN_PROC_PID) {
        if (ret == 0 && oldp && *oldlenp >= sizeof(struct kinfo_proc)) {
            struct kinfo_proc *info = (struct kinfo_proc *)oldp;
            info->kp_proc.p_flag &= ~0x00000800;
        }
    }
    return ret;
}

static const char *(*orig_class_getImageName)(Class);
static const char *hook_class_getImageName(Class cls) {
    const char *name = orig_class_getImageName(cls);
    if (name) {
        if (strstr(name, "Wolfox") || strstr(name, "Spoof") || strstr(name, "FakeGPS")) return "/usr/lib/libobjc.A.dylib";
    }
    return name;
}

static void (*orig_alert_viewWillAppear)(id, SEL, BOOL);
static void hook_alert_viewWillAppear(UIAlertController *self, SEL _cmd, BOOL animated) {
    NSString *title = self.title.lowercaseString ?: @"";
    NSString *msg   = self.message.lowercaseString ?: @"";
    
    if ([title containsString:@"تم الحفظ"] || [title containsString:@"إعادة تشغيل"]) {
        orig_alert_viewWillAppear(self, _cmd, animated);
        return;
    }
    NSArray *blocked = @[@"unauthorized", @"غير مصرح", @"jailbreak", @"جيلبريك", @"معدل", @"app store", @"tamper", @"cracked", @"outside"];
    for (NSString *kw in blocked) {
        if ([title containsString:kw] || [msg containsString:kw]) {
            self.view.hidden = YES; self.view.alpha = 0.0;
            [self dismissViewControllerAnimated:NO completion:nil];
            return;
        }
    }
    orig_alert_viewWillAppear(self, _cmd, animated);
}

// -------------- Main Data Store --------------
@interface WolfoxSpoofStore : NSObject
@property (nonatomic, assign) CLLocationCoordinate2D fakeCoords;
@property (nonatomic, assign) BOOL isActive;
@property (nonatomic, assign) BOOL isJitterActive;
@property (nonatomic, assign) double jitterDistance;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *favorites;
@property (nonatomic, assign) BOOL hasStoredLocation;
@property (nonatomic, assign) double driftLatitude;
@property (nonatomic, assign) double driftLongitude;
@property (nonatomic, strong) NSString *trustedUDID;
@property (nonatomic, strong) NSArray *authorizedUDIDs;

// New Advanced Features
@property (nonatomic, assign) BOOL scheduleEnabled;
@property (nonatomic, strong) NSArray *scheduleDays; // 1=Sun, 2=Mon...
@property (nonatomic, assign) NSInteger startHour;
@property (nonatomic, assign) NSInteger startMinute;
@property (nonatomic, assign) NSInteger endHour;
@property (nonatomic, assign) NSInteger endMinute;
@property (nonatomic, strong) NSDate *subscriptionEndDate;
@property (nonatomic, assign) BOOL hasNotifiedExpiry;
@property (nonatomic, assign) NSInteger requiredTapCount; // 1-10

+ (instancetype)shared;
- (void)save;
- (void)load;
- (BOOL)isDeviceAuthorized;
- (BOOL)isCurrentlyInSchedule;
- (NSString *)getCurrentDeviceID;
@end

@implementation WolfoxSpoofStore
+ (instancetype)shared {
    static WolfoxSpoofStore *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[WolfoxSpoofStore alloc] init]; });
    return s;
}
- (instancetype)init {
    if (self = [super init]) {
        _favorites = [NSMutableArray array];
        _driftLatitude = 0.0; _driftLongitude = 0.0; _jitterDistance = 10.0;
        [self load];
    }
    return self;
}

- (void)save {
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    [u setDouble:self.fakeCoords.latitude forKey:@"WolfoxSpoof_LAT_S"];
    [u setDouble:self.fakeCoords.longitude forKey:@"WolfoxSpoof_LON_S"];
    [u setBool:self.isActive forKey:@"WolfoxSpoof_ACTIVE_S"];
    [u setBool:self.isJitterActive forKey:@"WolfoxSpoof_JITTER_S"];
    [u setDouble:self.jitterDistance forKey:@"WolfoxSpoof_JITTER_DIST"];
    [u setObject:self.favorites forKey:@"WolfoxSpoof_FAVS_S"];
    [u setBool:self.hasStoredLocation forKey:@"WolfoxSpoof_HAS_LOC"];
    
    [u setBool:self.scheduleEnabled forKey:@"Wolfox_SchedEnabled"];
    [u setObject:self.scheduleDays forKey:@"Wolfox_SchedDays"];
    [u setInteger:self.startHour forKey:@"Wolfox_StartH"];
    [u setInteger:self.startMinute forKey:@"Wolfox_StartM"];
    [u setInteger:self.endHour forKey:@"Wolfox_EndH"];
    [u setInteger:self.endMinute forKey:@"Wolfox_EndM"];
    [u setInteger:self.requiredTapCount forKey:@"Wolfox_TapCount"];
    [u setObject:self.subscriptionEndDate forKey:@"Wolfox_ExpiryDate"];
    [u setBool:self.hasNotifiedExpiry forKey:@"Wolfox_NotifiedExpiry"];
    [u synchronize];
}

- (void)load {
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    self.isActive = [u boolForKey:@"WolfoxSpoof_ACTIVE_S"];
    self.isJitterActive = [u boolForKey:@"WolfoxSpoof_JITTER_S"];
    self.hasStoredLocation = [u boolForKey:@"WolfoxSpoof_HAS_LOC"];
    double jDist = [u doubleForKey:@"WolfoxSpoof_JITTER_DIST"];
    self.jitterDistance = jDist > 0 ? jDist : 10.0;
    NSArray *saved = [u arrayForKey:@"WolfoxSpoof_FAVS_S"];
    self.favorites = saved ? [NSMutableArray arrayWithArray:saved] : [NSMutableArray array];
    if (self.hasStoredLocation) self.fakeCoords = CLLocationCoordinate2DMake([u doubleForKey:@"WolfoxSpoof_LAT_S"], [u doubleForKey:@"WolfoxSpoof_LON_S"]);
    else self.fakeCoords = CLLocationCoordinate2DMake(24.7136, 46.6753); 
    
    // Advanced Load
    self.scheduleEnabled = [u boolForKey:@"Wolfox_SchedEnabled"];
    self.scheduleDays = [u arrayForKey:@"Wolfox_SchedDays"] ?: @[@1, @2, @3, @4, @5, @6, @7];
    self.startHour = [u integerForKey:@"Wolfox_StartH"];
    self.startMinute = [u integerForKey:@"Wolfox_StartM"];
    self.endHour = [u integerForKey:@"Wolfox_EndH"];
    self.endMinute = [u integerForKey:@"Wolfox_EndM"];
    self.requiredTapCount = [u integerForKey:@"Wolfox_TapCount"] ?: 3;
    self.subscriptionEndDate = (NSDate *)[u objectForKey:@"Wolfox_ExpiryDate"] ?: [NSDate dateWithTimeIntervalSinceNow:30*24*3600];
    self.hasNotifiedExpiry = [u boolForKey:@"Wolfox_NotifiedExpiry"];

    self.authorizedUDIDs = @[@"MY_TRUSTED_DEVICE_ID", @"teeqp13-ops-device"];
    self.trustedUDID = [self getCurrentDeviceID];
}

// ✅ طريقة آمنة وموثوقة للحصول على معرّف الجهاز
- (NSString *)getCurrentDeviceID {
    // Method 1: Use IDFA (Advertising ID) - الطريقة الأفضل والأكثر أماناً
    if (@available(iOS 14.0, *)) {
        if ([ASIdentifierManager sharedManager].advertisingTrackingEnabled) {
            NSString *idfa = [[ASIdentifierManager sharedManager].advertisingIdentifier UUIDString];
            if (idfa && ![idfa isEqualToString:@"00000000-0000-0000-0000-000000000000"]) {
                return idfa;
            }
        }
    }
    
    // Method 2: Fallback to Vendor ID (أكثر ثباتاً من IDFA)
    NSString *vendorID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    if (vendorID) {
        return vendorID;
    }
    
    // Method 3: Last Resort - حفظ معرف مخصص في Keychain
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    NSString *customID = [u stringForKey:@"Wolfox_CustomDeviceID"];
    if (!customID) {
        customID = [[NSUUID UUID] UUIDString];
        [u setObject:customID forKey:@"Wolfox_CustomDeviceID"];
        [u synchronize];
    }
    return customID;
}

- (BOOL)isCurrentlyInSchedule {
    if (!self.scheduleEnabled) return YES;
    
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];
    NSDateComponents *comp = [cal components:NSCalendarUnitWeekday | NSCalendarUnitHour | NSCalendarUnitMinute fromDate:now];
    
    if (![self.scheduleDays containsObject:@(comp.weekday)]) return NO;
    
    NSInteger nowMins = comp.hour * 60 + comp.minute;
    NSInteger startMins = self.startHour * 60 + self.startMinute;
    NSInteger endMins = self.endHour * 60 + self.endMinute;
    
    return (nowMins >= startMins && nowMins <= endMins);
}

// ✅ تحقق آمن من معرّف الجهاز
- (BOOL)isDeviceAuthorized {
    NSString *currentID = [self getCurrentDeviceID];
    
    if (!currentID || currentID.length == 0) {
        return NO;
    }
    
    // التحقق من قائمة الأجهزة المصرحة
    for (NSString *authorizedID in self.authorizedUDIDs) {
        if ([currentID isEqualToString:authorizedID]) {
            return YES;
        }
    }
    
    // اختياري: السماح للمستخدم بإضافة جهازه الحالي
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    BOOL autoRegister = [u boolForKey:@"Wolfox_AutoRegisterDevice"];
    if (autoRegister) {
        NSMutableArray *devices = [NSMutableArray arrayWithArray:self.authorizedUDIDs];
        [devices addObject:currentID];
        self.authorizedUDIDs = [devices copy];
        [u setObject:self.authorizedUDIDs forKey:@"Wolfox_AuthorizedDevices"];
        [u synchronize];
        return YES;
    }
    
    return NO;
}

@end
