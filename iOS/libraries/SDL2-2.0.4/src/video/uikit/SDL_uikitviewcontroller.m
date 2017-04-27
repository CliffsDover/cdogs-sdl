/*
  Simple DirectMedia Layer
  Copyright (C) 1997-2015 Sam Lantinga <slouken@libsdl.org>

  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
  arising from the use of this software.

  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
     claim that you wrote the original software. If you use this software
     in a product, an acknowledgment in the product documentation would be
     appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
     misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.
*/
#include "../../SDL_internal.h"

#if SDL_VIDEO_DRIVER_UIKIT

#include "SDL_video.h"
#include "SDL_assert.h"
#include "SDL_hints.h"
#include "../SDL_sysvideo.h"
#include "../../events/SDL_events_c.h"

#import "SDL_uikitviewcontroller.h"
#import "SDL_uikitmessagebox.h"
#include "SDL_uikitvideo.h"
#include "SDL_uikitmodes.h"
#include "SDL_uikitwindow.h"
#include "SDL_uikitappdelegate.h"

#if SDL_IPHONE_KEYBOARD
#include "keyinfotable.h"
#endif

#import "SDVersion.h"




@implementation SDL_uikitviewcontroller {
    CADisplayLink *displayLink;
    int animationInterval;
    void (*animationCallback)(void*);
    void *animationCallbackParam;

#if SDL_IPHONE_KEYBOARD
    UITextField *textField;
#endif
    
    JSDPad *dPad;
    JSButton* yesButton;
    JSButton* noButton;
    //JSButton* plusButton;
    //JSButton* minusButton;
    //JSButton* keyboardButton;
    //JSButton* hudButton;
    JSButton* optionsButton;

    BOOL isHudShown;
    NSTimer* dpadTimer;
    
    
    UILongPressGestureRecognizer * longPressGesture;
    UILongPressGestureRecognizer * doubleLongPressGesture;
    UILongPressGestureRecognizer * tripleLongPressGesture;
    UITapGestureRecognizer *singleTap;
    UITapGestureRecognizer *doubleTap;
    UITapGestureRecognizer *tripleTap;
    
    
    //MBProgressHUD *hud;
    
    BOOL isModifyingUI;
    NSTimer* uiBlickTimer;
    
    float dPadScale;
    float dPadPosX;
    float dPadPosY;
    
    
    
    BOOL isRecording;
    
  

}

@synthesize window;

- (instancetype)initWithSDLWindow:(SDL_Window *)_window
{
    if (self = [super initWithNibName:nil bundle:nil]) {
        self.window = _window;

#if SDL_IPHONE_KEYBOARD
        [self initKeyboard];
#endif
    }
    return self;
}

- (void)dealloc
{
#if SDL_IPHONE_KEYBOARD
    [self deinitKeyboard];
#endif
}

- (void)setAnimationCallback:(int)interval
                    callback:(void (*)(void*))callback
               callbackParam:(void*)callbackParam
{
    [self stopAnimation];

    animationInterval = interval;
    animationCallback = callback;
    animationCallbackParam = callbackParam;

    if (animationCallback) {
        [self startAnimation];
    }
}

- (void)startAnimation
{
    displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(doLoop:)];
    [displayLink setFrameInterval:animationInterval];
    [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
}

- (void)stopAnimation
{
    [displayLink invalidate];
    displayLink = nil;
}

- (void)doLoop:(CADisplayLink*)sender
{
    /* Don't run the game loop while a messagebox is up */
    if (!UIKit_ShowingMessageBox()) {
        animationCallback(animationCallbackParam);
    }
}

- (void)loadView
{
    /* Do nothing. */
}

-(void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    
    const CGSize size = self.view.bounds.size;
    int w = (int) size.width;
    int h = (int) size.height;
    
    SDL_SendWindowEvent(window, SDL_WINDOWEVENT_RESIZED, w, h);

    [self.view setNeedsDisplay];
}

