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
+ (instancetype)shared;
- (void)save;
- (void)load;
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
}
@end

// -------------- PassThrough Window --------------
@interface WolfoxSpoofPassThroughWindow : UIWindow
@end
@implementation WolfoxSpoofPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self || hitView == self.rootViewController.view) return nil;
    return hitView;
}
@end
static UIWindow *wolfox_overlayWindow = nil;

// -------------- Main UI & Bluetooth Scanner --------------
@interface WolfoxSpoofOverlay : UIView <MKMapViewDelegate, UISearchBarDelegate, UITableViewDelegate, UITableViewDataSource, CBCentralManagerDelegate>
@property (nonatomic, strong) UIButton *gpsBtn;
@property (nonatomic, strong) UIVisualEffectView *panel;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *controlsContainer;
@property (nonatomic, strong) MKMapView *map;
@property (nonatomic, strong) UIButton *expandMapBtn;
@property (nonatomic, strong) UISegmentedControl *mapTypeControl;
@property (nonatomic, strong) MKPointAnnotation *pin;
@property (nonatomic, strong) UISearchBar *searchBar;

// Favorites
@property (nonatomic, strong) UIVisualEffectView *favView;
@property (nonatomic, strong) UITableView *table;

// Bluetooth Scanner
@property (nonatomic, strong) UIVisualEffectView *btView;
@property (nonatomic, strong) UITableView *btTable;
@property (nonatomic, strong) UILabel *btStatusLabel;
@property (nonatomic, strong) CBCentralManager *cbManager;
@property (nonatomic, strong) NSMutableArray *discoveredDevices;

// Controls
@property (nonatomic, strong) UIButton *mainActionBtn;
@property (nonatomic, strong) UISwitch *jitterSwitch;
@property (nonatomic, strong) UISlider *jitterSlider;
@property (nonatomic, strong) UILabel *jitterLabel;

// Restart Modal
@property (nonatomic, strong) UIVisualEffectView *confirmDialogBackdrop;
@property (nonatomic, strong) UIView *confirmDialogView;
@property (nonatomic, strong) UILabel *timerLabel;
@property (nonatomic, assign) NSInteger countdownTimer;
@property (nonatomic, strong) NSTimer *restartTimer;
@property (nonatomic, assign) BOOL isPendingRestart;
@property (nonatomic, assign) BOOL isMapExpanded;

@property (nonatomic, strong) NSTimer *jitterTimer;
@property (nonatomic, assign) BOOL toolHidden;

+ (instancetype)shared;
- (void)hideToolCompletely;
- (void)showToolGesture;
@end

@implementation WolfoxSpoofOverlay

+ (instancetype)shared {
    static WolfoxSpoofOverlay *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[WolfoxSpoofOverlay alloc] initWithFrame:[UIScreen mainScreen].bounds];
    });
    return instance;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        _toolHidden = NO;
        _isMapExpanded = NO;
        _discoveredDevices = [NSMutableArray new];
        [self buildUI];
        _jitterTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateJitter) userInfo:nil repeats:YES];
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self) return nil;
    return hitView;
}

- (void)hideToolCompletely {
    self.toolHidden = YES;
    self.gpsBtn.hidden = YES;
    self.panel.hidden = YES;
    self.favView.hidden = YES;
    self.btView.hidden = YES;
}

- (void)showToolGesture {
    self.toolHidden = NO;
    self.gpsBtn.hidden = NO;
}

- (void)updateJitter {
    if ([WolfoxSpoofStore shared].isActive && [WolfoxSpoofStore shared].isJitterActive) {
        double maxD = [WolfoxSpoofStore shared].jitterDistance;
        double distance = 0.1 + ((double)arc4random_uniform((uint32_t)(maxD * 1000.0)) / 1000.0);
        double angle = (arc4random_uniform(360)) * M_PI / 180.0;
        double latOffset = (distance * cos(angle)) / 111111.0;
        double lonOffset = (distance * sin(angle)) / (111111.0 * cos([WolfoxSpoofStore shared].fakeCoords.latitude * M_PI / 180.0));
        [WolfoxSpoofStore shared].driftLatitude = latOffset;
        [WolfoxSpoofStore shared].driftLongitude = lonOffset;
    } else {
        [WolfoxSpoofStore shared].driftLatitude = 0;
        [WolfoxSpoofStore shared].driftLongitude = 0;
    }
}

