// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#import "OCTTox+Private.h"
#import "OCTToxOptions+Private.h"
#import "OCTLogging.h"

void (*_tox_self_get_public_key)(const Tox *tox, uint8_t *public_key);

@interface OCTTox ()

@property (assign, nonatomic) Tox *tox;

@property (strong, nonatomic) dispatch_source_t timer;
@property (assign, nonatomic) uint64_t previousIterate;

@end

@implementation OCTTox

static long long last_check_time = 0;
static long long TWO_MIN_IN_MILLIS = (2 * 60 * 1000); // 2 minutes in milliseconds

#pragma mark -  Class methods

+ (NSString *)version
{
    return [NSString stringWithFormat:@"%lu.%lu.%lu",
            (unsigned long)[self versionMajor], (unsigned long)[self versionMinor], (unsigned long)[self versionPatch]];
}

+ (NSUInteger)versionMajor
{
    return tox_version_major();
}

+ (NSUInteger)versionMinor
{
    return tox_version_minor();
}

+ (NSUInteger)versionPatch
{
    return tox_version_patch();
}

#pragma mark -  Lifecycle

- (instancetype)initWithOptions:(OCTToxOptions *)options savedData:(NSData *)data error:(NSError **)error
{
    NSParameterAssert(options);

    self = [super init];

    OCTLogVerbose(@"OCTTox: loading with options %@", options);

    if (data) {
        OCTLogVerbose(@"loading from data of length %lu", (unsigned long)data.length);
        tox_options_set_savedata_type(options.options, TOX_SAVEDATA_TYPE_TOX_SAVE);
        tox_options_set_savedata_data(options.options, data.bytes, data.length);
    }
    else {
        tox_options_set_savedata_type(options.options, TOX_SAVEDATA_TYPE_NONE);
    }

    tox_options_set_log_callback(options.options, logCallback);

    TOX_ERR_NEW cError;

    _tox = tox_new(options.options, &cError);

    [self fillError:error withCErrorInit:cError];

    if (! _tox) {
        return nil;
    }

    [self setupCFunctions];
    [self setupCallbacks];

    return self;
}

- (void)dealloc
{
    [self stop];

    if (self.tox) {
        tox_kill(self.tox);
    }

    OCTLogVerbose(@"dealloc called, tox killed");
}

- (NSData *)save
{
    OCTLogVerbose(@"saving...");

    size_t size = tox_get_savedata_size(self.tox);
    uint8_t *cData = malloc(size);

    tox_get_savedata(self.tox, cData);

    NSData *data = [NSData dataWithBytes:cData length:size];
    free(cData);

    OCTLogInfo(@"saved to data with length %lu", (unsigned long)data.length);

    return data;
}

- (void)start
{
    OCTLogVerbose(@"start method called");

    @synchronized(self) {
        if (self.timer) {
            OCTLogWarn(@"already started");
            return;
        }

        dispatch_queue_t queue = dispatch_queue_create("me.dvor.objcTox.OCTToxQueue", NULL);
        self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);

        [self updateTimerIntervalIfNeeded];

        // HINT: prevent bootstrapping here on startup. so add 2 minutes grace period
        last_check_time = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
        last_check_time = last_check_time + TWO_MIN_IN_MILLIS;

        __weak OCTTox *weakSelf = self;
        dispatch_source_set_event_handler(self.timer, ^{
            OCTTox *strongSelf = weakSelf;
            if (! strongSelf) {
                return;
            }

            tox_iterate(strongSelf.tox, (__bridge void *)self);

            long long current_time = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);

            if (current_time > (last_check_time + (TWO_MIN_IN_MILLIS))) {
                last_check_time = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
                int cstatus = tox_self_get_connection_status(strongSelf.tox);

                OCTLogInfo(@"Tox checking online status: %d", cstatus);

                if (cstatus == 0) {
                    OCTLogInfo(@"Tox offline for a long time, bootstrapping again ...");

                    uint8_t *key_bin = hex_to_bin("CD133B521159541FB1D326DE9850F5E56A6C724B5B8E5EB5CD8D950408E95707",
                                                 (TOX_PUBLIC_KEY_SIZE * 2));

                    if (key_bin != NULL) {
                        // -------------------------------------------------------------
                        // HINT: fix me. how to access OCTSubmanagerBootstrapImpl here?
                        //       add a hardcoded node to least make it come online
                        //       after a long period of being offline.
                        // -------------------------------------------------------------
                        tox_add_tcp_relay(strongSelf.tox, "46.101.197.175", 33445, key_bin, NULL);
                        tox_bootstrap(strongSelf.tox, "46.101.197.175", 33445, key_bin, NULL);

                        tox_add_tcp_relay(strongSelf.tox, "2a03:b0c0:3:d0::ac:5001", 33445, key_bin, NULL);
                        tox_bootstrap(strongSelf.tox, "2a03:b0c0:3:d0::ac:5001", 33445, key_bin, NULL);

                        OCTLogInfo(@"Tox offline for a long time, bootstrapping DONE");
                        free(key_bin);
                    }
                }
            }

            [strongSelf updateTimerIntervalIfNeeded];
        });

        dispatch_resume(self.timer);
    }

    OCTLogInfo(@"started");
}

- (void)stop
{
    OCTLogVerbose(@"stop method called");

    @synchronized(self) {
        if (! self.timer) {
            OCTLogWarn(@"tox isn't running, nothing to stop");
            return;
        }

        dispatch_source_cancel(self.timer);
        self.timer = nil;
    }

    OCTLogInfo(@"stopped");
}

#pragma mark -  Properties

- (OCTToxConnectionStatus)connectionStatus
{
    return [self userConnectionStatusFromCUserStatus:tox_self_get_connection_status(self.tox)];
}

- (OCTToxCapabilities)capabilities
{
    OCTLogVerbose(@"get capabilities");

    return tox_self_get_capabilities();
}

- (NSString *)userAddress
{
    OCTLogVerbose(@"get userAddress");

    const NSUInteger length = TOX_ADDRESS_SIZE;
    uint8_t *cAddress = malloc(length);

    tox_self_get_address(self.tox, cAddress);

    if (! cAddress) {
        return nil;
    }

    NSString *address = [OCTTox binToHexString:cAddress length:length];

    free(cAddress);

    return address;
}

- (NSString *)publicKey
{
    OCTLogVerbose(@"get publicKey");

    uint8_t *cPublicKey = malloc(TOX_PUBLIC_KEY_SIZE);

    _tox_self_get_public_key(self.tox, cPublicKey);

    NSString *publicKey = [OCTTox binToHexString:cPublicKey length:TOX_PUBLIC_KEY_SIZE];
    free(cPublicKey);

    return publicKey;
}

- (NSString *)secretKey
{
    OCTLogVerbose(@"get secretKey");

    uint8_t *cSecretKey = malloc(TOX_SECRET_KEY_SIZE);

    tox_self_get_secret_key(self.tox, cSecretKey);

    NSString *secretKey = [OCTTox binToHexString:cSecretKey length:TOX_SECRET_KEY_SIZE];
    free(cSecretKey);

    return secretKey;
}

- (void)setNospam:(OCTToxNoSpam)nospam
{
    OCTLogVerbose(@"set nospam");
    tox_self_set_nospam(self.tox, nospam);
}

- (OCTToxNoSpam)nospam
{
    OCTLogVerbose(@"get nospam");
    return tox_self_get_nospam(self.tox);
}

- (void)setUserStatus:(OCTToxUserStatus)status
{
    TOX_USER_STATUS cStatus = TOX_USER_STATUS_NONE;

    switch (status) {
        case OCTToxUserStatusNone:
            cStatus = TOX_USER_STATUS_NONE;
            break;
        case OCTToxUserStatusAway:
            cStatus = TOX_USER_STATUS_AWAY;
            break;
        case OCTToxUserStatusBusy:
            cStatus = TOX_USER_STATUS_BUSY;
            break;
    }

    tox_self_set_status(self.tox, cStatus);

    OCTLogInfo(@"set user status to %lu", (unsigned long)status);
}

- (OCTToxUserStatus)userStatus
{
    return [self userStatusFromCUserStatus:tox_self_get_status(self.tox)];
}

#pragma mark -  Methods

/*
 * Converts an ASCII character in hexadecimal (lower or upper case) into the corresponding decimal value.
 *
 * Returns decimal value on success.
 * Returns -1 on failure.
 */
int char_to_int(char c)
{
    if (c >= '0' && c <= '9')
    {
        return c - '0';
    }

    if (c >= 'A' && c <= 'F')
    {
        return 10 + c - 'A';
    }

    if (c >= 'a' && c <= 'f')
    {
        return 10 + c - 'a';
    }

    return -1;
}

/*
 * Converts a hexidecimal string of length hex_string_len to binary format and puts the result in output.
 * output_size must be exactly half of hex_string_len.
 *
 * Returns (uint8_t *) on success. the caller must free the buffer after use.
 * Returns NULL on failure.
 */
uint8_t *hex_to_bin(const char *hex_string_buffer, size_t hex_string_len)
{
    if ((!hex_string_buffer) || (hex_string_len < 2))
    {
        return NULL;
    }

    if ((hex_string_len % 2) != 0)
    {
        return NULL;
    }

    size_t len_bin = (hex_string_len / 2);
    uint8_t *val = calloc(1, len_bin);

    for (size_t i = 0; i < len_bin; i++)
    {
        val[i] = (16 * char_to_int(hex_string_buffer[2 * i])) + (char_to_int(hex_string_buffer[2 * i + 1]));
    }

    return val;
}

/*
 * Converts byte buffer into a hexidecimal string.
 *
 * Returns 0 on success. the caller must must provide a buffer with enough space to hold the hex string.
 * Returns -1 on failure.
 */
int bin_to_hex(const char *bin_id, size_t bin_id_size, char *output)
{
    if ((!output) || (!bin_id) || (bin_id_size < 1))
    {
        return -1;
    }

    size_t i;

    for (i = 0; i < bin_id_size; i++)
    {
        snprintf(&output[i * 2], ((bin_id_size * 2) + 1) - (i * 2), "%02X", bin_id[i] & 0xff);
    }

    return 0;
}

