// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#import <Realm/Realm.h>

#import "OCTRealmManager.h"
#import "OCTFriend.h"
#import "OCTFriendRequest.h"
#import "OCTChat.h"
#import "OCTCall.h"
#import "OCTMessageAbstract.h"
#import "OCTMessageText.h"
#import "OCTMessageFile.h"
#import "OCTMessageCall.h"
#import "OCTSettingsStorageObject.h"
#import "OCTLogging.h"

static const uint64_t kCurrentSchemeVersion = 16;
static NSString *kSettingsStorageObjectPrimaryKey = @"kSettingsStorageObjectPrimaryKey";

@interface OCTRealmManager ()

@property (strong, nonatomic) dispatch_queue_t queue;
@property (strong, nonatomic) RLMRealm *realm;

@end

@implementation OCTRealmManager
@synthesize settingsStorage = _settingsStorage;

#pragma mark -  Class methods

+ (BOOL)migrateToEncryptedDatabase:(NSString *)databasePath
                     encryptionKey:(NSData *)encryptionKey
                             error:(NSError **)error
{
    NSString *tempPath = [databasePath stringByAppendingPathExtension:@"tmp"];

    @autoreleasepool {
        RLMRealm *old = [OCTRealmManager createRealmWithFileURL:[NSURL fileURLWithPath:databasePath]
                                                  encryptionKey:nil
                                                          error:error];

        if (! old) {
            return NO;
        }

        if (! [old writeCopyToURL:[NSURL fileURLWithPath:tempPath] encryptionKey:encryptionKey error:error]) {
            return NO;
        }
    }

    if (! [[NSFileManager defaultManager] removeItemAtPath:databasePath error:error]) {
        return NO;
    }

    if (! [[NSFileManager defaultManager] moveItemAtPath:tempPath toPath:databasePath error:error]) {
        return NO;
    }

    return YES;
}

#pragma mark -  Lifecycle

- (instancetype)initWithDatabaseFileURL:(NSURL *)fileURL encryptionKey:(NSData *)encryptionKey
{
    NSParameterAssert(fileURL);

    self = [super init];

    if (! self) {
        return nil;
    }

    OCTLogInfo(@"init with fileURL %@", fileURL);

    _queue = dispatch_queue_create("OCTRealmManager queue", NULL);

    __weak OCTRealmManager *weakSelf = self;
    dispatch_sync(_queue, ^{
        __strong OCTRealmManager *strongSelf = weakSelf;

        // TODO handle error
        self->_realm = [OCTRealmManager createRealmWithFileURL:fileURL encryptionKey:encryptionKey error:nil];
        [strongSelf createSettingsStorage];
    });

    [self convertAllCallsToMessages];

    return self;
}

#pragma mark -  Public

- (NSURL *)realmFileURL
{
    return self.realm.configuration.fileURL;
}

#pragma mark -  Basic methods

- (id)objectWithUniqueIdentifier:(NSString *)uniqueIdentifier class:(Class)class
{
    NSParameterAssert(uniqueIdentifier);
    NSParameterAssert(class);

    __block OCTObject *object = nil;

    dispatch_sync(self.queue, ^{
        object = [class objectInRealm:self.realm forPrimaryKey:uniqueIdentifier];
    });

    return object;
}

- (RLMResults *)objectsWithClass:(Class)class predicate:(NSPredicate *)predicate
{
    NSParameterAssert(class);

    __block RLMResults *results;

    dispatch_sync(self.queue, ^{
        results = [class objectsInRealm:self.realm withPredicate:predicate];
    });

    return results;
}

- (void)updateObject:(OCTObject *)object withBlock:(void (^)(id theObject))updateBlock
{
    NSParameterAssert(object);
    NSParameterAssert(updateBlock);

    // OCTLogInfo(@"updateObject %@", object);

    dispatch_sync(self.queue, ^{
        [self.realm beginWriteTransaction];

        updateBlock(object);

        [self.realm commitWriteTransaction];
    });
}

- (void)updateObjectsWithClass:(Class)class
                     predicate:(NSPredicate *)predicate
                   updateBlock:(void (^)(id theObject))updateBlock
{
    NSParameterAssert(class);
    NSParameterAssert(updateBlock);

    // OCTLogInfo(@"updating objects of class %@ with predicate %@", NSStringFromClass(class), predicate);

    dispatch_sync(self.queue, ^{
        RLMResults *results = [class objectsInRealm:self.realm withPredicate:predicate];

        [self.realm beginWriteTransaction];
        for (id object in results) {
            updateBlock(object);
        }
        [self.realm commitWriteTransaction];
    });
}