- (void)viewDidAppear:(BOOL)animated
{
    BOOL static firstTime = YES;
    [super viewDidAppear:animated];
    
    if( firstTime )
    {
        NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
        
        firstTime = NO;
        
        float scale = 1;
        if( ( [SDVersion deviceVersion] == iPad2 ) ||
           ( [SDVersion deviceVersion] == iPadAir ) ||
           ( [SDVersion deviceVersion] == iPadAir2 ) ||
           ( [SDVersion deviceVersion] == iPadMini ) ||
           ( [SDVersion deviceVersion] == iPadMini2 ) ||
           ( [SDVersion deviceVersion] == iPadMini3 ) ||
           ( [SDVersion deviceVersion] == iPadMini4 ) )
            scale = 2;
        
        
        dPad = [[JSDPad alloc] initWithFrame:CGRectMake(0, CGRectGetHeight(self.view.bounds) - 114 * scale, 114 * scale, 114 * scale)];
        dPad.delegate = self;
        dPad.alpha = 0.3f;
        
        dPadScale = [userDefaults floatForKey:@"DPadScale"];
        dPadPosX = [userDefaults floatForKey:@"DPadPosX"];
        dPadPosY = [userDefaults floatForKey:@"DPadPosY"];
        
        if( dPadPosX == -1.0f || dPadPosY == -1.0f )
        {
            dPadPosX = dPad.center.x;
            dPadPosY = dPad.center.y;
            [userDefaults setFloat:dPadPosX forKey:@"DPadPosX"];
            [userDefaults setFloat:dPadPosY forKey:@"DPadPosY"];
            [userDefaults synchronize];
        }
        
        [dPad setTransform:CGAffineTransformMakeScale(dPadScale, dPadScale)];
        [dPad setCenter:CGPointMake(dPadPosX, dPadPosY)];

        [self.view addSubview:dPad];
        //[dPad setHidden:YES];

        
        
        
        optionsButton = [[JSButton alloc] initWithFrame:CGRectMake(0, 0, 28 * scale, 28* scale)];
        [optionsButton setBackgroundImage:[UIImage imageNamed:@"options_silver_on"]];
        [optionsButton setBackgroundImagePressed:[UIImage imageNamed:@"options_silver_off"]];
        optionsButton.delegate = self;
        optionsButton.alpha = 0.3f;
        [self.view addSubview:optionsButton];
    
        
        
    //    keyboardButton = [[JSButton alloc] initWithFrame:CGRectMake(0, 0, 28 * scale, 28* scale)];
    //    [keyboardButton setBackgroundImage:[UIImage imageNamed:@"Show"]];
    //    [keyboardButton setBackgroundImagePressed:[UIImage imageNamed:@"Show_Touched"]];
    //    keyboardButton.delegate = self;
    //    keyboardButton.alpha = 0.3f;
    //    [self.view addSubview:keyboardButton];
        
        
        
    //    plusButton = [[JSButton alloc] initWithFrame:CGRectMake(0, ( 4 + 28* scale ) * 1, 28* scale, 28* scale)];
    //    [plusButton setBackgroundImage:[UIImage imageNamed:@"Plus"]];
    //    [plusButton setBackgroundImagePressed:[UIImage imageNamed:@"Plus_Touched"]];
    //    plusButton.delegate = self;
    //    plusButton.alpha = 0.3f;
    //    [self.view addSubview:plusButton];
        
        
        
    //    minusButton = [[JSButton alloc] initWithFrame:CGRectMake(0, ( 4 + 28 * scale) * 2, 28* scale, 28* scale)];
    //    [minusButton setBackgroundImage:[UIImage imageNamed:@"Minus"]];
    //    [minusButton setBackgroundImagePressed:[UIImage imageNamed:@"Minus_Touched"]];
    //    minusButton.delegate = self;
    //    minusButton.alpha = 0.3f;
    //    [self.view addSubview:minusButton];
        
        
        yesButton = [[JSButton alloc] initWithFrame:CGRectMake(self.view.bounds.size.width-64, self.view.bounds.size.height-64, 64, 64)];
        [yesButton setBackgroundImage:[UIImage imageNamed:@"Yes"]];
        [yesButton setBackgroundImagePressed:[UIImage imageNamed:@"Yes_Touched"]];
        yesButton.delegate = self;
        yesButton.alpha = 0.3f;
        [self.view addSubview:yesButton];
        
        
        noButton = [[JSButton alloc] initWithFrame:CGRectMake(self.view.bounds.size.width-64-64-16, self.view.bounds.size.height-64, 64, 64)];
        [noButton setBackgroundImage:[UIImage imageNamed:@"No"]];
        [noButton setBackgroundImagePressed:[UIImage imageNamed:@"No_Touched"]];
        noButton.delegate = self;
        noButton.alpha = 0.3f;
        [self.view addSubview:noButton];
        
        
        
        
    //    hudButton = [[JSButton alloc] initWithFrame:CGRectMake(0, ( 4 + 28* scale ) * 5, 28* scale, 28* scale)];
    //    [hudButton setBackgroundImage:[UIImage imageNamed:@"Hud"]];
    //    [hudButton setBackgroundImagePressed:[UIImage imageNamed:@"Hud"]];
    //    hudButton.delegate = self;
    //    hudButton.alpha = 0.30f;
    //    
    //    isHudShown = NO;
    //    [self.view addSubview:hudButton];
        
        
        longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hangleLongPress:)];
        longPressGesture.minimumPressDuration = 1.0;
        longPressGesture.delegate = self;
        [self.view addGestureRecognizer:longPressGesture];
        
        doubleLongPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleLongPress:)];
        doubleLongPressGesture.numberOfTouchesRequired = 2;
        doubleLongPressGesture.minimumPressDuration = 1.0;
        [self.view addGestureRecognizer:doubleLongPressGesture];
        
        
        singleTap = [[UITapGestureRecognizer alloc] initWithTarget: self action:@selector(singleTapped:)];
        singleTap.numberOfTapsRequired = 1;
        singleTap.numberOfTouchesRequired = 1;
        singleTap.delegate = self;
        [self.view addGestureRecognizer:singleTap];
        
        doubleTap = [[UITapGestureRecognizer alloc] initWithTarget: self action:@selector(doubleTapped:)];
        doubleTap.numberOfTapsRequired = 1;
        doubleTap.numberOfTouchesRequired = 2;
        doubleTap.delegate = self;
        [self.view addGestureRecognizer:doubleTap];
        
