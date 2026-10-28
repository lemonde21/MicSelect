#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <AVFoundation/AVFoundation.h>
#import <notify.h>
#import "../Shared.h"

@interface PSListController (MSPPrivate)
- (void)reloadSpecifierID:(NSString *)specifierID animated:(BOOL)animated;
@end

#pragma mark - Level meter cell

@interface MSPLevelCell : PSTableCell
- (void)setInputName:(NSString *)name;
- (void)setLevel:(float)level;
@end

static __weak MSPLevelCell *gLevelCell;

@implementation MSPLevelCell {
    UILabel *_label;
    UIProgressView *_meter;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _label = [UILabel new];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        _label.textColor = UIColor.secondaryLabelColor;
        _label.numberOfLines = 0;

        _meter = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _meter.translatesAutoresizingMaskIntoConstraints = NO;

        [self.contentView addSubview:_label];
        [self.contentView addSubview:_meter];

        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_label.topAnchor constraintEqualToAnchor:margins.topAnchor],
            [_label.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [_label.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            [_meter.topAnchor constraintEqualToAnchor:_label.bottomAnchor constant:12],
            [_meter.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [_meter.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            [_meter.bottomAnchor constraintLessThanOrEqualToAnchor:margins.bottomAnchor],
        ]];

        [self setInputName:nil];
        gLevelCell = self;
    }
    return self;
}

- (void)setInputName:(NSString *)name {
    _label.text = name ? [NSString stringWithFormat:@"Microphone in use: %@", name]
                       : @"Microphone in use: – (turn on Listen)";
}

- (void)setLevel:(float)level {
    [_meter setProgress:level animated:NO];
}

@end

#pragma mark - Helpers

// Only monitor into something private, so the speaker can't feed back into the mic.
static BOOL MSPOutputIsPrivate(AVAudioSession *session) {
    NSArray *privateOutputs = @[ AVAudioSessionPortHeadphones,
                                 AVAudioSessionPortBluetoothA2DP,
                                 AVAudioSessionPortBluetoothHFP,
                                 AVAudioSessionPortBluetoothLE,
                                 AVAudioSessionPortUSBAudio ];
    for (AVAudioSessionPortDescription *port in session.currentRoute.outputs) {
        if ([privateOutputs containsObject:port.portType]) return YES;
    }
    return NO;
}

#pragma mark - Controller

@interface MSPRootListController : PSListController
@property (nonatomic, strong) AVAudioEngine *engine;
@end

@implementation MSPRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(routeChanged:)
               name:AVAudioSessionRouteChangeNotification object:nil];
    [nc addObserver:self selector:@selector(engineConfigurationChanged:)
               name:AVAudioEngineConfigurationChangeNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopMonitoring];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self stopEngine];
}

#pragma mark Mode segment

// Saves the value as usual, then pushes it to running apps instantly.
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];

    if ([[specifier propertyForKey:@"key"] isEqualToString:@kMSModeKey]) {
        int token;
        if (notify_register_check(kMSNotifyName, &token) == NOTIFY_STATUS_OK) {
            notify_set_state(token, [value unsignedLongLongValue]);
            notify_post(kMSNotifyName);
            notify_cancel(token);
        }
    }
}

#pragma mark Listen switch

- (id)readMonitor:(PSSpecifier *)specifier {
    return @(self.engine.isRunning);
}

- (void)setMonitor:(id)value specifier:(PSSpecifier *)specifier {
    if ([value boolValue]) {
        [self requestPermissionAndStart];
    } else {
        [self stopMonitoring];
    }
}

- (void)refreshSwitch {
    [self reloadSpecifierID:@"monitor" animated:YES];
}

- (void)requestPermissionAndStart {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    switch (session.recordPermission) {
        case AVAudioSessionRecordPermissionGranted:
            [self startMonitoring];
            break;
        case AVAudioSessionRecordPermissionDenied:
            [self showAlert:@"Microphone access is off"
                    message:@"Allow the Settings app to use the microphone in Settings → Privacy → Microphone."];
            [self refreshSwitch];
            break;
        default:
            [session requestRecordPermission:^(BOOL granted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (granted) [self startMonitoring];
                    else [self refreshSwitch];
                });
            }];
            break;
    }
}