- (void)buildUI {
    CGFloat sw = self.bounds.size.width, sh = self.bounds.size.height;
    
    // GPS Floating Button
    _gpsBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _gpsBtn.frame = CGRectMake(15, 90, 60, 60);
    _gpsBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:0.95];
    _gpsBtn.layer.cornerRadius = 30;
    _gpsBtn.layer.shadowOpacity = 0.4;
    _gpsBtn.layer.shadowRadius = 8;
    _gpsBtn.layer.shadowOffset = CGSizeMake(0, 4);
    _gpsBtn.layer.borderWidth = 1.0;
    _gpsBtn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.1].CGColor;
    _gpsBtn.clipsToBounds = YES;
    
    UIImage *keyImg = [UIImage systemImageNamed:@"key.fill"];
    [_gpsBtn setImage:keyImg forState:UIControlStateNormal];
    _gpsBtn.tintColor = [UIColor systemYellowColor];
    [_gpsBtn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_gpsBtn];

    // Main Panel
    CGFloat pW = MIN(sw - 20, 420);
    CGFloat pH = MIN(sh - 60, 800);
    
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    _panel = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    _panel.frame = CGRectMake((sw - pW)/2, (sh - pH)/2, pW, pH);
    _panel.layer.cornerRadius = 24;
    _panel.layer.shadowOpacity = 0.5;
    _panel.layer.shadowRadius = 20;
    _panel.layer.borderWidth = 1.0;
    _panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.15].CGColor;
    _panel.clipsToBounds = YES;
    _panel.hidden = YES;
    [self addSubview:_panel];

    // ScrollView
    _scrollView = [[UIScrollView alloc] initWithFrame:_panel.bounds];
    _scrollView.showsVerticalScrollIndicator = NO;
    [_panel.contentView addSubview:_scrollView];

    CGFloat y = 15;
    
    // Header
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(50, y, pW - 100, 30)];
    titleLabel.text = WOLFOX_TOOL_NAME;
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    [_scrollView addSubview:titleLabel];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(pW - 45, y, 30, 30);
    [closeBtn setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    closeBtn.tintColor = [UIColor colorWithRed:0.4 green:0.5 blue:0.9 alpha:1];
    [closeBtn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [_scrollView addSubview:closeBtn];

    UIImageView *keyIcon = [[UIImageView alloc] initWithFrame:CGRectMake(20, y + 2, 24, 24)];
    keyIcon.image = [UIImage systemImageNamed:@"key.fill"];
    keyIcon.tintColor = [UIColor systemYellowColor];
    [_scrollView addSubview:keyIcon];

    y += 45;
    
    // Segmented Control
    _mapTypeControl = [[UISegmentedControl alloc] initWithItems:@[@"خريطة", @"قمر صناعي", @"مختلط"]];
    _mapTypeControl.frame = CGRectMake(15, y, pW - 30, 35);
    _mapTypeControl.selectedSegmentIndex = 0;
    [_mapTypeControl addTarget:self action:@selector(mapTypeChanged:) forControlEvents:UIControlEventValueChanged];
    if (@available(iOS 13.0, *)) {
        _mapTypeControl.selectedSegmentTintColor = [UIColor colorWithWhite:0.4 alpha:1.0];
        [_mapTypeControl setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]} forState:UIControlStateNormal];
    }
    [_scrollView addSubview:_mapTypeControl];
    
    y += 45;
    
    // Map
    CGFloat mapHeight = 250; 
    _map = [[MKMapView alloc] initWithFrame:CGRectMake(15, y, pW - 30, mapHeight)];
    _map.delegate = self;
    _map.showsUserLocation = YES;
    _map.layer.cornerRadius = 16;
    _map.clipsToBounds = YES;
    [_map addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLP:)]];
    [_scrollView addSubview:_map];

    _expandMapBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _expandMapBtn.frame = CGRectMake(pW - 30 - 40, 10, 32, 32);
    _expandMapBtn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
    _expandMapBtn.tintColor = [UIColor whiteColor];
    _expandMapBtn.layer.cornerRadius = 8;
    [_expandMapBtn setImage:[UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"] forState:UIControlStateNormal];
    [_expandMapBtn addTarget:self action:@selector(toggleMapSize) forControlEvents:UIControlEventTouchUpInside];
    [_map addSubview:_expandMapBtn];
    
    y += mapHeight + 15;

    // Controls Container
    _controlsContainer = [[UIView alloc] initWithFrame:CGRectMake(0, y, pW, pH)];
    [_scrollView addSubview:_controlsContainer];

    CGFloat cy = 0;
    
    // Search Bar
    _searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(15, cy, pW - 30, 44)];
    _searchBar.delegate = self;
    _searchBar.placeholder = @"بحث عن موقع";
    _searchBar.backgroundImage = [UIImage new];
    if (@available(iOS 13.0, *)) {
        _searchBar.searchTextField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.6];
        _searchBar.searchTextField.textColor = [UIColor whiteColor];
        _searchBar.searchTextField.textAlignment = NSTextAlignmentRight;
        _searchBar.searchTextField.layer.cornerRadius = 10;
        _searchBar.searchTextField.clipsToBounds = YES;
    }
    [_controlsContainer addSubview:_searchBar];
    cy += 55;

    // Favorites & Save Row
    CGFloat btnW2 = (pW - 40) / 2;
    UIButton *saveBtn = [self modernButtonWithTitle:@"حفظ الموقع" icon:@"square.and.arrow.down.fill" color:[UIColor colorWithRed:0.2 green:0.2 blue:0.25 alpha:0.8] frame:CGRectMake(15, cy, btnW2, 40)];
    [saveBtn addTarget:self action:@selector(addFav) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton *favBtn = [self modernButtonWithTitle:@"المفضلة" icon:@"star.fill" color:[UIColor colorWithRed:0.2 green:0.2 blue:0.25 alpha:0.8] frame:CGRectMake(15 + btnW2 + 10, cy, btnW2, 40)];
    [favBtn addTarget:self action:@selector(showFav) forControlEvents:UIControlEventTouchUpInside];
    
    [_controlsContainer addSubview:saveBtn];
    [_controlsContainer addSubview:favBtn];
    cy += 55;
    
    // Grid 3 Row (Hide, Mosques, Bluetooth)
    CGFloat btnW3 = (pW - 50) / 3;
    UIButton *hideBtn = [self modernButtonWithTitle:@"إخفاء" icon:@"eye.slash.fill" color:[UIColor colorWithRed:0.2 green:0.2 blue:0.25 alpha:0.8] frame:CGRectMake(15, cy, btnW3, 40)];
    [hideBtn addTarget:self action:@selector(hideToolCompletely) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton *mosqueBtn = [self modernButtonWithTitle:@"مساجد" icon:@"building.columns.fill" color:[UIColor colorWithRed:0.2 green:0.2 blue:0.25 alpha:0.8] frame:CGRectMake(15 + btnW3 + 10, cy, btnW3, 40)];
    [mosqueBtn addTarget:self action:@selector(findAllMosques) forControlEvents:UIControlEventTouchUpInside];
    
    // ⭐️ Bluetooth Scanner Button ⭐️
    UIButton *btBtn = [self modernButtonWithTitle:@"بلوتوث" icon:@"antenna.radiowaves.left.and.right" color:[UIColor colorWithRed:0.1 green:0.3 blue:0.6 alpha:0.8] frame:CGRectMake(15 + (btnW3 * 2) + 20, cy, btnW3, 40)];
    [btBtn addTarget:self action:@selector(openBluetoothScanner) forControlEvents:UIControlEventTouchUpInside];
    
    [_controlsContainer addSubview:hideBtn];
    [_controlsContainer addSubview:mosqueBtn];
    [_controlsContainer addSubview:btBtn];
    cy += 55;
    
    // Switches
    [self addLabelRowWithTitle:@"تفعيل دائم ∞" yPos:cy isOn:YES color:[UIColor whiteColor]];
    cy += 45;
    [self addLabelRowWithTitle:@"تنبيه قبل انتهاء الاشتراك" yPos:cy isOn:YES color:[UIColor systemGreenColor]];
    cy += 45;

    // Jitter
    _jitterLabel = [[UILabel alloc] initWithFrame:CGRectMake(80, cy, pW - 95, 30)];
    _jitterLabel.text = [NSString stringWithFormat:@"تفعيل الحركة (%.1f أمتار)", [WolfoxSpoofStore shared].jitterDistance];
    _jitterLabel.textColor = [UIColor whiteColor];
    _jitterLabel.textAlignment = NSTextAlignmentRight;
    _jitterLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [_controlsContainer addSubview:_jitterLabel];
    
    _jitterSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(15, cy, 50, 30)];
    _jitterSwitch.on = [WolfoxSpoofStore shared].isJitterActive;
    [_jitterSwitch addTarget:self action:@selector(toggleJitter:) forControlEvents:UIControlEventValueChanged];
    [_controlsContainer addSubview:_jitterSwitch];
    cy += 35;
    
    _jitterSlider = [[UISlider alloc] initWithFrame:CGRectMake(15, cy, pW - 30, 30)];
    _jitterSlider.minimumValue = 0.1;
    _jitterSlider.maximumValue = 10.0;
    _jitterSlider.value = [WolfoxSpoofStore shared].jitterDistance;
    _jitterSlider.minimumTrackTintColor = [UIColor systemBlueColor];
    [_jitterSlider addTarget:self action:@selector(jitterSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_controlsContainer addSubview:_jitterSlider];
    cy += 45;

    // Schedule Switch
    [self addLabelRowWithTitle:@"تفعيل بالجدولة" yPos:cy isOn:NO color:[UIColor whiteColor]];
    cy += 55;

    // Main Button
    _mainActionBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _mainActionBtn.frame = CGRectMake(15, cy, pW - 30, 50);
    _mainActionBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.4 blue:1.0 alpha:1.0];
    _mainActionBtn.layer.cornerRadius = 14;
    _mainActionBtn.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    [_mainActionBtn setTitle:@"اختر هذا الموقع" forState:UIControlStateNormal];
    [_mainActionBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_mainActionBtn addTarget:self action:@selector(applyLocationWithRestart) forControlEvents:UIControlEventTouchUpInside];
    [_controlsContainer addSubview:_mainActionBtn];

    cy += 70;
    _controlsContainer.frame = CGRectMake(0, y, pW, cy);
    _scrollView.contentSize = CGSizeMake(pW, y + cy);

    // -------------- Favorites View --------------
    _favView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    _favView.frame = _panel.frame;
    _favView.layer.cornerRadius = 24;
    _favView.clipsToBounds = YES;
    _favView.hidden = YES;
    [self addSubview:_favView];
    
    UIButton *bk = [UIButton buttonWithType:UIButtonTypeSystem];
    bk.frame = CGRectMake(15, 20, 80, 35);
    bk.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.6];
    [bk setTitle:@"رجوع" forState:UIControlStateNormal];
    [bk setImage:[UIImage systemImageNamed:@"chevron.right"] forState:UIControlStateNormal];
    bk.tintColor = [UIColor whiteColor];
    bk.layer.cornerRadius = 10;
    bk.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [bk addTarget:self action:@selector(hideFav) forControlEvents:UIControlEventTouchUpInside];
    [_favView.contentView addSubview:bk];
    
    UILabel *favTitle = [[UILabel alloc] initWithFrame:CGRectMake(100, 20, pW - 115, 35)];
    favTitle.text = @"الأماكن المحفوظة";
    favTitle.textColor = [UIColor whiteColor];
    favTitle.textAlignment = NSTextAlignmentRight;
    favTitle.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    [_favView.contentView addSubview:favTitle];
    
    _table = [[UITableView alloc] initWithFrame:CGRectMake(10, 70, pW - 20, pH - 80) style:UITableViewStylePlain];
    _table.delegate = self;
    _table.dataSource = self;
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    [_favView.contentView addSubview:_table];
    
    // -------------- Bluetooth Scanner View --------------
    _btView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    _btView.frame = _panel.frame;
    _btView.layer.cornerRadius = 24;
    _btView.clipsToBounds = YES;
    _btView.hidden = YES;
    [self addSubview:_btView];
    
    UIButton *bkBT = [UIButton buttonWithType:UIButtonTypeSystem];
    bkBT.frame = CGRectMake(15, 20, 80, 35);
    bkBT.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.6];
    [bkBT setTitle:@"رجوع" forState:UIControlStateNormal];
    [bkBT setImage:[UIImage systemImageNamed:@"chevron.right"] forState:UIControlStateNormal];
    bkBT.tintColor = [UIColor whiteColor];
    bkBT.layer.cornerRadius = 10;
    bkBT.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [bkBT addTarget:self action:@selector(closeBluetoothScanner) forControlEvents:UIControlEventTouchUpInside];
    [_btView.contentView addSubview:bkBT];
    
    UILabel *btTitle = [[UILabel alloc] initWithFrame:CGRectMake(100, 20, pW - 115, 35)];
    btTitle.text = @"الأجهزة القريبة 📡";
    btTitle.textColor = [UIColor whiteColor];
    btTitle.textAlignment = NSTextAlignmentRight;
    btTitle.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    [_btView.contentView addSubview:btTitle];
    
    _btStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 65, pW - 20, 30)];
    _btStatusLabel.text = @"الرجاء الانتظار...";
    _btStatusLabel.textColor = [UIColor systemGreenColor];
    _btStatusLabel.textAlignment = NSTextAlignmentCenter;
    _btStatusLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [_btView.contentView addSubview:_btStatusLabel];
    
    _btTable = [[UITableView alloc] initWithFrame:CGRectMake(10, 100, pW - 20, pH - 110) style:UITableViewStylePlain];
    _btTable.delegate = self;
    _btTable.dataSource = self;
    _btTable.backgroundColor = [UIColor clearColor];
    _btTable.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    [_btView.contentView addSubview:_btTable];

    // -------------- Safe Restart Dialog --------------
    _confirmDialogBackdrop = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    _confirmDialogBackdrop.frame = self.bounds;
    _confirmDialogBackdrop.hidden = YES;
    [self addSubview:_confirmDialogBackdrop];

    _confirmDialogView = [[UIView alloc] initWithFrame:CGRectMake((sw-320)/2, (sh-240)/2, 320, 220)];
    _confirmDialogView.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.18 alpha:0.9];
    _confirmDialogView.layer.cornerRadius = 24;
    _confirmDialogView.layer.borderWidth = 1.0;
    _confirmDialogView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.1].CGColor;
    [_confirmDialogBackdrop.contentView addSubview:_confirmDialogView];

    UILabel *cdTitle = [[UILabel alloc] initWithFrame:CGRectMake(10, 20, 300, 30)];
    cdTitle.textAlignment = NSTextAlignmentCenter;
    cdTitle.text = @"إعادة تشغيل آمنة 🛡️";
    cdTitle.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1.0];
    cdTitle.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    [_confirmDialogView addSubview:cdTitle];

    UILabel *cdMsg = [[UILabel alloc] initWithFrame:CGRectMake(20, 55, 280, 80)];
    cdMsg.textAlignment = NSTextAlignmentCenter;
    cdMsg.textColor = [UIColor whiteColor];
    cdMsg.numberOfLines = 0;
    cdMsg.text = @"لتكون عملية تغيير الموقع آمنة جداً وكأنك فتحت التطبيق من الموقع الجديد (لعدم كشف النظام)، سيتم إعادة التشغيل خلال:";
    cdMsg.font = [UIFont systemFontOfSize:15];
    [_confirmDialogView addSubview:cdMsg];
    
    _timerLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 140, 300, 60)];
    _timerLabel.textAlignment = NSTextAlignmentCenter;
    _timerLabel.textColor = [UIColor whiteColor];
    _timerLabel.font = [UIFont systemFontOfSize:50 weight:UIFontWeightHeavy];
    [_confirmDialogView addSubview:_timerLabel];
    
    [self loadInitialState];
}

