/*
 * cocos2d+ext for iPhone
 *
 * Copyright (c) 2011 - Ngo Duc Hiep
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */

#import "TouchTrailLayer.h"
#import "UIBezierPath-Points.h"
#import "CMUnistrokeRecognizer.h"
#import "CMUnistrokeGestureResult.h"
#import "CMUDTemplatePaths.h"
#import "CMUDTemplate.h"


static void
        CMURCGPathApplierFunc(void *info, const CGPathElement *element);

@interface TouchTrailLayer()

@property (nonatomic, strong) NSMutableArray *touchPaths;
@property (nonatomic, strong) UIBezierPath *strokePath;

@property (nonatomic, assign) float minimumScoreThreshold;

@property (nonatomic, strong, readwrite) CMUnistrokeGestureResult *result;

@property (strong, nonatomic) NSMutableDictionary *templates;

@end


@implementation TouchTrailLayer{
    CMURTemplatesRef _unistrokeTemplates;
    CMUROptionsRef _options;
}

- (id) init{
	self = [super init];

    if (self) {
        _touchEnabled = 1;
        map = CFDictionaryCreateMutable(NULL,0,NULL,NULL);
        CCSprite *bg = [CCSprite spriteWithFile:@"Default.png"];
        bg.rotation = 90;
        bg.position = ccp(240,160);
        [self addChild:bg];


        self.touchPaths = @[].mutableCopy;


        _unistrokeTemplates = CMURTemplatesNew();
        _options = CMUROptionsNew();
        _options->useProtractor = false;
        _options->rotationNormalisationDisabled = false;


        [self initializeDefaultTemplates];

        [self addStrokeTemplates];
    }

	return self;
}

- (void) dealloc{
    CFRelease(map);


    if (_options) {
        CMUROptionsDelete(_options); _options = NULL;
    }
    if (_unistrokeTemplates) {
        CMURTemplatesDelete(_unistrokeTemplates); _unistrokeTemplates = NULL;
    }
}

+ (CCScene *) scene{
    CCScene *scene = [CCScene node];
    [scene addChild:[self node]];
    return scene;
}

- (void) ccTouchesBegan:(NSSet *) touches withEvent:(UIEvent *) event{
	for (UITouch *touch in touches) {
		CCBlade *w = [CCBlade bladeWithMaximumPoint:100];
        w.autoDim = YES;
        int rand = arc4random() % 3 + 1;
		w.texture = [[CCTextureCache sharedTextureCache] addImage:[NSString stringWithFormat:@"streak%d.png",rand]];
        
        CFDictionaryAddValue(map,(__bridge const void *)(touch),(__bridge void*)w);
        
		[self addChild:w];
		CGPoint pos = [touch locationInView:touch.view];
		pos = [[CCDirector sharedDirector] convertToGL:pos];
		[w push:pos];
	}
}

- (void) ccTouchesMoved:(NSSet *) touches withEvent:(UIEvent *) event{
	for (UITouch *touch in touches) {
		CCBlade *w = (CCBlade *)CFDictionaryGetValue(map, (__bridge const void *)(touch));
		CGPoint pos = [touch locationInView:touch.view];
		pos = [[CCDirector sharedDirector] convertToGL:pos];
		[w push:pos];
	}
}

- (void) ccTouchesEnded:(NSSet *) touches withEvent:(UIEvent *) event{
	for (UITouch *touch in touches) {
		CCBlade *w = (CCBlade *)CFDictionaryGetValue(map, (__bridge const void *)(touch));
        [w finish];

        self.strokePath = [UIBezierPath pathWithPoints:w.path];
        [_touchPaths addObject:_strokePath];

        CFDictionaryRemoveValue(map,(__bridge const void *)(touch));

        DLog(@"Recognized:%@", [self isUnistrokeRecognized]? @"YES" : @"NO");
	}
}



#pragma mark - Private

