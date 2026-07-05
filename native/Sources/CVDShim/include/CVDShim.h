#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin wrapper around the private CGVirtualDisplay API. Creates an off-screen
/// virtual display and returns its CGDirectDisplayID (0 on failure). The
/// underlying object is retained internally so the display stays alive.
@interface CVDFactory : NSObject

+ (BOOL)isAvailable;
+ (uint32_t)createDisplayWithWidth:(uint32_t)width
                            height:(uint32_t)height
                              name:(NSString *)name;
+ (void)removeAll;

@end

NS_ASSUME_NONNULL_END
