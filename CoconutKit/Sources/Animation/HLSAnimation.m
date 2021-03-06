//
//  HLSAnimation.m
//  CoconutKit
//
//  Created by Samuel Défago on 2/8/11.
//  Copyright 2011 Hortis. All rights reserved.
//

#import "HLSAnimation.h"

#import "HLSAnimationStep+Friend.h"
#import "HLSAssert.h"
#import "HLSConverters.h"
#import "HLSFloat.h"
#import "HLSLayerAnimationStep.h"
#import "HLSLogger.h"
#import "HLSUserInterfaceLock.h"
#import "HLSZeroingWeakRef.h"
#import "NSArray+HLSExtensions.h"
#import "NSString+HLSExtensions.h"

/**
 * HLSAnimation does not provide any safety measures against non-integral frames (which ultimately lead to blurry
 * views). The reason is that fixing such issues in an automatic way would make reverse animations difficult to
 * generate, since HLSAnimation does not store any information about the original state of the views which are
 * animated.
 */

static NSString * const kDelayLayerAnimationTag = @"HLSDelayLayerAnimationStep";

@interface HLSAnimation () <HLSAnimationStepDelegate>

+ (NSArray *)duplicateAnimationSteps:(NSArray *)animationSteps;

@property (nonatomic, retain) NSArray *animationSteps;
@property (nonatomic, retain) NSArray *animationStepCopies;
@property (nonatomic, retain) NSEnumerator *animationStepsEnumerator;
@property (nonatomic, retain) HLSAnimationStep *currentAnimationStep;
@property (nonatomic, assign, getter=isRunning) BOOL running;
@property (nonatomic, assign, getter=isPlaying) BOOL playing;
@property (nonatomic, assign, getter=isStarted) BOOL started;
@property (nonatomic, assign, getter=isCancelling) BOOL cancelling;
@property (nonatomic, assign, getter=isTerminating) BOOL terminating;
@property (nonatomic, retain) HLSZeroingWeakRef *delegateZeroingWeakRef;

- (void)playWithStartTime:(NSTimeInterval)startTime
              repeatCount:(NSUInteger)repeatCount
       currentRepeatCount:(NSUInteger)currentRepeatCount
               afterDelay:(NSTimeInterval)delay
                 animated:(BOOL)animated;

- (void)playAnimationStep:(HLSAnimationStep *)animationStep animated:(BOOL)animated;
- (void)playNextAnimationStepAnimated:(BOOL)animated;

- (NSArray *)reverseAnimationSteps;

- (void)applicationDidEnterBackground:(NSNotification *)notification;
- (void)applicationWillEnterForeground:(NSNotification *)notification;

@end

@implementation HLSAnimation

#pragma mark Class methods

+ (HLSAnimation *)animationWithAnimationSteps:(NSArray *)animationSteps
{
    return [[[[self class] alloc] initWithAnimationSteps:animationSteps] autorelease];
}

+ (HLSAnimation *)animationWithAnimationStep:(HLSAnimationStep *)animationStep
{
    NSArray *animationSteps = nil;
    if (animationStep) {
        animationSteps = [NSArray arrayWithObject:animationStep];
    }
    return [HLSAnimation animationWithAnimationSteps:animationSteps];
}

+ (NSArray *)duplicateAnimationSteps:(NSArray *)animationSteps
{
    NSMutableArray *animationStepCopies = [NSMutableArray array];
    for (HLSAnimationStep *animationStep in animationSteps) {
        [animationStepCopies addObject:[[animationStep copy] autorelease]];
    }
    return [NSArray arrayWithArray:animationStepCopies];
}

#pragma mark Object creation and destruction

- (id)initWithAnimationSteps:(NSArray *)animationSteps
{
    if ((self = [super init])) {
        if (! animationSteps) {
            self.animationSteps = [NSArray array];
        }
        else {
            HLSAssertObjectsInEnumerationAreKindOfClass(animationSteps, HLSAnimationStep);
            self.animationSteps = [HLSAnimation duplicateAnimationSteps:animationSteps];
        }
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillEnterForeground:)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
    }
    return self;
}

- (id)init
{
    HLSForbiddenInheritedMethod();
    return nil;
}

- (void)dealloc
{
    [self cancel];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.animationSteps = nil;
    self.animationStepCopies = nil;
    self.animationStepsEnumerator = nil;
    self.currentAnimationStep = nil;
    self.tag = nil;
    self.userInfo = nil;
    self.delegateZeroingWeakRef = nil;
    
    [super dealloc];
}