- (void)startMonitoring {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSError *error = nil;

    // MicSelect (loaded in Settings too) applies the chosen input on these calls.
    if (![session setCategory:AVAudioSessionCategoryPlayAndRecord
                         mode:AVAudioSessionModeDefault
                      options:AVAudioSessionCategoryOptionAllowBluetoothA2DP
                        error:&error] ||
        ![session setActive:YES error:&error]) {
        [self showAlert:@"Couldn’t start audio" message:error.localizedDescription];
        [self refreshSwitch];
        return;
    }
    [session setPreferredIOBufferDuration:0.005 error:nil]; // low latency

    if (!MSPOutputIsPrivate(session)) {
        [session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
        [self showAlert:@"Plug in earphones first"
                message:@"Listening through the iPad speaker would cause loud feedback."];
        [self refreshSwitch];
        return;
    }

    if (![self startEngine:&error]) {
        [self showAlert:@"Couldn’t start listening" message:error.localizedDescription];
        [self stopMonitoring];
        return;
    }
    [self refreshSwitch];
    [self updateInputName];
}

- (BOOL)startEngine:(NSError **)error {
    AVAudioEngine *engine = [AVAudioEngine new];
    AVAudioInputNode *input = engine.inputNode;
    AVAudioFormat *format = [input outputFormatForBus:0];

    if (format.sampleRate == 0 || format.channelCount == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"MicSelect" code:1
                                     userInfo:@{ NSLocalizedDescriptionKey: @"No microphone input is available." }];
        }
        return NO;
    }

    // Mic → speaker/earphones
    [engine connect:input to:engine.mainMixerNode format:format];

    // Level meter
    [input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        float *samples = buffer.floatChannelData ? buffer.floatChannelData[0] : NULL;
        AVAudioFrameCount count = buffer.frameLength;
        if (!samples || count == 0) return;

        float sum = 0;
        for (AVAudioFrameCount i = 0; i < count; i++) sum += samples[i] * samples[i];
        float db = 20.0f * log10f(fmaxf(sqrtf(sum / count), 1e-6f));
        float level = fminf(fmaxf((db + 60.0f) / 60.0f, 0.0f), 1.0f); // -60 dB…0 dB → 0…1

        dispatch_async(dispatch_get_main_queue(), ^{
            [gLevelCell setLevel:level];
        });
    }];

    [engine prepare];
    if (![engine startAndReturnError:error]) {
        [input removeTapOnBus:0];
        return NO;
    }
    self.engine = engine;
    return YES;
}

- (void)stopEngine {
    if (!self.engine) return;
    [self.engine.inputNode removeTapOnBus:0];
    [self.engine stop];
    self.engine = nil;
    [gLevelCell setLevel:0];
}

- (void)stopMonitoring {
    BOOL wasRunning = (self.engine != nil);
    [self stopEngine];
    if (wasRunning) {
        [AVAudioSession.sharedInstance setActive:NO
                                     withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                           error:nil];
    }
    [gLevelCell setInputName:nil];
    [self refreshSwitch];
}

- (void)updateInputName {
    if (!self.engine) {
        [gLevelCell setInputName:nil];
        return;
    }
    AVAudioSessionPortDescription *input = AVAudioSession.sharedInstance.currentRoute.inputs.firstObject;
    [gLevelCell setInputName:input.portName ?: @"none"];
}

#pragma mark Notifications

- (void)routeChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.engine && !MSPOutputIsPrivate(AVAudioSession.sharedInstance)) {
            [self stopMonitoring]; // earphones unplugged: stop before it feeds back
            return;
        }
        [self updateInputName];
    });
}

// Switching mics changes the input format, which stops the engine: rebuild it.
- (void)engineConfigurationChanged:(NSNotification *)note {
    id changedEngine = note.object;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.engine || changedEngine != self.engine) return;
        [self stopEngine];
        NSError *error = nil;
        if (![self startEngine:&error]) {
            [self stopMonitoring];
            return;
        }
        [self updateInputName];
    });
}

#pragma mark Buttons

// "Check connected microphones": lists the inputs iOS exposes right now.
- (void)showInputs {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSString *oldCategory = session.category;
    if (!self.engine) [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];

    NSMutableString *text = [NSMutableString string];
    for (AVAudioSessionPortDescription *port in session.availableInputs) {
        [text appendFormat:@"• %@\n", port.portName];
    }
    if (text.length == 0) [text appendString:@"No inputs reported."];

    if (!self.engine) [session setCategory:oldCategory error:nil];
    [self showAlert:@"Available microphones" message:text];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