- (void)addObject:(OCTObject *)object
{
    NSParameterAssert(object);

    // OCTLogInfo(@"add object %@", object);

    dispatch_sync(self.queue, ^{
        [self.realm beginWriteTransaction];

        [self.realm addObject:object];

        [self.realm commitWriteTransaction];
    });
}

- (void)deleteObject:(OCTObject *)object
{
    NSParameterAssert(object);

    // OCTLogInfo(@"delete object %@", object);

    dispatch_sync(self.queue, ^{
        [self.realm beginWriteTransaction];

        [self.realm deleteObject:object];

        [self.realm commitWriteTransaction];
    });
}

#pragma mark -  Other methods

+ (RLMRealm *)createRealmWithFileURL:(NSURL *)fileURL encryptionKey:(NSData *)encryptionKey error:(NSError **)error
{
    RLMRealmConfiguration *configuration = [RLMRealmConfiguration defaultConfiguration];
    configuration.fileURL = fileURL;
    configuration.schemaVersion = kCurrentSchemeVersion;
    configuration.migrationBlock = [self realmMigrationBlock];
    configuration.encryptionKey = encryptionKey;

    RLMRealm *realm = [RLMRealm realmWithConfiguration:configuration error:error];

    if (! realm && error) {
        OCTLogInfo(@"Cannot create Realm, error %@", *error);
    }

    return realm;
}

- (void)createSettingsStorage
{
    _settingsStorage = [OCTSettingsStorageObject objectInRealm:self.realm
                                                 forPrimaryKey:kSettingsStorageObjectPrimaryKey];

    if (! _settingsStorage) {
        OCTLogInfo(@"no _settingsStorage, creating it");
        _settingsStorage = [OCTSettingsStorageObject new];
        _settingsStorage.uniqueIdentifier = kSettingsStorageObjectPrimaryKey;

        [self.realm beginWriteTransaction];
        [self.realm addObject:_settingsStorage];
        [self.realm commitWriteTransaction];
    }
}

- (OCTFriend *)friendWithPublicKey:(NSString *)publicKey
{
    NSAssert(publicKey, @"Public key should be non-empty.");
    __block OCTFriend *friend;

    dispatch_sync(self.queue, ^{
        friend = [[OCTFriend objectsInRealm:self.realm where:@"publicKey == %@", publicKey] firstObject];
    });

    return friend;
}

- (OCTChat *)getOrCreateChatWithFriend:(OCTFriend *)friend
{
    __block OCTChat *chat = nil;

    dispatch_sync(self.queue, ^{
        // TODO add this (friends.@count == 1) condition. Currentry Realm doesn't support collection queries
        // See https://github.com/realm/realm-cocoa/issues/1490
        chat = [[OCTChat objectsInRealm:self.realm where:@"ANY friends == %@", friend] firstObject];

        if (chat) {
            return;
        }

        OCTLogInfo(@"creating chat with friend %@", friend);

        chat = [OCTChat new];
        chat.lastActivityDateInterval = [[NSDate date] timeIntervalSince1970];

        [self.realm beginWriteTransaction];

        [self.realm addObject:chat];
        [chat.friends addObject:friend];

        [self.realm commitWriteTransaction];
    });

    return chat;
}

- (OCTCall *)createCallWithChat:(OCTChat *)chat status:(OCTCallStatus)status
{
    __block OCTCall *call = nil;

    dispatch_sync(self.queue, ^{

        call = [[OCTCall objectsInRealm:self.realm where:@"chat == %@", chat] firstObject];

        if (call) {
            return;
        }

        OCTLogInfo(@"creating call with chat %@", chat);

        call = [OCTCall new];
        call.status = status;
        call.chat = chat;

        [self.realm beginWriteTransaction];
        [self.realm addObject:call];
        [self.realm commitWriteTransaction];
    });

    return call;
}

- (OCTCall *)getCurrentCallForChat:(OCTChat *)chat
{
    __block OCTCall *call = nil;

    dispatch_sync(self.queue, ^{

        call = [[OCTCall objectsInRealm:self.realm where:@"chat == %@", chat] firstObject];
    });

    return call;
}

