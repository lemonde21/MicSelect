// MicSelect — force the microphone input used by apps (built-in vs headset)
// Target: iOS 15, rootless (Dopamine), Theos + Logos

#import <AVFoundation/AVFoundation.h>
#import <notify.h>
#import <os/log.h>

#import "Shared.h"

typedef NS_ENUM(uint64_t, MSMode) {
    MSModeDefault = 0,   // don't interfere, let iOS / the app decide
    MSModeBuiltIn = 1,   // always use the iPad's internal mic
    MSModeHeadset = 2,   // always use the wired headset mic
};

static os_log_t sLog;
static int sStateToken = -1;          // used to read the shared mode (notify state)
static int sChangeToken = -1;         // used to get told when the mode changes
static __thread BOOL sApplying = NO;  // true while *we* call setPreferredInput

#pragma mark - Helpers

static MSMode MSCurrentMode(void) {
    if (sStateToken < 0) return MSModeDefault;
    uint64_t state = 0;
    if (notify_get_state(sStateToken, &state) != NOTIFY_STATUS_OK) return MSModeDefault;
    return state <= MSModeHeadset ? (MSMode)state : MSModeDefault;
}

// Inputs are only listed / selectable when the category can record.
static BOOL MSSessionCanRecord(AVAudioSession *session) {
    NSString *cat = session.category;
    return [cat isEqualToString:AVAudioSessionCategoryPlayAndRecord] ||
           [cat isEqualToString:AVAudioSessionCategoryRecord] ||
           [cat isEqualToString:AVAudioSessionCategoryMultiRoute];
}

static AVAudioSessionPortDescription *MSDesiredInput(AVAudioSession *session) {
    MSMode mode = MSCurrentMode();
    if (mode == MSModeDefault) return nil;

    NSString *wanted = (mode == MSModeBuiltIn) ? AVAudioSessionPortBuiltInMic
                                               : AVAudioSessionPortHeadsetMic;
    for (AVAudioSessionPortDescription *port in session.availableInputs) {
        if ([port.portType isEqualToString:wanted]) return port;
    }
    return nil;
}

static void MSApply(AVAudioSession *session) {
    if (sApplying || !MSSessionCanRecord(session)) return;
    if (MSCurrentMode() == MSModeDefault) return;

    AVAudioSessionPortDescription *port = MSDesiredInput(session);
    if (!port) {
        os_log(sLog, "wanted port not available; inputs = %{public}@", session.availableInputs);
        return;
    }

    AVAudioSessionPortDescription *current = session.currentRoute.inputs.firstObject;
    if ([current.UID isEqualToString:port.UID]) return; // already there

    sApplying = YES;
    NSError *error = nil;
    if ([session setPreferredInput:port error:&error]) {
        os_log(sLog, "switched input to %{public}@ (%{public}@)", port.portName, port.portType);
    } else {
        os_log_error(sLog, "setPreferredInput failed: %{public}@", error);
    }
    sApplying = NO;
}

static void MSModeChanged(void) {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    if (!MSSessionCanRecord(session)) return;

    if (MSCurrentMode() == MSModeDefault) {
        // Hand control back to iOS.
        sApplying = YES;
        [session setPreferredInput:nil error:nil];
        sApplying = NO;
        os_log(sLog, "mode -> default, cleared preferred input");
    } else {
        MSApply(session);
    }
}

#pragma mark - Hooks

%hook AVAudioSession

// If the app (or WebRTC inside Discord) picks an input itself, override it.
- (BOOL)setPreferredInput:(AVAudioSessionPortDescription *)inPort error:(NSError **)outError {
    if (!sApplying) {
        AVAudioSessionPortDescription *forced = MSDesiredInput(self);
        if (forced) inPort = forced;
    }
    return %orig(inPort, outError);
}

- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)outError {
    BOOL ok = %orig;
    if (ok && active) MSApply(self);
    return ok;
}

- (BOOL)setActive:(BOOL)active error:(NSError **)outError {
    BOOL ok = %orig;
    if (ok && active) MSApply(self);
    return ok;
}

- (BOOL)setCategory:(AVAudioSessionCategory)category mode:(AVAudioSessionMode)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    BOOL ok = %orig;
    if (ok) MSApply(self);
    return ok;
}

- (BOOL)setCategory:(AVAudioSessionCategory)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    BOOL ok = %orig;
    if (ok) MSApply(self);
    return ok;
}

- (BOOL)setCategory:(AVAudioSessionCategory)category error:(NSError **)outError {
    BOOL ok = %orig;
    if (ok) MSApply(self);
    return ok;
}

- (BOOL)setMode:(AVAudioSessionMode)mode error:(NSError **)outError {
    BOOL ok = %orig;
    if (ok) MSApply(self);
    return ok;
}

%end

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        sLog = os_log_create("com.lemonde21.micselect", "tweak");
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;

        // SpringBoard owns persistence:
        //  - at boot/respring it loads the saved mode into notifyd
        //  - whenever the mode changes (Settings or the micsel tool) it saves it
        // The tokens are intentionally never cancelled: notifyd drops a name's
        // state once nobody is registered for it.
        if ([bundleID isEqualToString:@"com.apple.springboard"]) {
            uint64_t mode = 0;
            CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR(kMSModeKey), CFSTR(kMSDomain));
            if (value) {
                if (CFGetTypeID(value) == CFNumberGetTypeID()) {
                    CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, &mode);
                }
                CFRelease(value);
            }

            static int sbStateToken, sbChangeToken;
            if (notify_register_check(kMSNotifyName, &sbStateToken) == NOTIFY_STATUS_OK) {
                notify_set_state(sbStateToken, mode);
                os_log(sLog, "SpringBoard restored mode %llu", mode);

                notify_register_dispatch(kMSNotifyName, &sbChangeToken, dispatch_get_main_queue(), ^(int token) {
                    uint64_t newMode = 0;
                    notify_get_state(sbStateToken, &newMode);
                    CFPreferencesSetAppValue(CFSTR(kMSModeKey), (__bridge CFNumberRef)@(newMode), CFSTR(kMSDomain));
                    CFPreferencesAppSynchronize(CFSTR(kMSDomain));
                });
            }
            return;
        }

        // Apps: read the mode + listen for changes.
        if (notify_register_check(kMSNotifyName, &sStateToken) != NOTIFY_STATUS_OK) {
            sStateToken = -1;
            return;
        }
        notify_register_dispatch(kMSNotifyName, &sChangeToken, dispatch_get_main_queue(), ^(int token) {
            MSModeChanged();
        });

        // Re-apply when the route changes (headset plugged/unplugged, etc.).
        [[NSNotificationCenter defaultCenter] addObserverForName:AVAudioSessionRouteChangeNotification
                                                          object:nil
                                                           queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(NSNotification *note) {
            NSUInteger reason = [note.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
            switch (reason) {
                case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
                case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
                case AVAudioSessionRouteChangeReasonCategoryChange:
                case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
                    MSApply(AVAudioSession.sharedInstance);
                    break;
                default:
                    break;
            }
        }];

        %init;
    }
}