//        tripleTap = [[UITapGestureRecognizer alloc] initWithTarget: self action:@selector(tripleTapped:)];
//        tripleTap.numberOfTapsRequired = 1;
//        tripleTap.numberOfTouchesRequired = 3;
//        tripleTap.delegate = self;
//        [self.view addGestureRecognizer:tripleTap];
        
        
        tripleLongPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(tripleTapped:)];
        tripleLongPressGesture.numberOfTouchesRequired = 3;
        tripleLongPressGesture.minimumPressDuration = 1.0;
        [self.view addGestureRecognizer:tripleLongPressGesture];
        
        //[singleTap requireGestureRecognizerToFail:doubleTap];
        
        
        UIPinchGestureRecognizer* pinchGestureRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchGesture:)];
        [self.view addGestureRecognizer:pinchGestureRecognizer];

        
        
        UISwipeGestureRecognizer *swipeUp = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
        swipeUp.numberOfTouchesRequired = 1;
        swipeUp.direction = UISwipeGestureRecognizerDirectionUp;
        swipeUp.delegate = self;
        [self.view addGestureRecognizer:swipeUp];
        
        UISwipeGestureRecognizer *swipeDown = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
        swipeDown.numberOfTouchesRequired = 1;
        swipeDown.direction = UISwipeGestureRecognizerDirectionDown;
        swipeDown.delegate = self;
        [self.view addGestureRecognizer:swipeDown];
        
        
        UISwipeGestureRecognizer *doubleSwipeUp = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleSwipe:)];
        doubleSwipeUp.numberOfTouchesRequired = 2;
        doubleSwipeUp.direction = UISwipeGestureRecognizerDirectionUp;
        doubleSwipeUp.delegate = self;
        [self.view addGestureRecognizer:doubleSwipeUp];
        
    //    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
    //    swipeLeft.numberOfTouchesRequired = 2;
    //    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    //    swipeLeft.delegate = self;
    //    [self.view addGestureRecognizer:swipeLeft];
    //    
    //    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
    //    swipeRight.numberOfTouchesRequired = 2;
    //    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    //    swipeRight.delegate = self;
    //    [self.view addGestureRecognizer:swipeRight];
    
        self.lockKeyboard = YES;
        isModifyingUI = NO;
        isRecording = NO;

    }
    else
    {
        SDL_WindowData *data = (__bridge SDL_WindowData *)(self->window->driverdata);
        SDL_VideoDisplay *display = SDL_GetDisplayForWindow(self->window);
        SDL_DisplayModeData *displaymodedata = (__bridge SDL_DisplayModeData *) display->current_mode.driverdata;
        const CGSize size = self.view.bounds.size;
        int w, h;
        
        w = self.view.bounds.size.width;
        h = self.view.bounds.size.height;
        
        SDL_SendWindowEvent(self->window, SDL_WINDOWEVENT_EXPOSED, w, h);
        
        
        
    }
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIKit_GetSupportedOrientations(window);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orient
{
    return ([self supportedInterfaceOrientations] & (1 << orient)) != 0;
}

- (BOOL)prefersStatusBarHidden
{
    return (window->flags & (SDL_WINDOW_FULLSCREEN|SDL_WINDOW_BORDERLESS)) != 0;
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    /* We assume most SDL apps don't have a bright white background. */
    return UIStatusBarStyleLightContent;
}

/*
 ---- Keyboard related functionality below this line ----
 */
#if SDL_IPHONE_KEYBOARD

@synthesize textInputRect;
@synthesize keyboardHeight;
@synthesize keyboardVisible;