- (void)removeMessages:(NSArray<OCTMessageAbstract *> *)messages
{
    NSParameterAssert(messages);

    OCTLogInfo(@"removing messages %lu", (unsigned long)messages.count);

    dispatch_sync(self.queue, ^{
        [self.realm beginWriteTransaction];

        NSMutableSet *changedChats = [NSMutableSet new];
        for (OCTMessageAbstract *message in messages) {
            [changedChats addObject:message.chatUniqueIdentifier];
        }

        [self removeMessagesWithSubmessages:messages];

        for (NSString *chatUniqueIdentifier in changedChats) {
            RLMResults *messages = [OCTMessageAbstract objectsInRealm:self.realm where:@"chatUniqueIdentifier == %@", chatUniqueIdentifier];
            messages = [messages sortedResultsUsingKeyPath:@"dateInterval" ascending:YES];

            OCTChat *chat = [OCTChat objectInRealm:self.realm forPrimaryKey:chatUniqueIdentifier];
            chat.lastMessage = messages.lastObject;
        }

        [self.realm commitWriteTransaction];
    });
}

- (void)removeAllMessagesInChat:(OCTChat *)chat removeChat:(BOOL)removeChat
{
    NSParameterAssert(chat);

    OCTLogInfo(@"removing chat with all messages %@", chat);

    dispatch_sync(self.queue, ^{
        RLMResults *messages = [OCTMessageAbstract objectsInRealm:self.realm where:@"chatUniqueIdentifier == %@", chat.uniqueIdentifier];

        [self.realm beginWriteTransaction];

        [self removeMessagesWithSubmessages:messages];
        if (removeChat) {
            [self.realm deleteObject:chat];
        }

        [self.realm commitWriteTransaction];
    });
}

- (void)convertAllCallsToMessages
{
    RLMResults *calls = [OCTCall allObjectsInRealm:self.realm];

    OCTLogInfo(@"removing %lu calls", (unsigned long)calls.count);

    for (OCTCall *call in calls) {
        [self addMessageCall:call];
    }

    [self.realm beginWriteTransaction];
    [self.realm deleteObjects:calls];
    [self.realm commitWriteTransaction];
}

- (OCTMessageAbstract *)addMessageWithText:(NSString *)text
                                      type:(OCTToxMessageType)type
                                      chat:(OCTChat *)chat
                                    sender:(OCTFriend *)sender
                                 messageId:(OCTToxMessageId)messageId
                              msgv3HashHex:(NSString *)msgv3HashHex
                                  sentPush:(BOOL)sentPush
                                    tssent:(UInt32)tssent
                                    tsrcvd:(UInt32)tsrcvd
{
    NSParameterAssert(text);

    OCTLogInfo(@"adding messageText to chat %@", chat);

    OCTMessageText *messageText = [OCTMessageText new];
    messageText.text = text;
    messageText.isDelivered = NO;
    messageText.type = type;
    messageText.messageId = messageId;
    messageText.msgv3HashHex = msgv3HashHex;
    messageText.sentPush = sentPush;

    return [self addMessageAbstractWithChat:chat sender:sender messageText:messageText messageFile:nil messageCall:nil tssent:tssent tsrcvd:tsrcvd];
}

- (OCTMessageAbstract *)addMessageWithFileNumber:(OCTToxFileNumber)fileNumber
                                        fileType:(OCTMessageFileType)fileType
                                        fileSize:(OCTToxFileSize)fileSize
                                        fileName:(NSString *)fileName
                                        filePath:(NSString *)filePath
                                         fileUTI:(NSString *)fileUTI
                                            chat:(OCTChat *)chat
                                          sender:(OCTFriend *)sender
{
    OCTLogInfo(@"adding messageFile to chat %@, fileSize %lld", chat, fileSize);

    OCTMessageFile *messageFile = [OCTMessageFile new];
    messageFile.internalFileNumber = fileNumber;
    messageFile.fileType = fileType;
    messageFile.fileSize = fileSize;
    messageFile.fileName = fileName;
    [messageFile internalSetFilePath:filePath];
    messageFile.fileUTI = fileUTI;

    return [self addMessageAbstractWithChat:chat sender:sender messageText:nil messageFile:messageFile messageCall:nil tssent:0 tsrcvd:0];
}

