#import "CVDShim.h"

// ---- private CGVirtualDisplay interfaces (reverse-engineered) ---------------
// Declared for the compiler only; the real classes are provided at runtime by
// CoreGraphics and resolved via NSClassFromString (no link-time symbols).

@interface CGVirtualDisplayDescriptor : NSObject
@property(strong) dispatch_queue_t queue;
@property(copy) NSString *name;
@property unsigned int maxPixelsWide;
@property unsigned int maxPixelsHigh;
@property CGSize sizeInMillimeters;
@property unsigned int productID;
@property unsigned int vendorID;
@property unsigned int serialNum;
@property(copy) void (^terminationHandler)(id);
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width
                       height:(unsigned int)height
                  refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property unsigned int hiDPI;
@property(strong) NSArray *modes;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@property(readonly) unsigned int displayID;
@end

// ---------------------------------------------------------------------------

static NSMutableArray *gDisplays;

@implementation CVDFactory

+ (BOOL)isAvailable {
    return NSClassFromString(@"CGVirtualDisplay") != nil
        && NSClassFromString(@"CGVirtualDisplayDescriptor") != nil;
}

+ (uint32_t)createDisplayWithWidth:(uint32_t)width
                            height:(uint32_t)height
                              name:(NSString *)name {
    Class descCls = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class modeCls = NSClassFromString(@"CGVirtualDisplayMode");
    Class setCls  = NSClassFromString(@"CGVirtualDisplaySettings");
    Class dispCls = NSClassFromString(@"CGVirtualDisplay");
    if (!descCls || !modeCls || !setCls || !dispCls) return 0;

    if (!gDisplays) gDisplays = [NSMutableArray array];

    CGVirtualDisplayDescriptor *desc = [[descCls alloc] init];
    desc.queue = dispatch_queue_create("com.xreal.spatial.vd", DISPATCH_QUEUE_SERIAL);
    desc.name = name;
    desc.maxPixelsWide = width;
    desc.maxPixelsHigh = height;
    desc.sizeInMillimeters = CGSizeMake(width * 0.2117, height * 0.2117); // ~120 dpi
    desc.productID = 0x1234;
    desc.vendorID = 0x3456;
    desc.serialNum = arc4random();
    desc.terminationHandler = ^(id x) {};

    CGVirtualDisplay *disp = [[dispCls alloc] initWithDescriptor:desc];
    if (!disp) return 0;

    CGVirtualDisplayMode *mode = [[modeCls alloc] initWithWidth:width
                                                         height:height
                                                    refreshRate:60.0];
    CGVirtualDisplaySettings *settings = [[setCls alloc] init];
    settings.hiDPI = 0;
    settings.modes = @[mode];

    if (![disp applySettings:settings]) return 0;

    [gDisplays addObject:disp];
    return disp.displayID;
}

+ (void)removeAll {
    [gDisplays removeAllObjects];
}

@end