- (UIButton *)modernButtonWithTitle:(NSString *)title icon:(NSString *)iconName color:(UIColor *)color frame:(CGRect)frame {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = frame;
    btn.backgroundColor = color;
    btn.layer.cornerRadius = 10;
    btn.tintColor = [UIColor whiteColor];

    if (iconName) {
        UIImage *icon = [UIImage systemImageNamed:iconName];
        [btn setImage:icon forState:UIControlStateNormal];
        btn.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 6);
    }
    
    [btn setTitle:[NSString stringWithFormat:@" %@", title] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    return btn;
}

- (void)addLabelRowWithTitle:(NSString *)title yPos:(CGFloat)y isOn:(BOOL)isOn color:(UIColor *)color {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(80, y, _panel.bounds.size.width - 95, 30)];
    lbl.text = title;
    lbl.textColor = [UIColor whiteColor];
    lbl.textAlignment = NSTextAlignmentRight;
    lbl.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [_controlsContainer addSubview:lbl];
    
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(15, y, 50, 30)];
    sw.on = isOn;
    sw.onTintColor = color;
    sw.userInteractionEnabled = YES; 
    [_controlsContainer addSubview:sw];
}

- (void)loadInitialState {
    if ([WolfoxSpoofStore shared].hasStoredLocation) [self moveMapToCoordinate:[WolfoxSpoofStore shared].fakeCoords];
}