/* Set ourselves up as a UITextFieldDelegate */
- (void)initKeyboard
{
    textField = [[UITextField alloc] initWithFrame:CGRectZero];
    textField.delegate = self;
    /* placeholder so there is something to delete! */
    textField.text = @" ";

    /* set UITextInputTrait properties, mostly to defaults */
    textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    textField.autocorrectionType = UITextAutocorrectionTypeNo;
    textField.enablesReturnKeyAutomatically = NO;
    textField.keyboardAppearance = UIKeyboardAppearanceDefault;
    textField.keyboardType = UIKeyboardTypeDefault;
    textField.returnKeyType = UIReturnKeyDefault;
    textField.secureTextEntry = NO;

    textField.hidden = YES;
    keyboardVisible = NO;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [center addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)setView:(UIView *)view
{
    [super setView:view];

    [view addSubview:textField];

    if (keyboardVisible) {
        [self showKeyboard];
    }
}

- (void)deinitKeyboard
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [center removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

/* reveal onscreen virtual keyboard */
- (void)showKeyboard
{
    keyboardVisible = YES;
    if (textField.window) {
        [textField becomeFirstResponder];
    }
}

/* hide onscreen virtual keyboard */
- (void)hideKeyboard
{
    keyboardVisible = NO;
    [textField resignFirstResponder];
}

- (void)keyboardWillShow:(NSNotification *)notification
{
    CGRect kbrect = [[notification userInfo][UIKeyboardFrameBeginUserInfoKey] CGRectValue];

    /* The keyboard rect is in the coordinate space of the screen/window, but we
     * want its height in the coordinate space of the view. */
    kbrect = [self.view convertRect:kbrect fromView:nil];

    [self setKeyboardHeight:(int)kbrect.size.height];
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    [self setKeyboardHeight:0];
}

- (void)updateKeyboard
{
    CGAffineTransform t = self.view.transform;
    CGPoint offset = CGPointMake(0.0, 0.0);
    CGRect frame = UIKit_ComputeViewFrame(window, self.view.window.screen);

    if (self.keyboardHeight) {
        int rectbottom = self.textInputRect.y + self.textInputRect.h;
        int keybottom = self.view.bounds.size.height - self.keyboardHeight;
        if (keybottom < rectbottom) {
            offset.y = keybottom - rectbottom;
        }
    }

    /* Apply this view's transform (except any translation) to the offset, in
     * order to orient it correctly relative to the frame's coordinate space. */
    t.tx = 0.0;
    t.ty = 0.0;
    offset = CGPointApplyAffineTransform(offset, t);

    /* Apply the updated offset to the view's frame. */
    frame.origin.x += offset.x;
    frame.origin.y += offset.y;

    self.view.frame = frame;
}

- (void)setKeyboardHeight:(int)height
{
    keyboardVisible = height > 0;
    keyboardHeight = height;
    [self updateKeyboard];
}

/* UITextFieldDelegate method.  Invoked when user types something. */
- (BOOL)textField:(UITextField *)_textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    NSUInteger len = string.length;

    if (len == 0) {
        /* it wants to replace text with nothing, ie a delete */
        SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_BACKSPACE);
        SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_BACKSPACE);
    } else {
        /* go through all the characters in the string we've been sent and
         * convert them to key presses */
        int i;
        for (i = 0; i < len; i++) {
            unichar c = [string characterAtIndex:i];
            Uint16 mod = 0;
            SDL_Scancode code;

            if (c < 127) {
                /* figure out the SDL_Scancode and SDL_keymod for this unichar */
                code = unicharToUIKeyInfoTable[c].code;
                mod  = unicharToUIKeyInfoTable[c].mod;
            } else {
                /* we only deal with ASCII right now */
                code = SDL_SCANCODE_UNKNOWN;
                mod = 0;
            }

            if (mod & KMOD_SHIFT) {
                /* If character uses shift, press shift down */
                SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_LSHIFT);
            }

            /* send a keydown and keyup even for the character */
            SDL_SendKeyboardKey(SDL_PRESSED, code);
            SDL_SendKeyboardKey(SDL_RELEASED, code);

            if (mod & KMOD_SHIFT) {
                /* If character uses shift, press shift back up */
                SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_LSHIFT);
            }
        }

        SDL_SendKeyboardText([string UTF8String]);
    }

    if( !self.lockKeyboard )
        [self hideKeyboard];
    
    return NO; /* don't allow the edit! (keep placeholder text there) */
}

/* Terminates the editing session */
- (BOOL)textFieldShouldReturn:(UITextField*)_textField
{
    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_RETURN);
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_RETURN);
    SDL_StopTextInput();
    return YES;
}




