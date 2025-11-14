//
//  InsecureURLSessionDelegate.swift
//  HueDatShared
//
//  Created by David Tanquary on 10/29/25.
//

import Foundation

// MARK: - Insecure URL Session Delegate
public class InsecureURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {

    public override init() {
        super.init()
    }

    // Session-level challenge handler (for backward compatibility with data(for:) and other methods)
    public func urlSession(_ session: URLSession,
                   didReceive challenge: URLAuthenticationChallenge,
                   completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    // Task-level challenge handler (required for bytes(for:) and async streaming methods)
    public func urlSession(_ session: URLSession,
                   task: URLSessionTask,
                   didReceive challenge: URLAuthenticationChallenge,
                   completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    // Shared SSL bypass logic
    private func handleChallenge(_ challenge: URLAuthenticationChallenge,
                                completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Accept any certificate (insecure - only use for trusted local network devices!)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            let credential = URLCredential(trust: trust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
