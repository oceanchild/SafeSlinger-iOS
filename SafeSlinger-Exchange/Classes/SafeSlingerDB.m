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

#import "SafeSlingerDB.h"
#import "Base64.h"
#import "SSContactSelector.h"
#import "Utility.h"
#import "ErrorLogger.h"

@implementation FileInfo
@synthesize FName, FSize, FExt;

-(void)dealloc{
    if(FName)[FName release]; FName = nil;
    if(FExt)[FExt release]; FExt = nil;
    [super dealloc];
}

@end

@implementation MsgEntry

@synthesize msgid, cTime, rTime, attach, smsg, sfile, fext, face;
@synthesize dir, token, sender, msgbody, fname, fbody;


-(MsgEntry*)initPlainTextMessage: (NSData*)newmsgid UserName:(NSString*)uname Token:(NSString*)tokenstr Message:(NSString*)message Photo:(NSString*)encodePhoto FileName:(NSString*)File FileType:(NSString*)MimeType FIleData:(NSData*)FileRaw
{
    // msgid
    self.msgid = newmsgid;
    self.dir = 1;
    self.sender = uname;
    self.token = tokenstr;
    self.rTime = self.cTime = [NSString GetGMTString:DATABASE_TIMESTR];
    
    if([message length]>0) self.msgbody = [message dataUsingEncoding:NSUTF8StringEncoding];
    else self.msgbody = nil;
    
    self.attach = ((File==nil) ? 0 : 1);
    self.smsg = self.sfile = Decrypted;
    
    self.face = encodePhoto;
    
    if(File)
    {
        self.fname = File;
        self.fbody = FileRaw;
        self.fext = MimeType;
    }
    return self;
}

-(MsgEntry*)initSecureMessage: (NSData*)newmsgid UserName:(NSString*)uname Token:(NSString*)tokenstr Message:(NSData*)cipher SecureM:(int)mflag SecureF:(int)fflag
{
    // msgid
    self.msgid = newmsgid;
    self.dir = 0;
    self.rTime = self.cTime = [NSString GetGMTString:DATABASE_TIMESTR];
    
    self.sender = uname;
    self.token = tokenstr;
    self.msgbody = [cipher retain];
    self.smsg = mflag;
    self.sfile = fflag;
    // not decided yet, set it as no file as default
    self.attach = 0;
    self.face = nil;
    
    return self;
}


-(void)dealloc{
     if(msgid)[msgid release]; msgid = nil;
     if(cTime)[cTime release]; cTime = nil;
     if(token)[token release]; token = nil;
     if(sender)[sender release]; sender = nil;
     if(msgbody)[msgbody release]; msgbody = nil;
     if(fname)[fname release]; fname = nil;
     if(fbody)[fbody release]; fbody = nil;
     if(fext)[fext release]; fext = nil;
     if(face)[face release]; face = nil;
     [super dealloc];
}

@end

@implementation MsgListEntry
@synthesize username, token, lastSeen, messagecount, ciphercount;
@end

@implementation SafeSlingerDB

// private method
- (BOOL) LoadDBFromStorage : (NSString*)specific_path
{
    BOOL success = YES;
	@try{
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *error;
        NSString *writableDBPath = nil;
        if(specific_path) writableDBPath = specific_path;
        else writableDBPath = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent: DATABASE_NAME];
        
        if (![fileManager fileExistsAtPath:writableDBPath])
        {
            // The writable database does not exist, so copy the default to the appropriate location.
            NSString *defaultDBPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:DATABASE_NAME];
            if (![fileManager copyItemAtPath:defaultDBPath toPath:writableDBPath error:&error]) {
                [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Failed to create writable database file with message '%@'.", [error localizedDescription]]];
                success = NO;
            }
        }
        if(!(sqlite3_open([writableDBPath UTF8String], &db) == SQLITE_OK)){
            [ErrorLogger ERRORDEBUG:@"ERROR: Unable to open database."];
            success = NO;
        }
    }@catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: An exception occured, %@", [exception reason]]];
        success = NO;
    }@finally {
        return success;
    }
}

- (BOOL)TrimTable: (NSString*)table_name
{
    if(db==nil){
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return NO;
    }
    
    BOOL ret = YES;
    @try {
        
        sqlite3_stmt *sqlStatement;
        const char *sql = [[NSString stringWithFormat:@"DELETE FROM %@", table_name]cStringUsingEncoding:NSASCIIStringEncoding];
        
        if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while creating statement. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        if(SQLITE_DONE != sqlite3_step(sqlStatement)){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while deleting table. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            ret = NO;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: An exception occured, %@", [exception reason]]];
        ret = NO;
    }
    @finally {
        return ret;
    }
}

- (BOOL)RemoveConfigTag:(NSString*)tag
{
    if((db==nil)||(tag==nil)){
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or input is null."];
        return NO;
    }
    
    BOOL ret = YES;
    @try {
        sqlite3_stmt *sqlStatement;
        const char *sql = "DELETE FROM configs WHERE item_key=?;";
        
        if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat: @"ERROR: Error while preparing statement. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        // bind item_key
        sqlite3_bind_text(sqlStatement, 1, [tag UTF8String], -1, SQLITE_TRANSIENT);
        if (sqlite3_step(sqlStatement) == SQLITE_ERROR) {
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat: @"ERROR: Error while deleting data. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            ret = NO;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: An exception occured, %@", [exception reason]]];
        ret = NO;
    }
    @finally {
        return ret;
    }
}

- (BOOL)InsertOrUpdateConfig: (NSData*)value withTag:(NSString*)tag
{
    if((db==nil)||(tag==nil)){
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or input is null."];
        return NO;
    }
    
    BOOL ret = YES;
    BOOL exist = NO;
    
    @try {
        sqlite3_stmt *sqlStatement;
        const char *sql = "SELECT COUNT(*) FROM configs WHERE item_key=?;";
        
        if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat: @"ERROR: Error while preparing statement. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        // bind item_key
        sqlite3_bind_text(sqlStatement, 1, [tag UTF8String], -1, SQLITE_TRANSIENT);
        if (sqlite3_step(sqlStatement) == SQLITE_ERROR) {
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat: @"ERROR: Error while query data. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        } else {
            if(sqlite3_column_int(sqlStatement, 0)>0) exist = YES;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            ret = NO;
        }
        
        if(exist)
        {
            sql = "update configs set item_value=? WHERE item_key=?;";
        }else{
            sql = "insert into configs (item_value, item_key) Values (?,?);";
        }
        
        if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat: @"Error while creating add statement. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        //item_value
        if(value)
            sqlite3_bind_blob(sqlStatement, 1, [value bytes], [value length], SQLITE_TRANSIENT);
        else
            sqlite3_bind_null(sqlStatement, 1);
        //item_key
        sqlite3_bind_text(sqlStatement, 2, [tag UTF8String], -1, SQLITE_TRANSIENT);
        
        if(SQLITE_DONE != sqlite3_step(sqlStatement)){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat: @"ERROR: Error while inserting data. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            ret = NO;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: An exception occured, %@", [exception reason]]];
        ret = NO;
    }
    @finally {
        return ret;
    }
}