#pragma mark Accessors and mutators

@synthesize animationSteps = m_animationSteps;

@synthesize animationStepCopies = m_animationStepCopies;

@synthesize animationStepsEnumerator = m_animationStepsEnumerator;

@synthesize currentAnimationStep = m_currentAnimationStep;

@synthesize tag = m_tag;

@synthesize userInfo = m_userInfo;

@synthesize lockingUI = m_lockingUI;

@synthesize running = m_running;

@synthesize playing = m_playing;

@synthesize started = m_started;

- (BOOL)isPaused
{
    return [self.currentAnimationStep isPaused];
}

@synthesize cancelling = m_cancelling;

@synthesize terminating = m_terminating;

@synthesize delegateZeroingWeakRef = m_delegateZeroingWeakRef;

- (id<HLSAnimationDelegate>)delegate
{
    return self.delegateZeroingWeakRef.object;
}

- (void)setDelegate:(id<HLSAnimationDelegate>)delegate
{
    self.delegateZeroingWeakRef = [[[HLSZeroingWeakRef alloc] initWithObject:delegate] autorelease];
    [self.delegateZeroingWeakRef addCleanupAction:@selector(cancel) onTarget:self];
}

- (NSTimeInterval)duration
{
    NSTimeInterval duration = 0.;
    for (HLSAnimationStep *animationStep in self.animationSteps) {
        duration += animationStep.duration;
    }
    return duration;
}

#pragma mark Animation

- (void)playAnimated:(BOOL)animated
{
    [self playWithStartTime:0. repeatCount:1 currentRepeatCount:0 afterDelay:0. animated:animated];
}

- (void)playAfterDelay:(NSTimeInterval)delay
{
    [self playWithStartTime:0. repeatCount:1 currentRepeatCount:0 afterDelay:delay animated:YES];
}

- (void)playWithRepeatCount:(NSUInteger)repeatCount animated:(BOOL)animated
{
    [self playWithStartTime:0. repeatCount:repeatCount currentRepeatCount:0 afterDelay:0. animated:animated];
}

- (void)playWithRepeatCount:(NSUInteger)repeatCount afterDelay:(NSTimeInterval)delay
{
    [self playWithStartTime:0. repeatCount:repeatCount currentRepeatCount:0 afterDelay:delay animated:YES];
}

- (void)playWithStartTime:(NSTimeInterval)startTime
{
    [self playWithStartTime:startTime repeatCount:1 currentRepeatCount:0 afterDelay:0. animated:YES];
}

- (void)playWithStartTime:(NSTimeInterval)startTime repeatCount:(NSUInteger)repeatCount
{
    [self playWithStartTime:startTime repeatCount:repeatCount currentRepeatCount:0 afterDelay:0. animated:YES];
}