-(void)dpadTimerHandler:(NSTimer *)timer
{
    //NSLog( @"dpadTimerHandler" );
    
    switch( [[timer userInfo][@"Direction"] integerValue] )
    {
        case JSDPadDirectionLeft:
            SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_LEFT );
            SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_LEFT );
            break;
            
        case JSDPadDirectionRight:
            SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_RIGHT );
            SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_RIGHT );
            break;
            
        case JSDPadDirectionUp:
            SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_UP );
            SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_UP );
            break;
            
        case JSDPadDirectionDown:
            SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_DOWN );
            SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_DOWN );
            break;
            
        case JSDPadDirectionUpLeft:
            SDL_SendKeyboardText( "y" );
            break;
            
        case JSDPadDirectionUpRight:
            SDL_SendKeyboardText( "u" );
            break;
            
        case JSDPadDirectionDownLeft:
            SDL_SendKeyboardText( "b" );
            break;
            
        case JSDPadDirectionDownRight:
            SDL_SendKeyboardText( "n" );
            break;
        case JSDPadDirectionCenter:
            SDL_SendKeyboardText( "." );
            //NSLog(@"center");
            break;
        default:
            break;
            
    }
    
    //dpadTimer = [NSTimer scheduledTimerWithTimeInterval:0.333 target:self selector:@selector(dpadTimerHandler:) userInfo:@{@"Direction": [timer userInfo][@"Direction"]} repeats:NO];
    
    //    [dpadTimer fire];
    
}


#pragma mark - JSDPadDelegate
- (NSString *)stringForDirection:(JSDPadDirection)direction
{
    NSString *string = nil;
    
    switch (direction) {
        case JSDPadDirectionNone:
            string = @"None";
            SDL_SendKeyboardText( "." );
            break;
        case JSDPadDirectionUp:
            string = @"Up";
            SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_UP );
            //SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_UP );
            
            break;
        case JSDPadDirectionDown:
            string = @"Down";
            SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_DOWN );
            //SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_DOWN );
            
            break;
        case JSDPadDirectionLeft:
            string = @"Left";
            SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_LEFT );
            //SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_LEFT );
            
            break;
        case JSDPadDirectionRight:
            string = @"Right";
            SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_RIGHT );
            //SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_RIGHT );
                        break;
        case JSDPadDirectionUpLeft:
            string = @"Up Left";
            SDL_SendKeyboardText( "y" );
            
            break;
        case JSDPadDirectionUpRight:
            string = @"Up Right";
            SDL_SendKeyboardText( "u" );
            
            break;
        case JSDPadDirectionDownLeft:
            string = @"Down Left";
            SDL_SendKeyboardText( "b" );
            
            break;
        case JSDPadDirectionDownRight:
            string = @"Down Right";
            SDL_SendKeyboardText( "n" );
            
            break;
        case JSDPadDirectionCenter:
            //SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_RETURN );
            //SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_RETURN );
            SDL_SendKeyboardText( "." );
            
            break;
        default:
            string = @"NO";
            break;
    }
    
    return string;
}

- (void *)didReleaseDirection:(JSDPadDirection)direction
{
    switch (direction) {
        case JSDPadDirectionNone:
            //SDL_SendKeyboardText( "." );
            break;
        case JSDPadDirectionUp:
            SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_UP );
            break;
        case JSDPadDirectionDown:
            SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_DOWN );
            break;
        case JSDPadDirectionLeft:
            SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_LEFT );
            break;
        case JSDPadDirectionRight:
            SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_RIGHT );
            break;
        case JSDPadDirectionUpLeft:
            //SDL_SendKeyboardText( "y" );
            break;
        case JSDPadDirectionUpRight:
            //SDL_SendKeyboardText( "u" );
            break;
        case JSDPadDirectionDownLeft:
            //SDL_SendKeyboardText( "b" );
            break;
        case JSDPadDirectionDownRight:
            //SDL_SendKeyboardText( "n" );
            break;
        case JSDPadDirectionCenter:
            //SDL_SendKeyboardText( "." );
    
            break;
        default:
    
            break;
    }
}


- (void)dPad:(JSDPad *)dPad didPressDirection:(JSDPadDirection)direction
{
    //[longPressGesture setEnabled:NO];
    [self stringForDirection:direction];
    //NSLog(@"Changing direction to: %@", [self stringForDirection:direction]);
    //[self updateDirectionLabel];
    
}

- (void)dPadDidReleaseDirection:(JSDPadDirection *)direction
{
    //NSLog(@"Releasing DPad");
    //[self updateDirectionLabel];
    [self didReleaseDirection:direction];
    //[dpadTimer invalidate];
    //dpadTimer = nil;
    //[longPressGesture setEnabled:YES];
}





#pragma mark - JSButtonDelegate

- (void)buttonPressed:(JSButton *)button
{
    if ([button isEqual:yesButton])
    {
        SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_RETURN );
        //SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_RETURN );
    }
    else if ([button isEqual:noButton])
    {
        SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_RSHIFT );
        //SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_ESCAPE );
    }
    else if( [button isEqual:optionsButton] )
    {
        //[self didTapOptionsButton];
        SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_ESCAPE );
        
    }
}