- (void)mapTypeChanged:(UISegmentedControl *)sender {
    switch (sender.selectedSegmentIndex) {
        case 0: self.map.mapType = MKMapTypeStandard; break;
        case 1: self.map.mapType = MKMapTypeSatellite; break;
        case 2: self.map.mapType = MKMapTypeHybrid; break;
    }
}

- (void)togglePanel {
    if (_isPendingRestart) return;
    _panel.hidden = !_panel.hidden;
    _favView.hidden = YES;
    _btView.hidden = YES;
    if (!_panel.hidden) {
        [self bringSubviewToFront:_panel];
        if (_pin) {
            MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(_pin.coordinate, 5000, 5000);
            [_map setRegion:region animated:NO];
        }
    } else {
        [_searchBar resignFirstResponder];
    }
}

- (void)toggleMapSize {
    self.isMapExpanded = !self.isMapExpanded;
    [UIView animateWithDuration:0.3 animations:^{
        if (self.isMapExpanded) {
            self.map.frame = CGRectMake(15, 105, self.panel.bounds.size.width - 30, self.panel.bounds.size.height - 125);
            self.controlsContainer.alpha = 0.0;
            [self.expandMapBtn setImage:[UIImage systemImageNamed:@"arrow.down.right.and.arrow.up.left"] forState:UIControlStateNormal];
        } else {
            self.map.frame = CGRectMake(15, 105, self.panel.bounds.size.width - 30, 250);
            self.controlsContainer.alpha = 1.0;
            [self.expandMapBtn setImage:[UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"] forState:UIControlStateNormal];
        }
    }];
}

- (void)toggleJitter:(UISwitch *)sender {
    [WolfoxSpoofStore shared].isJitterActive = sender.isOn;
    [[WolfoxSpoofStore shared] save];
}

- (void)jitterSliderChanged:(UISlider *)sender {
    [WolfoxSpoofStore shared].jitterDistance = sender.value;
    _jitterLabel.text = [NSString stringWithFormat:@"تفعيل الحركة (%.1f أمتار)", sender.value];
    [[WolfoxSpoofStore shared] save];
}

- (void)handleLP:(UILongPressGestureRecognizer *)s {
    if (s.state == UIGestureRecognizerStateBegan) {
        CLLocationCoordinate2D c = [_map convertPoint:[s locationInView:_map] toCoordinateFromView:_map];
        [self moveMapToCoordinate:c];
    }
}

- (void)moveMapToCoordinate:(CLLocationCoordinate2D)coord {
    if (_pin) [_map removeAnnotation:_pin];
    _pin = [[MKPointAnnotation alloc] init];
    _pin.coordinate = coord;
    _pin.title = @"الموقع المحدد";
    [_map addAnnotation:_pin];
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coord, 3000, 3000);
    [_map setRegion:region animated:YES];
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[MKUserLocation class]]) return nil;
    
    NSString *identifier = @"Pin";
    MKMarkerAnnotationView *view = (MKMarkerAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:identifier];
    if (!view) {
        view = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:identifier];
        view.canShowCallout = YES;
    } else {
        view.annotation = annotation;
    }
    
    if ([annotation.title containsString:@"مسجد"] || [annotation.title containsString:@"جامع"]) {
        view.markerTintColor = [UIColor systemGreenColor];
        view.glyphImage = [UIImage systemImageNamed:@"building.columns.fill"];
        view.displayPriority = MKFeatureDisplayPriorityRequired;
    } else {
        view.markerTintColor = [UIColor systemRedColor];
        view.glyphImage = [UIImage systemImageNamed:@"mappin"];
    }
    return view;
}