- (void)playWithStartTime:(NSTimeInterval)startTime
              repeatCount:(NSUInteger)repeatCount
       currentRepeatCount:(NSUInteger)currentRepeatCount
               afterDelay:(NSTimeInterval)delay
                 animated:(BOOL)animated
{
    if (repeatCount == 0) {
        HLSLoggerError(@"repeatCount cannot be 0");
        return;
    }
    
    if (repeatCount == NSUIntegerMax && ! animated) {
        HLSLoggerError(@"An animation running indefinitely must be played with animated = YES");
        return;
    }
    
    if (! animated && ! doubleeq(delay, 0.)) {
        HLSLoggerWarn(@"A delay has been defined, but the animation is played non-animated. The delay will be ignored");
        delay = 0.;
    }
        
    if (floatlt(delay, 0.)) {
        delay = 0;
        HLSLoggerWarn(@"Negative delay. Fixed to 0");
    }
    
    if (doublelt(startTime, 0.)) {
        HLSLoggerWarn(@"The start time cannot be negative. Fixed to 0");
        startTime = 0.;
    }
    
    NSTimeInterval totalDuration = repeatCount * [self duration];
    if (doublegt(startTime, totalDuration)) {
        HLSLoggerWarn(@"The start time %.2f is larger than the total animation duration %.2f (including repeats). Set to the total duration",
                      startTime, totalDuration);
        startTime = repeatCount * [self duration];
    }
        
    // Cannot be played if already running and trying to play the first time
    if (currentRepeatCount == 0) {
        if (self.running) {
            HLSLoggerDebug(@"The animation is already running");
            return;
        }
                
        self.running = YES;
        self.playing = YES;
    
        // Lock the UI during the animation
        if (self.lockingUI) {
            [[HLSUserInterfaceLock sharedUserInterfaceLock] lock];
        }
    }
    
    // Animation steps carry state information. To avoid issues when playing the same animation step several times (most
    // notably when repeatCount > 1), we work on a deep copy of them
    self.animationStepCopies = [HLSAnimation duplicateAnimationSteps:self.animationSteps];
        
    m_animated = animated;
    m_repeatCount = repeatCount;
    m_currentRepeatCount = currentRepeatCount;
    m_remainingTimeBeforeStart = startTime;
    m_elapsedTime = 0.;
    
    // Create a dummy animation step to simulate the delay. This way we avoid two potential issues:
    //   - if an animation step subclass is implemented using an animation framework which does not support delays,
    //     delayed animations would not be possible
    //   - there is an issue with Core Animation delays: CALayer properties must namely be updated ASAP (ideally
    //     when creating the animation), but this cannot be done with delayed Core Animations (otherwise the animated
    //     layer reaches its end state before the animation has actually started). In such cases, properties should
    //     be set in the -animationDidStart: animation callback. This works well in most cases, but it is too late
    //     (after all, the start delegate method is called 'didStart', not 'willStart') if the animated layers are
    //     heavy, e.g. with many transparent sublayers, creating an ugly flickering in animations. By creating delays
    //     with a dummy layer animation step, this problem vanishes
    HLSLayerAnimationStep *delayAnimationStep = [HLSLayerAnimationStep animationStep];
    delayAnimationStep.tag = kDelayLayerAnimationTag;
    delayAnimationStep.duration = delay;
    
    // Set the dummy animation step as current animation step, so that cancel / terminate work as expected, even
    // if they occur during the initial delay period
    self.currentAnimationStep = delayAnimationStep;
    [self playAnimationStep:delayAnimationStep animated:animated];
}

- (void)playAnimationStep:(HLSAnimationStep *)animationStep animated:(BOOL)animated
{
    // Instantaneously play all animation steps which complete before the start time. The value of m_remainingTimeBeforeStart
    // is updated before the animation is played (so that it can be used as a criterium to guess whether we are playing
    // animation steps instantaneously to reach the start time)
    if (doublegt(m_remainingTimeBeforeStart, animationStep.duration)) {
        m_remainingTimeBeforeStart -= animationStep.duration;
        [animationStep playWithDelegate:self startTime:0. animated:NO];
    }
    // Play the incomplete animation step, starting where appropriate
    else {
        NSTimeInterval remainingTimeBeforeStart = m_remainingTimeBeforeStart;
        m_remainingTimeBeforeStart = 0.;
        [animationStep playWithDelegate:self startTime:remainingTimeBeforeStart animated:animated];
    }
}

- (void)playNextAnimationStepAnimated:(BOOL)animated
{
    // First call?
    if (! self.animationStepsEnumerator) {
        self.animationStepsEnumerator = [self.animationStepCopies objectEnumerator];
    }
    
    // Proceeed with the next step (if any)
    self.currentAnimationStep = [self.animationStepsEnumerator nextObject];
    if (self.currentAnimationStep) {
        [self playAnimationStep:self.currentAnimationStep animated:(self.cancelling || self.terminating) ? NO : m_animated];
    }
    // Done with the animation
    else {
        // Empty animations (without animation steps) must still call the animationWillStart:animated delegate method
        if (m_currentRepeatCount == 0 && [self.animationStepCopies count] == 0) {
            if ([self.delegate respondsToSelector:@selector(animationWillStart:animated:)]) {
                [self.delegate animationWillStart:self animated:animated];
            }
            
            self.started = YES;
        }
        
        self.animationStepsEnumerator = nil;
                
        // Could theoretically overflow if m_repeatCount == NSUIntegerMax, but this would still yield a correct
        // behavior here
        ++m_currentRepeatCount;
        
        if ((m_repeatCount == NSUIntegerMax && (self.terminating || self.cancelling))
                || (m_repeatCount != NSUIntegerMax && m_currentRepeatCount == m_repeatCount)) {
            // Unlock the UI
            if (self.lockingUI) {
                [[HLSUserInterfaceLock sharedUserInterfaceLock] unlock];
            }
            
            m_started = NO;
            m_playing = NO;
            
            if (! self.cancelling) {
                if ([self.delegate respondsToSelector:@selector(animationDidStop:animated:)]) {
                    [self.delegate animationDidStop:self animated:self.terminating ? NO : animated];
                }
            }
            
            // End of the animation
            m_running = NO;
            m_cancelling = NO;
            m_terminating = NO;
        }    
        // Repeat as needed
        else {
            [self playWithStartTime:m_remainingTimeBeforeStart
                        repeatCount:m_repeatCount
                 currentRepeatCount:m_currentRepeatCount
                         afterDelay:0.
                           animated:(self.cancelling || self.terminating) ? NO : m_animated];
        }
    }
}

