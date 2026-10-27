#import "LFGUITests-Bridging-Header.h"
#import <UIKit/UIKit.h>

// XCTest's public gestures expose pinch and two-finger tap, but not a
// two-finger translation. These selectors belong to the XCTest runner's own
// event-synthesis classes and are confined to this UI-test target.
@interface NSObject (LFGXCTestEventSynthesis)
- (instancetype)initWithName:(NSString *)name interfaceOrientation:(NSInteger)orientation;
- (instancetype)initForTouchAtPoint:(CGPoint)point offset:(NSTimeInterval)offset;
- (void)moveToPoint:(CGPoint)point atOffset:(NSTimeInterval)offset;
- (void)liftUpAtOffset:(NSTimeInterval)offset;
- (void)addPointerEventPath:(id)path;
- (BOOL)synthesizeWithError:(NSError **)error;
@end

BOOL LFGPerformTwoFingerPan(
    CGPoint firstStart,
    CGPoint firstEnd,
    CGPoint secondStart,
    CGPoint secondEnd,
    NSTimeInterval duration,
    NSError **error
) {
    Class recordClass = NSClassFromString(@"XCSynthesizedEventRecord");
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    if (recordClass == Nil || pathClass == Nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"LFGUITests" code:1 userInfo:@{
                NSLocalizedDescriptionKey: @"XCTest event synthesis classes are unavailable"
            }];
        }
        return NO;
    }

    id record = [[recordClass alloc] initWithName:@"LFG two-finger pan"
                              interfaceOrientation:UIInterfaceOrientationPortrait];
    id first = [[pathClass alloc] initForTouchAtPoint:firstStart offset:0];
    id second = [[pathClass alloc] initForTouchAtPoint:secondStart offset:0];
    [first moveToPoint:firstEnd atOffset:duration];
    [second moveToPoint:secondEnd atOffset:duration];
    [first liftUpAtOffset:duration + 0.05];
    [second liftUpAtOffset:duration + 0.05];
    [record addPointerEventPath:first];
    [record addPointerEventPath:second];
    return [record synthesizeWithError:error];
}

BOOL LFGPerformTwoFingerTap(CGPoint center, CGFloat separation, NSError **error) {
    Class recordClass = NSClassFromString(@"XCSynthesizedEventRecord");
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    if (recordClass == Nil || pathClass == Nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"LFGUITests" code:2 userInfo:@{
                NSLocalizedDescriptionKey: @"XCTest event synthesis classes are unavailable"
            }];
        }
        return NO;
    }

    id record = [[recordClass alloc] initWithName:@"LFG two-finger tap"
                              interfaceOrientation:UIInterfaceOrientationPortrait];
    id first = [[pathClass alloc] initForTouchAtPoint:CGPointMake(center.x - separation, center.y) offset:0];
    id second = [[pathClass alloc] initForTouchAtPoint:CGPointMake(center.x + separation, center.y) offset:0];
    [first liftUpAtOffset:0.12];
    [second liftUpAtOffset:0.12];
    [record addPointerEventPath:first];
    [record addPointerEventPath:second];
    return [record synthesizeWithError:error];
}