- (void)findAllMosques {
    NSMutableArray *oldMosques = [NSMutableArray array];
    for (id<MKAnnotation> ann in self.map.annotations) {
        if ([ann.title containsString:@"مسجد"] || [ann.title containsString:@"جامع"]) {
            [oldMosques addObject:ann];
        }
    }
    [self.map removeAnnotations:oldMosques];

    MKCoordinateRegion regions[] = {
        MKCoordinateRegionMake(CLLocationCoordinate2DMake(24.7136, 46.6753), MKCoordinateSpanMake(0.5, 0.5)),
        MKCoordinateRegionMake(CLLocationCoordinate2DMake(26.3927, 49.9777), MKCoordinateSpanMake(0.5, 0.5)),
        MKCoordinateRegionMake(CLLocationCoordinate2DMake(21.4858, 39.1925), MKCoordinateSpanMake(0.5, 0.5)),
        MKCoordinateRegionMake(CLLocationCoordinate2DMake(21.3891, 39.8579), MKCoordinateSpanMake(0.5, 0.5)),
        MKCoordinateRegionMake(CLLocationCoordinate2DMake(18.2164, 42.5053), MKCoordinateSpanMake(0.5, 0.5)),
        _map.region 
    };
    
    NSArray *queries = @[@"مسجد", @"جامع"];
    for (int i = 0; i < 6; i++) {
        for (NSString *query in queries) {
            MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] init];
            request.naturalLanguageQuery = query;
            request.region = regions[i];
            
            MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
            [search startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
                if (!error && response.mapItems.count > 0) {
                    for (MKMapItem *item in response.mapItems) {
                        MKPointAnnotation *mosquePin = [[MKPointAnnotation alloc] init];
                        mosquePin.coordinate = item.placemark.coordinate;
                        mosquePin.title = item.name;
                        mosquePin.subtitle = @"مسجد 🕌";
                        [self.map addAnnotation:mosquePin];
                    }
                }
            }];
        }
    }
}

- (void)openBluetoothScanner {
    [_searchBar resignFirstResponder];
    _panel.hidden = YES;
    _favView.hidden = YES;
    _btView.hidden = NO;
    
    [self.discoveredDevices removeAllObjects];
    [self.btTable reloadData];
    
    if (!_cbManager) {
        _cbManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    } else {
        if (_cbManager.state == CBManagerStatePoweredOn) {
            [_cbManager scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @NO}];
            _btStatusLabel.text = @"جاري صيد الأجهزة المحيطة... ⏳";
        } else {
            _btStatusLabel.text = @"يرجى تشغيل البلوتوث أولاً ❌";
        }
    }
}

