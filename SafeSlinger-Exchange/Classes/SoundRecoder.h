/*
 * The MIT License (MIT)
 * 
 * Copyright (c) 2010-2014 Carnegie Mellon University
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
 */

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@class KeySlingerAppDelegate;

@interface SoundRecoder : UIViewController <AVAudioRecorderDelegate, AVAudioPlayerDelegate, UINavigationControllerDelegate>
{
    UILabel *TimeLabel;
    UIButton *PlayBtn;
    UIButton *RecordBtn;
    UIButton *StopBtn;
    UIButton *DiscardBtn;
    UIButton *SaveBtn;
    
    AVAudioRecorder *audio_recorder;
    AVAudioPlayer *audio_player;
    NSTimer *polling_timer;
    KeySlingerAppDelegate* delegate;
}

@property (nonatomic, assign) KeySlingerAppDelegate *delegate;
@property (nonatomic, retain) IBOutlet UILabel *TimeLabel;
@property (nonatomic, retain) IBOutlet UIButton *PlayBtn;
@property (nonatomic, retain) IBOutlet UIButton *RecordBtn;
@property (nonatomic, retain) IBOutlet UIButton *StopBtn;
@property (nonatomic, retain) IBOutlet UIButton *DiscardBtn;
@property (nonatomic, retain) IBOutlet UIButton *SaveBtn;
@property (weak) NSTimer *polling_timer;

// audio recorder/player button actions
- (IBAction) play;
- (IBAction) record;
- (IBAction) stop;
- (IBAction) discard;
- (IBAction) save;

@end