- (NSData*)GetConfig: (NSString*)tag
{
    if((db==nil)||(tag==nil))
    {
        [ErrorLogger ERRORDEBUG:@"ERROR: DB Object is null or input is null."];
        return nil;
    }
    
    NSData* value = nil;
    @try {
        const char *sql = "SELECT item_value FROM configs where item_key = ?";
        sqlite3_stmt *sqlStatement;
        if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK)
        {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Problem with prepare statement: %s", sql]];
        }
        
        sqlite3_bind_text(sqlStatement, 1, [tag UTF8String], -1, SQLITE_TRANSIENT);
        
        if (sqlite3_step(sqlStatement)==SQLITE_ROW) {
            int rawLen = sqlite3_column_bytes(sqlStatement, 0);
            if(rawLen>0)
                value = [NSData dataWithBytes:sqlite3_column_blob(sqlStatement, 0) length:rawLen];
        }
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement."];
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: An exception occured, %@", [exception reason]]];
        if(value) [value release];
        value = nil;
    }
    @finally {
        return value;
    }
    
}

- (NSData*)QueryInMsgTableByMsgID: (NSData*)MSGID Field:(NSString*)FIELD
{
    if(db==nil||MSGID==nil||FIELD==nil)
    {
        [ErrorLogger ERRORDEBUG:@"ERROR: DB Object is null or input is null."];
        return nil;
    }
    NSData* queryterm = nil;
    @try {
        
        NSString* sqlstr = [NSString stringWithFormat:@"SELECT %@ FROM msgtable WHERE msgid = ?;", FIELD];
        const char *sql = [sqlstr UTF8String];
        
        sqlite3_stmt *sqlStatement;
        if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK)
        {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Problem with prepare statement: %s", sql]];
            return nil;
        }
        
        sqlite3_bind_blob(sqlStatement, 1, [MSGID bytes], [MSGID length], SQLITE_TRANSIENT);
        if (sqlite3_step(sqlStatement)==SQLITE_ROW) {
            if(sqlite3_column_type(sqlStatement, 0)==SQLITE_TEXT)
            {
                // string term
                queryterm = [[NSString stringWithUTF8String:(char*)sqlite3_column_text(sqlStatement, 0)] dataUsingEncoding:NSUTF8StringEncoding];
            }else if(sqlite3_column_type(sqlStatement, 0)==SQLITE_BLOB)
            {
                // data term
                int rawLen = sqlite3_column_bytes(sqlStatement, 0);
                if(rawLen>0) {
                    queryterm = [NSData dataWithBytes:sqlite3_column_blob(sqlStatement, 0) length:rawLen];
                }
            }
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement."];
        }
    }
    @catch (NSException *exception) {
        
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: An exception occured, %@", [exception reason]]];
        if(queryterm)[queryterm release];
        queryterm = nil;
    }
    @finally {
        return queryterm;
    }
}

- (NSString*)QueryStringInTokenTableByKeyID:(NSString*)KEYID Field:(NSString*)FIELD
{
    if(db==nil||KEYID==nil||FIELD==nil){
        [ErrorLogger ERRORDEBUG:@"ERROR: DB Object is null or input is null."];
        return nil;
    }
    NSString* queryterm = nil;
    @try {
        sqlite3_stmt *sqlStatement;
        NSString* sqlstr = [NSString stringWithFormat:@"SELECT %@ FROM tokenstore WHERE keyid=? ORDER BY pstamp", FIELD];
        const char *sql = [sqlstr UTF8String];
        
        if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) == SQLITE_OK){
            sqlite3_bind_blob(sqlStatement, 1, [KEYID cStringUsingEncoding:NSUTF8StringEncoding], [KEYID lengthOfBytesUsingEncoding:NSUTF8StringEncoding], SQLITE_TRANSIENT);
            
            // get newest one
            if (sqlite3_step(sqlStatement)==SQLITE_ROW)
            {
                if(sqlite3_column_type(sqlStatement, 0)!=SQLITE_NULL)
                {
                    queryterm = [NSString stringWithUTF8String:(char*)sqlite3_column_text(sqlStatement, 0)];
                }
            }
            if(sqlite3_finalize(sqlStatement) != SQLITE_OK)[ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
        }else
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while creating statement. '%s'", sqlite3_errmsg(db)]];
    }
    @catch (NSException *exception) {
        
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: An exception occured, %@", [exception reason]]];
        if(queryterm)[queryterm release];
        queryterm = nil;
    }
    @finally {
        return queryterm;
    }
}

- (NSString*)QueryStringInTokenTableByToken: (NSString*)TOKEN Field:(NSString*)FIELD
{
    if(db==nil||TOKEN==nil||FIELD==nil){
        [ErrorLogger ERRORDEBUG:@"ERROR: DB Object is null or input is null."];
        return nil;
    }
    NSString* queryterm = nil;
    @try {
        sqlite3_stmt *sqlStatement;
        NSString* sqlstr = [NSString stringWithFormat:@"SELECT %@ FROM tokenstore WHERE ptoken=? ORDER BY pstamp", FIELD];
        const char *sql = [sqlstr UTF8String];
        
        if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) == SQLITE_OK){
            sqlite3_bind_text(sqlStatement, 1, [TOKEN UTF8String], -1, SQLITE_TRANSIENT);
            // get newest one
            if (sqlite3_step(sqlStatement)==SQLITE_ROW)
            {
                if(sqlite3_column_type(sqlStatement, 0)!=SQLITE_NULL)
                {
                    queryterm = [NSString stringWithUTF8String:(char*)sqlite3_column_text(sqlStatement, 0)];
                }
            }
            if(sqlite3_finalize(sqlStatement) != SQLITE_OK)[ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
        }else
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while creating statement. '%s'", sqlite3_errmsg(db)]];
    }
    @catch (NSException *exception) {
        
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: An exception occured, %@", [exception reason]]];
        if(queryterm)[queryterm release];
        queryterm = nil;
    }
    @finally {
        return queryterm;
    }
}


