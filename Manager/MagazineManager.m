//
//  MagazineManager.m
//  Magazine
//
//  Created by jason on 11/6/12.
//  Copyright (c) 2012 jason. All rights reserved.
//

#import "MagazineManager.h"
#import "AFNetworking.h"


@implementation MagazineManager

#pragma mark - define

#define CacheDirectory [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0]
#define DocumentsDirectory [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0]

#pragma mark - init

- (id)init
{
    self = [super init];
    if (self) {
        _isFlowLayout = YES;
        
        // StoreKit transaction observer
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    }
    return self;
}

#pragma mark - issue info methods

- (NSDictionary *)issueAtIndex:(NSInteger)index
{
    return [self.issueArray objectAtIndex:index];
}

- (NSString *)titleOfIssueAtIndex:(NSInteger)index
{
    return [[self issueAtIndex:index] objectForKey:@"title"];
}

- (NSString *)nameOfIssueAtIndex:(NSInteger)index
{
    return [[self issueAtIndex:index] objectForKey:@"name"];
}

- (NSURL *)contentURLForIssueWithName:(NSString *)name
{
    NSURL *contentURL = nil;
    
    for(NSDictionary *issue in self.issueArray)
    {
        NSString *aName = [issue objectForKey:@"name"];
        if([aName isEqualToString:name])
        {
            contentURL = [NSURL URLWithString:[issue objectForKey:@"content"]];
            break;
        }
    }
    
    NSLog(@"Content URL for issue with name %@ is %@", name, contentURL);
    
    return contentURL;
}

- (NSString *)downloadPathForIssue:(NKIssue *)nkIssue
{
    return [nkIssue.contentURL path];
}

- (UIImage *)coverImageForIssue:(NKIssue *)nkIssue
{
    NSString *name = nkIssue.name;
    for(NSDictionary *issueInfo in self.issueArray)
    {
        if([name isEqualToString:[issueInfo objectForKey:@"name"]])
        {
            NSString *coverPath = [issueInfo objectForKey:@"cover"];
            NSString *coverName = [coverPath lastPathComponent];
            NSString *coverFilePath = [CacheDirectory stringByAppendingPathComponent:coverName];
            UIImage *image = [UIImage imageWithContentsOfFile:coverFilePath];
            return image;
        }
    }
    
    return nil;
}

- (void)setCoverOfIssueAtIndex:(NSInteger)index
               completionBlock:(void(^)(UIImage *img))block
{
    NSURL *coverURL = [NSURL URLWithString:[[self issueAtIndex:index] objectForKey:@"cover"]];
    NSString *coverFileName = [coverURL lastPathComponent];
    NSString *coverFilePath = [CacheDirectory stringByAppendingPathComponent:coverFileName];
    
    UIImage *image = [UIImage imageWithContentsOfFile:coverFilePath];
    
    if(DEVELOPMENT_MODE == YES)
    {
        image = [UIImage imageNamed:@"bookCover_large.png"];
    }
    
    if(image)
    {
        if(block)
            block(image);
    }
    else
    {
        AFImageRequestOperation *op = [AFImageRequestOperation imageRequestOperationWithRequest:[NSURLRequest requestWithURL:coverURL] success:^(UIImage *image) {
            
            NSData *imageData = UIImagePNGRepresentation(image);
            [imageData writeToFile:coverFilePath atomically:YES];
            
            if(block)
                block(image);
        }];
        
        [op start];
    }
}

#pragma mark - main methods