- (void)buttonReleased:(JSButton *)button
{
    if ([button isEqual:yesButton])
    {
        //SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_RETURN );
        SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_RSHIFT );
    }
    else if ([button isEqual:noButton])
    {
        //SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_ESCAPE );
        SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_ESCAPE );
    }
    else if( [button isEqual:optionsButton] )
    {
        //[self didTapOptionsButton];
        SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_ESCAPE );
        
    }
//    else if ([button isEqual:keyboardButton])
//    {
//        if( SDL_IsScreenKeyboardShown( SDL_GetFocusWindow() ) )
//        {
//            SDL_StopTextInput();
//            [keyboardButton setBackgroundImage:[UIImage imageNamed:@"Show"]];
//            [keyboardButton setBackgroundImagePressed:[UIImage imageNamed:@"Show_Touched"]];
//        }
//        else
//        {
//            SDL_StartTextInput();
//            [keyboardButton setBackgroundImage:[UIImage imageNamed:@"Hide"]];
//            [keyboardButton setBackgroundImagePressed:[UIImage imageNamed:@"Hide_Touched"]];
//        }
//    }
//    else if ([button isEqual:plusButton])
//    {
//        SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_KP_PLUS);
//        SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_KP_PLUS);
//    }
//    else if ([button isEqual:minusButton])
//    {
//        SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_KP_MINUS);
//        SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_KP_MINUS);
//    }
//    else if ([button isEqual:hudButton])
//    {
//        isHudShown = !isHudShown;
//        if( YES == isHudShown )
//        {
//            //[self.view addSubview:dPad];
//            [dPad setHidden:NO];
//            [hudButton setAlpha:0.15];
//        }
//        else
//        {
//            [dPad setHidden:YES];
//            [hudButton setAlpha:0.3];
//        }
//    }
//    else if( [button isEqual:prevButton])
//    {
//        SDL_SendKeyboardText("<");
//    }
//    else if( [button isEqual:nextButton] )
//    {
//        SDL_SendKeyboardText(">");
//        //SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_TAB );
//        //SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_TAB );
//    }
//    else if( [button isEqual:tabButton] )
//    {
//        SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_TAB );
//        SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_TAB );
//    }
    
    
    
    
    //[longPressGesture setEnabled:YES];
}





-(BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    if ([touch.view isKindOfClass:[self.view class]] /*|| [touch.view isKindOfClass:[noButton class]]*/ )
    {
        return YES;
    }
    
    return NO;
}



-(void)hangleLongPress:(UILongPressGestureRecognizer*)gesture
{
    if( isModifyingUI )
        return;
    
    if( gesture.state == UIGestureRecognizerStateEnded )
    {
        //NSLog( @"Long Press Ended" );
    }
    else if( gesture.state == UIGestureRecognizerStateBegan )
    {
        NSLog( @"Long Pressed" );
        //NSLog( @"Long Press Began" );
        
        CGPoint locationInView = [gesture locationInView: self.view ];
        
        /* send mouse moved event */
        SDL_SendMouseMotion(SDL_GetFocusWindow(), SDL_TOUCH_MOUSEID, 0, locationInView.x, locationInView.y);
        
        /* send mouse down event */
        SDL_SendMouseButton(SDL_GetFocusWindow(), SDL_TOUCH_MOUSEID, SDL_PRESSED, SDL_BUTTON_RIGHT);
        
        SDL_SendMouseButton(SDL_GetFocusWindow(), SDL_TOUCH_MOUSEID, SDL_RELEASED, SDL_BUTTON_RIGHT);
    }
}

-(void)handleDoubleLongPress:(UILongPressGestureRecognizer*)gesture
{
    if( isModifyingUI )
        return;
    
    if( gesture.state == UIGestureRecognizerStateBegan )
    {
        NSLog( @"Double Long Pressed" );
        SDL_SendKeyboardKey( SDL_PRESSED, SDL_SCANCODE_ESCAPE );
        SDL_SendKeyboardKey( SDL_RELEASED, SDL_SCANCODE_ESCAPE );
    }
}



- (void)singleTapped:(UITapGestureRecognizer *)sender
{
    if( isModifyingUI )
        return;
    
    NSLog( @"Single Tapped" );
    
    if (sender.state == UIGestureRecognizerStateEnded)
    {
        CGPoint locationInView = [sender locationInView: self.view ];
        /* send mouse moved event */
        SDL_SendMouseMotion(SDL_GetFocusWindow(), SDL_TOUCH_MOUSEID, 0, locationInView.x, locationInView.y);
        
        /* send mouse down event */
        SDL_SendMouseButton(SDL_GetFocusWindow(), SDL_TOUCH_MOUSEID, SDL_PRESSED, SDL_BUTTON_LEFT);
        
        SDL_SendMouseButton(SDL_GetFocusWindow(), SDL_TOUCH_MOUSEID, SDL_RELEASED, SDL_BUTTON_LEFT);
    }
    
    
}


