import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

/// Connexion : « Se connecter avec Apple » ou code à 6 chiffres reçu par e-mail.
struct SignInView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var nonce = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header

                    SignInWithAppleButton(.signIn) { request in
                        nonce = Nonce.random()
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = Nonce.sha256(nonce)
                    } onCompletion: { result in
                        handleApple(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(isWorking)

                    HStack {
                        Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                        Text("ou").font(.footnote).foregroundStyle(.secondary)
                        Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                    }

                    emailSection

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.pass)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("En te connectant, tu acceptes les conditions générales de vente de la boutique StyleMatch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Plus tard") { dismiss() }
                }
            }
            .overlay {
                if isWorking { ProgressView().controlSize(.large) }
            }
            .onChange(of: store.isSignedIn) { _, signedIn in
                if signedIn { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.hotRed)
            Text("Connecte-toi")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
            Text("Pour remplir ton panier, acheter tes pièces préférées et suivre tes commandes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var emailSection: some View {
        VStack(spacing: 12) {
            TextField("Ton adresse e-mail", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .disabled(codeSent)

            if codeSent {
                TextField("Code à 6 chiffres", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .font(.title3.monospacedDigit())
                    .padding(14)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                Button("Valider le code", action: verifyCode)
                    .buttonStyle(GradientButtonStyle())
                    .disabled(code.filter(\.isNumber).count < 6 || isWorking)
                Button("Changer d'adresse ou renvoyer un code") {
                    codeSent = false
                    code = ""
                }
                .font(.footnote)
            } else {
                Button("Recevoir un code par e-mail", action: sendCode)
                    .buttonStyle(GradientButtonStyle())
                    .disabled(!email.contains("@") || isWorking)
            }
        }
    }

    // MARK: - Actions

    private func sendCode() {
        run {
            try await store.sendEmailCode(to: email)
            codeSent = true
        }
    }

    private func verifyCode() {
        run {
            try await store.verifyEmailCode(email: email, code: code.filter(\.isNumber))
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Connexion Apple impossible, réessaie."
                return
            }
            let fullName = credential.fullName
            let rawNonce = nonce
            run {
                try await store.signInWithApple(idToken: token, nonce: rawNonce, fullName: fullName)
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = error.localizedDescription
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        errorMessage = nil
        isWorking = true
        Task {
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

/// Nonce de sécurité exigé par « Se connecter avec Apple ».
enum Nonce {
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Encart « Connecte-toi » affiché dans le panier ou le profil sans compte.
struct SignInPrompt: View {
    @Environment(AppStore.self) private var store
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text(message)
        } actions: {
            Button("Se connecter") { store.showSignIn = true }
                .buttonStyle(GradientButtonStyle())
                .frame(maxWidth: 260)
        }
    }
}
