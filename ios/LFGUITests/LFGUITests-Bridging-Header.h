#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

BOOL LFGPerformTwoFingerPan(
    CGPoint firstStart,
    CGPoint firstEnd,
    CGPoint secondStart,
    CGPoint secondEnd,
    NSTimeInterval duration,
    NSError * _Nullable * _Nullable error
);

BOOL LFGPerformTwoFingerTap(
    CGPoint center,
    CGFloat separation,
    NSError * _Nullable * _Nullable error
);