-(NSString*)GetRawKeyByToken: (NSString*)RecipientToken
{
    if(db==nil||RecipientToken==nil)
    {
        [ErrorLogger ERRORDEBUG:@"ERROR: DB Object is null or input is null."];
        return nil;
    }
    
    NSString *pubkey = nil;
    @try {
        // get the newest term
        const char *sql = "SELECT pkey FROM tokenstore WHERE ptoken=?";
        sqlite3_stmt *sqlStatement;
        if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) == SQLITE_OK)
        {
            // keyid
            sqlite3_bind_text(sqlStatement, 1, [RecipientToken cStringUsingEncoding:NSUTF8StringEncoding], -1, SQLITE_TRANSIENT);
            if (sqlite3_step(sqlStatement)==SQLITE_ROW) {
                if(sqlite3_column_type(sqlStatement, 0)!=SQLITE_NULL)
                {
                    pubkey = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 0)];
                }
            }
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK)
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
        }else
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Problem with prepare statement: %s", sql]];
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        if(pubkey)[pubkey release];
        pubkey = nil;
    }
    @finally {
        return pubkey;
    }
}

- (int)GetDEVTypeByToken: (NSString*)RecipientToken
{
    if(db==nil||RecipientToken==nil)
    {
        [ErrorLogger ERRORDEBUG:@"ERROR: DB Object is null or input is null."];
        return -1;
    }
    
    int dev = -1;
    @try {
        // get the newest key
        const char *sql = "select dev from tokenstore where ptoken=?;";
        sqlite3_stmt *sqlStatement;
        if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK)
        {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Problem with prepare statement: %s", sql]];
            dev = -1;
        }
        
        //token
        sqlite3_bind_text(sqlStatement, 1, [RecipientToken UTF8String], -1, SQLITE_TRANSIENT);
        
        if (sqlite3_step(sqlStatement)==SQLITE_ROW) {
            dev = sqlite3_column_int(sqlStatement, 0);
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            dev = -1;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        dev = -1;
    }
    @finally {
        return dev;
    }
}

- (int)GetEXTypeByToken: (NSString*)RecipientToken
{    
    if(db==nil||RecipientToken==nil)
    {
        [ErrorLogger ERRORDEBUG:@"ERROR: DB Object is null or input is null."];
        return -1;
    }
    
    int ex_type = -1;
    @try {
        // get the newest key
        const char *sql = "select ex_type from tokenstore where ptoken=?;";
        sqlite3_stmt *sqlStatement;
        if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK)
        {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Problem with prepare statement: %s", sql]];
        }
        
        //token
        sqlite3_bind_text(sqlStatement, 1, [RecipientToken UTF8String], -1, SQLITE_TRANSIENT);
        
        while (sqlite3_step(sqlStatement)==SQLITE_ROW) {
            ex_type = sqlite3_column_int(sqlStatement, 0);
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            ex_type = -1;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        ex_type = -1;
    }
    @finally {
        return ex_type;
    }
}

- (BOOL)RemoveRecipient: (NSString*)RecipientToken
{
    if(db==nil){
        [ErrorLogger ERRORDEBUG:@"ERROR: DB Object is null or input is null."];
        return NO;
    }
    
    BOOL ret = YES;
    @try {
        
        sqlite3_stmt *sqlStatement;
        const char *sql = "DELETE FROM tokenstore WHERE ptoken=?";
        // first , remove toekn from token store
        if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while creating statement. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        // bind msgid
        sqlite3_bind_text(sqlStatement, 1, [RecipientToken UTF8String], -1, SQLITE_TRANSIENT);
        
        if(SQLITE_DONE != sqlite3_step(sqlStatement)){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat: @"ERROR: Error while inserting data. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            ret = NO;
        }

    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        ret = NO;
    }
    @finally {
        return ret;
    }
}

- (NSString*)SearchRecipient:(NSString*)RecipientToken
{
    if(db==nil||RecipientToken==nil)
    {
        [ErrorLogger ERRORDEBUG:@"ERROR: DB Object is null or input is null."];
        return nil;
    }
    
    NSString* Peer = nil;
    @try {
        const char *sql = "SELECT pid FROM tokenstore WHERE ptoken=?";
        sqlite3_stmt *sqlStatement;
        if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK)
        {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Problem with prepare statement: %s", sql]];
            if(Peer) [Peer release];
            Peer = nil;
        }
        sqlite3_bind_text(sqlStatement, 1, [RecipientToken UTF8String], -1, SQLITE_TRANSIENT);
        
        if (sqlite3_step(sqlStatement)==SQLITE_ROW) {
            Peer = [[NSString stringWithUTF8String:(char*)sqlite3_column_text(sqlStatement, 0)]retain];
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            if(Peer) [Peer release];
            Peer = nil;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        if(Peer) [Peer release];
        Peer = nil;
    }
    @finally {
        return Peer;
    }
}


- (BOOL)RegisterToken: (NSString*)token User:(NSString*)username Dev:(int)type Photo:(NSString*)UserPhoto KeyData: (NSData*)keyelement ExchangeOrIntroduction: (BOOL)flag
{
    if(db==nil)
    {
        [ErrorLogger ERRORDEBUG:@"ERROR: DB Object is null or input is null."];
        return NO;
    }
    
    // seperate keyelement
    NSString* rawdata = [NSString stringWithCString:[keyelement bytes] encoding:NSASCIIStringEncoding];
    rawdata = [rawdata substringToIndex:[keyelement length]];
    
    NSArray* data = [rawdata componentsSeparatedByString:@"\n"];
    if([data count]!=3) {
        [ErrorLogger ERRORDEBUG: (@"ERROR: Exchange public key is not well-formated!")];
        return NO;
    }
    
    BOOL ret = YES;
    @try {
        // get exchange time
        NSString* now = [NSString GetLocalTimeString:DATABASE_TIMESTR];
        sqlite3_stmt *sqlStatement;
        const char* sql = "INSERT INTO tokenstore (ptoken, pid, bdate, dev, ex_type, note, keyid, pkey, pstamp) Values (?,?,?,?,?,?,?,?,?)";
        
        if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK)
        {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Problem with prepare statement: %s", sql]];
            ret = NO;
        }
        // bind ptoken
        sqlite3_bind_text(sqlStatement, 1, [token UTF8String], -1, SQLITE_TRANSIENT);
        // bind pid
        sqlite3_bind_text(sqlStatement, 2, [username UTF8String], -1, SQLITE_TRANSIENT);
        // binf date
        sqlite3_bind_text(sqlStatement, 3, [now UTF8String], -1, SQLITE_TRANSIENT);
        // bind dev
        sqlite3_bind_int(sqlStatement, 4, type);
        // bind ex_type
        if(flag)sqlite3_bind_int(sqlStatement, 5, 0);
        else sqlite3_bind_int(sqlStatement, 5, 1);
        // bind photo
        if(UserPhoto!=nil)sqlite3_bind_text(sqlStatement, 6, [UserPhoto UTF8String], -1, SQLITE_TRANSIENT);
        else sqlite3_bind_null(sqlStatement, 6);
        // bind keyid
        NSString* keyid = [data objectAtIndex:0];
        sqlite3_bind_blob(sqlStatement, 7, [keyid cStringUsingEncoding:NSUTF8StringEncoding], [keyid lengthOfBytesUsingEncoding:NSUTF8StringEncoding], SQLITE_TRANSIENT);
        // pkey
        NSString* keystr = [data objectAtIndex:2];
        sqlite3_bind_text(sqlStatement, 8, [keystr UTF8String], -1, SQLITE_TRANSIENT);
        // pstamp
        NSString* stamp = [data objectAtIndex:1];
        sqlite3_bind_text( sqlStatement, 9, [stamp UTF8String], -1, SQLITE_TRANSIENT);
        
        if(SQLITE_DONE != sqlite3_step(sqlStatement)){
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"Error while inserting peer. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            ret = NO;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        ret = NO;
    }
    @finally {
        return ret;
    }
}