- (OCTMessageAbstract *)addMessageCall:(OCTCall *)call
{
    OCTLogInfo(@"adding messageCall to call %@", call);

    OCTMessageCallEvent event;
    switch (call.status) {
        case OCTCallStatusDialing:
        case OCTCallStatusRinging:
            event = OCTMessageCallEventUnanswered;
            break;
        case OCTCallStatusActive:
            event = OCTMessageCallEventAnswered;
            break;
    }

    OCTMessageCall *messageCall = [OCTMessageCall new];
    messageCall.callDuration = call.callDuration;
    messageCall.callEvent = event;

    return [self addMessageAbstractWithChat:call.chat sender:call.caller messageText:nil messageFile:nil messageCall:messageCall tssent:0 tsrcvd:0];
}

#pragma mark -  Private

+ (RLMMigrationBlock)realmMigrationBlock
{
    return ^(RLMMigration *migration, uint64_t oldSchemaVersion) {
               if (oldSchemaVersion < 1) {
                   // objcTox version 0.1.0
               }

               if (oldSchemaVersion < 2) {
                   // objcTox version 0.2.1
               }

               if (oldSchemaVersion < 3) {
                   // objcTox version 0.4.0
               }

               if (oldSchemaVersion < 4) {
                   // objcTox version 0.5.0
                   [self doMigrationVersion4:migration];
               }

               if (oldSchemaVersion < 5) {
                   // OCTMessageAbstract: chat property replaced with chatUniqueIdentifier
                   [self doMigrationVersion5:migration];
               }

               if (oldSchemaVersion < 6) {
                   // OCTSettingsStorageObject: adding genericSettingsData property.
               }

               if (oldSchemaVersion < 7) {
                   [self doMigrationVersion7:migration];
               }

               if (oldSchemaVersion < 8) {
                   [self doMigrationVersion8:migration];
               }

               if (oldSchemaVersion < 9) {}

               if (oldSchemaVersion < 10) {}

               if (oldSchemaVersion < 11) {
                   [self doMigrationVersion11:migration];
               }

               if (oldSchemaVersion < 12) {
                   [self doMigrationVersion12:migration];
               }

               if (oldSchemaVersion < 13) {
                   [self doMigrationVersion13:migration];
               }

               if (oldSchemaVersion < 14) {
                   [self doMigrationVersion14:migration];
               }

               if (oldSchemaVersion < 16) {
                   [self doMigrationVersion16:migration];
               }
    };
}

+ (void)doMigrationVersion4:(RLMMigration *)migration
{
    [migration enumerateObjects:OCTChat.className block:^(RLMObject *oldObject, RLMObject *newObject) {
        newObject[@"enteredText"] = [oldObject[@"enteredText"] length] > 0 ? oldObject[@"enteredText"] : nil;
    }];

    [migration enumerateObjects:OCTFriend.className block:^(RLMObject *oldObject, RLMObject *newObject) {
        newObject[@"name"] = [oldObject[@"name"] length] > 0 ? oldObject[@"name"] : nil;
        newObject[@"statusMessage"] = [oldObject[@"statusMessage"] length] > 0 ? oldObject[@"statusMessage"] : nil;
    }];

    [migration enumerateObjects:OCTFriendRequest.className block:^(RLMObject *oldObject, RLMObject *newObject) {
        newObject[@"message"] = [oldObject[@"message"] length] > 0 ? oldObject[@"message"] : nil;
    }];

    [migration enumerateObjects:OCTMessageFile.className block:^(RLMObject *oldObject, RLMObject *newObject) {
        newObject[@"fileName"] = [oldObject[@"fileName"] length] > 0 ? oldObject[@"fileName"] : nil;
        newObject[@"fileUTI"] = [oldObject[@"fileUTI"] length] > 0 ? oldObject[@"fileUTI"] : nil;
    }];

    [migration enumerateObjects:OCTMessageText.className block:^(RLMObject *oldObject, RLMObject *newObject) {
        newObject[@"text"] = [oldObject[@"text"] length] > 0 ? oldObject[@"text"] : nil;
    }];
}

+ (void)doMigrationVersion5:(RLMMigration *)migration
{
    [migration enumerateObjects:OCTMessageAbstract.className block:^(RLMObject *oldObject, RLMObject *newObject) {
        newObject[@"chatUniqueIdentifier"] = oldObject[@"chat"][@"uniqueIdentifier"];
        newObject[@"senderUniqueIdentifier"] = oldObject[@"sender"][@"uniqueIdentifier"];
    }];
}

