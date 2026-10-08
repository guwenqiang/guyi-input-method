#import <Foundation/Foundation.h>
#import "CInputMethodBridge.h"

@protocol FixtureProtocol
- (NSString *)ping;
@end

@interface FixtureServer : NSObject <FixtureProtocol>
@end

@implementation FixtureServer
- (NSString *)ping { return @"fixture"; }
@end

int main(void) {
    @autoreleasepool {
        FixtureServer *server = [FixtureServer new];
        NSProtocolChecker *checker = [NSProtocolChecker protocolCheckerWithTarget:server protocol:@protocol(FixtureProtocol)];
        NSConnection *connection = [[NSConnection alloc] initWithReceivePort:[NSMachPort port] sendPort:nil];
        connection.rootObject = checker;
        NSString *original = [NSString stringWithFormat:@"app.guyi.bridge-test.%d_Connection", getpid()];
        NSString *alias = [NSString stringWithFormat:@"app.guyi.bridge-test.%d.Connection", getpid()];
        NSCAssert([connection registerName:original], @"Original registration failed");
        NSCAssert(guyi_register_imk_connection_alias((__bridge void *)server, alias.UTF8String), @"Alias registration failed");
        NSCAssert(connection.rootObject == checker && checker.protocol == @protocol(FixtureProtocol), @"Protocol checker was replaced");
        NSPortNameServer *names = [NSPortNameServer systemDefaultPortNameServer];
        NSMachPort *originalPort = (NSMachPort *)[names portForName:original];
        NSMachPort *aliasPort = (NSMachPort *)[names portForName:alias];
        NSCAssert(originalPort && aliasPort && originalPort.machPort == aliasPort.machPort, @"Alias does not share the original endpoint");
        NSCAssert(!guyi_register_imk_connection_alias(NULL, alias.UTF8String), @"Null server accepted");
        NSCAssert(!guyi_register_imk_connection_alias((__bridge void *)server, ""), @"Empty name accepted");
        FixtureServer *other = [FixtureServer new];
        NSCAssert(!guyi_register_imk_connection_alias((__bridge void *)other, alias.UTF8String), @"Unrelated server accepted");
        connection.rootObject = server;
        NSCAssert(!guyi_register_imk_connection_alias((__bridge void *)server, alias.UTF8String), @"Unchecked root object accepted");
        [connection invalidate];
        puts("PASS · Same Mach endpoint and protocol checker preserved; unrelated, unchecked and invalid inputs rejected");
    }
}