- (BOOL)UpdateToken: (NSString*)token User:(NSString*)username Dev:(int)type Photo:(NSString*)UserPhoto KeyData: (NSData*)keyelement ExchangeOrIntroduction: (BOOL)flag
{
    if(db==nil)
    {
        [ErrorLogger ERRORDEBUG:@"ERROR: DB Object is null or input is null."];
        return NO;
    }
    
    // seperate keyelement
    NSString* rawdata = [NSString stringWithCString:[keyelement bytes] encoding:NSASCIIStringEncoding];
    rawdata = [rawdata substringToIndex:[keyelement length]];
    NSArray* data = [rawdata componentsSeparatedByString:@"\n"];
    if([data count]!=3) {
        [ErrorLogger ERRORDEBUG: @"ERROR: Exchange public key is not well-formated!"];
        return NO;
    }
    
    BOOL ret = YES;
    @try {
        
        // get exchange time
        NSString* now = [NSString GetLocalTimeString:DATABASE_TIMESTR];
        sqlite3_stmt *sqlStatement;
        const char* sql = "UPDATE tokenstore SET pid=?, dev=?, bdate=?, note=?, ex_type=?, keyid=?, pkey=?, pstamp=? WHERE ptoken=?";
        
        if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK)
        {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Problem with prepare statement: %s", sql]];
            ret = NO;
        }
        // bind pid
        sqlite3_bind_text(sqlStatement, 1, [username UTF8String], -1, SQLITE_TRANSIENT);
        // bind dev
        sqlite3_bind_int(sqlStatement, 2, type);
        // bind date
        sqlite3_bind_text(sqlStatement, 3, [now UTF8String], -1, SQLITE_TRANSIENT);
        // bind photo
        if(UserPhoto!=nil){
            sqlite3_bind_text(sqlStatement, 4, [UserPhoto UTF8String], -1, SQLITE_TRANSIENT);
        }else{
            sqlite3_bind_null(sqlStatement, 4);
        }
        // bind ex_type
        if(flag)sqlite3_bind_int(sqlStatement, 5, 0);
        else sqlite3_bind_int(sqlStatement, 5, 1);
        
        // bind keyid
        NSString* keyid = [data objectAtIndex:0];
        sqlite3_bind_blob(sqlStatement, 6, [keyid cStringUsingEncoding:NSUTF8StringEncoding], [keyid lengthOfBytesUsingEncoding:NSUTF8StringEncoding], SQLITE_TRANSIENT);
        // pkey
        NSString* keystr = [data objectAtIndex:2];
        sqlite3_bind_text(sqlStatement, 7, [keystr UTF8String], -1, SQLITE_TRANSIENT);
        // pstamp
        NSString* stamp = [data objectAtIndex:1];
        sqlite3_bind_text( sqlStatement, 8, [stamp UTF8String], -1, SQLITE_TRANSIENT);
        
        // bind ptoken
        sqlite3_bind_text(sqlStatement, 9, [token UTF8String], -1, SQLITE_TRANSIENT);
        
        if(SQLITE_DONE != sqlite3_step(sqlStatement)){
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"Error while inserting peer. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            ret = NO;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        ret = NO;
    }
    @finally {
        return ret;
    }
}


- (NSArray*)LoadRecipients:(BOOL)ExchangeOnly
{
    
    if(db==nil)
    {
        [ErrorLogger ERRORDEBUG:@"ERROR: DB Object is null or input is null."];
        return nil;
    }
    
    NSMutableArray *tmpArray = nil;
    @try {
        
        tmpArray = [NSMutableArray arrayWithCapacity:0];
        int rownum = 0;
        
        const char *sql = NULL;
        if(ExchangeOnly)
            sql = "SELECT * FROM tokenstore where ex_type = 0 ORDER BY pid COLLATE NOCASE DESC";
        else
            sql = "SELECT * FROM tokenstore ORDER BY pid COLLATE NOCASE DESC";
        
        sqlite3_stmt *sqlStatement = nil;
        if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK)
        {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Problem with prepare statement: %s", sql]];
            if(tmpArray) [tmpArray release];
            tmpArray = nil;
        }
        
        while (sqlite3_step(sqlStatement)==SQLITE_ROW) {
            
            SSContactEntry *sc = [[SSContactEntry alloc]init];
            
            NSString *output = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 0)];
            sc.pushtoken = output;
            
            output = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 1)];
            
            NSArray* namearray = [[output substringFromIndex:[output rangeOfString:@":"].location+1]componentsSeparatedByString:@";"];
            if([[namearray objectAtIndex:1]length]>0) sc.fname = [namearray objectAtIndex:1];
            if([[namearray objectAtIndex:0]length]>0) sc.lname = [namearray objectAtIndex:0];
            
            output = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 2)];
            sc.exchangeDate = output;
            sc.devType = sqlite3_column_int(sqlStatement, 3);
            sc.ex_type = sqlite3_column_int(sqlStatement, 4);
            
            // setphoto
            if(sqlite3_column_type(sqlStatement, 5)!=SQLITE_NULL)
            {
                output = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 5)];
                sc.photo = [Base64 decode: output];
            }
            
            // set keyid and pstamp
            int rawLen = sqlite3_column_bytes(sqlStatement, 6);
            if(rawLen>0) {
                sc.keyid = [NSString stringWithUTF8String:(char*)sqlite3_column_text(sqlStatement, 6)];
            }
            if(sqlite3_column_type(sqlStatement, 8)!=SQLITE_NULL)
            {
                sc.keygenDate = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 8)];
            }
            
            [tmpArray addObject:sc];
            [sc release];
            sc = nil;
            rownum++;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        if(tmpArray) [tmpArray release];
        tmpArray = nil;
    }
    @finally {
        return tmpArray;
    }
}

