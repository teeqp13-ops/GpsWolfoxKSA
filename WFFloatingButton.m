//
//  WFFloatingButton.m
//

#import "WFFloatingButton.h"

@interface WFFloatingButton ()
@property (nonatomic, strong) UIButton *innerButton;
@property (nonatomic, assign) CGPoint lastCenter;
@end

@implementation WFFloatingButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor colorWithRed:0x07/255.0 green:0x0b/255.0 blue:0x18/255.0 alpha:0.95];
    self.layer.cornerRadius = self.bounds.size.width / 2.0;
    self.layer.borderWidth = 1.5;
    self.layer.borderColor = [UIColor colorWithRed:0xc9/255.0 green:0xa2/255.0 blue:0x27/255.0 alpha:1.0].CGColor;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.4;
    self.layer.shadowRadius = 6;
    self.layer.shadowOffset = CGSizeMake(0, 3);

    self.innerButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.innerButton.frame = self.bounds;
    self.innerButton.tintColor = [UIColor colorWithRed:0xc9/255.0 green:0xa2/255.0 blue:0x27/255.0 alpha:1.0];
    [self.innerButton setTitle:@"GPS" forState:UIControlStateNormal];
    self.innerButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [self.innerButton addTarget:self action:@selector(handleTap) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.innerButton];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];

    self.hidden = YES; // مخفي افتراضيًا حتى يُستدعى show
}

- (void)handleTap {
    [self.delegate floatingButtonWasTapped];
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *container = self.superview;
    if (!container) return;

    CGPoint translation = [gesture translationInView:container];

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.lastCenter = self.center;
    }

    CGPoint newCenter = CGPointMake(self.lastCenter.x + translation.x,
                                    self.lastCenter.y + translation.y);

    // إبقاء الزر داخل حدود الشاشة
    CGFloat halfW = self.bounds.size.width / 2.0;
    CGFloat halfH = self.bounds.size.height / 2.0;
    newCenter.x = MAX(halfW, MIN(container.bounds.size.width - halfW, newCenter.x));
    newCenter.y = MAX(halfH, MIN(container.bounds.size.height - halfH, newCenter.y));

    self.center = newCenter;

    if (gesture.state == UIGestureRecognizerStateEnded) {
        [self snapToNearestEdgeInContainer:container];
    }
}

- (void)snapToNearestEdgeInContainer:(UIView *)container {
    CGFloat margin = 12;
    CGFloat halfW = self.bounds.size.width / 2.0;
    BOOL closerToLeft = self.center.x < container.bounds.size.width / 2.0;

    [UIView animateWithDuration:0.25 animations:^{
        CGFloat targetX = closerToLeft ? (margin + halfW) : (container.bounds.size.width - margin - halfW);
        self.center = CGPointMake(targetX, self.center.y);
    }];
}

- (void)attachToView:(UIView *)containerView {
    if (self.superview == containerView) return;
    [self removeFromSuperview];
    [containerView addSubview:self];

    if (CGRectEqualToRect(self.frame, CGRectZero)) {
        self.frame = CGRectMake(containerView.bounds.size.width - 76, 140, 56, 56);
    }
}

- (void)show {
    self.hidden = NO;
}

- (void)hide {
    self.hidden = YES;
}

@end

#pragma mark - WFSecretTapCounter

@interface WFSecretTapCounter ()
@property (nonatomic, assign) NSInteger requiredTaps;
@property (nonatomic, assign) NSInteger currentTaps;
@property (nonatomic, assign) NSTimeInterval resetInterval;
@property (nonatomic, copy) void (^triggerBlock)(void);
@property (nonatomic, strong) NSTimer *resetTimer;
@end

@implementation WFSecretTapCounter

- (instancetype)initWithRequiredTaps:(NSInteger)requiredTaps
                          resetAfter:(NSTimeInterval)seconds
                           onTrigger:(void (^)(void))triggerBlock {
    self = [super init];
    if (self) {
        _requiredTaps = requiredTaps;
        _resetInterval = seconds;
        _triggerBlock = [triggerBlock copy];
        _currentTaps = 0;
    }
    return self;
}

- (void)registerTap {
    self.currentTaps += 1;
    [self.resetTimer invalidate];
    self.resetTimer = [NSTimer scheduledTimerWithTimeInterval:self.resetInterval
                                                        target:self
                                                      selector:@selector(resetCount)
                                                      userInfo:nil
                                                       repeats:NO];

    if (self.currentTaps >= self.requiredTaps) {
        self.currentTaps = 0;
        [self.resetTimer invalidate];
        if (self.triggerBlock) self.triggerBlock();
    }
}

- (void)resetCount {
    self.currentTaps = 0;
}

@end
