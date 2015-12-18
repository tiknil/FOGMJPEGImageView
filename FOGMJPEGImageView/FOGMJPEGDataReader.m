//
//  FOGMJPEGDataReader.m
//  
//  Copyright (c) 2014 Richard McGuire
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

#import "FOGMJPEGDataReader.h"
#import "FOGJPEGImageMarker.h"

@interface FOGMJPEGDataReader()

@property (nonatomic, strong, readwrite) NSURLSession *URLSession;

@property (nonatomic, strong) NSOperationQueue *processingQueue;

@property (nonatomic, strong, readwrite) NSURLSessionDataTask *dataTask;

@property (nonatomic, strong, readwrite) NSMutableData *receivedData;

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSString *username;
@property (nonatomic, strong) NSString *password;

@end

@implementation FOGMJPEGDataReader

#pragma mark - Initializers

- (instancetype)init
{
    self = [super init];
    if ( !self ) {
        return nil;
    }
    self.imageScale = 0.5;
    self.processingQueue = [[NSOperationQueue alloc] init];
    
    return self;
}

#pragma mark - FOGMJPEGDataReader

- (void)startReadingFromURL:(NSURL *)URL username:(NSString *)username password:(NSString *)password
{
    self.receivedData = [[NSMutableData alloc] init];
    self.url = URL;
    self.username = username;
    self.password = password;
    
    
    // 1 - define credentials as a string with format:
    //    "username:password"
    //
    NSString *authString = [NSString stringWithFormat:@"%@:%@",
                            username,
                            password];
    
    // 2 - convert authString to an NSData instance
    NSData *authData = [authString dataUsingEncoding:NSUTF8StringEncoding];
    
    // 3 - build the header string with base64 encoded data
    NSString *authHeader = [NSString stringWithFormat: @"Basic %@",
                            [authData base64EncodedStringWithOptions:0]];
    
    // 4 - create an NSURLSessionConfiguration instance
    NSURLSessionConfiguration *sessionConfig =
    [NSURLSessionConfiguration defaultSessionConfiguration];
    
    // 5 - add custom headers, including the Authorization header
    [sessionConfig setHTTPAdditionalHeaders:@{
                                              @"Authorization": authHeader
                                              }
     ];
    self.URLSession = [NSURLSession sessionWithConfiguration:sessionConfig delegate:self delegateQueue:self.processingQueue];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:URL];
    self.dataTask = [self.URLSession dataTaskWithRequest:request];
    [self.dataTask resume];
}

- (void)stop
{
    [self.dataTask cancel];
    self.dataTask = nil;
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    [self.receivedData appendData:data];
//    NSLog(@"[%@] - data: %@ %@", self.url, data, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    
    // if we don't have an end marker then we can continue
    NSRange endMarkerRange = [self.receivedData rangeOfData:[FOGJPEGImageMarker JPEGEndMarker]
                                                    options:0
                                                      range:NSMakeRange(0, [self.receivedData length])];
    if ( endMarkerRange.location == NSNotFound ) {
        return;
    }
    
    // if we don't have a start marker prior to the end marker discard bytes and continue
    NSRange startMarkerRange = [self.receivedData rangeOfData:[FOGJPEGImageMarker JPEGStartMarker]
                                                      options:0
                                                        range:NSMakeRange(0, endMarkerRange.location)];
    if ( startMarkerRange.location == NSNotFound ) {
        // todo: should trim receivedData to endMarkerRange.location + 2 until end
        return;
    }
    
    NSUInteger imageDataLength = (endMarkerRange.location + 2) - startMarkerRange.location;
    NSRange imageDataRange = NSMakeRange(startMarkerRange.location, imageDataLength);
    NSData *imageData = [self.receivedData subdataWithRange:imageDataRange];
    UIImage *image = [UIImage imageWithData:imageData scale:self.imageScale];
    
    if ( image ) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong id<FOGMJPEGDataReaderDelegate> strongDelegate = self.delegate;
            [strongDelegate FOGMJPEGDataReader:self receivedImage:image];
        });
    }
    
    NSUInteger newStartLocation = endMarkerRange.location + 2;
    NSUInteger newDataLength = [self.receivedData length] - newStartLocation;
    NSData *unusedData = [self.receivedData subdataWithRange:NSMakeRange(newStartLocation, newDataLength)];
    self.receivedData = [NSMutableData dataWithData:unusedData];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (error.code == kCFURLErrorCancelled) {
        // Manually cancelled request
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong id<FOGMJPEGDataReaderDelegate> strongDelegate = self.delegate;
        [strongDelegate FOGMJPEGDataReader:self loadingImageDidFailWithError:error];
    });
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler
{
    if (self.username != nil) {
        completionHandler(NSURLSessionAuthChallengeUseCredential,[NSURLCredential credentialWithUser:self.username
                                                                                            password:(self.password != nil ? self.password : @"")
                                                                                         persistence:NSURLCredentialPersistenceForSession]);
    }else{
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge,nil);
    }
}

@end
