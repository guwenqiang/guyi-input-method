#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "CInputMethodBridge.h"

bool guyi_register_imk_connection_alias(void *serverPointer, const char *name) {
    if (!serverPointer || !name || ![NSThread isMainThread]) return false;
    id server = (__bridge id)serverPointer;
    NSString *alias = [NSString stringWithUTF8String:name];
    if (!alias.length) return false;
    for (NSConnection *connection in [NSConnection allConnections]) {
        id root = connection.rootObject;
        BOOL checked = NO;
        for (Class rootClass = object_getClass(root); rootClass; rootClass = class_getSuperclass(rootClass)) {
            if (rootClass == [NSProtocolChecker class]) { checked = YES; break; }
        }
        if (!checked || [(NSProtocolChecker *)root target] != server || !connection.valid) continue;
        if (![connection.receivePort isKindOfClass:[NSMachPort class]]) continue;
        return [connection registerName:alias withNameServer:[NSPortNameServer systemDefaultPortNameServer]];
    }
    return false;
}