size_t xnet_pack_u16(uint8_t *bytes, uint16_t v)
{
    bytes[0] = (v >> 8) & 0xff;
    bytes[1] = v & 0xff;
    return sizeof(v);
}

size_t xnet_pack_u32(uint8_t *bytes, uint32_t v)
{
    uint8_t *p = bytes;
    p += xnet_pack_u16(p, (v >> 16) & 0xffff);
    p += xnet_pack_u16(p, v & 0xffff);
    return p - bytes;
}

size_t xnet_unpack_u16(const uint8_t *bytes, uint16_t *v)
{
    uint8_t hi = bytes[0];
    uint8_t lo = bytes[1];
    *v = ((uint16_t)hi << 8) | lo;
    return sizeof(*v);
}

size_t xnet_unpack_u32(const uint8_t *bytes, uint32_t *v)
{
    const uint8_t *p = bytes;
    uint16_t hi;
    uint16_t lo;
    p += xnet_unpack_u16(p, &hi);
    p += xnet_unpack_u16(p, &lo);
    *v = ((uint32_t)hi << 16) | lo;
    return p - bytes;
}

- (BOOL)bootstrapFromHost:(NSString *)host port:(OCTToxPort)port publicKey:(NSString *)publicKey error:(NSError **)error
{
    NSParameterAssert(host);
    NSParameterAssert(publicKey);

    OCTLogInfo(@"bootstrap with host %@ port %d publicKey %@", host, port, publicKey);

    const char *cAddress = host.UTF8String;
    uint8_t *cPublicKey = [OCTTox hexStringToBin:publicKey];

    TOX_ERR_BOOTSTRAP cError;

    bool result = tox_bootstrap(self.tox, cAddress, port, cPublicKey, &cError);

    [self fillError:error withCErrorBootstrap:cError];

    free(cPublicKey);

    return (BOOL)result;
}

- (BOOL)addTCPRelayWithHost:(NSString *)host port:(OCTToxPort)port publicKey:(NSString *)publicKey error:(NSError **)error
{
    NSParameterAssert(host);
    NSParameterAssert(publicKey);

    OCTLogInfo(@"add TCP relay with host %@ port %d publicKey %@", host, port, publicKey);

    const char *cAddress = host.UTF8String;
    uint8_t *cPublicKey = [OCTTox hexStringToBin:publicKey];

    TOX_ERR_BOOTSTRAP cError;

    bool result = tox_add_tcp_relay(self.tox, cAddress, port, cPublicKey, &cError);

    [self fillError:error withCErrorBootstrap:cError];

    free(cPublicKey);

    return (BOOL)result;
}