- (void)pause
{
    if (! self.running) {
        HLSLoggerDebug(@"The animation is not running, nothing to pause");
        return;
    }
    
    if (self.cancelling || self.terminating) {
        HLSLoggerDebug(@"The animation is being cancelled or terminated");
        return;
    }
    
    if (self.paused) {
        HLSLoggerDebug(@"The animation is already paused");
        return;
    }
    
    [self.currentAnimationStep pause];
}

- (void)resume
{
    if (! self.paused) {
        HLSLoggerDebug(@"The animation has not being paused. Nothing to resume");
        return;
    }
    
    [self.currentAnimationStep resume];
}

- (void)cancel
{
    if (! self.running) {
        HLSLoggerDebug(@"The animation is not running, nothing to cancel");
        return;
    }
    
    if (self.cancelling || self.terminating) {
        HLSLoggerDebug(@"The animation is already being cancelled or terminated");
        return;
    }
    
    self.cancelling = YES;
    
    // Cancel all animations
    [self.currentAnimationStep terminate];
}

- (void)terminate
{
    if (! self.running) {
        HLSLoggerDebug(@"The animation is not running, nothing to terminate");
        return;
    }
    
    if (self.cancelling || self.terminating) {
        HLSLoggerDebug(@"The animation is already being cancelled or terminated");
        return;
    }
    
    self.terminating = YES;
    
    // Cancel all animations
    [self.currentAnimationStep terminate];
}

#pragma mark Creating animations variants from an existing animation

- (HLSAnimation *)animationWithDuration:(NSTimeInterval)duration
{
    if (doublelt(duration, 0.f)) {
        HLSLoggerError(@"The duration cannot be negative");
        return nil;
    }
    
    HLSAnimation *animation = [[self copy] autorelease];
    
    // Find out which factor must be applied to each animation step to preserve the animation appearance for the
    // specified duration
    double factor = duration / [self duration];
    
    // Distribute the total duration evenly among animation steps
    for (HLSAnimationStep *animationStep in animation.animationSteps) {
        animationStep.duration *= factor;
    }
    
    return animation;
}

- (NSArray *)reverseAnimationSteps
{
    NSMutableArray *reverseAnimationSteps = [NSMutableArray array];
    for (HLSAnimationStep *animationStep in [self.animationSteps reverseObjectEnumerator]) {
        [reverseAnimationSteps addObject:[animationStep reverseAnimationStep]];
    }
    return [NSArray arrayWithArray:reverseAnimationSteps];
}

- (HLSAnimation *)reverseAnimation
{
    HLSAnimation *reverseAnimation = [HLSAnimation animationWithAnimationSteps:[self reverseAnimationSteps]];
    reverseAnimation.tag = [self.tag isFilled] ? [NSString stringWithFormat:@"reverse_%@", self.tag] : nil;
    reverseAnimation.lockingUI = self.lockingUI;
    reverseAnimation.delegate = self.delegate;
    reverseAnimation.userInfo = self.userInfo;
    
    return reverseAnimation;
}

- (HLSAnimation *)loopAnimation
{
    NSMutableArray *animationSteps = [NSMutableArray arrayWithArray:self.animationSteps];
    [animationSteps addObjectsFromArray:[self reverseAnimationSteps]];
    
    // Add a loop_ prefix to all animation step tags
    for (HLSAnimationStep *animationStep in animationSteps) {
        animationStep.tag = [animationStep.tag isFilled] ? [NSString stringWithFormat:@"loop_%@", animationStep.tag] : nil;
    }
    
    HLSAnimation *loopAnimation = [HLSAnimation animationWithAnimationSteps:[NSArray arrayWithArray:animationSteps]];
    loopAnimation.tag = [self.tag isFilled] ? [NSString stringWithFormat:@"loop_%@", self.tag] : nil;
    loopAnimation.lockingUI = self.lockingUI;
    loopAnimation.delegate = self.delegate;
    loopAnimation.userInfo = self.userInfo;
    
    return loopAnimation;
}

#pragma mark HLSAnimationStepDelegate protocol implementation