- (NSArray*)LoadRecentRecipients:(BOOL)ExchangeOnly
{
    if(db==nil)
    {
        [ErrorLogger ERRORDEBUG:@"ERROR: DB Object is null or input is null."];
        return nil;
    }
    NSMutableArray *tmpArray = nil;
    @try {
        
        tmpArray = [NSMutableArray arrayWithCapacity:0];
        int rownum = 0;
        const char *sql = NULL;
        if(ExchangeOnly)
            sql = "SELECT * FROM tokenstore where ex_type = 0 ORDER BY pid COLLATE NOCASE DESC, bdate DESC";
        else
            sql = "SELECT * FROM tokenstore ORDER BY pid COLLATE NOCASE DESC, bdate DESC";
        
        sqlite3_stmt *sqlStatement = nil;
        if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK)
        {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Problem with prepare statement: %s", sql]];
            if(tmpArray) [tmpArray release];
            tmpArray = nil;
        }
        
        NSMutableSet *unqiueSet = [[NSMutableSet alloc]initWithCapacity:0];
        
        while (sqlite3_step(sqlStatement)==SQLITE_ROW) {
            
            // try different device as different entries
            NSString* output = [NSString stringWithFormat:@"%@:%d", [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 1)], sqlite3_column_int(sqlStatement, 3)];
            if([unqiueSet containsObject:output])
            {
                continue;
            }
            
            // add to set
            [unqiueSet addObject:output];
            SSContactEntry *sc = [[SSContactEntry alloc]init];
            
            output = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 1)];
            NSArray* namearray = [[output substringFromIndex:[output rangeOfString:@":"].location+1]componentsSeparatedByString:@";"];
            if([[namearray objectAtIndex:1]length]>0) sc.fname = [namearray objectAtIndex:1];
            if([[namearray objectAtIndex:0]length]>0) sc.lname = [namearray objectAtIndex:0];
            
            output = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 0)];
            sc.pushtoken = output;
            
            output = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 2)];
            sc.exchangeDate = output;
            sc.devType = sqlite3_column_int(sqlStatement, 3);
            sc.ex_type = sqlite3_column_int(sqlStatement, 4);
            
            // setphoto
            if(sqlite3_column_type(sqlStatement, 5)!=SQLITE_NULL)
            {
                output = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 5)];
                sc.photo = [Base64 decode: output];
            }
            
            // set keyid and pstamp
            int rawLen = sqlite3_column_bytes(sqlStatement, 6);
            if(rawLen>0) {
                sc.keyid = [NSString stringWithUTF8String:(char*)sqlite3_column_text(sqlStatement, 6)];
            }
            if(sqlite3_column_type(sqlStatement, 8)!=SQLITE_NULL)
            {
                sc.keygenDate = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 8)];
            }
            
            [tmpArray addObject:sc];
            [sc release];
            sc = nil;
            rownum++;
        }
        [unqiueSet release];
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        if(tmpArray) [tmpArray release];
        tmpArray = nil;
    }
    @finally {
        return tmpArray;
    }
}

- (NSArray*)LoadMessageThreads
{
    if(db==nil)
    {
        [ErrorLogger ERRORDEBUG:@"ERROR: DB Object is null or input is null."];
        return nil;
    }
    
    NSMutableArray *MsgThreadArray = nil;
    @try {
        
        MsgThreadArray = [NSMutableArray arrayWithCapacity:0];
        const char *sql = NULL;
        sqlite3_stmt *sqlStatement;
        
        // New Thread Only
        sql = "SELECT token, sender, cTime, count(msgid), sum(smsg) FROM msgtable WHERE thread_id<>-1 GROUP BY token order by cTime desc";
        if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK)
        {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Problem with prepare statement: %s", sql]];
            if(MsgThreadArray)[MsgThreadArray release];
            MsgThreadArray = nil;
        }
        
        while (sqlite3_step(sqlStatement)==SQLITE_ROW) {
            // 1 cTime, might be null
            if(sqlite3_column_type(sqlStatement, 0)!=SQLITE_NULL)
            {
                MsgListEntry *listEnt = [[MsgListEntry alloc]init];
                listEnt.token = [NSString stringWithUTF8String:(char*)sqlite3_column_text(sqlStatement, 0)];
                listEnt.username = [NSString stringWithUTF8String:(char*)sqlite3_column_text(sqlStatement, 1)];
                listEnt.lastSeen = [NSString stringWithUTF8String:(char*)sqlite3_column_text(sqlStatement, 2)];
                listEnt.messagecount = sqlite3_column_int(sqlStatement, 3);
                listEnt.ciphercount = sqlite3_column_int(sqlStatement, 4);
                [MsgThreadArray addObject:listEnt];
                [listEnt release];
            }
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        if(MsgThreadArray)[MsgThreadArray release];
        MsgThreadArray = nil;
    }
    @finally {
        return MsgThreadArray;
    }
}

- (int)ThreadCipherCount: (NSString*)token
{
    if(db==nil||token==nil)
    {
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return 0;
    }
    
    int count = 0;
    @try {
        const char *sql = "SELECT count(msgid) FROM msgtable WHERE thread_id<>-1 AND token=? AND smsg=1";
        sqlite3_stmt *sqlStatement;
        if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK)
        {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Problem with prepare statement: %s", sql]];
        }
        
        sqlite3_bind_text(sqlStatement, 1, [token UTF8String], -1, SQLITE_TRANSIENT);
        
        if (sqlite3_step(sqlStatement) == SQLITE_ERROR) {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"Error while querying data. '%s'", sqlite3_errmsg(db)]];
        } else {
            count = sqlite3_column_int(sqlStatement, 0);
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            count = 0;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        count = 0;
    }
    @finally {
        return count;
    }
}