- (void)getIssuesListSuccess:(void (^)())success
                     failure:(void (^)(NSString *reason, NSError *error))failure
{
    if(DEVELOPMENT_MODE)
    {
        NSURL *catalogURL = [[NSBundle mainBundle] URLForResource:@"catalog" withExtension:@"plist"];
        
        NSMutableArray *array = [NSMutableArray arrayWithArray:[[NSArray alloc] initWithContentsOfURL:catalogURL]];
        [array insertObject:[NSDictionary dictionary] atIndex:0]; // the first object is reserved for "subscribe cell"
        
        self.issueArray = array;
        self.ready = YES;
        [self addIssuesInNewsstand];
        
        if(success)
            success();
    }
    else
    {
        //線上版書架內容--plist
        
        AFPropertyListRequestOperation *op = [AFPropertyListRequestOperation propertyListRequestOperationWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:PLIST_PATH]] success:^(NSURLRequest *request, NSHTTPURLResponse *response, id propertyList) {
            
            NSMutableArray *array = [NSMutableArray arrayWithArray:propertyList];
            [array insertObject:[NSDictionary dictionary] atIndex:0]; // the first object is reserved for "subscribe cell"
            
            self.issueArray = array;
            self.ready = YES;
            [self addIssuesInNewsstand];
            
            if(success)
                success();
            
        } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id propertyList) {
            
            self.ready = NO;
            if(failure)
                failure(@"無法下載型錄", error);
        }];
         
        
        [op start];
    }
}

- (void)addIssuesInNewsstand
{
    NKLibrary *nkLib = [NKLibrary sharedLibrary];
    [self.issueArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop)
     {
         NSString *name = [(NSDictionary *)obj objectForKey:@"name"];
         if(name)
         {
             NKIssue *nkIssue = [nkLib issueWithName:name];
             if(!nkIssue)
             {
                 nkIssue = [nkLib addIssueWithName:name date:[(NSDictionary *)obj objectForKey:@"date"]];
                 
                 // so this is a new issue (so far)
                 // update the newsstand app icon and add "new" badge to it
                 NSString *newsstandIconImageUrl = [(NSDictionary *)obj objectForKey:@"newsstandIcon"];
                 if(newsstandIconImageUrl)
                 {
                     AFImageRequestOperation *op = [AFImageRequestOperation imageRequestOperationWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:newsstandIconImageUrl]] success:^(UIImage *image) {
                         if(image)
                         {
                             [[UIApplication sharedApplication] setNewsstandIconImage:image];
                             [[UIApplication sharedApplication] setApplicationIconBadgeNumber:1];
                         }
                     }];
                     
                     [op start];
                 }
                 
                 [self saveLatestIssue:name];
             }
             
             NSLog(@"Issue: %@",nkIssue);
         }
     }];
}

- (NSInteger)numberOfIssues
{
    if(self.ready && self.issueArray)
        return self.issueArray.count;
    else
        return 0;
}

- (void)removeDownloadedIssue:(NSString *)issueName
{
    NKLibrary *nkLib = [NKLibrary sharedLibrary];
    NKIssue *issue = [nkLib issueWithName:issueName];
    if (issue)
    {
        [[NKLibrary sharedLibrary] removeIssue:issue];
        
        // now we need to add the removed issue(s) meta data from plist back to nk library
        [self addIssuesInNewsstand];
    }
}

- (void)downloadIssue:(NSString *)issueName
           indexPath:(NSIndexPath *)indexPath
{
    NKLibrary *library = [NKLibrary sharedLibrary];
    
    NKIssue *issue = [library issueWithName:issueName];
    NSURL *downloadURL = [self contentURLForIssueWithName:issue.name];
    
    if(!downloadURL)
        return;
    
    NKAssetDownload *assetDownload = [issue addAssetWithRequest:[NSURLRequest requestWithURL:downloadURL]];
    
    [assetDownload setUserInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                [NSNumber numberWithInt:indexPath.row], @"indexPathRow",
                                [NSNumber numberWithInt:indexPath.section], @"indexPathSection",nil]];
    
    [assetDownload downloadWithDelegate:self];
}

- (void)resumeAnyFailedDownload
{
    // resume any failed downloads
    NKLibrary *nkLib = [NKLibrary sharedLibrary];
    for(NKAssetDownload *asset in [nkLib downloadingAssets])
    {
        [asset downloadWithDelegate:self];
    }
}

- (void)setCurrentIssue:(NSString *)issueName
{
    NKLibrary *library = [NKLibrary sharedLibrary];
    NKIssue *nkIssue = [library issueWithName:issueName];
    
    if(nkIssue)
        library.currentlyReadingIssue = nkIssue;
}