- (void)closeBluetoothScanner {
    _btView.hidden = YES;
    if (!_toolHidden) _panel.hidden = NO;
    if (_cbManager) [_cbManager stopScan];
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if (central.state == CBManagerStatePoweredOn) {
        if (!_btView.hidden) {
            [_cbManager scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @NO}];
            _btStatusLabel.text = @"جاري صيد الأجهزة المحيطة... ⏳";
        }
    } else {
        _btStatusLabel.text = @"البلوتوث مغلق أو غير مصرح ❌";
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI {
    for (NSDictionary *d in self.discoveredDevices) {
        if ([d[@"peripheral"] isEqual:peripheral]) return;
    }
    [self.discoveredDevices addObject:@{@"peripheral": peripheral, @"rssi": RSSI}];
    [self.btTable reloadData];
    _btStatusLabel.text = [NSString stringWithFormat:@"تم صيد %lu جهاز ✅", (unsigned long)self.discoveredDevices.count];
}

- (void)addFav {
    if (!_pin) return;
    NSString *name = [NSString stringWithFormat:@"موقع (%.4f, %.4f)", _pin.coordinate.latitude, _pin.coordinate.longitude];
    [[WolfoxSpoofStore shared].favorites addObject:@{@"name": name, @"lat": @(_pin.coordinate.latitude), @"lon": @(_pin.coordinate.longitude)}];
    [[WolfoxSpoofStore shared] save];
    [_table reloadData];
    
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"تم الحفظ" message:@"تم حفظ الموقع في المفضلة بنجاح ⭐️" preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
    if (vc.presentedViewController) vc = vc.presentedViewController;
    [vc presentViewController:ac animated:YES completion:nil];
}

- (void)showFav {
    [_searchBar resignFirstResponder];
    _panel.hidden = YES;
    _btView.hidden = YES;
    _favView.hidden = NO;
    [_table reloadData];
}

- (void)hideFav {
    _favView.hidden = YES;
    if (!_toolHidden) _panel.hidden = NO;
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { 
    if (t == _btTable) return self.discoveredDevices.count;
    return [WolfoxSpoofStore shared].favorites.count; 
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)i {
    if (t == _btTable) {
        UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"btcell"];
        if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"btcell"];
        NSDictionary *d = self.discoveredDevices[i.row];
        CBPeripheral *p = d[@"peripheral"];
        c.textLabel.text = (p.name && p.name.length > 0) ? p.name : @"جهاز بلوتوث غير معروف ❓";
        c.detailTextLabel.text = [NSString stringWithFormat:@"قوة الإشارة (RSSI): %@", d[@"rssi"]];
        c.backgroundColor = [UIColor clearColor];
        c.textLabel.textColor = [UIColor whiteColor];
        c.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        c.detailTextLabel.textColor = [UIColor systemGreenColor];
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        return c;
    } else {
        UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"c"];
        if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
        NSDictionary *f = [WolfoxSpoofStore shared].favorites[i.row];
        c.textLabel.text = f[@"name"];
        c.detailTextLabel.text = [NSString stringWithFormat:@"%@, %@", f[@"lat"], f[@"lon"]];
        c.backgroundColor = [UIColor clearColor];
        c.textLabel.textColor = [UIColor whiteColor];
        c.detailTextLabel.textColor = [UIColor lightGrayColor];
        c.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        return c;
    }
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)i {
    if (t == _table) {
        NSDictionary *f = [WolfoxSpoofStore shared].favorites[i.row];
        CLLocationCoordinate2D c = CLLocationCoordinate2DMake([f[@"lat"] doubleValue], [f[@"lon"] doubleValue]);
        [self moveMapToCoordinate:c];
        [self hideFav];
    }
}

- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)s forRowAtIndexPath:(NSIndexPath *)i {
    if (t == _table && s == UITableViewCellEditingStyleDelete) {
        [[WolfoxSpoofStore shared].favorites removeObjectAtIndex:i.row];
        [[WolfoxSpoofStore shared] save];
        [t deleteRowsAtIndexPaths:@[i] withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)s {
    [s resignFirstResponder];
    if (!s.text.length) return;
    CLGeocoder *geo = [[CLGeocoder alloc] init];
    [geo geocodeAddressString:s.text completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (placemarks.firstObject.location) [self moveMapToCoordinate:placemarks.firstObject.location.coordinate];
        });
    }];
}

- (void)applyLocationWithRestart {
    if (!_pin) return;
    [WolfoxSpoofStore shared].isActive = YES;
    [WolfoxSpoofStore shared].hasStoredLocation = YES;
    [WolfoxSpoofStore shared].fakeCoords = _pin.coordinate;
    [[WolfoxSpoofStore shared] save];
    
    _isPendingRestart = YES;
    _panel.hidden = YES;
    _confirmDialogBackdrop.hidden = NO;
    [self bringSubviewToFront:_confirmDialogBackdrop];
    
    self.countdownTimer = 5;
    _timerLabel.text = @"5";
    self.restartTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(tickRestartTimer) userInfo:nil repeats:YES];
}

- (void)tickRestartTimer {
    self.countdownTimer--;
    _timerLabel.text = [NSString stringWithFormat:@"%ld", (long)self.countdownTimer];
    if (self.countdownTimer <= 0) {
        [self.restartTimer invalidate];
        self.restartTimer = nil;
        wolfox_safe_exit(0);
    }
}
@end

// -------------- Location Spoofing Logic --------------
@interface WolfoxSpoofDelegatePatcher : NSObject
- (void)wolfox_locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations;
- (void)wolfox_locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation;
@end