- (int)ThreadMessageCount: (NSString*)token
{
    
    if(db==nil||token==nil)
    {
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return 0;
    }
    
    int count = 0;
    @try {
        const char *sql = "SELECT count(msgid) FROM msgtable WHERE thread_id<>-1 AND token=?";
        sqlite3_stmt *sqlStatement;
        if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK)
        {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Problem with prepare statement: %s", sql]];
        }
        
        sqlite3_bind_text(sqlStatement, 1, [token UTF8String], -1, SQLITE_TRANSIENT);
        
        if (sqlite3_step(sqlStatement) == SQLITE_ERROR) {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"Error while querying data. '%s'", sqlite3_errmsg(db)]];
        } else {
            count = sqlite3_column_int(sqlStatement, 0);
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            count = 0;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        count = 0;
    }
    @finally {
        return count;
    }
}

- (NSArray*)LoadThreadMessage: (NSString*)token
{
    
    if(db==nil||token==nil)
    {
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return nil;
    }
    
    NSMutableArray *tmparray = nil;
    @try {
        
        int rownum = 0;
        tmparray = [NSMutableArray arrayWithCapacity:0];
        
        const char *sql = "SELECT * FROM msgtable WHERE thread_id<>-1 AND token=? ORDER BY cTime DESC";
        sqlite3_stmt *sqlStatement;
        if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK)
        {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Problem with prepare statement: %s", sql]];
            if(tmparray) [tmparray release];
            tmparray = nil;
        }
        
        sqlite3_bind_text(sqlStatement, 1, [token UTF8String], -1, SQLITE_TRANSIENT);
        
        char* output = NULL;
        while (sqlite3_step(sqlStatement)==SQLITE_ROW) {
            
            MsgEntry *amsg = [[MsgEntry alloc]init];
            
            //1:msid
            int rawLen = sqlite3_column_bytes(sqlStatement, 0);
            if(rawLen>0) {
                amsg.msgid = [NSData dataWithBytes:sqlite3_column_blob(sqlStatement, 0) length:rawLen];
            }
            
            // 2 cTime, might be null
            if(sqlite3_column_type(sqlStatement, 1)!=SQLITE_NULL)
            {
                //2/3 cTime/rTime
                amsg.cTime = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 1)];
            }
            
            // 3 rTime, not used anymore
            if(sqlite3_column_type(sqlStatement, 2)!=SQLITE_NULL)
            {
                //2/3 cTime/rTime
                amsg.rTime = [NSString stringWithUTF8String:(char *)sqlite3_column_text(sqlStatement, 2)];
            }
            
            //4 dir
            amsg.dir = sqlite3_column_int(sqlStatement, 3);
            
            // 5 token, might be null
            if(sqlite3_column_type(sqlStatement, 4)!=SQLITE_NULL)
            {
                output = (char *)sqlite3_column_text(sqlStatement, 4);
                amsg.token = [NSString stringWithUTF8String:output];
            }
            
            // 6 sender, might be null
            if(sqlite3_column_type(sqlStatement, 5)!=SQLITE_NULL)
            {
                output = (char *)sqlite3_column_text(sqlStatement, 5);
                amsg.sender = [NSString stringWithUTF8String:output];
            }
            
            // 7 msgbody
            if(sqlite3_column_type(sqlStatement, 6)!=SQLITE_NULL)
            {
                int rawLen = sqlite3_column_bytes(sqlStatement, 6);
                if(rawLen>0) {
                    output = (char*)sqlite3_column_blob(sqlStatement, 6);
                    amsg.msgbody = [NSData dataWithBytes:output length:rawLen];
                }
            }
            
            // 8 attach
            amsg.attach = sqlite3_column_int(sqlStatement, 7);
            
            // 9 fname text
            if(sqlite3_column_type(sqlStatement, 8)!=SQLITE_NULL)
            {
                output = (char *)sqlite3_column_text(sqlStatement, 8);
                amsg.fname = [NSString stringWithUTF8String:output];
            }
            
            // 12 fext
            if(sqlite3_column_type(sqlStatement, 11)!=SQLITE_NULL)
            {
                output = (char *)sqlite3_column_text(sqlStatement, 11);
                amsg.fext = [NSString stringWithUTF8String:output];
            }
            
            // 13 smsg boolean
            amsg.smsg = sqlite3_column_int(sqlStatement, 12);
            // 14 sfile boolean
            amsg.sfile = sqlite3_column_int(sqlStatement, 13);
            
            [tmparray addObject:amsg];
            [amsg release];
            amsg = nil;
            rownum++;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        if(tmparray) [tmparray release];
        tmparray = nil;
    }
    @finally {
        return tmparray;
    }
}


- (FileInfo*)GetFileInfo: (NSData*)msgid
{
    if((db==nil)||(msgid==nil))
    {
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return nil;
    }
    
    FileInfo* finfo = nil;
    @try {
        
        finfo = [[FileInfo alloc]init];
        const char *sql = "SELECT fname, fext, fbody, sfile FROM msgtable where msgid = ?";
        sqlite3_stmt *sqlStatement;
        if(sqlite3_prepare(db, sql, -1, &sqlStatement, NULL) == SQLITE_OK)
        {
            sqlite3_bind_blob(sqlStatement, 1, [msgid bytes], [msgid length], SQLITE_TRANSIENT);
            
            char* output = NULL;
            if (sqlite3_step(sqlStatement)==SQLITE_ROW) {
                
                output = (char*)sqlite3_column_text(sqlStatement, 0);
                finfo.FName = [NSString stringWithUTF8String:output];
                output = (char*)sqlite3_column_text(sqlStatement, 1);
                finfo.FExt = [NSString stringWithUTF8String:output];
                
                finfo.FSize = 0;
                if(sqlite3_column_int(sqlStatement, 3)==0)
                {
                    // decrypted file
                    finfo.FSize = sqlite3_column_bytes(sqlStatement, 2);
                }
                else if(sqlite3_column_int(sqlStatement, 3)>=1)
                {
                    // encrypted file
                    int rawLen = sqlite3_column_bytes(sqlStatement, 2);
                    if(rawLen==36)  // 32 bytes for hash + 4 bytes for size
                    {
                        //raw = raw+32;
                        output = (char*)sqlite3_column_text(sqlStatement, 2);
                        NSData *data = [NSData dataWithBytes:(output+32) length:4];
                        int size = 0;
                        [data getBytes: &size length: sizeof(size)];
                        finfo.FSize = size;
                    }
                }
            }
            if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
                [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            }
            
        }else {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: Problem with prepare statement: %s", sql]];
            if(finfo) [finfo release];
            finfo = nil;
        }
        
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        if(finfo) [finfo release];
        finfo = nil;
    }
    @finally {
        return finfo;
    }
}

