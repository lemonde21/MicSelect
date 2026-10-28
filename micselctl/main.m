// micsel — command-line switch for MicSelect
// usage: micsel [default|builtin|headset]

#import <Foundation/Foundation.h>
#import <notify.h>
#include <stdio.h>
#include <string.h>

#import "../Shared.h"

static const char *kModes[] = { "default", "builtin", "headset" };

static void usage(void) {
    fprintf(stderr, "usage: micsel [default|builtin|headset]\n");
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        int token;
        if (notify_register_check(kMSNotifyName, &token) != NOTIFY_STATUS_OK) {
            fprintf(stderr, "error: could not register with notifyd\n");
            return 1;
        }

        if (argc < 2) {
            uint64_t state = 0;
            notify_get_state(token, &state);
            printf("current mode: %s\n", state < 3 ? kModes[state] : "unknown");
            usage();
            return 0;
        }

        int mode = -1;
        for (int i = 0; i < 3; i++) {
            if (strcmp(argv[1], kModes[i]) == 0) mode = i;
        }
        if (mode < 0) { usage(); return 1; }

        // Live update for running apps; SpringBoard also saves it so the
        // Settings pane stays in sync and the choice survives a reboot.
        notify_set_state(token, (uint64_t)mode);
        notify_post(kMSNotifyName);
        printf("microphone mode set to: %s\n", kModes[mode]);
    }
    return 0;
}