- (void)doubleTapped:(UITapGestureRecognizer *)sender
{
    if( isModifyingUI )
        return;
    
    NSLog( @"Double Tapped" );
    
    SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_RETURN);
    SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_RETURN);
}


//- (void)tripleTapped:(UILongPressGestureRecognizer*)gesture
-(void)didTapOptionsButton
{
    //if( gesture.state == UIGestureRecognizerStateBegan )
    {
        
        
        NSLog( @"Triple Tapped" );
        
        if( isModifyingUI )
        {
            isModifyingUI = NO;
            
            [uiBlickTimer invalidate];
            [self showAllUI];
            
            NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
            [userDefaults setFloat:dPadScale forKey:@"DPadScale"];
            [userDefaults setFloat:dPad.center.x forKey:@"DPadPosX"];
            [userDefaults setFloat:dPad.center.y forKey:@"DPadPosY"];
            [userDefaults synchronize];
            
        }
        else
        {
//            alertView = [[SCLAlertView alloc] init];
//            //Using Selector
//            SCLButton* button = [alertView addButton:@"Show tutorial" actionBlock:^(void) {
//                NSLog(@"Show tutorial");
//                //[self showLeaderboard];
//            }];
//            button.persistAfterExecution = YES;
//            
//            //Using Block
//            button = [alertView addButton:@"Show keybindings" actionBlock:^(void) {
//                NSLog(@"Show keybindings");
//                [self showKeybindings];
//                
//            }];
//            button.persistAfterExecution = YES;
//            
//            //Using Block
//            button = [alertView addButton:@"Adjust user interface" actionBlock:^(void) {
//                NSLog(@"Adjust user interface");
//                isModifyingUI = YES;
//                [self adjustUI];
//                
//                MBProgressHUD* hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
//                hud.mode = MBProgressHUDModeText;
//                hud.labelText = @"Drag or pinch to adjust UI. Tap OPTIONS to confirm.";
//    
//                [hud hide:YES afterDelay:3];
//                
//            }];
//            button.persistAfterExecution = NO;
//            
//            
//            if( iOSVersionGreaterThanOrEqualTo(@"9") )
//            {
//                if( isRecording )
//                {
//                    button = [alertView addButton:@"Stop recording" actionBlock:^(void) {
//                        NSLog(@"Stop recording");
//                        isRecording = NO;
//                        [self stopRecording];
//                    }];
//                }
//                else
//                {
//                    button = [alertView addButton:@"Start recording" actionBlock:^(void) {
//                        NSLog(@"Start recording");
//                        isRecording = YES;
//                        [self startRecording];
//                    }];
//                }
//                button.persistAfterExecution = NO;
//            }
//            
//            
//            alertView.shouldDismissOnTapOutside = YES;
//            [alertView showCustom:self image:[UIImage imageNamed:@"stone_soup_icon-512x512"] color:[UIColor blackColor] title:@"Options" subTitle:nil closeButtonTitle:nil duration:0.0f];
            
            
        }

    }
    

}



-(void)showMenuDescription
{
    
}

-(void)adjustUI
{
    dPad.isModifying = YES;
    dPad.panGestureRecognizer.enabled = YES;
    
    uiBlickTimer = [NSTimer scheduledTimerWithTimeInterval:0.333 target:self
                                                                selector:@selector(blinkUI:) userInfo:nil repeats:YES];
}

- (void) blinkUI:(NSTimer *)timer
{
    static BOOL isHidden = NO;
    
    isHidden = isHidden ? NO : YES;

    if( isHidden )
    {
        [dPad setAlpha:0.05f];
        optionsButton.backgroundImage = [UIImage imageNamed:@"options_gold_off"];
    }
    else
    {
        [dPad setAlpha:0.3f];
        optionsButton.backgroundImage = [UIImage imageNamed:@"options_gold_on"];
    }
    
}

-(void) showAllUI
{
    dPad.isModifying = NO;
    dPad.panGestureRecognizer.enabled = NO;
    
    [dPad setAlpha:0.3f];
    optionsButton.backgroundImage = [UIImage imageNamed:@"options_silver_on"];

}