- (void)saveLatestIssue:(NSString *)issueName
{
    if(issueName)
    {
        [[NSUserDefaults standardUserDefaults] setValue:issueName forKey:@"latestIssueName"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (void)markIssueRead:(NSString *)issueName
{
    NSUserDefaults *df = [NSUserDefaults standardUserDefaults];
    NSString *latestIssue = [df stringForKey:@"latestIssueName"];
    
    if(issueName && latestIssue && [issueName isEqualToString:latestIssue] == YES)
    {
         [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
    }
}

- (BOOL)checkAvailableDiskSpace
{
    NSDictionary * fileAttributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:DocumentsDirectory error:NULL];
    unsigned long long freeSpaceInBytes = [[fileAttributes objectForKey:NSFileSystemFreeSize] unsignedLongLongValue];
    
    return freeSpaceInBytes > 1000 * 1000 * 700; //700mb
}

#pragma mark - subscription related code

- (void)processSubscription
{
    if(subscriptionProcessing == YES)
        return;
    
    subscriptionProcessing = YES;
    NSSet *subscription = [NSSet setWithObject:FREE_SUBSCRIPTION_ID];
    SKProductsRequest *subscriptionRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:subscription];
    subscriptionRequest.delegate = self;
    
    [subscriptionRequest start];
}

#pragma mark - SKProductsRequestDelegate

- (void)requestDidFinish:(SKRequest *)request
{
    subscriptionProcessing = NO;
    NSLog(@"requestDidFinish Request: %@", request);
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error
{
    subscriptionProcessing = NO;
    NSLog(@"Request %@ failed with error %@", request, error);
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"訂閱失敗"
                                                    message:[error localizedDescription]
                                                   delegate:nil
                                          cancelButtonTitle:@"Close"
                                          otherButtonTitles:nil];
    [alert show];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response
{
    NSLog(@"productsRequest: %@ -- didReceiveResponse: %@", request, response);
    NSLog(@"Products: %@", response.products);
    
    for(SKProduct *product in response.products)
    {
        SKPayment *payment = [SKPayment paymentWithProduct:product];
        [[SKPaymentQueue defaultQueue] addPayment:payment];
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions
{
    for(SKPaymentTransaction *transaction in transactions)
    {
        NSLog(@"Updated updatedTransactions %@", transaction);
        
        switch (transaction.transactionState)
        {
            case SKPaymentTransactionStateFailed:
                [self errorWithTransaction:transaction];
                break;
            case SKPaymentTransactionStatePurchasing:
                NSLog(@"Purchasing...");
                break;
            case SKPaymentTransactionStatePurchased:
            case SKPaymentTransactionStateRestored:
                [self finishedTransaction:transaction];
                break;
            default:
                break;
        }
    }
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    NSLog(@"Restored all completed transactions");
}

- (void)finishedTransaction:(SKPaymentTransaction *)transaction
{
    NSLog(@"finishedTransaction %@", transaction);
    
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    
    // save receipt
    [[NSUserDefaults standardUserDefaults] setObject:transaction.transactionIdentifier
                                              forKey:@"receipt"];
    // check receipt
    [self checkReceipt:transaction.transactionReceipt];
}

- (void)errorWithTransaction:(SKPaymentTransaction *)transaction
{
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"訂閱失敗"
                                                    message:[transaction.error localizedDescription]
                                                   delegate:nil
                                          cancelButtonTitle:@"Close"
                                          otherButtonTitles:nil];
    [alert show];
}

- (void)checkReceipt:(NSData *)receipt
{
    // save receipt
    NSString *receiptStorageFile = [DocumentsDirectory stringByAppendingPathComponent:@"receipts.plist"];
    NSMutableArray *receiptStorage = [[NSMutableArray alloc] initWithContentsOfFile:receiptStorageFile];
    
    if(!receiptStorage) {
        receiptStorage = [[NSMutableArray alloc] init];
    }
    
    [receiptStorage addObject:receipt];
    [receiptStorage writeToFile:receiptStorageFile atomically:YES];
    
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"訂閱成功"
                                                    message:nil
                                                   delegate:nil
                                          cancelButtonTitle:@"Close"
                                          otherButtonTitles:nil];
    [alert show];
    
    /*
    
    [ReceiptCheck validateReceiptWithData:receipt completionHandler:^(BOOL success,NSString *answer){
        
        if(success==YES)
        {
            NSLog(@"Receipt has been validated: %@",answer);
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Purchase OK" message:nil delegate:nil cancelButtonTitle:@"Close" otherButtonTitles:nil];
            [alert show];
        }
        else
        {
            NSLog(@"Receipt not validated! Error: %@",answer);
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Purchase Error" message:@"Cannot validate receipt" delegate:nil cancelButtonTitle:@"Close" otherButtonTitles:nil];
            [alert show];
        };
    }];
     */
}

#pragma mark - NSURLConnectionDownloadDelegate

- (void)connection:(NSURLConnection *)connection
      didWriteData:(long long)bytesWritten
 totalBytesWritten:(long long)totalBytesWritten
expectedTotalBytes:(long long)expectedTotalBytes
{
    NKAssetDownload *assetDownload = connection.newsstandAssetDownload;
    
    NSNumber *row = [assetDownload.userInfo objectForKey:@"indexPathRow"];
    NSNumber *section = [assetDownload.userInfo objectForKey:@"indexPathSection"];
    
    if(row && section)
    {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row.intValue
                                                    inSection:section.intValue];
        
        if(self.bookcaseDelegate)
           [self.bookcaseDelegate downloadingProgressForIndexPath:indexPath
                                                     didWriteData:bytesWritten
                                                totalBytesWritten:totalBytesWritten
                                               expectedTotalBytes:expectedTotalBytes];
    }
}

- (void)connectionDidResumeDownloading:(NSURLConnection *)connection
                     totalBytesWritten:(long long)totalBytesWritten
                    expectedTotalBytes:(long long)expectedTotalBytes
{
    NKAssetDownload *assetDownload = connection.newsstandAssetDownload;
    
    NSNumber *row = [assetDownload.userInfo objectForKey:@"indexPathRow"];
    NSNumber *section = [assetDownload.userInfo objectForKey:@"indexPathSection"];
    
    if(row && section)
    {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row.intValue
                                                    inSection:section.intValue];
        
        if(self.bookcaseDelegate)
            [self.bookcaseDelegate downloadingResumedForIndexPath:indexPath
                                                totalBytesWritten:totalBytesWritten
                                               expectedTotalBytes:expectedTotalBytes];
    }
}

- (void)connectionDidFinishDownloading:(NSURLConnection *)connection
                        destinationURL:(NSURL *)destinationURL
{
    NKAssetDownload *assetDownload = connection.newsstandAssetDownload;
    NKIssue *issue = assetDownload.issue;
    NSNumber *row = [assetDownload.userInfo objectForKey:@"indexPathRow"];
    NSNumber *section = [assetDownload.userInfo objectForKey:@"indexPathSection"];
    
    if(row && section)
    {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row.intValue
                                                    inSection:section.intValue];
        
        if(self.bookcaseDelegate)
            [self.bookcaseDelegate downloadingFinishedForIndexPath:indexPath
                                                             issue:issue
                                                    destinationURL:destinationURL];
    }
}

#pragma mark - singleton implementation code

static MagazineManager *singletonManager = nil;
+ (MagazineManager *)sharedInstance {
    
    static dispatch_once_t pred;
    static MagazineManager *manager;
    
    dispatch_once(&pred, ^{
        manager = [[self alloc] init];
    });
    return manager;
}
+ (id)allocWithZone:(NSZone *)zone {
    @synchronized(self) {
        if (singletonManager == nil) {
            singletonManager = [super allocWithZone:zone];
            return singletonManager;  // assignment and return on first allocation
        }
    }
    return nil; // on subsequent allocation attempts return nil
}
- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end