- (OCTToxFriendNumber)addFriendWithAddress:(NSString *)address message:(NSString *)message error:(NSError **)error
{
    NSParameterAssert(address);
    NSParameterAssert(message);
    NSAssert(address.length == kOCTToxAddressLength, @"Address must be kOCTToxAddressLength length");

    OCTLogVerbose(@"add friend with address.length %lu, message.length %lu", (unsigned long)address.length, (unsigned long)message.length);

    uint8_t *cAddress = [OCTTox hexStringToBin:address];
    const char *cMessage = [message cStringUsingEncoding:NSUTF8StringEncoding];
    size_t length = [message lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    TOX_ERR_FRIEND_ADD cError;

    OCTToxFriendNumber result = tox_friend_add(self.tox, cAddress, (const uint8_t *)cMessage, length, &cError);

    free(cAddress);

    [self fillError:error withCErrorFriendAdd:cError];

    return result;
}

- (OCTToxFriendNumber)addFriendWithNoRequestWithPublicKey:(NSString *)publicKey error:(NSError **)error
{
    NSParameterAssert(publicKey);
    NSAssert(publicKey.length == kOCTToxPublicKeyLength, @"Public key must be kOCTToxPublicKeyLength length");

    OCTLogVerbose(@"add friend with no request and publicKey.length %lu", (unsigned long)publicKey.length);

    uint8_t *cPublicKey = [OCTTox hexStringToBin:publicKey];

    TOX_ERR_FRIEND_ADD cError;

    OCTToxFriendNumber result = tox_friend_add_norequest(self.tox, cPublicKey, &cError);

    free(cPublicKey);

    [self fillError:error withCErrorFriendAdd:cError];

    return result;
}

- (BOOL)deleteFriendWithFriendNumber:(OCTToxFriendNumber)friendNumber error:(NSError **)error
{
    TOX_ERR_FRIEND_DELETE cError;

    bool result = tox_friend_delete(self.tox, friendNumber, &cError);

    [self fillError:error withCErrorFriendDelete:cError];

    OCTLogVerbose(@"deleting friend with friendNumber %d, result %d", friendNumber, (result == 0));

    return (BOOL)result;
}

- (OCTToxFriendNumber)friendNumberWithPublicKey:(NSString *)publicKey error:(NSError **)error
{
    NSParameterAssert(publicKey);
    NSAssert(publicKey.length == kOCTToxPublicKeyLength, @"Public key must be kOCTToxPublicKeyLength length");

    OCTLogVerbose(@"get friend number with publicKey.length %lu", (unsigned long)publicKey.length);

    uint8_t *cPublicKey = [OCTTox hexStringToBin:publicKey];

    TOX_ERR_FRIEND_BY_PUBLIC_KEY cError;

    OCTToxFriendNumber result = tox_friend_by_public_key(self.tox, cPublicKey, &cError);

    free(cPublicKey);

    [self fillError:error withCErrorFriendByPublicKey:cError];

    return result;
}

- (NSString *)publicKeyFromFriendNumber:(OCTToxFriendNumber)friendNumber error:(NSError **)error
{
    OCTLogVerbose(@"get public key from friend number %d", friendNumber);

    uint8_t *cPublicKey = malloc(TOX_PUBLIC_KEY_SIZE);

    TOX_ERR_FRIEND_GET_PUBLIC_KEY cError;

    bool result = tox_friend_get_public_key(self.tox, friendNumber, cPublicKey, &cError);

    NSString *publicKey = nil;

    if (result) {
        publicKey = [OCTTox binToHexString:cPublicKey length:TOX_PUBLIC_KEY_SIZE];
    }

    if (cPublicKey) {
        free(cPublicKey);
    }

    [self fillError:error withCErrorFriendGetPublicKey:cError];

    return publicKey;
}

- (BOOL)friendExistsWithFriendNumber:(OCTToxFriendNumber)friendNumber
{
    bool result = tox_friend_exists(self.tox, friendNumber);

    OCTLogVerbose(@"friend exists with friendNumber %d, result %d", friendNumber, result);

    return (BOOL)result;
}

- (NSDate *)friendGetLastOnlineWithFriendNumber:(OCTToxFriendNumber)friendNumber error:(NSError **)error
{
    TOX_ERR_FRIEND_GET_LAST_ONLINE cError;

    uint64_t timestamp = tox_friend_get_last_online(self.tox, friendNumber, &cError);

    [self fillError:error withCErrorFriendGetLastOnline:cError];

    if (timestamp == UINT64_MAX) {
        return nil;
    }

    return [NSDate dateWithTimeIntervalSince1970:timestamp];
}


- (OCTToxCapabilities)friendGetCapabilitiesWithFriendNumber:(OCTToxFriendNumber)friendNumber
{
    return tox_friend_get_capabilities(self.tox, friendNumber);
}

- (OCTToxUserStatus)friendStatusWithFriendNumber:(OCTToxFriendNumber)friendNumber error:(NSError **)error
{
    TOX_ERR_FRIEND_QUERY cError;

    TOX_USER_STATUS cStatus = tox_friend_get_status(self.tox, friendNumber, &cError);

    [self fillError:error withCErrorFriendQuery:cError];

    return [self userStatusFromCUserStatus:cStatus];
}

- (OCTToxConnectionStatus)friendConnectionStatusWithFriendNumber:(OCTToxFriendNumber)friendNumber error:(NSError **)error
{
    TOX_ERR_FRIEND_QUERY cError;

    TOX_CONNECTION cStatus = tox_friend_get_connection_status(self.tox, friendNumber, &cError);

    [self fillError:error withCErrorFriendQuery:cError];

    return [self userConnectionStatusFromCUserStatus:cStatus];
}

- (BOOL)sendLosslessPacketWithFriendNumber:(OCTToxFriendNumber)friendNumber
                                                pktid:(uint8_t)pktid
                                                 data:(NSString *)data
                                                error:(NSError **)error
{
    // TODO: this now only works with UTF8 strings as data, make it work fully with byte arrays later

    NSParameterAssert(data);

    char *cData = [data cStringUsingEncoding:NSUTF8StringEncoding];
    size_t length = [data lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    cData[0] = pktid;

    TOX_ERR_FRIEND_CUSTOM_PACKET cError;

    bool result = tox_friend_send_lossless_packet(self.tox, friendNumber, (const uint8_t *)cData, length, &cError);

    // TODO: fill cError with errorcode
    // [self fillError:error xxxxxxxxxx:cError];

    return (BOOL)result;
}

- (OCTToxMessageId)sendMessageWithFriendNumber:(OCTToxFriendNumber)friendNumber
                                          type:(OCTToxMessageType)type
                                       message:(NSString *)message
                                  msgv3HashHex:(NSString *)msgv3HashHex
                                    msgv3tssec:(UInt32)msgv3tssec
                                         error:(NSError **)error
{
    NSParameterAssert(message);

    char *cMessage = [message cStringUsingEncoding:NSUTF8StringEncoding];
    size_t length = [message lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    TOX_MESSAGE_TYPE cType;
    switch (type) {
        case OCTToxMessageTypeNormal:
            cType = TOX_MESSAGE_TYPE_NORMAL;
            break;
        case OCTToxMessageTypeAction:
            cType = TOX_MESSAGE_TYPE_ACTION;
            break;
        case OCTToxMessageTypeHighlevelack:
            cType = TOX_MESSAGE_TYPE_HIGH_LEVEL_ACK;
            break;
    }

    TOX_ERR_FRIEND_SEND_MESSAGE cError;

    char *cMessage2 = cMessage;
    size_t length2 = length;
    char *cMessage2_alloc = NULL;
    uint8_t *hash_buffer_c = NULL;

    if (msgv3HashHex != nil)
    {
        char *msgv3HashHex_cstr = [msgv3HashHex cStringUsingEncoding:NSUTF8StringEncoding];
        size_t msgv3HashHex_length = [msgv3HashHex lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

        if (msgv3HashHex_length >= (TOX_MSGV3_MSGID_LENGTH * 2))
        {
            size_t length_orig_corrected = length;
            if (length > TOX_MSGV3_MAX_MESSAGE_LENGTH)
            {
                length_orig_corrected = TOX_MSGV3_MAX_MESSAGE_LENGTH;
            }

            cMessage2_alloc = (char *)calloc(1, (size_t)(length_orig_corrected +
                    TOX_MSGV3_GUARD + TOX_MSGV3_MSGID_LENGTH + TOX_MSGV3_TIMESTAMP_LENGTH));
            hash_buffer_c = hex_to_bin(msgv3HashHex_cstr, (TOX_MSGV3_MSGID_LENGTH * 2));

            if ((cMessage2_alloc) && (hash_buffer_c))
            {
                uint32_t timestamp_unix = (uint32_t)msgv3tssec;
                uint32_t timestamp_unix_buf = 0;
                // NSLog(@"mmm:timestamp_unix %d", timestamp_unix);
                xnet_pack_u32((uint8_t *)&timestamp_unix_buf, timestamp_unix);
                // NSLog(@"mmm:timestamp_unix_buf %d", timestamp_unix_buf);

                uint8_t* position = cMessage2_alloc;
                memcpy(position, cMessage, (size_t)(length_orig_corrected));
                position = position + length_orig_corrected;
                position = position + TOX_MSGV3_GUARD;
                memcpy(position, hash_buffer_c, (size_t)(TOX_MSGV3_MSGID_LENGTH));
                position = position + TOX_MSGV3_MSGID_LENGTH;
                memcpy(position, &timestamp_unix_buf, (size_t)(TOX_MSGV3_TIMESTAMP_LENGTH));

                length2 = length_orig_corrected + TOX_MSGV3_GUARD + TOX_MSGV3_MSGID_LENGTH + TOX_MSGV3_TIMESTAMP_LENGTH;
                cMessage2 = cMessage2_alloc;
            }
        }
    }

    OCTToxMessageId result = tox_friend_send_message(self.tox, friendNumber, cType, (const uint8_t *)cMessage2, length2, &cError);

    if (cMessage2_alloc)
    {
        free(cMessage2_alloc);
    }

    if (hash_buffer_c)
    {
        free(hash_buffer_c);
    }

    [self fillError:error withCErrorFriendSendMessage:cError];

    return result;
}

- (BOOL)setNickname:(NSString *)name error:(NSError **)error
{
    NSParameterAssert(name);

    const char *cName = [name cStringUsingEncoding:NSUTF8StringEncoding];
    size_t length = [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    TOX_ERR_SET_INFO cError;

    bool result = tox_self_set_name(self.tox, (const uint8_t *)cName, length, &cError);

    [self fillError:error withCErrorSetInfo:cError];

    OCTLogInfo(@"set userName to %@, result %d", name, result);

    return (BOOL)result;
}

- (NSString *)userName
{
    size_t length = tox_self_get_name_size(self.tox);

    if (! length) {
        return nil;
    }

    uint8_t *cName = malloc(length);
    tox_self_get_name(self.tox, cName);

    NSString *name = [[NSString alloc] initWithBytes:cName length:length encoding:NSUTF8StringEncoding];

    free(cName);

    return name;
}

- (NSString *)friendNameWithFriendNumber:(OCTToxFriendNumber)friendNumber error:(NSError **)error
{
    TOX_ERR_FRIEND_QUERY cError;
    size_t size = tox_friend_get_name_size(self.tox, friendNumber, &cError);

    [self fillError:error withCErrorFriendQuery:cError];

    if (cError != TOX_ERR_FRIEND_QUERY_OK) {
        return nil;
    }

    uint8_t *cName = malloc(size);
    bool result = tox_friend_get_name(self.tox, friendNumber, cName, &cError);

    NSString *name = nil;

    if (result) {
        name = [[NSString alloc] initWithBytes:cName length:size encoding:NSUTF8StringEncoding];
    }

    if (cName) {
        free(cName);
    }

    [self fillError:error withCErrorFriendQuery:cError];

    return name;
}

- (BOOL)setUserStatusMessage:(NSString *)statusMessage error:(NSError **)error
{
    NSParameterAssert(statusMessage);

    const char *cStatusMessage = [statusMessage cStringUsingEncoding:NSUTF8StringEncoding];
    size_t length = [statusMessage lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    TOX_ERR_SET_INFO cError;

    bool result = tox_self_set_status_message(self.tox, (const uint8_t *)cStatusMessage, length, &cError);

    [self fillError:error withCErrorSetInfo:cError];

    OCTLogInfo(@"set user status message to %@, result %d", statusMessage, result);

    return (BOOL)result;
}

- (NSString *)userStatusMessage
{
    size_t length = tox_self_get_status_message_size(self.tox);

    if (! length) {
        return nil;
    }

    uint8_t *cBuffer = malloc(length);

    tox_self_get_status_message(self.tox, cBuffer);

    NSString *message = [[NSString alloc] initWithBytes:cBuffer length:length encoding:NSUTF8StringEncoding];
    free(cBuffer);

    return message;
}

- (NSString *)friendStatusMessageWithFriendNumber:(OCTToxFriendNumber)friendNumber error:(NSError **)error
{
    TOX_ERR_FRIEND_QUERY cError;

    size_t size = tox_friend_get_status_message_size(self.tox, friendNumber, &cError);

    [self fillError:error withCErrorFriendQuery:cError];

    if (cError != TOX_ERR_FRIEND_QUERY_OK) {
        return nil;
    }

    uint8_t *cBuffer = malloc(size);

    bool result = tox_friend_get_status_message(self.tox, friendNumber, cBuffer, &cError);

    NSString *message = nil;

    if (result) {
        message = [[NSString alloc] initWithBytes:cBuffer length:size encoding:NSUTF8StringEncoding];
    }

    if (cBuffer) {
        free(cBuffer);
    }

    [self fillError:error withCErrorFriendQuery:cError];

    return message;
}

- (BOOL)setUserIsTyping:(BOOL)isTyping forFriendNumber:(OCTToxFriendNumber)friendNumber error:(NSError **)error
{
    TOX_ERR_SET_TYPING cError;

    bool result = tox_self_set_typing(self.tox, friendNumber, (bool)isTyping, &cError);

    [self fillError:error withCErrorSetTyping:cError];

    OCTLogInfo(@"set user isTyping to %d for friend number %d, result %d", isTyping, friendNumber, result);

    return (BOOL)result;
}

- (BOOL)isFriendTypingWithFriendNumber:(OCTToxFriendNumber)friendNumber error:(NSError **)error
{
    TOX_ERR_FRIEND_QUERY cError;

    bool isTyping = tox_friend_get_typing(self.tox, friendNumber, &cError);

    [self fillError:error withCErrorFriendQuery:cError];

    return (BOOL)isTyping;
}

- (NSUInteger)friendsCount
{
    return tox_self_get_friend_list_size(self.tox);
}

- (NSArray *)friendsArray
{
    size_t count = tox_self_get_friend_list_size(self.tox);

    if (! count) {
        return @[];
    }

    size_t listSize = count * sizeof(uint32_t);
    uint32_t *cList = malloc(listSize);

    tox_self_get_friend_list(self.tox, cList);

    NSMutableArray *list = [NSMutableArray new];

    for (NSUInteger index = 0; index < count; index++) {
        int32_t friendId = cList[index];
        [list addObject:@(friendId)];
    }

    free(cList);

    OCTLogVerbose(@"friend array %@", list);

    return [list copy];
}

- (NSData *)hashData:(NSData *)data
{
    uint8_t *cHash = malloc(TOX_HASH_LENGTH);
    const uint8_t *cData = [data bytes];

    bool result = tox_hash(cHash, cData, (uint32_t)data.length);
    NSData *hash;

    if (result) {
        hash = [NSData dataWithBytes:cHash length:TOX_HASH_LENGTH];
    }

    if (cHash) {
        free(cHash);
    }

    OCTLogInfo(@"hash data result %@", hash);

    return hash;
}

- (BOOL)fileSendControlForFileNumber:(OCTToxFileNumber)fileNumber
                        friendNumber:(OCTToxFriendNumber)friendNumber
                             control:(OCTToxFileControl)control
                               error:(NSError **)error
{
    TOX_FILE_CONTROL cControl;

    switch (control) {
        case OCTToxFileControlResume:
            cControl = TOX_FILE_CONTROL_RESUME;
            break;
        case OCTToxFileControlPause:
            cControl = TOX_FILE_CONTROL_PAUSE;
            break;
        case OCTToxFileControlCancel:
            cControl = TOX_FILE_CONTROL_CANCEL;
            break;
    }

    TOX_ERR_FILE_CONTROL cError;

    bool result = tox_file_control(self.tox, friendNumber, fileNumber, cControl, &cError);

    [self fillError:error withCErrorFileControl:cError];

    return (BOOL)result;
}

- (BOOL)fileSeekForFileNumber:(OCTToxFileNumber)fileNumber
                 friendNumber:(OCTToxFriendNumber)friendNumber
                     position:(OCTToxFileSize)position
                        error:(NSError **)error
{
    TOX_ERR_FILE_SEEK cError;

    bool result = tox_file_seek(self.tox, friendNumber, fileNumber, position, &cError);

    [self fillError:error withCErrorFileSeek:cError];

    return (BOOL)result;
}

- (NSData *)fileGetFileIdForFileNumber:(OCTToxFileNumber)fileNumber
                          friendNumber:(OCTToxFriendNumber)friendNumber
                                 error:(NSError **)error
{
    uint8_t *cFileId = malloc(kOCTToxFileIdLength);
    TOX_ERR_FILE_GET cError;

    bool result = tox_file_get_file_id(self.tox, friendNumber, fileNumber, cFileId, &cError);
    NSData *fileId;

    [self fillError:error withCErrorFileGet:cError];

    if (result) {
        fileId = [NSData dataWithBytes:cFileId length:kOCTToxFileIdLength];
    }

    if (cFileId) {
        free(cFileId);
    }

    return fileId;
}

- (OCTToxFileNumber)fileSendWithFriendNumber:(OCTToxFriendNumber)friendNumber
                                        kind:(OCTToxFileKind)kind
                                    fileSize:(OCTToxFileSize)fileSize
                                      fileId:(NSData *)fileId
                                    fileName:(NSString *)fileName
                                       error:(NSError **)error
{
    TOX_ERR_FILE_SEND cError;
    TOX_FILE_KIND cKind;
    const uint8_t *cFileId = NULL;
    const uint8_t *cFileName = NULL;

    switch (kind) {
        case OCTToxFileKindData:
            cKind = TOX_FILE_KIND_DATA;
            break;
        case OCTToxFileKindAvatar:
            cKind = TOX_FILE_KIND_AVATAR;
            break;
    }

    if (fileId.length) {
        cFileId = [fileId bytes];
    }

    if (fileName.length) {
        cFileName = (const uint8_t *)[fileName cStringUsingEncoding:NSUTF8StringEncoding];
    }

    OCTToxFileNumber result = tox_file_send(self.tox, friendNumber, cKind, fileSize, cFileId, cFileName, fileName.length, &cError);

    [self fillError:error withCErrorFileSend:cError];

    return result;
}

- (BOOL)fileSendChunkForFileNumber:(OCTToxFileNumber)fileNumber
                      friendNumber:(OCTToxFriendNumber)friendNumber
                          position:(OCTToxFileSize)position
                              data:(NSData *)data
                             error:(NSError **)error
{
    TOX_ERR_FILE_SEND_CHUNK cError;
    const uint8_t *cData = [data bytes];

    bool result = tox_file_send_chunk(self.tox, friendNumber, fileNumber, position, cData, (uint32_t)data.length, &cError);

    [self fillError:error withCErrorFileSendChunk:cError];

    return (BOOL)result;
}

#pragma mark -  Private methods

- (void)updateTimerIntervalIfNeeded
{
    uint64_t nextIterate = tox_iteration_interval(self.tox) * USEC_PER_SEC;

    if (self.previousIterate == nextIterate) {
        return;
    }

    self.previousIterate = nextIterate;
    dispatch_source_set_timer(self.timer, dispatch_walltime(NULL, nextIterate), nextIterate, nextIterate / 5);
}

- (void)setupCFunctions
{
    _tox_self_get_public_key = tox_self_get_public_key;
}

- (void)setupCallbacks
{
    tox_callback_self_connection_status(_tox, connectionStatusCallback);
    tox_callback_friend_name(_tox, friendNameCallback);
    tox_callback_friend_status_message(_tox, friendStatusMessageCallback);
    tox_callback_friend_status(_tox, friendStatusCallback);
    tox_callback_friend_connection_status(_tox, friendConnectionStatusCallback);
    tox_callback_friend_typing(_tox, friendTypingCallback);
    tox_callback_friend_read_receipt(_tox, friendReadReceiptCallback);
    tox_callback_friend_request(_tox, friendRequestCallback);
    tox_callback_friend_message(_tox, friendMessageCallback);
    tox_callback_friend_lossless_packet(_tox, friendLosslessPacketCallback);
    tox_callback_file_recv_control(_tox, fileReceiveControlCallback);
    tox_callback_file_chunk_request(_tox, fileChunkRequestCallback);
    tox_callback_file_recv(_tox, fileReceiveCallback);
    tox_callback_file_recv_chunk(_tox, fileReceiveChunkCallback);
}

- (OCTToxUserStatus)userStatusFromCUserStatus:(TOX_USER_STATUS)cStatus
{
    switch (cStatus) {
        case TOX_USER_STATUS_NONE:
            return OCTToxUserStatusNone;
        case TOX_USER_STATUS_AWAY:
            return OCTToxUserStatusAway;
        case TOX_USER_STATUS_BUSY:
            return OCTToxUserStatusBusy;
    }
}

- (OCTToxConnectionStatus)userConnectionStatusFromCUserStatus:(TOX_CONNECTION)cStatus
{
    switch (cStatus) {
        case TOX_CONNECTION_NONE:
            return OCTToxConnectionStatusNone;
        case TOX_CONNECTION_TCP:
            return OCTToxConnectionStatusTCP;
        case TOX_CONNECTION_UDP:
            return OCTToxConnectionStatusUDP;
    }
}

- (OCTToxMessageType)messageTypeFromCMessageType:(TOX_MESSAGE_TYPE)cType
{
    switch (cType) {
        case TOX_MESSAGE_TYPE_NORMAL:
            return OCTToxMessageTypeNormal;
        case TOX_MESSAGE_TYPE_ACTION:
            return OCTToxMessageTypeAction;
    }
}

- (OCTToxFileControl)fileControlFromCFileControl:(TOX_FILE_CONTROL)cControl
{
    switch (cControl) {
        case TOX_FILE_CONTROL_RESUME:
            return OCTToxFileControlResume;
        case TOX_FILE_CONTROL_PAUSE:
            return OCTToxFileControlPause;
        case TOX_FILE_CONTROL_CANCEL:
            return OCTToxFileControlCancel;
    }
}

- (BOOL)fillError:(NSError **)error withCErrorInit:(TOX_ERR_NEW)cError
{
    if (! error || (cError == TOX_ERR_NEW_OK)) {
        return NO;
    }

    OCTToxErrorInitCode code = OCTToxErrorInitCodeUnknown;
    NSString *description = @"Cannot initialize Tox";
    NSString *failureReason = nil;

    switch (cError) {
        case TOX_ERR_NEW_OK:
            NSAssert(NO, @"We shouldn't be here");
            return NO;
        case TOX_ERR_NEW_NULL:
            code = OCTToxErrorInitCodeUnknown;
            failureReason = @"Unknown error occured";
            break;
        case TOX_ERR_NEW_MALLOC:
            code = OCTToxErrorInitCodeMemoryError;
            failureReason = @"Not enough memory";
            break;
        case TOX_ERR_NEW_PORT_ALLOC:
            code = OCTToxErrorInitCodePortAlloc;
            failureReason = @"Cannot bint to a port";
            break;
        case TOX_ERR_NEW_PROXY_BAD_TYPE:
            code = OCTToxErrorInitCodeProxyBadType;
            failureReason = @"Proxy type is invalid";
            break;
        case TOX_ERR_NEW_PROXY_BAD_HOST:
            code = OCTToxErrorInitCodeProxyBadHost;
            failureReason = @"Proxy host is invalid";
            break;
        case TOX_ERR_NEW_PROXY_BAD_PORT:
            code = OCTToxErrorInitCodeProxyBadPort;
            failureReason = @"Proxy port is invalid";
            break;
        case TOX_ERR_NEW_PROXY_NOT_FOUND:
            code = OCTToxErrorInitCodeProxyNotFound;
            failureReason = @"Proxy host could not be resolved";
            break;
        case TOX_ERR_NEW_LOAD_ENCRYPTED:
            code = OCTToxErrorInitCodeEncrypted;
            failureReason = @"Tox save is encrypted";
            break;
        case TOX_ERR_NEW_LOAD_BAD_FORMAT:
            code = OCTToxErrorInitCodeLoadBadFormat;
            failureReason = @"Tox save is corrupted";
            break;
    }

    *error = [OCTTox createErrorWithCode:code description:description failureReason:failureReason];

    return YES;
}

- (BOOL)fillError:(NSError **)error withCErrorBootstrap:(TOX_ERR_BOOTSTRAP)cError
{
    if (! error || (cError == TOX_ERR_BOOTSTRAP_OK)) {
        return NO;
    }

    OCTToxErrorBootstrapCode code = OCTToxErrorBootstrapCodeUnknown;
    NSString *description = @"Cannot bootstrap with specified node";
    NSString *failureReason = nil;

    switch (cError) {
        case TOX_ERR_BOOTSTRAP_OK:
            NSAssert(NO, @"We shouldn't be here");
            return NO;
        case TOX_ERR_BOOTSTRAP_NULL:
            code = OCTToxErrorBootstrapCodeUnknown;
            failureReason = @"Unknown error occured";
            break;
        case TOX_ERR_BOOTSTRAP_BAD_HOST:
            code = OCTToxErrorBootstrapCodeBadHost;
            failureReason = @"The host could not be resolved to an IP address, or the IP address passed was invalid";
            break;
        case TOX_ERR_BOOTSTRAP_BAD_PORT:
            code = OCTToxErrorBootstrapCodeBadPort;
            failureReason = @"The port passed was invalid";
            break;
    }

    *error = [OCTTox createErrorWithCode:code description:description failureReason:failureReason];

    return YES;
}

- (BOOL)fillError:(NSError **)error withCErrorFriendAdd:(TOX_ERR_FRIEND_ADD)cError
{
    if (! error || (cError == TOX_ERR_FRIEND_ADD_OK)) {
        return NO;
    }

    OCTToxErrorFriendAdd code = OCTToxErrorFriendAddUnknown;
    NSString *description = @"Cannot add friend";
    NSString *failureReason = nil;

    switch (cError) {
        case TOX_ERR_FRIEND_ADD_OK:
            NSAssert(NO, @"We shouldn't be here");
            return NO;
        case TOX_ERR_FRIEND_ADD_NULL:
            code = OCTToxErrorFriendAddUnknown;
            failureReason = @"Unknown error occured";
            break;
        case TOX_ERR_FRIEND_ADD_TOO_LONG:
            code = OCTToxErrorFriendAddTooLong;
            failureReason = @"The message is too long";
            break;
        case TOX_ERR_FRIEND_ADD_NO_MESSAGE:
            code = OCTToxErrorFriendAddNoMessage;
            failureReason = @"No message specified";
            break;
        case TOX_ERR_FRIEND_ADD_OWN_KEY:
            code = OCTToxErrorFriendAddOwnKey;
            failureReason = @"Cannot add own address";
            break;
        case TOX_ERR_FRIEND_ADD_ALREADY_SENT:
            code = OCTToxErrorFriendAddAlreadySent;
            failureReason = @"The request was already sent";
            break;
        case TOX_ERR_FRIEND_ADD_BAD_CHECKSUM:
            code = OCTToxErrorFriendAddBadChecksum;
            failureReason = @"Bad checksum";
            break;
        case TOX_ERR_FRIEND_ADD_SET_NEW_NOSPAM:
            code = OCTToxErrorFriendAddSetNewNospam;
            failureReason = @"The no spam value is outdated";
            break;
        case TOX_ERR_FRIEND_ADD_MALLOC:
            code = OCTToxErrorFriendAddMalloc;
            failureReason = nil;
            break;
    }

    *error = [OCTTox createErrorWithCode:code description:description failureReason:failureReason];

    return YES;
}

- (BOOL)fillError:(NSError **)error withCErrorFriendDelete:(TOX_ERR_FRIEND_DELETE)cError
{
    if (! error || (cError == TOX_ERR_FRIEND_DELETE_OK)) {
        return NO;
    }

    OCTToxErrorFriendDelete code = OCTToxErrorFriendDeleteNotFound;
    NSString *description = @"Cannot delete friend";
    NSString *failureReason = nil;

    switch (cError) {
        case TOX_ERR_FRIEND_DELETE_OK:
            NSAssert(NO, @"We shouldn't be here");
            return NO;
        case TOX_ERR_FRIEND_DELETE_FRIEND_NOT_FOUND:
            code = OCTToxErrorFriendDeleteNotFound;
            failureReason = @"Friend not found";
            break;
    }

    *error = [OCTTox createErrorWithCode:code description:description failureReason:failureReason];

    return YES;
}

- (BOOL)fillError:(NSError **)error withCErrorFriendByPublicKey:(TOX_ERR_FRIEND_BY_PUBLIC_KEY)cError
{
    if (! error || (cError == TOX_ERR_FRIEND_BY_PUBLIC_KEY_OK)) {
        return NO;
    }

    OCTToxErrorFriendByPublicKey code = OCTToxErrorFriendByPublicKeyUnknown;
    NSString *description = @"Cannot get friend by public key";
    NSString *failureReason = nil;

    switch (cError) {
        case TOX_ERR_FRIEND_BY_PUBLIC_KEY_OK:
            NSAssert(NO, @"We shouldn't be here");
            return NO;
        case TOX_ERR_FRIEND_BY_PUBLIC_KEY_NULL:
            code = OCTToxErrorFriendByPublicKeyUnknown;
            failureReason = @"Unknown error occured";
            break;
        case TOX_ERR_FRIEND_BY_PUBLIC_KEY_NOT_FOUND:
            code = OCTToxErrorFriendByPublicKeyNotFound;
            failureReason = @"No friend with the given Public Key exists on the friend list";
            break;
    }

    *error = [OCTTox createErrorWithCode:code description:description failureReason:failureReason];

    return YES;
}

- (BOOL)fillError:(NSError **)error withCErrorFriendGetPublicKey:(TOX_ERR_FRIEND_GET_PUBLIC_KEY)cError
{
    if (! error || (cError == TOX_ERR_FRIEND_GET_PUBLIC_KEY_OK)) {
        return NO;
    }

    OCTToxErrorFriendGetPublicKey code = OCTToxErrorFriendGetPublicKeyFriendNotFound;
    NSString *description = @"Cannot get public key of a friend";
    NSString *failureReason = nil;

    switch (cError) {
        case TOX_ERR_FRIEND_GET_PUBLIC_KEY_OK:
            NSAssert(NO, @"We shouldn't be here");
            return NO;
        case TOX_ERR_FRIEND_GET_PUBLIC_KEY_FRIEND_NOT_FOUND:
            code = OCTToxErrorFriendGetPublicKeyFriendNotFound;
            failureReason = @"Friend not found";
            break;
    }

    *error = [OCTTox createErrorWithCode:code description:description failureReason:failureReason];

    return YES;
}

- (BOOL)fillError:(NSError **)error withCErrorSetInfo:(TOX_ERR_SET_INFO)cError
{
    if (! error || (cError == TOX_ERR_SET_INFO_OK)) {
        return NO;
    }

    OCTToxErrorSetInfoCode code = OCTToxErrorSetInfoCodeUnknow;
    NSString *description = @"Cannot set user info";
    NSString *failureReason = nil;

    switch (cError) {
        case TOX_ERR_SET_INFO_OK:
            NSAssert(NO, @"We shouldn't be here");
            return NO;
        case TOX_ERR_SET_INFO_NULL:
            code = OCTToxErrorSetInfoCodeUnknow;
            failureReason = @"Unknown error occured";
            break;
        case TOX_ERR_SET_INFO_TOO_LONG:
            code = OCTToxErrorSetInfoCodeTooLong;
            failureReason = @"Specified string is too long";
            break;
    }

    *error = [OCTTox createErrorWithCode:code description:description failureReason:failureReason];

    return YES;
}

- (BOOL)fillError:(NSError **)error withCErrorFriendGetLastOnline:(TOX_ERR_FRIEND_GET_LAST_ONLINE)cError
{
    if (! error || (cError == TOX_ERR_FRIEND_GET_LAST_ONLINE_OK)) {
        return NO;
    }

    OCTToxErrorFriendGetLastOnline code;
    NSString *description = @"Cannot get last online of a friend";
    NSString *failureReason = nil;

    switch (cError) {
        case TOX_ERR_FRIEND_GET_LAST_ONLINE_OK:
            NSAssert(NO, @"We shouldn't be here");
            return NO;
        case TOX_ERR_FRIEND_GET_LAST_ONLINE_FRIEND_NOT_FOUND:
            code = OCTToxErrorFriendGetLastOnlineFriendNotFound;
            failureReason = @"Friend not found";
            break;
    }

    *error = [OCTTox createErrorWithCode:code description:description failureReason:failureReason];

    return YES;
}

- (BOOL)fillError:(NSError **)error withCErrorFriendQuery:(TOX_ERR_FRIEND_QUERY)cError
{
    if (! error || (cError == TOX_ERR_FRIEND_QUERY_OK)) {
        return NO;
    }

    OCTToxErrorFriendQuery code = OCTToxErrorFriendQueryUnknown;
    NSString *description = @"Cannot perform friend query";
    NSString *failureReason = nil;

    switch (cError) {
        case TOX_ERR_FRIEND_QUERY_OK:
            NSAssert(NO, @"We shouldn't be here");
            return NO;
        case TOX_ERR_FRIEND_QUERY_NULL:
            code = OCTToxErrorFriendQueryUnknown;
            failureReason = @"Unknown error occured";
            break;
        case TOX_ERR_FRIEND_QUERY_FRIEND_NOT_FOUND:
            code = OCTToxErrorFriendQueryFriendNotFound;
            failureReason = @"Friend not found";
            break;
    }

    *error = [OCTTox createErrorWithCode:code description:description failureReason:failureReason];

    return YES;
}

- (BOOL)fillError:(NSError **)error withCErrorSetTyping:(TOX_ERR_SET_TYPING)cError
{
    if (! error || (cError == TOX_ERR_SET_TYPING_OK)) {
        return NO;
    }

    OCTToxErrorSetTyping code = OCTToxErrorSetTypingFriendNotFound;
    NSString *description = @"Cannot set typing status for a friend";
    NSString *failureReason = nil;

    switch (cError) {
        case TOX_ERR_SET_TYPING_OK:
            NSAssert(NO, @"We shouldn't be here");
            return NO;
        case TOX_ERR_SET_TYPING_FRIEND_NOT_FOUND:
            code = OCTToxErrorSetTypingFriendNotFound;
            failureReason = @"Friend not found";
            break;
    }

    *error = [OCTTox createErrorWithCode:code description:description failureReason:failureReason];

    return YES;
}

- (BOOL)fillError:(NSError **)error withCErrorFriendSendMessage:(TOX_ERR_FRIEND_SEND_MESSAGE)cError
{
    if (! error || (cError == TOX_ERR_FRIEND_SEND_MESSAGE_OK)) {
        return NO;
    }

    OCTToxErrorFriendSendMessage code = OCTToxErrorFriendSendMessageUnknown;
    NSString *description = @"Cannot send message to a friend";
    NSString *failureReason = nil;

    switch (cError) {
        case TOX_ERR_FRIEND_SEND_MESSAGE_OK:
            NSAssert(NO, @"We shouldn't be here");
            return NO;
        case TOX_ERR_FRIEND_SEND_MESSAGE_NULL:
            code = OCTToxErrorFriendSendMessageUnknown;
            failureReason = @"Unknown error occured";
            break;
        case TOX_ERR_FRIEND_SEND_MESSAGE_FRIEND_NOT_FOUND:
            code = OCTToxErrorFriendSendMessageFriendNotFound;
            failureReason = @"Friend not found";
            break;
        case TOX_ERR_FRIEND_SEND_MESSAGE_FRIEND_NOT_CONNECTED:
            code = OCTToxErrorFriendSendMessageFriendNotConnected;
            failureReason = @"Friend not connected";
            break;
        case TOX_ERR_FRIEND_SEND_MESSAGE_SENDQ:
            code = OCTToxErrorFriendSendMessageAlloc;
            failureReason = @"Allocation error";
            break;
        case TOX_ERR_FRIEND_SEND_MESSAGE_TOO_LONG:
            code = OCTToxErrorFriendSendMessageTooLong;
            failureReason = @"Message is too long";
            break;
        case TOX_ERR_FRIEND_SEND_MESSAGE_EMPTY:
            code = OCTToxErrorFriendSendMessageEmpty;
            failureReason = @"Message is empty";
            break;
    }

    *error = [OCTTox createErrorWithCode:code description:description failureReason:failureReason];

    return YES;
}

- (BOOL)fillError:(NSError **)error withCErrorFileControl:(TOX_ERR_FILE_CONTROL)cError
{
    if (! error || (cError == TOX_ERR_FILE_CONTROL_OK)) {
        return NO;
    }

    OCTToxErrorFileControl code;
    NSString *description = @"Cannot send file control to a friend";
    NSString *failureReason = nil;

    switch (cError) {
        case TOX_ERR_FILE_CONTROL_OK:
            NSAssert(NO, @"We shouldn't be here");
            return NO;
        case TOX_ERR_FILE_CONTROL_FRIEND_NOT_FOUND:
            code = OCTToxErrorFileControlFriendNotFound;
            failureReason = @"Friend not found";
            break;
        case TOX_ERR_FILE_CONTROL_FRIEND_NOT_CONNECTED:
            code = OCTToxErrorFileControlFriendNotConnected;
            failureReason = @"Friend is not connected";
            break;
        case TOX_ERR_FILE_CONTROL_NOT_FOUND:
            code = OCTToxErrorFileControlNotFound;
            failureReason = @"No file transfer with given file number found";
            break;
        case TOX_ERR_FILE_CONTROL_NOT_PAUSED:
            code = OCTToxErrorFileControlNotPaused;
            failureReason = @"Resume was send, but file transfer if running normally";
            break;
        case TOX_ERR_FILE_CONTROL_DENIED:
            code = OCTToxErrorFileControlDenied;
            failureReason = @"Cannot resume, file transfer was paused by the other party.";
            break;
        case TOX_ERR_FILE_CONTROL_ALREADY_PAUSED:
            code = OCTToxErrorFileControlAlreadyPaused;
            failureReason = @"File is already paused";
            break;
        case TOX_ERR_FILE_CONTROL_SENDQ:
            code = OCTToxErrorFileControlSendq;
            failureReason = @"Packet queue is full";
            break;
    }

    *error = [OCTTox createErrorWithCode:code description:description failureReason:failureReason];

    return YES;
}

- (BOOL)fillError:(NSError **)error withCErrorFileSeek:(TOX_ERR_FILE_SEEK)cError
{
    if (! error || (cError == TOX_ERR_FILE_SEEK_OK)) {
        return NO;
    }

    OCTToxErrorFileSeek code;
    NSString *description = @"Cannot perform file seek";
    NSString *failureReason = nil;

    switch (cError) {
        case TOX_ERR_FILE_SEEK_OK:
            NSAssert(NO, @"We shouldn't be here");
            return NO;
        case TOX_ERR_FILE_SEEK_FRIEND_NOT_FOUND:
            code = OCTToxErrorFileSeekFriendNotFound;
            failureReason = @"Friend not found";
            break;
        case TOX_ERR_FILE_SEEK_FRIEND_NOT_CONNECTED:
            code = OCTToxErrorFileSeekFriendNotConnected;
            failureReason = @"Friend is not connected";
            break;
        case TOX_ERR_FILE_SEEK_NOT_FOUND:
            code = OCTToxErrorFileSeekNotFound;
            failureReason = @"No file transfer with given file number found";
            break;
        case TOX_ERR_FILE_SEEK_DENIED:
            code = OCTToxErrorFileSeekDenied;
            failureReason = @"File was not in a state where it could be seeked";
            break;
        case TOX_ERR_FILE_SEEK_INVALID_POSITION:
            code = OCTToxErrorFileSeekInvalidPosition;
            failureReason = @"Seek position was invalid";
            break;
        case TOX_ERR_FILE_SEEK_SENDQ:
            code = OCTToxErrorFileSeekSendq;
            failureReason = @"Packet queue is full";
            break;
    }

    *error = [OCTTox createErrorWithCode:code description:description failureReason:failureReason];

    return YES;
}

- (BOOL)fillError:(NSError **)error withCErrorFileGet:(TOX_ERR_FILE_GET)cError
{
    if (! error || (cError == TOX_ERR_FILE_GET_OK)) {
        return NO;
    }

    OCTToxErrorFileGet code;
    NSString *description = @"Cannot get file id";
    NSString *failureReason = nil;

    switch (cError) {
        case TOX_ERR_FILE_GET_OK:
            NSAssert(NO, @"We shouldn't be here");
            return NO;
        case TOX_ERR_FILE_GET_NULL:
            code = OCTToxErrorFileGetInternal;
            failureReason = @"Interval error";
            break;
        case TOX_ERR_FILE_GET_FRIEND_NOT_FOUND:
            code = OCTToxErrorFileGetFriendNotFound;
            failureReason = @"Friend not found";
            break;
        case TOX_ERR_FILE_GET_NOT_FOUND:
            code = OCTToxErrorFileGetNotFound;
            failureReason = @"No file transfer with given file number found";
            break;
    }

    *error = [OCTTox createErrorWithCode:code description:description failureReason:failureReason];

    return YES;
}

- (BOOL)fillError:(NSError **)error withCErrorFileSend:(TOX_ERR_FILE_SEND)cError
{
    if (! error || (cError == TOX_ERR_FILE_SEND_OK)) {
        return NO;
    }

    OCTToxErrorFileSend code;
    NSString *description = @"Cannot send file";
    NSString *failureReason = nil;

    switch (cError) {
        case TOX_ERR_FILE_SEND_OK:
            NSAssert(NO, @"We shouldn't be here");
            return NO;
        case TOX_ERR_FILE_SEND_NULL:
            code = OCTToxErrorFileSendUnknown;
            failureReason = @"Unknown error occured";
            break;
        case TOX_ERR_FILE_SEND_FRIEND_NOT_FOUND:
            code = OCTToxErrorFileSendFriendNotFound;
            failureReason = @"Friend not found";
            break;
        case TOX_ERR_FILE_SEND_FRIEND_NOT_CONNECTED:
            code = OCTToxErrorFileSendFriendNotConnected;
            failureReason = @"Friend not connected";
            break;
        case TOX_ERR_FILE_SEND_NAME_TOO_LONG:
            code = OCTToxErrorFileSendNameTooLong;
            failureReason = @"File name is too long";
            break;
        case TOX_ERR_FILE_SEND_TOO_MANY:
            code = OCTToxErrorFileSendTooMany;
            failureReason = @"Too many ongoing transfers with friend";
            break;
    }

    *error = [OCTTox createErrorWithCode:code description:description failureReason:failureReason];

    return YES;
}

- (BOOL)fillError:(NSError **)error withCErrorFileSendChunk:(TOX_ERR_FILE_SEND_CHUNK)cError
{
    if (! error || (cError == TOX_ERR_FILE_SEND_CHUNK_OK)) {
        return NO;
    }

    OCTToxErrorFileSendChunk code;
    NSString *description = @"Cannot send chunk of file";
    NSString *failureReason = nil;

    switch (cError) {
        case TOX_ERR_FILE_SEND_CHUNK_OK:
            NSAssert(NO, @"We shouldn't be here");
            return NO;
        case TOX_ERR_FILE_SEND_CHUNK_NULL:
            code = OCTToxErrorFileSendChunkUnknown;
            failureReason = @"Unknown error occured";
            break;
        case TOX_ERR_FILE_SEND_CHUNK_FRIEND_NOT_FOUND:
            code = OCTToxErrorFileSendChunkFriendNotFound;
            failureReason = @"Friend not found";
            break;
        case TOX_ERR_FILE_SEND_CHUNK_FRIEND_NOT_CONNECTED:
            code = OCTToxErrorFileSendChunkFriendNotConnected;
            failureReason = @"Friend not connected";
            break;
        case TOX_ERR_FILE_SEND_CHUNK_NOT_FOUND:
            code = OCTToxErrorFileSendChunkNotFound;
            failureReason = @"No file transfer with given file number found";
            break;
        case TOX_ERR_FILE_SEND_CHUNK_NOT_TRANSFERRING:
            code = OCTToxErrorFileSendChunkNotTransferring;
            failureReason = @"Wrong file transferring state";
            break;
        case TOX_ERR_FILE_SEND_CHUNK_INVALID_LENGTH:
            code = OCTToxErrorFileSendChunkInvalidLength;
            failureReason = @"Invalid chunk length";
            break;
        case TOX_ERR_FILE_SEND_CHUNK_SENDQ:
            code = OCTToxErrorFileSendChunkSendq;
            failureReason = @"Packet queue is full";
            break;
        case TOX_ERR_FILE_SEND_CHUNK_WRONG_POSITION:
            code = OCTToxErrorFileSendChunkWrongPosition;
            failureReason = @"Wrong position in file";
            break;
    }

    *error = [OCTTox createErrorWithCode:code description:description failureReason:failureReason];

    return YES;
}

+ (NSError *)createErrorWithCode:(NSUInteger)code
                     description:(NSString *)description
                   failureReason:(NSString *)failureReason
{
    NSMutableDictionary *userInfo = [NSMutableDictionary new];

    if (description) {
        userInfo[NSLocalizedDescriptionKey] = description;
    }

    if (failureReason) {
        userInfo[NSLocalizedFailureReasonErrorKey] = failureReason;
    }

    return [NSError errorWithDomain:kOCTToxErrorDomain code:code userInfo:userInfo];
}

+ (NSString *)binToHexString:(uint8_t *)bin length:(NSUInteger)length
{
    NSMutableString *string = [NSMutableString stringWithCapacity:length];

    for (NSUInteger idx = 0; idx < length; ++idx) {
        [string appendFormat:@"%02X", bin[idx]];
    }

    return [string copy];
}

// You are responsible for freeing the return value!
+ (uint8_t *)hexStringToBin:(NSString *)string
{
    // byte is represented by exactly 2 hex digits, so lenth of binary string
    // is half of that of the hex one. only hex string with even length
    // valid. the more proper implementation would be to check if strlen(hex_string)
    // is odd and return error code if it is. we assume strlen is even. if it's not
    // then the last byte just won't be written in 'ret'.

    char *hex_string = (char *)string.UTF8String;
    size_t i, len = strlen(hex_string) / 2;
    uint8_t *ret = malloc(len);
    char *pos = hex_string;

    for (i = 0; i < len; ++i, pos += 2) {
        sscanf(pos, "%2hhx", &ret[i]);
    }

    return ret;
}

@end

#pragma mark -  Callbacks

void logCallback(Tox *tox,
                 TOX_LOG_LEVEL level,
                 const char *file,
                 uint32_t line,
                 const char *func,
                 const char *message,
                 void *user_data)
{
    switch (level) {
        case TOX_LOG_LEVEL_TRACE:
            OCTLogCCVerbose(@"TRACE: <toxcore: %s:%u, %s> %s", file, line, func, message);
            break;
        case TOX_LOG_LEVEL_DEBUG:
            OCTLogCCDebug(@"DEBUG: <toxcore: %s:%u, %s> %s", file, line, func, message);
            break;
        case TOX_LOG_LEVEL_INFO:
            OCTLogCCInfo(@"INFO: <toxcore: %s:%u, %s> %s", file, line, func, message);
            break;
        case TOX_LOG_LEVEL_WARNING:
            OCTLogCCWarn(@"WARNING: <toxcore: %s:%u, %s> %s", file, line, func, message);
            break;
        case TOX_LOG_LEVEL_ERROR:
            OCTLogCCError(@"ERROR: <toxcore: %s:%u, %s> %s", file, line, func, message);
            break;
    }
}

void connectionStatusCallback(Tox *cTox, TOX_CONNECTION cStatus, void *userData)
{
    OCTTox *tox = (__bridge OCTTox *)(userData);

    OCTToxConnectionStatus status = [tox userConnectionStatusFromCUserStatus:cStatus];

    dispatch_async(dispatch_get_main_queue(), ^{
        OCTLogCInfo(@"connectionStatusCallback with status %lu", tox, (unsigned long)status);

        if ([tox.delegate respondsToSelector:@selector(tox:connectionStatus:)]) {
            [tox.delegate tox:tox connectionStatus:status];
        }
    });
}

void friendNameCallback(Tox *cTox, uint32_t friendNumber, const uint8_t *cName, size_t length, void *userData)
{
    OCTTox *tox = (__bridge OCTTox *)(userData);

    NSString *name = [NSString stringWithCString:(const char *)cName encoding:NSUTF8StringEncoding];

    dispatch_async(dispatch_get_main_queue(), ^{
        OCTLogCInfo(@"nameChangeCallback with name %@, friend number %d", tox, name, friendNumber);

        if ([tox.delegate respondsToSelector:@selector(tox:friendNameUpdate:friendNumber:)]) {
            [tox.delegate tox:tox friendNameUpdate:name friendNumber:friendNumber];
        }
    });
}

void friendStatusMessageCallback(Tox *cTox, uint32_t friendNumber, const uint8_t *cMessage, size_t length, void *userData)
{
    OCTTox *tox = (__bridge OCTTox *)(userData);

    NSString *message = [NSString stringWithCString:(const char *)cMessage encoding:NSUTF8StringEncoding];

    dispatch_async(dispatch_get_main_queue(), ^{
        OCTLogCInfo(@"statusMessageCallback with status message %@, friend number %d", tox, message, friendNumber);

        if ([tox.delegate respondsToSelector:@selector(tox:friendStatusMessageUpdate:friendNumber:)]) {
            [tox.delegate tox:tox friendStatusMessageUpdate:message friendNumber:friendNumber];
        }
    });
}

void friendStatusCallback(Tox *cTox, uint32_t friendNumber, TOX_USER_STATUS cStatus, void *userData)
{
    OCTTox *tox = (__bridge OCTTox *)(userData);

    OCTToxUserStatus status = [tox userStatusFromCUserStatus:cStatus];

    dispatch_async(dispatch_get_main_queue(), ^{
        OCTLogCInfo(@"userStatusCallback with status %lu, friend number %d", tox, (unsigned long)status, friendNumber);

        if ([tox.delegate respondsToSelector:@selector(tox:friendStatusUpdate:friendNumber:)]) {
            [tox.delegate tox:tox friendStatusUpdate:status friendNumber:friendNumber];
        }
    });
}

void friendConnectionStatusCallback(Tox *cTox, uint32_t friendNumber, TOX_CONNECTION cStatus, void *userData)
{
    OCTTox *tox = (__bridge OCTTox *)(userData);

    OCTToxConnectionStatus status = [tox userConnectionStatusFromCUserStatus:cStatus];

    OCTLogCInfo(@"connectionStatusCallback with status %lu, friendNumber %d", tox, (unsigned long)status, friendNumber);

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([tox.delegate respondsToSelector:@selector(tox:friendConnectionStatusChanged:friendNumber:)]) {
            [tox.delegate tox:tox friendConnectionStatusChanged:status friendNumber:friendNumber];
        }
    });
}

void friendTypingCallback(Tox *cTox, uint32_t friendNumber, bool isTyping, void *userData)
{
    OCTTox *tox = (__bridge OCTTox *)(userData);

    OCTLogCInfo(@"typingChangeCallback with isTyping %d, friend number %d", tox, isTyping, friendNumber);

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([tox.delegate respondsToSelector:@selector(tox:friendIsTypingUpdate:friendNumber:)]) {
            [tox.delegate tox:tox friendIsTypingUpdate:(BOOL)isTyping friendNumber:friendNumber];
        }
    });
}

void friendReadReceiptCallback(Tox *cTox, uint32_t friendNumber, uint32_t messageId, void *userData)
{
    OCTTox *tox = (__bridge OCTTox *)(userData);

    OCTLogCInfo(@"readReceiptCallback with message id %d, friendNumber %d", tox, messageId, friendNumber);

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([tox.delegate respondsToSelector:@selector(tox:messageDelivered:friendNumber:)]) {
            [tox.delegate tox:tox messageDelivered:messageId friendNumber:friendNumber];
        }
    });
}