- (void) handleSwipe:(UISwipeGestureRecognizer*)gesture
{
    if( isModifyingUI )
        return;
    
    NSLog( @"Swipe" );
    
    if( UISwipeGestureRecognizerDirectionUp == gesture.direction )
    {
        NSLog( @"UISwipeGestureRecognizerDirectionUp" );
        if( !SDL_IsScreenKeyboardShown( SDL_GetFocusWindow() ) )
        {
            self.lockKeyboard = NO;
            SDL_StartTextInput();
        }
    }
    else if( UISwipeGestureRecognizerDirectionDown == gesture.direction )
    {
        NSLog( @"UISwipeGestureRecognizerDirectionDown" );
        if( SDL_IsScreenKeyboardShown( SDL_GetFocusWindow() ) )
        {
            SDL_StopTextInput();
            self.lockKeyboard = YES;
        }
    }
}



- (void) handleDoubleSwipe:(UISwipeGestureRecognizer*)gesture
{
    if( isModifyingUI )
        return;
    
    NSLog( @"Double Swipe" );
    
    if( UISwipeGestureRecognizerDirectionUp == gesture.direction )
    {
        NSLog( @"UISwipeGestureRecognizerDirectionUp" );
        if( !SDL_IsScreenKeyboardShown( SDL_GetFocusWindow() ) )
        {
            self.lockKeyboard = YES;
            SDL_StartTextInput();
        }
    }
}


-(void)handlePinchGesture:(UIPinchGestureRecognizer*)pinchGestureRecognier
{
    NSLog( @"Pinch" );
    NSLog( @"%f", pinchGestureRecognier.scale );
    const float threshold = 0.1f;

    
    if( pinchGestureRecognier.state == UIGestureRecognizerStateEnded )
    {
        if( pinchGestureRecognier.scale > ( 1.0f + threshold ) )
        {
            if( isModifyingUI )
            {
                dPadScale += 0.25f;
                //NSLog( @"%f", dPadScale );
                if( dPadScale > 2.0f )
                    dPadScale = 2.0f;
                
                [dPad setTransform:CGAffineTransformMakeScale(dPadScale, dPadScale)];
            }
            else
            {
                SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_KP_PLUS);
                SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_KP_PLUS);
                pinchGestureRecognier.scale = 1.0f;
            }
            
        }
        else if( pinchGestureRecognier.scale < ( 1.0f - threshold ) )
        {
            if( isModifyingUI )
            {
                dPadScale -= 0.25f;
                if( dPadScale < 0.5f )
                    dPadScale = 0.5f;
                //NSLog( @"%f", dPadScale );
                [dPad setTransform:CGAffineTransformMakeScale(dPadScale, dPadScale)];
            }
            else
            {
                SDL_SendKeyboardKey(SDL_PRESSED, SDL_SCANCODE_KP_MINUS);
                SDL_SendKeyboardKey(SDL_RELEASED, SDL_SCANCODE_KP_MINUS);
                pinchGestureRecognier.scale = 1.0f;
            }
            
        }
        
        
    }
}

#endif

@end

/* iPhone keyboard addition functions */
#if SDL_IPHONE_KEYBOARD

static SDL_uikitviewcontroller *
GetWindowViewController(SDL_Window * window)
{
    if (!window || !window->driverdata) {
        SDL_SetError("Invalid window");
        return nil;
    }

    SDL_WindowData *data = (__bridge SDL_WindowData *)window->driverdata;

    return data.viewcontroller;
}

SDL_bool
UIKit_HasScreenKeyboardSupport(_THIS)
{
    return SDL_TRUE;
}

void
UIKit_ShowScreenKeyboard(_THIS, SDL_Window *window)
{
    @autoreleasepool {
        SDL_uikitviewcontroller *vc = GetWindowViewController(window);
        [vc showKeyboard];
    }
}

void
UIKit_HideScreenKeyboard(_THIS, SDL_Window *window)
{
    @autoreleasepool {
        SDL_uikitviewcontroller *vc = GetWindowViewController(window);
        [vc hideKeyboard];
    }
}

SDL_bool
UIKit_IsScreenKeyboardShown(_THIS, SDL_Window *window)
{
    @autoreleasepool {
        SDL_uikitviewcontroller *vc = GetWindowViewController(window);
        if (vc != nil) {
            return vc.isKeyboardVisible;
        }
        return SDL_FALSE;
    }
}

void
UIKit_SetTextInputRect(_THIS, SDL_Rect *rect)
{
    if (!rect) {
        SDL_InvalidParamError("rect");
        return;
    }

    @autoreleasepool {
        SDL_uikitviewcontroller *vc = GetWindowViewController(SDL_GetFocusWindow());
        if (vc != nil) {
            vc.textInputRect = *rect;

            if (vc.keyboardVisible) {
                [vc updateKeyboard];
            }
        }
    }
}


#endif /* SDL_IPHONE_KEYBOARD */

#endif /* SDL_VIDEO_DRIVER_UIKIT */

/* vi: set ts=4 sw=4 expandtab: */
