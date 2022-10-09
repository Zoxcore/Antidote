// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#import "OCTSubmanagerChatsImpl.h"
#import "OCTTox.h"
#import "OCTRealmManager.h"
#import "OCTMessageAbstract.h"
#import "OCTMessageText.h"
#import "OCTChat.h"
#import "OCTLogging.h"
#import "OCTSendMessageOperation.h"
#import "OCTTox+Private.h"
#import "OCTToxOptions+Private.h"
#import "Firebase.h"

@interface OCTSubmanagerChatsImpl ()

@property (strong, nonatomic, readonly) NSOperationQueue *sendMessageQueue;

@end

@implementation OCTSubmanagerChatsImpl
@synthesize dataSource = _dataSource;

- (instancetype)init
{
    self = [super init];

    if (! self) {
        return nil;
    }

    _sendMessageQueue = [NSOperationQueue new];
    _sendMessageQueue.maxConcurrentOperationCount = 1;

    return self;
}

- (void)dealloc
{
    [self.dataSource.managerGetNotificationCenter removeObserver:self];
}

- (void)configure
{
    [self.dataSource.managerGetNotificationCenter addObserver:self
                                                     selector:@selector(friendConnectionStatusChangeNotification:)
                                                         name:kOCTFriendConnectionStatusChangeNotification
                                                       object:nil];
}

#pragma mark -  Public

- (OCTChat *)getOrCreateChatWithFriend:(OCTFriend *)friend
{
    return [[self.dataSource managerGetRealmManager] getOrCreateChatWithFriend:friend];
}

- (void)removeMessages:(NSArray<OCTMessageAbstract *> *)messages
{
    [[self.dataSource managerGetRealmManager] removeMessages:messages];
    [self.dataSource.managerGetNotificationCenter postNotificationName:kOCTScheduleFileTransferCleanupNotification object:nil];
}

- (void)removeAllMessagesInChat:(OCTChat *)chat removeChat:(BOOL)removeChat
{
    [[self.dataSource managerGetRealmManager] removeAllMessagesInChat:chat removeChat:removeChat];
    [self.dataSource.managerGetNotificationCenter postNotificationName:kOCTScheduleFileTransferCleanupNotification object:nil];
}

- (void)sendOwnPush
{
    NSLog(@"PUSH:sendOwnPush");
    NSString *token = [FIRMessaging messaging].FCMToken;
    if (token.length > 0)
    {
        NSString *my_pushToken = [NSString stringWithFormat:@"https://tox.zoff.xyz/toxfcm/fcm.php?id=%@&type=1", token];
        // NSLog(@"token push url=%@", my_pushToken);
        triggerPush(my_pushToken, nil, nil, nil);
    }
    else
    {
        NSLog(@"PUSH:sendOwnPush:no token");
    }
}

- (void)sendMessagePushToChat:(OCTChat *)chat
{
    NSParameterAssert(chat);
    NSLog(@"PUSH:sendMessagePushToChat");
    __weak OCTSubmanagerChatsImpl *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong OCTSubmanagerChatsImpl *strongSelf = weakSelf;
        OCTRealmManager *realmManager = [strongSelf.dataSource managerGetRealmManager];

        OCTFriend *friend = [chat.friends firstObject];
        __block NSString *friend_pushToken = friend.pushToken;

        if (friend_pushToken == nil)
        {
            NSLog(@"sendMessagePushToChat:Friend has No Pushtoken");
        }
        else
        {
            // HINT: only select outgoing messages (senderUniqueIdentifier == NULL)
            NSPredicate *predicate = [NSPredicate predicateWithFormat:@"chatUniqueIdentifier == %@ AND messageText.isDelivered == 0 AND messageText.sentPush == 0 AND senderUniqueIdentifier == nil", chat.uniqueIdentifier];

            RLMResults *results = [realmManager objectsWithClass:[OCTMessageAbstract class] predicate:predicate];
            OCTMessageAbstract *message_found = [results firstObject];
            if (message_found) {

                [realmManager updateObject:message_found withBlock:^(OCTMessageAbstract *theMessage) {
                    theMessage.messageText.sentPush = YES;
                }];
                triggerPush(friend_pushToken, message_found.messageText.msgv3HashHex, strongSelf, chat);
            }
        }
    });
}