- (BOOL)InsertMessage: (MsgEntry*)MSG
{
    if(db==nil){
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return NO;
    }
    
    BOOL ret = YES;
    @try {
        
        sqlite3_stmt *sqlStatement;
        const char *sql = "insert into msgtable (msgid, cTime, rTime, dir, token, sender, msgbody, attach, fname, fbody, ft, fext, smsg, sfile, note, thread_id) Values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0)";
        if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while creating statement. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        // msgid
        sqlite3_bind_blob(sqlStatement, 1, [MSG.msgid bytes], [MSG.msgid length], SQLITE_TRANSIENT);
        // 2/3: cTime/rTime, rTime is not used anymore
        sqlite3_bind_text(sqlStatement, 2, [MSG.cTime UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(sqlStatement, 3, [MSG.rTime UTF8String], -1, SQLITE_TRANSIENT);
        //4: dir
        sqlite3_bind_int(sqlStatement, 4, MSG.dir);
        
        // 5: token, 6: sender (receiver when receiving messages)
        if(MSG.token)
            sqlite3_bind_text(sqlStatement, 5, [MSG.token UTF8String], -1, SQLITE_TRANSIENT);
        else
            sqlite3_bind_null(sqlStatement, 5);
        
        if(MSG.sender)
            sqlite3_bind_text(sqlStatement, 6, [MSG.sender UTF8String], -1, SQLITE_TRANSIENT);
        else
            sqlite3_bind_null(sqlStatement, 6);
        
        // 7: msgbody
        if(MSG.msgbody)
            sqlite3_bind_blob(sqlStatement, 7, [MSG.msgbody bytes], [MSG.msgbody length], SQLITE_TRANSIENT);
        else
            sqlite3_bind_null(sqlStatement, 7);
        
        // 8: attach, 9: fname, 10: fbody, 11: ft, 12: fext
        if(MSG.attach)
        {
            sqlite3_bind_int(sqlStatement, 8, 1);
            if(MSG.dir==ToMsg)
            {
                // fname/fdata
                sqlite3_bind_text(sqlStatement, 9, [MSG.fname UTF8String], -1, SQLITE_TRANSIENT);
                sqlite3_bind_blob(sqlStatement, 10, [MSG.fbody bytes], [MSG.fbody length], NULL);
                sqlite3_bind_null(sqlStatement, 11);
                sqlite3_bind_text(sqlStatement, 12, [MSG.fext UTF8String], -1, SQLITE_TRANSIENT);
            }
            
        }else {
            // for receive only
            sqlite3_bind_int(sqlStatement, 8, 0);
            // fname and fdata are null
            sqlite3_bind_null(sqlStatement,9);
            sqlite3_bind_null(sqlStatement,10);
            sqlite3_bind_null(sqlStatement,11);
            sqlite3_bind_null(sqlStatement,12);
        }
        
        // smsg, sfile 
        sqlite3_bind_int(sqlStatement, 13, MSG.smsg);
        sqlite3_bind_int(sqlStatement, 14, MSG.sfile);
        
        // note
        if(MSG.face){
            sqlite3_bind_text(sqlStatement, 15, [MSG.face UTF8String], -1, SQLITE_TRANSIENT);
        }else {
            sqlite3_bind_null(sqlStatement, 15);
        }
        
        if(SQLITE_DONE != sqlite3_step(sqlStatement)){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat: @"ERROR: Error while inserting data. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            ret = NO;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        ret = NO;
    }
    @finally {
        return ret;
    }
}

- (void)UpdateUndefinedThread
{
    if(db==nil){
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
    }
    
    @try {
        sqlite3_stmt *sqlStatement;
        const char *sql = "UPDATE msgtable SET smsg=0 where token = 'UNDEFINED'";
        if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while creating statement. '%s'", sqlite3_errmsg(db)]];
        }
        
        if(SQLITE_DONE != sqlite3_step(sqlStatement)){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat: @"Error while updating data. '%s'", sqlite3_errmsg(db)]];
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
    }
}

- (BOOL)UpdateMessagesWithToken: (NSString*)oldKeyID ReplaceUsername:(NSString*)username ReplaceToken:(NSString*)token
{
    if(db==nil||oldKeyID==nil||username==nil||token==nil){
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return NO;
    }
    
    BOOL ret = YES;
    @try {
        sqlite3_stmt *sqlStatement;
        const char *sql = "UPDATE msgtable SET token=?, sender=? where token = ?";
        if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while creating statement. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        // Binding
        sqlite3_bind_text(sqlStatement, 1, [token UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(sqlStatement, 2, [username UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(sqlStatement, 3, [oldKeyID UTF8String], -1, SQLITE_TRANSIENT);
        
        if(SQLITE_DONE != sqlite3_step(sqlStatement)){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat: @"Error while updating data. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            ret = NO;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        ret = NO;
    }
    @finally {
        return ret;
    }
}

- (BOOL)UpdateMessage: (NSData*)msgid NewMSG:(NSString*)decrypted_message Time:(NSString*)GMTTime User:(NSString*)Name Token:(NSString*)TID Photo:(NSString*)UserPhoto
{
    if(db==nil){
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return NO;
    }
    
    BOOL ret = YES;
    @try {
        sqlite3_stmt *sqlStatement;
        const char *sql = "UPDATE msgtable SET msgbody=?, cTime=?, token=?, sender=?, note=?, smsg='N' where msgid = ?";
        if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while creating statement. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        // bind msgbody
        if(decrypted_message!=NULL)
        {
            sqlite3_bind_blob(sqlStatement, 1, [[decrypted_message dataUsingEncoding:NSUTF8StringEncoding] bytes], [decrypted_message lengthOfBytesUsingEncoding:NSUTF8StringEncoding], SQLITE_TRANSIENT);
        }
        else {
            sqlite3_bind_null(sqlStatement, 1);
        }
        
        // getGMT and transfter to local time
        sqlite3_bind_text(sqlStatement, 2, [GMTTime UTF8String], -1, SQLITE_TRANSIENT);
        
        // for name and token and picture
        if(TID)
        {
            sqlite3_bind_text(sqlStatement, 3, [TID UTF8String], -1, SQLITE_TRANSIENT);
        }else {
            sqlite3_bind_null(sqlStatement, 3);
        }
        
        if(Name)
        {
            sqlite3_bind_text(sqlStatement, 4, [Name UTF8String], -1, SQLITE_TRANSIENT);
        }else {
            sqlite3_bind_null(sqlStatement, 4);
        }
        
        
        if(UserPhoto!=nil) sqlite3_bind_text(sqlStatement, 5, [UserPhoto UTF8String], -1, SQLITE_TRANSIENT);
        else sqlite3_bind_null(sqlStatement, 5);
        // bind msgid
        sqlite3_bind_blob(sqlStatement, 6, [msgid bytes], [msgid length], SQLITE_TRANSIENT);
        
        if(SQLITE_DONE != sqlite3_step(sqlStatement)){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat: @"Error while updating data. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            ret = NO;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"An exception occured: %@", [exception reason]]];
        ret = NO;
    }
    @finally {
        return ret;
    }
}

- (BOOL)UpdateFileBody: (NSData*)msgid DecryptedData:(NSData*)data
{
    if(db==nil||data==nil||msgid==nil){
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return NO;
    }
    
    BOOL ret = YES;
    @try {
        sqlite3_stmt *sqlStatement;
        const char *sql = "UPDATE msgtable SET fbody=?, sfile='N' where msgid = ?";
        
        if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while creating statement. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        // bind msgbody
        sqlite3_bind_blob(sqlStatement, 1, [data bytes], [data length], SQLITE_TRANSIENT);
        // bind msgid
        sqlite3_bind_blob(sqlStatement, 2, [msgid bytes], [msgid length], SQLITE_TRANSIENT);
        
        if(SQLITE_DONE != sqlite3_step(sqlStatement)){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat: @"Error while updating data. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            ret = NO;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: An exception occured, %@", [exception reason]]];
        ret = NO;
    }
    @finally {
        return ret;
    }
}

- (BOOL)UpdateFileInfo:(NSData*)msgid filename:(NSString*)fname filetype: (NSString*)ext Time:(NSString*)GMTTime fileinfo:(NSData*)finfo
{
    if(db==nil){
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return NO;
    }
    
    BOOL ret = YES;
    @try {
        
        sqlite3_stmt *sqlStatement;
        const char *sql = "UPDATE msgtable SET fname=?,fext=?,ft=?,fbody=?,attach=? where msgid = ?";
        
        if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while creating statement. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        //fname
        sqlite3_bind_text(sqlStatement, 1, [fname UTF8String], -1, SQLITE_TRANSIENT);
        //fext
        if(ext!=nil)sqlite3_bind_text(sqlStatement, 2, [ext UTF8String], -1, SQLITE_TRANSIENT);
        else sqlite3_bind_text(sqlStatement, 2, [[fname lastPathComponent] UTF8String], -1, SQLITE_TRANSIENT);
        //ft
        sqlite3_bind_text(sqlStatement, 3, [GMTTime UTF8String], -1, SQLITE_TRANSIENT);
        //fbody
        sqlite3_bind_blob(sqlStatement, 4, [finfo bytes], [finfo length], SQLITE_TRANSIENT);
        // attach value
        sqlite3_bind_int(sqlStatement, 5, 1);
        //msgid
        sqlite3_bind_blob(sqlStatement, 6, [msgid bytes], [msgid length], SQLITE_TRANSIENT);
        
        if(SQLITE_DONE != sqlite3_step(sqlStatement)){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat: @"Error while updating data. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            ret = NO;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: An exception occured, %@", [exception reason]]];
        ret = NO;
    }
    @finally {
        return ret;
    }
}

- (BOOL)CheckMessage: (NSData*)msgid
{
    if(db==nil||msgid==nil){
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return NO;
    }
    
    BOOL exist = NO;
    @try {
        
        sqlite3_stmt *sqlStatement;
        const char *sql = "SELECT COUNT(*) FROM msgtable WHERE msgid=?";
        
        if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while creating statement. '%s'", sqlite3_errmsg(db)]];
        }
        
        // bind msgid
        sqlite3_bind_blob(sqlStatement, 1, [msgid bytes], [msgid length], SQLITE_TRANSIENT);
        
        if (sqlite3_step(sqlStatement) == SQLITE_ERROR) {
            [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"Error while querying data. '%s'", sqlite3_errmsg(db)]];
        } else {
            if(sqlite3_column_int(sqlStatement, 0)>0) exist = YES;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: An exception occured, %@", [exception reason]]];
    }
    @finally {
        return exist;
    }
}


- (BOOL)DeleteThread: (NSString*)thread_token
{
    if(db==nil||thread_token==nil){
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return NO;
    }
    
    BOOL ret = YES;
    @try {
        
        sqlite3_stmt *sqlStatement;
        const char *sql = "DELETE FROM msgtable WHERE token=? AND thread_id<>-1;";
        if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while creating statement. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        // bind msgid
        sqlite3_bind_text(sqlStatement, 1, [thread_token UTF8String], -1, SQLITE_TRANSIENT);
        
        if(SQLITE_DONE != sqlite3_step(sqlStatement)){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while deleting data. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            ret = NO;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: An exception occured, %@", [exception reason]]];
        
        ret = NO;
    }
    @finally {
        return ret;
    }
}

- (BOOL)DeleteMessage: (NSData*)msgid
{
    if(db==nil){
        [ErrorLogger ERRORDEBUG: @"ERROR: DB Object is null or Input is null."];
        return NO;
    }
    
    BOOL ret = YES;
    @try {
        
        sqlite3_stmt *sqlStatement;
        const char *sql = "DELETE FROM msgtable WHERE msgid=?";
        
        if(sqlite3_prepare_v2(db, sql, -1, &sqlStatement, NULL) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while creating statement. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        // bind msgid
        sqlite3_bind_blob(sqlStatement, 1, [msgid bytes], [msgid length], SQLITE_TRANSIENT);
        
        if(SQLITE_DONE != sqlite3_step(sqlStatement)){
            [ErrorLogger ERRORDEBUG:[NSString stringWithFormat:@"Error while deleting data. '%s'", sqlite3_errmsg(db)]];
            ret = NO;
        }
        
        if(sqlite3_finalize(sqlStatement) != SQLITE_OK){
            [ErrorLogger ERRORDEBUG: @"ERROR: Problem with finalize statement"];
            ret = NO;
        }
    }
    @catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: An exception occured, %@", [exception reason]]];
        
        ret = NO;
    }
    @finally {
        return ret;
    }
}

- (BOOL) SaveDBToStorage
{
    if(db==nil) return YES;
	@try{
        if(sqlite3_close(db)!=SQLITE_OK)
            [ErrorLogger ERRORDEBUG: @"ERROR: Unable to close the database."];
        else
            return YES;
    }@catch (NSException *exception) {
        [ErrorLogger ERRORDEBUG: [NSString stringWithFormat: @"ERROR: An exception occured in SaveDBToStorage: %@", [exception reason]]];
        return NO;
    }
}

@end
