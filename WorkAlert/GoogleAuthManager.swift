import Foundation
import GoogleSignIn

@Observable
class GoogleAuthManager {
    var isSignedIn: Bool = false
    var userEmail: String?
    var error: String?

    // OAuth Client ID from Google Cloud Console
    static let clientID = "229678887588-bt4vpmks8aaad0lkcomaavkmktf1ev78.apps.googleusercontent.com"

    // Calendar API scope for read-only access
    private let calendarScope = "https://www.googleapis.com/auth/calendar.readonly"

    init() {
        // Check if user is already signed in
        restorePreviousSignIn()
    }

    // MARK: - Restore Previous Sign In

    func restorePreviousSignIn() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            DispatchQueue.main.async {
                if let user = user {
                    self?.isSignedIn = true
                    self?.userEmail = user.profile?.email
                } else {
                    self?.isSignedIn = false
                    self?.userEmail = nil
                }
            }
        }
    }

    // MARK: - Sign In

    func signIn() async throws {
        guard let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = await windowScene.windows.first?.rootViewController else {
            throw GoogleAuthError.noRootViewController
        }

        // Configure with calendar scope
        let config = GIDConfiguration(clientID: Self.clientID)
        GIDSignIn.sharedInstance.configuration = config

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                GIDSignIn.sharedInstance.signIn(
                    withPresenting: rootViewController,
                    hint: nil,
                    additionalScopes: [self.calendarScope]
                ) { [weak self] result, error in
                    if let error = error {
                        self?.error = error.localizedDescription
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let user = result?.user else {
                        let error = GoogleAuthError.noUser
                        self?.error = error.localizedDescription
                        continuation.resume(throwing: error)
                        return
                    }

                    DispatchQueue.main.async {
                        self?.isSignedIn = true
                        self?.userEmail = user.profile?.email
                        self?.error = nil
                    }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Sign Out

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        userEmail = nil
    }

    // MARK: - Get Access Token

    func getAccessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleAuthError.notSignedIn
        }

        // Refresh token if needed
        return try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { user, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let accessToken = user?.accessToken.tokenString else {
                    continuation.resume(throwing: GoogleAuthError.noAccessToken)
                    return
                }

                continuation.resume(returning: accessToken)
            }
        }
    }
}

// MARK: - Errors

enum GoogleAuthError: LocalizedError {
    case noRootViewController
    case noUser
    case notSignedIn
    case noAccessToken

    var errorDescription: String? {
        switch self {
        case .noRootViewController:
            return "Unable to find root view controller"
        case .noUser:
            return "Sign in failed - no user returned"
        case .notSignedIn:
            return "User is not signed in"
        case .noAccessToken:
            return "Unable to get access token"
        }
    }
}
