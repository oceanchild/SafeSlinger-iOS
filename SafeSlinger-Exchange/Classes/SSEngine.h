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

#import <Foundation/Foundation.h>
#import "SafeSlingerDB.h"
#import "Config.h"

typedef enum KeyType {
	ENC_PRI = 0,
	SIGN_PRI
}KeyType;

@interface SSEngine : NSObject 

+(NSData*) BuildCipher:(NSString*)username Token:(NSString*)token Message:(NSString*)Message Attach:(NSString*)FileName RawFile:(NSData*)rawFile MIMETYPE:(NSString*)MimeType Cipher:(NSMutableData*)cipher;

// Key Generation API
+(BOOL)checkCredentialExist;
+(BOOL)GenKeyPairForENC;
+(BOOL)GenKeyPairForSIGN;
+(int)GenRSAKey: (int)bits withPubkey: (NSString*)pubpath withPrivKey: (NSString*)pripath;

// block cipher and hmac for message and files
+(NSData*)GenRandomAESKey;
+(NSData*)AESEncrypt: (NSData*)plain withAESKey: (NSData*)secret;
+(NSData*)AESDecrypt: (NSData*)cipher withAESKey: (NSData*)secret withPlen: (int)lengthOfPlain;

// public key cryptography
+(NSString*)getSelfPrivateKeyPath: (int)keytype;

+(NSData*)Encrypt: (NSString*)pubkeyData keysize:(int)bits withData:(NSData*)text;
+(BOOL)Verify: (NSString*)pubkeyData keySize:(int)bits withSig:(NSData*)sig withtext: (NSData*)text;
+(NSData*)Decrypt: (const char*)keypath withData:(NSData*)cipher withPrikey:(NSData*)keybytes;
+(NSData*)Sign: (const char*)keypath withData:(NSData*)text withPrikey:(NSData*)keybytes;

// Key information retrieve
+(NSString*)getSelfKeyID;
+(NSString*)getSelfGenKeyDate;
+(NSData*)getPackPubKeys;
+(NSData*)getPubKey: (BOOL)EncryptOrSign;

+(BOOL)TestPassPhase: (NSString*)Passphase KeySize1:(int)plen1 KeySize2:(int)plen2;
+(NSData*)UnlockPrivateKey: (NSString*)Passphase Size:(int)plen Type:(int)keytype;
+(void)LockPrivateKeys: (NSString*)Passphase RawData:(NSData*)plaintext Type:(int)keytype;
+(int)getSelfPrivateKeySize: (int)keytype;

// Packet Unpacking and packing
+(NSString*)ExtractKeyID: (NSData*)packet;
+(NSData*)PackMessage:(NSData*)plain PubKey:(NSString*)puk Prikey:(NSData*)pri;
+(NSData*)UnpackMessage:(NSData*)cipher PubKey:(NSString*)puk Prikey:(NSData*)pri;

@end