void friendRequestCallback(Tox *cTox, const uint8_t *cPublicKey, const uint8_t *cMessage, size_t length, void *userData)
{
    OCTTox *tox = (__bridge OCTTox *)(userData);

    NSString *publicKey = [OCTTox binToHexString:(uint8_t *)cPublicKey length:TOX_PUBLIC_KEY_SIZE];
    NSString *message = [[NSString alloc] initWithBytes:cMessage length:length encoding:NSUTF8StringEncoding];

    dispatch_async(dispatch_get_main_queue(), ^{
        OCTLogCInfo(@"friendRequestCallback with publicKey %@, message %@", tox, publicKey, message);

        if ([tox.delegate respondsToSelector:@selector(tox:friendRequestWithMessage:publicKey:)]) {
            [tox.delegate tox:tox friendRequestWithMessage:message publicKey:publicKey];
        }
    });
}

void friendMessageCallback(
    Tox *cTox,
    uint32_t friendNumber,
    TOX_MESSAGE_TYPE cType,
    const uint8_t *cMessage,
    size_t length,
    void *userData)
{
    OCTTox *tox = (__bridge OCTTox *)(userData);

    // HINT: invalid UTF-8 will make realm manager crash later, or if length is shorter than bytes in cMessage
    // so check at least for NULL bytes and shorten length accordingly

    uint8_t *newcMessage = calloc(1, length + 1);
    if (!newcMessage)
    {
        // HINT: we cant allocate the new buffer, so we must ignore this incoming message
        return;
    }

    size_t newLength = 0;
    for (int i=0; i < length; i++)
    {
        if (*(cMessage + i) != 0)
        {
            newLength++;
        }
        else
        {
            break;
        }
    }

    memcpy(newcMessage, cMessage, (size_t)newLength);

    // add 1 for the NULL byte at the end
    newLength++;

    if (newLength < 2)
    {
        // HINT: message seems to contain nothing before the first NULL byte, so discard it
        free(newcMessage);
        return;
    }

    NSString *message = [[NSString alloc] initWithBytes:newcMessage length:newLength encoding:NSUTF8StringEncoding];
    free(newcMessage);

    if (!message)
    {
        // HINT: message seems to contain invalid UTF-8
        //       instead use a dummy message "__"
        message = @"__";
        newLength = 2;
    }


    // HINT: msgV3 ------------------------------------------------
    // HINT: msgV3 ------------------------------------------------
    // HINT: msgV3 ------------------------------------------------
    int need_free = 0;
    uint32_t msgv3_timstamp_int = 0;
    char *message_v3_hash_hexstr = NULL;

    if ((cMessage) && (length > (TOX_MSGV3_MSGID_LENGTH + TOX_MSGV3_TIMESTAMP_LENGTH + TOX_MSGV3_GUARD)))
    {
        int pos = length - (TOX_MSGV3_MSGID_LENGTH + TOX_MSGV3_TIMESTAMP_LENGTH + TOX_MSGV3_GUARD);

        // bytes at guard position
        uint8_t g1 = *(cMessage + pos);
        uint8_t g2 = *(cMessage + pos + 1);

        // check for the msgv3 guard
        if ((g1 == 0) && (g2 == 0))
        {
            uint8_t *message_v3_hash_bin = calloc(1, TOX_MSGV3_MSGID_LENGTH);
            if (!message_v3_hash_bin)
            {
                OCTLogCInfo(@"friendMessageCallback:friend_message_cb:could not allocate buffer for hash: incoming message discarded", tox);
                return;
            }

            uint8_t *message_v3_timestamp_bin = calloc(1, TOX_MSGV3_TIMESTAMP_LENGTH);
            if (!message_v3_timestamp_bin)
            {
                OCTLogCInfo(@"friendMessageCallback:friend_message_cb:could not allocate buffer for timestamp: incoming message discarded", tox);
                free(message_v3_hash_bin);
                return;
            }

            need_free = 1;
            memcpy(message_v3_hash_bin, (cMessage + pos + TOX_MSGV3_GUARD), TOX_MSGV3_MSGID_LENGTH);
            memcpy(message_v3_timestamp_bin, (cMessage + pos + TOX_MSGV3_GUARD + TOX_MSGV3_MSGID_LENGTH), TOX_MSGV3_TIMESTAMP_LENGTH);

            message_v3_hash_hexstr = calloc(1, (TOX_MSGV3_MSGID_LENGTH * 2) + 1);
            if (message_v3_hash_hexstr)
            {
                bin_to_hex((const char *)message_v3_hash_bin, (size_t)TOX_MSGV3_MSGID_LENGTH, message_v3_hash_hexstr);
                const uint8_t *p = (uint8_t *)(message_v3_timestamp_bin);
                p += xnet_unpack_u32(p, &msgv3_timstamp_int);
                // OCTLogCInfo(@"mmm:friendMessageCallback:friend_message_cb:hash=%s ts=%d", tox, message_v3_hash_hexstr, msgv3_timstamp_int);
            }

            if (need_free == 1)
            {
                free(message_v3_hash_bin);
                free(message_v3_timestamp_bin);
            }
        }
    }
    // HINT: msgV3 ------------------------------------------------
    // HINT: msgV3 ------------------------------------------------
    // HINT: msgV3 ------------------------------------------------

    NSString *msgv3HashHexStr = nil;
    if (message_v3_hash_hexstr)
    {
        msgv3HashHexStr = [[NSString alloc] initWithBytes:message_v3_hash_hexstr length:(TOX_MSGV3_MSGID_LENGTH * 2) encoding:NSUTF8StringEncoding];
        free(message_v3_hash_hexstr);
        OCTLogCInfo(@"friendMessageCallback with friend message %@", tox, msgv3HashHexStr);
    }

    if (cType == TOX_MESSAGE_TYPE_HIGH_LEVEL_ACK)
    {
        // HINT: this message is not a normal message, but a msgV3 high level ACK.
        //       we do not save it in the database, nor show it in the chat window.
        if (msgv3HashHexStr != nil)
        {
            // HINT: set isDelivered status to true for the message with this hex hash.

            dispatch_async(dispatch_get_main_queue(), ^{
                OCTLogCInfo(@"friendMessageCallback received level ACK %@", tox, msgv3HashHexStr);

                if ([tox.delegate respondsToSelector:@selector(tox:friendHighLevelACK:friendNumber:msgv3HashHex:sendTimestamp:)]) {
                    [tox.delegate tox:tox friendHighLevelACK:message friendNumber:friendNumber
                                msgv3HashHex:msgv3HashHexStr sendTimestamp:msgv3_timstamp_int];
                }
            });

        }

        return;
    }
    else
    {
        if (msgv3HashHexStr != nil)
        {
            // HINT: msgV3 message reveived
            // friend must have msgV3 capability, set it in the database
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([tox.delegate respondsToSelector:@selector(tox:friendSetMsgv3Capability:friendNumber:)]) {
                    [tox.delegate tox:tox friendSetMsgv3Capability:YES friendNumber:friendNumber];
                }
                OCTLogCInfo(@"friendMessageCallback msgV3 YES", tox);
            });
        }
        else
        {
            // HINT: old msg version recevied
            // friend does not msgV3 capability, clear it in the database
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([tox.delegate respondsToSelector:@selector(tox:friendSetMsgv3Capability:friendNumber:)]) {
                    [tox.delegate tox:tox friendSetMsgv3Capability:NO friendNumber:friendNumber];
                }
                OCTLogCInfo(@"friendMessageCallback msgV3 --NO--", tox);
            });
        }

        OCTToxMessageType type = [tox messageTypeFromCMessageType:cType];

        dispatch_async(dispatch_get_main_queue(), ^{
            // OCTLogCInfo(@"friendMessageCallback with message %@, friend number %d", tox, message, friendNumber);
            // OCTLogCInfo(@"friendMessageCallback with friend number %d len %d newlen %d", tox, friendNumber, length, newLength);
            // OCTLogCInfo(@"friendMessageCallback with friend message %@", tox, msgv3HashHexStr);

            // HINT: save message to database
            if ([tox.delegate respondsToSelector:@selector(tox:friendMessage:type:friendNumber:msgv3HashHex:sendTimestamp:)]) {
                [tox.delegate tox:tox friendMessage:message type:type friendNumber:friendNumber
                            msgv3HashHex:msgv3HashHexStr sendTimestamp:msgv3_timstamp_int];
            }

            // HINT: now send msgV3 high level ACK
            if ([tox.delegate respondsToSelector:@selector(tox:sendFriendHighlevelACK:friendNumber:msgv3HashHex:sendTimestamp:)]) {
                NSString *message = @"_";
                [tox.delegate tox:tox sendFriendHighlevelACK:message friendNumber:friendNumber
                            msgv3HashHex:msgv3HashHexStr sendTimestamp:msgv3_timstamp_int];
            }

        });
    }
}

