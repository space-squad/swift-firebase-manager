//
//  Authentication.swift
//  
//
//  Created by Kevin Waltz on 22.04.22.
//

import AuthenticationServices
import FirebaseAuth

extension AuthenticationManager {
    /**
     Add to the Sign in with Apple request a nonce string.
     
     - Parameter request: Request sent to Apple
     - Parameter scopes: Required user data (full name and/or email)
     */
    public static func editRequest(_ request: ASAuthorizationAppleIDRequest? = nil, scopes: [ASAuthorization.Scope] = [.fullName, .email]) -> ASAuthorizationAppleIDRequest {
        let request = request ?? ASAuthorizationAppleIDProvider().createRequest()
        // needs to be generated on each request
        currentNonce = Nonce()
        
        request.requestedScopes = scopes
        request.nonce = currentNonce.sha256()
        
        return request
    }
    
    /**
     Handle the result passed after the Sign in with Apple button was tapped.
     
     - Parameter result: Result passed from Apple
     */
    public static func handleAuthorizationResult(_ authResult: Result<ASAuthorization, Error>, completion: @escaping (Error?) -> Void) {
        
        checkAuthorizationResult(authResult) { result in
            switch result {
            case .success(let credential):
                updateUserInfo(credential: credential, repository: nil, completion: completion)
            case .failure(let error):
                self.handleError(error, completion: completion)
            }
        }
    }
    
    private static func checkAuthorizationResult(_ result: Result<ASAuthorization, Error>, completion: @escaping (Result<ASAuthorizationAppleIDCredential, Error>) -> Void) {
        
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential
            else {
                completion(.failure(AuthorizationError.credential(description: "Did not receive an AppleIDCredential, but \(type(of: authorization.credential))")))
                return
            }
            authenticateByAppleId(credential: appleIDCredential, completion: completion)
        case .failure(let error):
            completion(.failure(AuthorizationError.credential(error: error)))
        }
    }
    
    private static func authenticateByAppleId(credential appleCredential: ASAuthorizationAppleIDCredential, completion: @escaping (Result<ASAuthorizationAppleIDCredential, Error>) -> Void) {
        self.authorizationKey = appleCredential.user
        
        guard let identityToken = appleCredential.identityToken,
              let stringifiedToken = String(data: identityToken, encoding: .utf8)
        else {
            completion(.failure(AuthorizationError.credential(description: "Missing Identity Token")))
            return
        }
        
        // create credential for firebase, based on apple-credential
        let credential = OAuthProvider.credential(withProviderID: providerId,
                                                  idToken: stringifiedToken,
                                                  rawNonce: currentNonce.value)
        
        authenticate(credential: credential) { result in
            completion(result.map {_ in appleCredential})
        }
    }
    
    static func authenticate(credential: AuthCredential, completion: @escaping (Result<Bool, Error>) -> Void) {
        // depending on current authentication state, the user is signed in, refreshed or linked
        if let currentUser = currentUser {
            if !userIsAuthenticated {
                // anonymous account is linked to new created one
                currentUser.link(with: credential, completion: handleResult)
            } else {
                currentUser.reauthenticate(with: credential, completion: handleResult)
            }
        } else {
            auth.signIn(with: credential, completion: handleResult)
        }
        
        func handleResult(authResult: AuthDataResult?, error: Error?) {
            if authResult?.user != nil {
                completion(.success(true))
                return
            }
            completion(.failure(AuthorizationError.firebase(error: error)))
        }
    }
    
    /**
     Save the received user information from sign in with Apple to Firebase.
     If the user authenticated on this device already, the requested infos are not in the scope, so we need to take care, that already existing values are not overwritten by empty values
     */
    static func updateUserInfo(credential: ASAuthorizationAppleIDCredential, repository: UserRepositoryProtocol?, completion: @escaping (Error?) -> Void) {
        if let email = credential.email {
            UserDefaults.standard.set(email, forKey: UserDefaultsKeys.emailKey.rawValue)
        }
        
        
        let fullName = credential.fullName
        let displayName = [fullName?.givenName, fullName?.familyName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        guard !displayName.isEmpty,
              let changeRequest = currentUser?.createProfileChangeRequest()
            else { completion(nil); return }
        
        UserDefaults.standard.set(displayName, forKey: UserDefaultsKeys.userNameKey.rawValue)
        
        changeRequest.displayName = displayName
        changeRequest.commitChanges { error in
            if error != nil {
                // TODO: This is an error that should only passed as a warning for the Dev for logging.
            }
            
            if let repository = repository, let email = credential.email {
                repository.saveUser(name: displayName, email: email, completion: completion)
            } else {
                completion(nil)
            }
        }
    }
}


extension AuthenticationManager: AuthDelegate {
    /**
     Security-sensitive actions (deleting account for now, later may be password change or mail-adress-change) require that the user has recently signed in and we catch at this point the "requiresRecentLogin"-Error.
     When a re-authentication is needed, we need to ask the user again for the credentials.
     */
    public static func reauthenticateUser() {
#if canImport(UIKit)
            self.authView = AuthenticationView(delegate: nil)
            self.authView?.authenticateBySignInWithApple()
        //        view?.authenticateBySignInWithApple(delegate: nil)
#endif
        // TODO: SwiftUI
    }
    
    
    public func authenticationCompleted(error: Error?) {
        print(error?.localizedDescription ?? "SUCCESS")
    }
    
    
}