triggerPush(NSString *used_pushToken,
            NSString *msgv3HashHex,
            OCTSubmanagerChatsImpl *strongSelf,
            OCTChat *chat)
{
    // HINT: call push token (URL) here
    //       best in a background thread
    //
    NSLog(@"PUSH:triggerPush");
    if ((used_pushToken != nil) && (used_pushToken.length > 5)) {

        // check push url starts with allowed values
        if (
            ([used_pushToken hasPrefix:@"https://tox.zoff.xyz/toxfcm/fcm.php?id="])
            ||
            ([used_pushToken hasPrefix:@"https://gotify1.unifiedpush.org/UP?token="])
            ||
            ([used_pushToken hasPrefix:@"https://ntfy.sh/"])
        ) {

            NSString *strong_pushToken = used_pushToken;

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                // NSString *strong_pushToken = weak_pushToken;
                int PUSH_URL_TRIGGER_AGAIN_MAX_COUNT = 8;
                int PUSH_URL_TRIGGER_AGAIN_SECONDS = 21;

                for (int i=0; i<(PUSH_URL_TRIGGER_AGAIN_MAX_COUNT + 1); i++)
                {
                    if (chat == nil) {
                        __block UIApplicationState as = UIApplicationStateBackground;
                        dispatch_sync(dispatch_get_main_queue(), ^{
                            as =[[UIApplication sharedApplication] applicationState];
                        });

                        if (as == UIApplicationStateActive) {
                            NSLog(@"PUSH:fg->break:1");
                            break;
                        }
                    }
                    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:strong_pushToken]];
                    NSString *userUpdate = [NSString stringWithFormat:@"&text=1", nil];
                    [urlRequest setHTTPMethod:@"POST"];

                    NSData *data1 = [userUpdate dataUsingEncoding:NSUTF8StringEncoding];

                    [urlRequest setHTTPBody:data1];
                    [urlRequest setCachePolicy:NSURLRequestReloadIgnoringCacheData];
                    [urlRequest setTimeoutInterval:10]; // HINT: 10 seconds
                    NSString *userAgent = @"Mozilla/5.0 (Windows NT 6.1; rv:60.0) Gecko/20100101 Firefox/60.0";
                    [urlRequest setValue:userAgent forHTTPHeaderField:@"User-Agent"];
                    [urlRequest setValue:@"no-cache, no-store, must-revalidate" forHTTPHeaderField:@"Cache-Control"];
                    [urlRequest setValue:@"no-cache" forHTTPHeaderField:@"Pragma"];
                    [urlRequest setValue:@"0" forHTTPHeaderField:@"Expires"];

                    // NSLog(@"PUSH:for msgv3HashHex=%@", msgv3HashHex);
                    // NSLog(@"PUSH:for friend.pushToken=%@", strong_pushToken);

                    NSURLSession *session = [NSURLSession sharedSession];
                    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:urlRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                        if ((httpResponse.statusCode < 300) && (httpResponse.statusCode > 199)) {
                            NSLog(@"calling PUSH URL:CALL:SUCCESS");
                        }
                        else {
                            NSLog(@"calling PUSH URL:-ERROR:01-");
                        }
                    }];
                    NSLog(@"calling PUSH URL:CALL:start");
                    [dataTask resume];
                    if (i < PUSH_URL_TRIGGER_AGAIN_MAX_COUNT)
                    {
                        NSLog(@"calling PUSH URL:WAIT:start");
                        [NSThread sleepForTimeInterval:PUSH_URL_TRIGGER_AGAIN_SECONDS];
                        NSLog(@"calling PUSH URL:WAIT:done");
                    }

                    if (chat == nil) {
                        __block UIApplicationState as = UIApplicationStateBackground;
                        dispatch_sync(dispatch_get_main_queue(), ^{
                            as =[[UIApplication sharedApplication] applicationState];
                        });

                        if (as == UIApplicationStateActive) {
                            NSLog(@"PUSH:fg->break:2");
                            break;
                        }
                    }

                    if (msgv3HashHex != nil)
                    {
                        OCTRealmManager *realmManager = [strongSelf.dataSource managerGetRealmManager];
                        __block BOOL msgIsDelivered = NO;

                        NSLog(@"calling PUSH URL:DB check:start");
                        dispatch_sync(dispatch_get_main_queue(), ^{
                            // HINT: only select outgoing messages (senderUniqueIdentifier == NULL)
                            NSPredicate *predicate = [NSPredicate predicateWithFormat:@"chatUniqueIdentifier == %@ AND messageText.msgv3HashHex == %@ AND senderUniqueIdentifier == nil",
                                                      chat.uniqueIdentifier, msgv3HashHex];
                            RLMResults *results = [realmManager objectsWithClass:[OCTMessageAbstract class] predicate:predicate];
                            OCTMessageAbstract *message_found = [results firstObject];
                            if (message_found) {
                                if (message_found.messageText) {
                                    msgIsDelivered = message_found.messageText.isDelivered;
                                }
                            }
                            NSLog(@"calling PUSH URL:DB check:end_real");
                        });
                        NSLog(@"calling PUSH URL:DB check:end");

                        if (msgIsDelivered == YES) {
                                // OCTLogInfo(@"PUSH:for msgv3HashHex isDelivered=YES");
                                NSLog(@"PUSH:for msgv3HashHex isDelivered=YES");
                                break;
                        }
                    }
                }
            });
        }
        else {
            NSLog(@"unsafe PUSH URL not allowed:-ERROR:02-");
        }
    }
}