void friendLosslessPacketCallback(
    Tox *cTox,
    uint32_t friendNumber,
    const uint8_t *data,
    size_t length,
    void *userData)
{
    if ((length <= 5) || (length >= 300)) {
        return;
    }

    OCTTox *tox = (__bridge OCTTox *)(userData);

    // TODO: catch errors and bad utf-8 here!
    NSData *lossless_bytes = [NSData dataWithBytes:data length:length];

    if (lossless_bytes == nil) {
        return;
    }

    NSString *pushTokenString = nil;

    if ((length > 5) && (length < 300)) {
        if (data[0] == 181) {
            pushTokenString = [[NSString alloc] initWithUTF8String:(data + 1)];
        } else {
            return;
        }
    } else {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        // OCTLogCInfo(@"friendLosslessPacketCallback with lossless data %@, friend number %d",
        //            tox, [lossless_bytes description], friendNumber);
        // OCTLogCInfo(@"friendLosslessPacketCallback with pushTokenString %@, friend number %d",
        //            tox, [pushTokenString description], friendNumber);

        if ([tox.delegate respondsToSelector:@selector(tox:friendPushTokenUpdate:friendNumber:)]) {
            [tox.delegate tox:tox friendPushTokenUpdate:pushTokenString friendNumber:friendNumber];
        }
    });
}