+ (void)doMigrationVersion7:(RLMMigration *)migration
{
    // Before this version OCTMessageText.isDelivered was broken.
    // See https://github.com/Antidote-for-Tox/objcTox/issues/158
    //
    // After update it was fixed + resending of undelivered messages feature was introduced.
    // This fired resending all messages that were in history for all friends.
    //
    // To fix an issue and stop people suffering we mark all outgoing text messages as delivered.

    [migration enumerateObjects:OCTMessageAbstract.className block:^(RLMObject *oldObject, RLMObject *newObject) {
        if (newObject[@"senderUniqueIdentifier"] != nil) {
            return;
        }

        RLMObject *messageText = newObject[@"messageText"];

        if (! messageText) {
            return;
        }

        messageText[@"isDelivered"] = @YES;
    }];
}

+ (void)doMigrationVersion8:(RLMMigration *)migration
{
    [migration enumerateObjects:OCTFriend.className block:^(RLMObject *oldObject, RLMObject *newObject) {
        newObject[@"pushToken"] = nil;
    }];
}

+ (void)doMigrationVersion11:(RLMMigration *)migration
{
    [migration enumerateObjects:OCTFriend.className block:^(RLMObject *oldObject, RLMObject *newObject) {
        newObject[@"msgv3Capability"] = @NO;
    }];
}

+ (void)doMigrationVersion12:(RLMMigration *)migration
{
    [migration enumerateObjects:OCTMessageText.className block:^(RLMObject *oldObject, RLMObject *newObject) {
        newObject[@"msgv3HashHex"] = nil;
    }];
}

+ (void)doMigrationVersion13:(RLMMigration *)migration
{
    [migration enumerateObjects:OCTMessageText.className block:^(RLMObject *oldObject, RLMObject *newObject) {
        newObject[@"sentPush"] = @YES;
    }];
}

+ (void)doMigrationVersion14:(RLMMigration *)migration
{
    [migration enumerateObjects:OCTMessageAbstract.className block:^(RLMObject *oldObject, RLMObject *newObject) {
        newObject[@"tssent"] = @0;
        newObject[@"tsrcvd"] = @0;
    }];
}

+ (void)doMigrationVersion16:(RLMMigration *)migration
{
    [migration enumerateObjects:OCTFriend.className block:^(RLMObject *oldObject, RLMObject *newObject) {
        newObject[@"capabilities2"] = nil;
    }];
}

/**
 * Only one of messageText, messageFile or messageCall can be non-nil.
 */
- (OCTMessageAbstract *)addMessageAbstractWithChat:(OCTChat *)chat
                                            sender:(OCTFriend *)sender
                                       messageText:(OCTMessageText *)messageText
                                       messageFile:(OCTMessageFile *)messageFile
                                       messageCall:(OCTMessageCall *)messageCall
                                            tssent:(UInt32)tssent
                                            tsrcvd:(UInt32)tsrcvd
{
    NSParameterAssert(chat);

    NSAssert( (messageText && ! messageFile && ! messageCall) ||
              (! messageText && messageFile && ! messageCall) ||
              (! messageText && ! messageFile && messageCall),
              @"Wrong options passed. Only one of messageText, messageFile or messageCall should be non-nil.");

    OCTMessageAbstract *messageAbstract = [OCTMessageAbstract new];
    messageAbstract.dateInterval = [[NSDate date] timeIntervalSince1970];
    messageAbstract.senderUniqueIdentifier = sender.uniqueIdentifier;
    messageAbstract.chatUniqueIdentifier = chat.uniqueIdentifier;
    messageAbstract.tssent = tssent;
    messageAbstract.tsrcvd = tsrcvd;
    messageAbstract.messageText = messageText;
    messageAbstract.messageFile = messageFile;
    messageAbstract.messageCall = messageCall;

    [self addObject:messageAbstract];

    [self updateObject:chat withBlock:^(OCTChat *theChat) {
        theChat.lastMessage = messageAbstract;
        theChat.lastActivityDateInterval = messageAbstract.dateInterval;
    }];

    return messageAbstract;
}

// Delete an NSArray, RLMArray, or RLMResults of messages from this Realm.
- (void)removeMessagesWithSubmessages:(id)messages
{
    for (OCTMessageAbstract *message in messages) {
        if (message.messageText) {
            [self.realm deleteObject:message.messageText];
        }
        if (message.messageFile) {
            [self.realm deleteObject:message.messageFile];
        }
        if (message.messageCall) {
            [self.realm deleteObject:message.messageCall];
        }
    }

    [self.realm deleteObjects:messages];
}

@end