- (void)sendMessageToChat:(OCTChat *)chat
                     text:(NSString *)text
                     type:(OCTToxMessageType)type
             successBlock:(void (^)(OCTMessageAbstract *message))userSuccessBlock
             failureBlock:(void (^)(NSError *error))userFailureBlock
{
    NSParameterAssert(chat);
    NSParameterAssert(text);

    OCTFriend *friend = [chat.friends firstObject];

    uint8_t *message_v3_hash_bin = calloc(1, TOX_MSGV3_MSGID_LENGTH);
    uint8_t *message_v3_hash_hexstr = calloc(1, (TOX_MSGV3_MSGID_LENGTH * 2) + 1);

    NSString *msgv3HashHex = nil;
    UInt32 msgv3tssec = 0;

    if ((message_v3_hash_bin) && (message_v3_hash_hexstr))
    {
        tox_messagev3_get_new_message_id(message_v3_hash_bin);
        bin_to_hex((const char *)message_v3_hash_bin, (size_t)TOX_MSGV3_MSGID_LENGTH, message_v3_hash_hexstr);

        msgv3HashHex = [[NSString alloc] initWithBytes:message_v3_hash_hexstr length:(TOX_MSGV3_MSGID_LENGTH * 2) encoding:NSUTF8StringEncoding];

        // HINT: set sent timestamp to now() as unixtimestamp value
        msgv3tssec = [[NSNumber numberWithDouble: [[NSDate date] timeIntervalSince1970]] integerValue];

        free(message_v3_hash_bin);
        free(message_v3_hash_hexstr);
     }

    __weak OCTSubmanagerChatsImpl *weakSelf = self;
    OCTSendMessageOperationSuccessBlock successBlock = ^(OCTToxMessageId messageId) {
        __strong OCTSubmanagerChatsImpl *strongSelf = weakSelf;

        BOOL sent_push = NO;

        if (messageId == -1) {
            if ((friend.pushToken != nil) && (friend.pushToken.length > 5)) {

                // check push url starts with allowed values
                if (
                    ([friend.pushToken hasPrefix:@"https://tox.zoff.xyz/toxfcm/fcm.php?id="])
                    ||
                    ([friend.pushToken hasPrefix:@"https://gotify1.unifiedpush.org/UP?token="])
                    ||
                    ([friend.pushToken hasPrefix:@"https://ntfy.sh/"])
                ) {
                    sent_push = YES;
                }
            }
        }

        OCTRealmManager *realmManager = [strongSelf.dataSource managerGetRealmManager];
        OCTMessageAbstract *message = [realmManager addMessageWithText:text type:type chat:chat sender:nil messageId:messageId msgv3HashHex:msgv3HashHex sentPush:sent_push tssent:msgv3tssec tsrcvd:0];

        if (userSuccessBlock) {
            userSuccessBlock(message);
        }
    };

    OCTSendMessageOperationFailureBlock failureBlock = ^(NSError *error) {
        __strong OCTSubmanagerChatsImpl *strongSelf = weakSelf;

        if ((error.code == OCTToxErrorFriendSendMessageFriendNotConnected) &&
            [strongSelf.dataSource managerUseFauxOfflineMessaging]) {
            NSString *friend_pushToken = friend.pushToken;
            triggerPush(friend_pushToken, msgv3HashHex, strongSelf, chat);
            successBlock(-1);
            return;
        }

        if (userFailureBlock) {
            userFailureBlock(error);
        }
    };

    OCTSendMessageOperation *operation = [[OCTSendMessageOperation alloc] initWithTox:[self.dataSource managerGetTox]
                                                                         friendNumber:friend.friendNumber
                                                                          messageType:type
                                                                              message:text
                                                                         msgv3HashHex:msgv3HashHex
                                                                           msgv3tssec:msgv3tssec
                                                                         successBlock:successBlock
                                                                         failureBlock:failureBlock];
    [self.sendMessageQueue addOperation:operation];
}