void fileReceiveControlCallback(Tox *cTox, uint32_t friendNumber, OCTToxFileNumber fileNumber, TOX_FILE_CONTROL cControl, void *userData)
{
    OCTTox *tox = (__bridge OCTTox *)(userData);

    OCTToxFileControl control = [tox fileControlFromCFileControl:cControl];

    dispatch_async(dispatch_get_main_queue(), ^{
        OCTLogCInfo(@"fileReceiveControlCallback with friendNumber %d fileNumber %d controlType %lu",
                    tox, friendNumber, fileNumber, (unsigned long)control);

        if ([tox.delegate respondsToSelector:@selector(tox:fileReceiveControl:friendNumber:fileNumber:)]) {
            [tox.delegate tox:tox fileReceiveControl:control friendNumber:friendNumber fileNumber:fileNumber];
        }
    });
}

void fileChunkRequestCallback(Tox *cTox, uint32_t friendNumber, OCTToxFileNumber fileNumber, uint64_t position, size_t length, void *userData)
{
    OCTTox *tox = (__bridge OCTTox *)(userData);

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([tox.delegate respondsToSelector:@selector(tox:fileChunkRequestForFileNumber:friendNumber:position:length:)]) {
            [tox.delegate tox:tox fileChunkRequestForFileNumber:fileNumber
                 friendNumber:friendNumber
                     position:position
                       length:length];
        }
    });
}