@implementation WolfoxSpoofDelegatePatcher
- (void)wolfox_locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    if ([WolfoxSpoofStore shared].isActive) {
        CLLocationCoordinate2D c = [WolfoxSpoofStore shared].fakeCoords;
        CLLocationCoordinate2D newCoord = CLLocationCoordinate2DMake(c.latitude + [WolfoxSpoofStore shared].driftLatitude, c.longitude + [WolfoxSpoofStore shared].driftLongitude);
        CLLocation *fakeLoc = [[CLLocation alloc] initWithCoordinate:newCoord altitude:300.0 horizontalAccuracy:5.0 verticalAccuracy:5.0 timestamp:[NSDate date]];
        [self wolfox_locationManager:manager didUpdateLocations:@[fakeLoc]];
    } else {
        [self wolfox_locationManager:manager didUpdateLocations:locations];
    }
}
- (void)wolfox_locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation {
    if ([WolfoxSpoofStore shared].isActive) {
        CLLocationCoordinate2D c = [WolfoxSpoofStore shared].fakeCoords;
        CLLocationCoordinate2D newCoord = CLLocationCoordinate2DMake(c.latitude + [WolfoxSpoofStore shared].driftLatitude, c.longitude + [WolfoxSpoofStore shared].driftLongitude);
        CLLocation *fakeLoc = [[CLLocation alloc] initWithCoordinate:newCoord altitude:300.0 horizontalAccuracy:5.0 verticalAccuracy:5.0 timestamp:[NSDate date]];
        [self wolfox_locationManager:manager didUpdateToLocation:fakeLoc fromLocation:oldLocation];
    } else {
        [self wolfox_locationManager:manager didUpdateToLocation:newLocation fromLocation:oldLocation];
    }
}
@end

static BOOL YHSafeHookMethod(Class cls, SEL sel, IMP newImp, IMP *oldImp) {
    if (!cls || !sel || !newImp) return NO;
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return NO;
    if (oldImp) *oldImp = method_getImplementation(method);
    method_setImplementation(method, newImp);
    return YES;
}

static IMP orig_coordinate;
static IMP orig_CLLocationManager_setDelegate_imp;
static IMP orig_CLLocationManager_location_imp;

CLLocationCoordinate2D my_coordinate(CLLocation *self, SEL _cmd) {
    if ([WolfoxSpoofStore shared].isActive) {
        CLLocationCoordinate2D c = [WolfoxSpoofStore shared].fakeCoords;
        return CLLocationCoordinate2DMake(c.latitude + [WolfoxSpoofStore shared].driftLatitude, c.longitude + [WolfoxSpoofStore shared].driftLongitude);
    }
    CLLocationCoordinate2D (*orig)(id, SEL) = (CLLocationCoordinate2D (*)(id, SEL))orig_coordinate;
    return orig ? orig(self, _cmd) : CLLocationCoordinate2DMake(0, 0);
}

CLLocation* override_CLLocationManager_location(CLLocationManager *self, SEL _cmd) {
    if ([WolfoxSpoofStore shared].isActive) {
        CLLocationCoordinate2D c = [WolfoxSpoofStore shared].fakeCoords;
        CLLocationCoordinate2D drifted = CLLocationCoordinate2DMake(c.latitude + [WolfoxSpoofStore shared].driftLatitude, c.longitude + [WolfoxSpoofStore shared].driftLongitude);
        return [[CLLocation alloc] initWithCoordinate:drifted altitude:300.0 horizontalAccuracy:5.0 verticalAccuracy:5.0 timestamp:[NSDate date]];
    }
    CLLocation* (*orig)(id, SEL) = (CLLocation* (*)(id, SEL))orig_CLLocationManager_location_imp;
    return orig ? orig(self, _cmd) : nil;
}

void override_CLLocationManager_setDelegate(id self, SEL _cmd, id delegate) {
    if (delegate) {
        Class delegateClass = [delegate class];
        SEL targetSel = @selector(locationManager:didUpdateLocations:);
        Method origMethod = class_getInstanceMethod(delegateClass, targetSel);
        if (origMethod) {
            SEL swizSel = NSSelectorFromString(@"wolfox_locationManager:didUpdateLocations:");
            if (!class_getInstanceMethod(delegateClass, swizSel)) {
                Method hookMethod = class_getInstanceMethod([WolfoxSpoofDelegatePatcher class], @selector(wolfox_locationManager:didUpdateLocations:));
                if (hookMethod) {
                    class_addMethod(delegateClass, swizSel, method_getImplementation(hookMethod), method_getTypeEncoding(hookMethod));
                    Method newOrig = class_getInstanceMethod(delegateClass, targetSel);
                    Method newSwiz = class_getInstanceMethod(delegateClass, swizSel);
                    if (newOrig && newSwiz) method_exchangeImplementations(newOrig, newSwiz);
                }
            }
        }
    }
    void (*orig)(id, SEL, id) = (void (*)(id, SEL, id))orig_CLLocationManager_setDelegate_imp;
    if (orig) orig(self, _cmd, delegate);
}

// -------------- Bluetooth Hooks (From k.mm) --------------
static BOOL hook_noiseFloor90(id self, SEL _cmd) { return NO; }
static BOOL hook_codecType(id self, SEL _cmd) { return NO; }
static BOOL hook_signalToNoiseRatio(id self, SEL _cmd) { return NO; }
static BOOL hook_isAppleVID(id self, SEL _cmd, unsigned short arg1, unsigned char arg2) { return YES; }
static unsigned char hook_heySiriProductType(id self, SEL _cmd) { return 0; }

