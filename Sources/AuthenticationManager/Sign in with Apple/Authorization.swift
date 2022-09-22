//
//  Authorization.swift
//  
//
//  Created by Kevin Waltz on 22.04.22.
//

import Foundation
import AuthenticationServices

extension AuthenticationManager {
    // identifier from apple credentials - used for checking authorization state after login
    public static var authorizationKey: String? {
        get { UserDefaults.standard.string(forKey: UserDefaultsKeys.authorizationIdKey.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.authorizationIdKey.rawValue) }
    }
    
    public static func removeAuthorizationKey() {
        UserDefaults.standard.set(nil, forKey: UserDefaultsKeys.authorizationIdKey.rawValue)
    }
    
    
    /**
     Check whether the user authorized the app to use SignInWithApple.
     
     This cannot be used to ask for permission. It is solely to check for the permission status.
     */
    static func checkAuthorizationState(completion: @escaping (Result<Any?, AuthorizationError>) -> Void) {
        guard let authorizationKey = authorizationKey, !authorizationKey.isEmpty else {
            completion(.failure(.credentialState(description: "Missing Key from User Defaults", error: nil)))
            return
        }
        
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: authorizationKey) { credentialState, error in
            switch credentialState {
            case .authorized:
                completion(.success(nil))
            default:
                completion(.failure(.credentialState(description: credentialState.description, error: error)))
            }
        }
    }
    
    
    
    
}