void fileReceiveCallback(
    Tox *cTox,
    uint32_t friendNumber,
    OCTToxFileNumber fileNumber,
    TOX_FILE_KIND cKind,
    uint64_t fileSize,
    const uint8_t *cFileName,
    size_t fileNameLength,
    void *userData)
{
    OCTTox *tox = (__bridge OCTTox *)(userData);

    OCTToxFileKind kind;

    switch (cKind) {
        case TOX_FILE_KIND_DATA:
            kind = OCTToxFileKindData;
            break;
        case TOX_FILE_KIND_AVATAR:
            kind = OCTToxFileKindAvatar;
            break;
    }

    NSString *fileName = [[NSString alloc] initWithBytes:cFileName length:fileNameLength encoding:NSUTF8StringEncoding];

    dispatch_async(dispatch_get_main_queue(), ^{
        OCTLogCInfo(@"fileReceiveCallback with friendNumber %d fileNumber %d kind %ld fileSize %llu fileName %@",
                    tox, friendNumber, fileNumber, (long)kind, fileSize, fileName);

        if ([tox.delegate respondsToSelector:@selector(tox:fileReceiveForFileNumber:friendNumber:kind:fileSize:fileName:)]) {
            [tox.delegate tox:tox fileReceiveForFileNumber:fileNumber
                 friendNumber:friendNumber
                         kind:kind
                     fileSize:fileSize
                     fileName:fileName];
        }
    });
}

void fileReceiveChunkCallback(
    Tox *cTox,
    uint32_t friendNumber,
    OCTToxFileNumber fileNumber,
    uint64_t position,
    const uint8_t *cData,
    size_t length,
    void *userData)
{
    OCTTox *tox = (__bridge OCTTox *)(userData);

    NSData *chunk = nil;

    if (length) {
        chunk = [NSData dataWithBytes:cData length:length];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([tox.delegate respondsToSelector:@selector(tox:fileReceiveChunk:fileNumber:friendNumber:position:)]) {
            [tox.delegate tox:tox fileReceiveChunk:chunk fileNumber:fileNumber friendNumber:friendNumber position:position];
        }
    });
}