static void init_bluetooth_bypasses() {
    Class cbUtilCls = NSClassFromString(@"CBUtil");
    if (cbUtilCls) {
        YHSafeHookMethod(objc_getMetaClass("CBUtil"), @selector(isAppleVID:forVIDSrc:), (IMP)hook_isAppleVID, NULL);
    }
    Class cbAudioCls = NSClassFromString(@"CBAudioLinkQualityInfo");
    if (cbAudioCls) {
        YHSafeHookMethod(cbAudioCls, @selector(noiseFloor90), (IMP)hook_noiseFloor90, NULL);
        YHSafeHookMethod(cbAudioCls, @selector(codecType), (IMP)hook_codecType, NULL);
        YHSafeHookMethod(cbAudioCls, @selector(signalToNoiseRatio), (IMP)hook_signalToNoiseRatio, NULL);
    }
    Class cbDeviceCls = NSClassFromString(@"CBDevice");
    if (cbDeviceCls) {
        YHSafeHookMethod(cbDeviceCls, @selector(heySiriProductType), (IMP)hook_heySiriProductType, NULL);
    }
}

// -------------- Startup --------------
static void installOverlay(void) {
    WolfoxSpoofOverlay *overlay = [WolfoxSpoofOverlay shared];
    if (!wolfox_overlayWindow) {
        if (@available(iOS 13.0, *)) {
            UIWindowScene *scene = nil;
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if (s.activationState == UISceneActivationStateForegroundActive && [s isKindOfClass:[UIWindowScene class]]) {
                    scene = (UIWindowScene *)s; break;
                }
            }
            if (scene) wolfox_overlayWindow = [[WolfoxSpoofPassThroughWindow alloc] initWithWindowScene:scene];
            else wolfox_overlayWindow = [[WolfoxSpoofPassThroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        } else {
            wolfox_overlayWindow = [[WolfoxSpoofPassThroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
        wolfox_overlayWindow.backgroundColor = [UIColor clearColor];
        wolfox_overlayWindow.opaque = NO;
        wolfox_overlayWindow.hidden = NO;
        wolfox_overlayWindow.userInteractionEnabled = YES;
        wolfox_overlayWindow.windowLevel = UIWindowLevelAlert + 2000.0;
        UIViewController *root = [UIViewController new];
        root.view.backgroundColor = [UIColor clearColor];
        wolfox_overlayWindow.rootViewController = root;
    }
    wolfox_overlayWindow.frame = [UIScreen mainScreen].bounds;
    overlay.frame = wolfox_overlayWindow.bounds;
    if (overlay.superview != wolfox_overlayWindow) {
        [overlay removeFromSuperview];
        [wolfox_overlayWindow addSubview:overlay];
    }
    [wolfox_overlayWindow bringSubviewToFront:overlay];
}

static void ensureVisible(void) {
    installOverlay();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ensureVisible();
    });
}

static void (*orig_sendEvent)(id, SEL, UIEvent *);
static void hook_sendEvent(UIWindow *self, SEL _cmd, UIEvent *event) {
    orig_sendEvent(self, _cmd, event);
    if (event.type == UIEventTypeTouches) {
        NSSet *touches = [event touchesForWindow:self];
        if (touches.count == 2) {
            BOOL allEnded = YES; BOOL allThreeTaps = YES;
            for (UITouch *t in touches) {
                if (t.phase != UITouchPhaseEnded) allEnded = NO;
                if (t.tapCount != 3) allThreeTaps = NO;
            }
            if (allEnded && allThreeTaps) {
                dispatch_async(dispatch_get_main_queue(), ^{ [[WolfoxSpoofOverlay shared] showToolGesture]; });
            }
        }
    }
}

__attribute__((constructor))
static void init_tool() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [WolfoxSpoofStore shared];
        init_bluetooth_bypasses();

        struct rebinding r[] = {
            {"dladdr", (void *)hook_dladdr, (void **)&orig_dladdr},
            {"sysctl", (void *)hook_sysctl, (void **)&orig_sysctl},
            {"exit", (void *)hook_exit_fn, (void **)&orig_exit_fn},
            {"class_getImageName", (void *)hook_class_getImageName, (void **)&orig_class_getImageName}
        };
        rebind_symbols(r, 4);

        Class windowClass = objc_getClass("UIWindow");
        if (windowClass) {
            Method mSendEvent = class_getInstanceMethod(windowClass, @selector(sendEvent:));
            if (mSendEvent) {
                orig_sendEvent = (void (*)(id, SEL, UIEvent *))method_getImplementation(mSendEvent);
                if (orig_sendEvent) method_setImplementation(mSendEvent, (IMP)hook_sendEvent);
            }
        }

        YHSafeHookMethod([CLLocation class], @selector(coordinate), (IMP)my_coordinate, (IMP*)&orig_coordinate);
        YHSafeHookMethod([CLLocationManager class], @selector(setDelegate:), (IMP)override_CLLocationManager_setDelegate, &orig_CLLocationManager_setDelegate_imp);
        YHSafeHookMethod([CLLocationManager class], @selector(location), (IMP)override_CLLocationManager_location, &orig_CLLocationManager_location_imp);

        Class alertClass = objc_getClass("UIAlertController");
        if (alertClass) {
            Method mAlert = class_getInstanceMethod(alertClass, @selector(viewWillAppear:));
            if (mAlert) {
                orig_alert_viewWillAppear = (void (*)(id, SEL, BOOL))method_getImplementation(mAlert);
                if (orig_alert_viewWillAppear) method_setImplementation(mAlert, (IMP)hook_alert_viewWillAppear);
            }
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ensureVisible();
        });
    });
}