- (void)animationStepDidStop:(HLSAnimationStep *)animationStep animated:(BOOL)animated finished:(BOOL)finished
{
    // Still send all delegate notifications if terminating and if not playing animation steps instantaneously
    // when a start time has been set
    if (! self.cancelling && doubleeq(m_remainingTimeBeforeStart, 0.)) {
        // Notify that the animation begins when the initial delay animation (always played) ends. This way
        // we get rid of subtle differences which might arise with animation steps only being able to notify
        // when they did start, rather than when they will
        if ([animationStep.tag isEqualToString:kDelayLayerAnimationTag]) {
            // Note that if a delay has been set, this event is not fired until the delay period is over, as for UIView
            // animation blocks)
            if (m_currentRepeatCount == 0) {
                if ([self.delegate respondsToSelector:@selector(animationWillStart:animated:)]) {
                    [self.delegate animationWillStart:self animated:animated];
                }
                
                self.started = YES;
            }
        }
        else {
            if ([self.delegate respondsToSelector:@selector(animation:didFinishStep:animated:)]) {
                [self.delegate animation:self didFinishStep:animationStep animated:animated];
            }
        }
    }
    
    // We accumulate the effective duration of the animation which has been run until now
    if (! self.cancelling && ! self.terminating) {
        m_elapsedTime += [self.currentAnimationStep duration];
    }
    
    // Play the next step (or the first step if the initial delay animation step has ended(), but non-animated if the
    // animation did not reach completion normally. Moreover, if some animation steps are played non-animated because
    // a start time has been set, we must override animated = NO with the original m_animated value of the animation
    [self playNextAnimationStepAnimated:finished ? (! doubleeq(m_remainingTimeBeforeStart, 0.) ? m_animated : animated) : NO];
}

#pragma mark NSCopying protocol implementation

- (id)copyWithZone:(NSZone *)zone
{
    HLSAnimation *animationCopy = nil;
    if (self.animationSteps) {
        NSMutableArray *animationStepCopies = [NSMutableArray array];
        for (HLSAnimationStep *animationStep in self.animationSteps) {
            HLSAnimationStep *animationStepCopy = [[animationStep copyWithZone:zone] autorelease];
            [animationStepCopies addObject:animationStepCopy];
        }
        animationCopy = [[HLSAnimation allocWithZone:zone] initWithAnimationSteps:[NSMutableArray arrayWithArray:animationStepCopies]];
    }
    else {
        animationCopy = [[HLSAnimation allocWithZone:zone] initWithAnimationSteps:nil];
    }
    
    animationCopy.tag = self.tag;
    animationCopy.lockingUI = self.lockingUI;
    animationCopy.delegate = self.delegate;
    animationCopy.userInfo = self.userInfo;
    
    return animationCopy;
}

#pragma mark Notification callbacks

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    m_runningBeforeEnteringBackground = self.running;
    
    if (m_runningBeforeEnteringBackground) {
        // Core Animations are removed and added back again automatically when the application enters / leaves background. This makes
        // it very hard to resume running animations after the application wakes up, since we have no real control over this process.
        // But since HLSAnimations can be given a start time, we can apply the following strategy to solve those issues:
        //   1) Remember how much time has elapsed and cancel the animation when the application enters background. The remaining
        //      delegate events are not received
        //   2) Rewind the animation at the beginning, without a delegate
        //   3) Play the animation from where it was cancelled when the application enters foreground
        m_elapsedTime += [self.currentAnimationStep elapsedTime];
        m_pausedBeforeEnteringBackground = self.paused;
        
        [self cancel];
        
        HLSAnimation *reverseAnimation = [self reverseAnimation];
        reverseAnimation.delegate = nil;
        [reverseAnimation playAnimated:NO];
    }
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    if (m_runningBeforeEnteringBackground) {
        //we need to retain here because playWithStartTime might stop the animation
        // and thus release us. THen we want to call [self pause]...
        [self retain];
        [self playWithStartTime:m_elapsedTime repeatCount:m_repeatCount];
        if (m_pausedBeforeEnteringBackground) {
            [self pause];
        }
        [self release];
        
        m_runningBeforeEnteringBackground = NO;
        m_pausedBeforeEnteringBackground = NO;
    }
}

#pragma mark Description

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p; animationSteps: %@; tag: %@; lockingUI: %@; delegate: %p>",
            [self class],
            self,
            self.animationSteps,
            self.tag,
            HLSStringFromBool(self.lockingUI),
            self.delegate];
}

@end