#pragma mark Setup
- (void)initializeDefaultTemplates
{
    NSMutableDictionary *templates = [NSMutableDictionary dictionary];

    for (unsigned int i=0; ; i++) {
        struct templatePath templatePath = templatePaths[i];
        if (templatePath.length == 0) break;

        UIBezierPath *bezierPath = [[UIBezierPath alloc] init];
        [bezierPath moveToPoint:templatePath.points[0]];
        for (NSUInteger j=1; j<templatePath.length; j++) {
            [bezierPath addLineToPoint:templatePath.points[j]];
        }

        NSString *name = [NSString stringWithUTF8String:templatePath.name];

        CMUDTemplate *template = [templates valueForKey:name];
        if (template == nil) {
            template = [[CMUDTemplate alloc] initWithName:name];
            [templates setValue:template forKey:name];
        }
        [template addPath:bezierPath];
    }

    self.templates = templates;
}

- (void)addStrokeTemplates
{
    [self clearAllUnistrokes];

    for (CMUDTemplate *template in [self.templates allValues]) {
        for (UIBezierPath *path in template.paths) {
            [self registerUnistrokeWithName:template.name bezierPath:path];
        }
    }
    DLog(@"Done registering");
}

#pragma mark - Unistroke Methods

- (void)clearAllUnistrokes
{
    if (_unistrokeTemplates) {
        CMURTemplatesDelete(_unistrokeTemplates);
    }
    _unistrokeTemplates = CMURTemplatesNew();
}

- (void)registerUnistrokeWithName:(NSString *)name bezierPath:(UIBezierPath *)bezierPath
{
    [self registerUnistrokeWithName:name bezierPath:bezierPath bidirectional:NO];
}

- (void)registerUnistrokeWithName:(NSString *)name bezierPath:(UIBezierPath *)bezierPath bidirectional:(BOOL)bidirectional
{
    CMURPathRef path = [self pathFromBezierPath:bezierPath];
    CMURTemplatesAdd(_unistrokeTemplates, [name cStringUsingEncoding:NSUTF8StringEncoding], path, _options);

    if (bidirectional) {
        CMURPathReverse(path);
        CMURTemplatesAdd(_unistrokeTemplates, [name cStringUsingEncoding:NSUTF8StringEncoding], path, _options);
    }

    CMURPathDelete(path);
}

- (BOOL)isUnistrokeRecognized
{
    CMURPathRef path = [self pathFromBezierPath:self.strokePath];
    CMURResultRef result = unistrokeRecognizePathFromTemplates(path, _unistrokeTemplates, _options);
    CMURPathDelete(path);

    BOOL isRecognized;
    if (result && result->score >= self.minimumScoreThreshold) {
        isRecognized = YES;
        self.result = [[CMUnistrokeGestureResult alloc] initWithName:[NSString stringWithCString:result->name encoding:NSUTF8StringEncoding] score:result->score];
        DLog(@"Recognized: result->score = %f result->name = '%s'", result->score, result->name);
    }
    else {
        isRecognized = NO;
        self.result = nil;
        DLog(@"NOT Recognized");
    }

    CMURResultDelete(result);

    return isRecognized;
}

- (CMURPathRef)pathFromBezierPath:(UIBezierPath *)bezierPath
{
    CMURPathRef path = CMURPathNew();
    CGPathApply(bezierPath.CGPath, path, CMURCGPathApplierFunc);

    return path;
}

static void
CMURCGPathApplierFunc(void *info, const CGPathElement *element)
{
    CMURPathRef path = (CMURPathRef)info;

    CGPoint *points = element->points;
    CGPathElementType type = element->type;

    switch(type) {
        case kCGPathElementMoveToPoint: // contains 1 point
            CMURPathAddPoint(path, points[0].x, points[0].y);
            break;

        case kCGPathElementAddLineToPoint: // contains 1 point
            CMURPathAddPoint(path, points[0].x, points[0].y);
            break;

        case kCGPathElementAddQuadCurveToPoint: // contains 2 points
            CMURPathAddPoint(path, points[0].x, points[0].y);
            CMURPathAddPoint(path, points[1].x, points[1].y);
            break;

        case kCGPathElementAddCurveToPoint: // contains 3 points
            CMURPathAddPoint(path, points[0].x, points[0].y);
            CMURPathAddPoint(path, points[1].x, points[1].y);
            CMURPathAddPoint(path, points[2].x, points[2].y);
            break;

        case kCGPathElementCloseSubpath: // contains no point
            break;
    }
}

@end