- (BOOL)setIsTyping:(BOOL)isTyping inChat:(OCTChat *)chat error:(NSError **)error
{
    NSParameterAssert(chat);

    OCTFriend *friend = [chat.friends firstObject];
    OCTTox *tox = [self.dataSource managerGetTox];

    return [tox setUserIsTyping:isTyping forFriendNumber:friend.friendNumber error:error];
}

#pragma mark -  NSNotification

- (void)friendConnectionStatusChangeNotification:(NSNotification *)notification
{
    OCTFriend *friend = notification.object;

    if (! friend) {
        OCTLogWarn(@"no friend received in notification %@, exiting", notification);
        return;
    }

    if (friend.isConnected) {
        [self resendUndeliveredMessagesToFriend:friend];
    }
}

#pragma mark -  Private

- (void)resendUndeliveredMessagesToFriend:(OCTFriend *)friend
{
    OCTRealmManager *realmManager = [self.dataSource managerGetRealmManager];

    OCTChat *chat = [realmManager getOrCreateChatWithFriend:friend];

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"chatUniqueIdentifier == %@"
                              @" AND senderUniqueIdentifier == nil"
                              @" AND messageText.isDelivered == NO",
                              chat.uniqueIdentifier];

    RLMResults *results = [realmManager objectsWithClass:[OCTMessageAbstract class] predicate:predicate];

    for (OCTMessageAbstract *message in results) {
        OCTLogInfo(@"Resending message to friend %@", friend);

        __weak OCTSubmanagerChatsImpl *weakSelf = self;
        OCTSendMessageOperationSuccessBlock successBlock = ^(OCTToxMessageId messageId) {
            __strong OCTSubmanagerChatsImpl *strongSelf = weakSelf;

            OCTRealmManager *realmManager = [strongSelf.dataSource managerGetRealmManager];

            [realmManager updateObject:message withBlock:^(OCTMessageAbstract *theMessage) {
                theMessage.messageText.messageId = messageId;
            }];
        };

        OCTSendMessageOperationFailureBlock failureBlock = ^(NSError *error) {
            OCTLogWarn(@"Cannot resend message to friend %@, error %@", friend, error);
        };

        OCTSendMessageOperation *operation = [[OCTSendMessageOperation alloc] initWithTox:[self.dataSource managerGetTox]
                                                                             friendNumber:friend.friendNumber
                                                                              messageType:message.messageText.type
                                                                                  message:message.messageText.text
                                                                             msgv3HashHex:message.messageText.msgv3HashHex
                                                                               msgv3tssec:message.tssent
                                                                             successBlock:successBlock
                                                                             failureBlock:failureBlock];
        [self.sendMessageQueue addOperation:operation];
    }
}

#pragma mark -  OCTToxDelegate

/*
 * send mesgV3 high level ACK message.
 */
- (void)tox:(OCTTox *)tox sendFriendHighlevelACK:(NSString *)message
                                    friendNumber:(OCTToxFriendNumber)friendNumber
                                    msgv3HashHex:(NSString *)msgv3HashHex
                                   sendTimestamp:(uint32_t)sendTimestamp
{
    OCTSendMessageOperation *operation = [[OCTSendMessageOperation alloc] initWithTox:[self.dataSource managerGetTox]
                                                                         friendNumber:friendNumber
                                                                          messageType:OCTToxMessageTypeHighlevelack
                                                                              message:message
                                                                         msgv3HashHex:msgv3HashHex
                                                                           msgv3tssec:sendTimestamp
                                                                         successBlock:nil
                                                                         failureBlock:nil];
    [self.sendMessageQueue addOperation:operation];
}

/*
 * Process incoming text message from friend.
 */
- (void)tox:(OCTTox *)tox friendMessage:(NSString *)message
                                   type:(OCTToxMessageType)type
                           friendNumber:(OCTToxFriendNumber)friendNumber
                           msgv3HashHex:(NSString *)msgv3HashHex
                           sendTimestamp:(uint32_t)sendTimestamp
{
    OCTRealmManager *realmManager = [self.dataSource managerGetRealmManager];

    NSString *publicKey = [[self.dataSource managerGetTox] publicKeyFromFriendNumber:friendNumber error:nil];
    OCTFriend *friend = [realmManager friendWithPublicKey:publicKey];
    OCTChat *chat = [realmManager getOrCreateChatWithFriend:friend];

    if (msgv3HashHex != nil)
    {
        // HINT: check for double message, but only select incoming messages (senderUniqueIdentifier != NULL)
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"chatUniqueIdentifier == %@ AND messageText.msgv3HashHex == %@ AND senderUniqueIdentifier != nil",
                                  chat.uniqueIdentifier, msgv3HashHex];
        RLMResults *results = [realmManager objectsWithClass:[OCTMessageAbstract class] predicate:predicate];
        OCTMessageAbstract *message_found = [results firstObject];

        if (message_found) {
            OCTLogInfo(@"friendMessage ignoring double message i %@", chat.uniqueIdentifier);
            OCTLogInfo(@"friendMessage ignoring double message f %@", friend);
            return;
        }
    }

    [realmManager addMessageWithText:message type:type chat:chat sender:friend messageId:0 msgv3HashHex:msgv3HashHex sentPush:NO tssent:sendTimestamp tsrcvd:0];
}

- (void)tox:(OCTTox *)tox friendHighLevelACK:(NSString *)message
                                friendNumber:(OCTToxFriendNumber)friendNumber
                                msgv3HashHex:(NSString *)msgv3HashHex
                               sendTimestamp:(uint32_t)sendTimestamp
{
    OCTRealmManager *realmManager = [self.dataSource managerGetRealmManager];

    NSString *publicKey = [[self.dataSource managerGetTox] publicKeyFromFriendNumber:friendNumber error:nil];
    OCTFriend *friend = [realmManager friendWithPublicKey:publicKey];
    OCTChat *chat = [realmManager getOrCreateChatWithFriend:friend];

    // HINT: only select outgoing messages
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"chatUniqueIdentifier == %@ AND messageText.msgv3HashHex == %@ AND senderUniqueIdentifier == nil",
                              chat.uniqueIdentifier, msgv3HashHex];

    // HINT: we still sort and use only 1 result row, just in case more than 1 row is returned.
    //       but if more than 1 row is returned that would actually be an error.
    //       we use the newest message with this Hash
    RLMResults *results = [realmManager objectsWithClass:[OCTMessageAbstract class] predicate:predicate];
    results = [results sortedResultsUsingKeyPath:@"dateInterval" ascending:YES];

    OCTMessageAbstract *message_found = [results firstObject];

    if (! message_found) {
        return;
    }

    OCTLogInfo(@"friendHighLevelACK recevied from friend %@", friend);

    [realmManager updateObject:message_found withBlock:^(OCTMessageAbstract *theMessage) {
        theMessage.messageText.isDelivered = YES;
    }];
}


- (void)tox:(OCTTox *)tox messageDelivered:(OCTToxMessageId)messageId friendNumber:(OCTToxFriendNumber)friendNumber
{
    OCTRealmManager *realmManager = [self.dataSource managerGetRealmManager];

    NSString *publicKey = [[self.dataSource managerGetTox] publicKeyFromFriendNumber:friendNumber error:nil];
    OCTFriend *friend = [realmManager friendWithPublicKey:publicKey];

    if (friend.msgv3Capability == YES)
    {
        // HINT: if friend has msgV3 capability, we ignore the low level ACK and keep waiting for the high level ACK
        OCTLogInfo(@"messageDelivered ignoring low level ACK %@", friend);
        return;
    }

    OCTChat *chat = [realmManager getOrCreateChatWithFriend:friend];

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"chatUniqueIdentifier == %@ AND messageText.messageId == %d",
                              chat.uniqueIdentifier, messageId];

    // messageId is reset on every launch, so we want to update delivered status on latest message.
    RLMResults *results = [realmManager objectsWithClass:[OCTMessageAbstract class] predicate:predicate];
    results = [results sortedResultsUsingKeyPath:@"dateInterval" ascending:NO];

    OCTMessageAbstract *message = [results firstObject];

    if (! message) {
        return;
    }

    [realmManager updateObject:message withBlock:^(OCTMessageAbstract *theMessage) {
        theMessage.messageText.isDelivered = YES;
    }];
}

@end
