import AppKit
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthService
    @State private var waiting = false
    @State private var userCode = ""
    @State private var verifyURL: URL?
    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 20)

            Image(systemName: "play.tv.fill")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text("Kinopub").font(.largeTitle.weight(.bold))
            Text("Войдите в аккаунт, чтобы продолжить")
                .foregroundColor(.secondary)

            if waiting {
                VStack(spacing: 12) {
                    if userCode.isEmpty {
                        ProgressView().scaleEffect(0.8)
                        Text("Получаю код…").foregroundColor(.secondary)
                    } else {
                        Text("Код для входа").font(.headline)

                        Text(userCode)
                            .font(.system(size: 34, weight: .bold, design: .monospaced))
                            .tracking(8)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 8)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

                        Text("Введите его на kino.watch/device")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        HStack(spacing: 10) {
                            Button("Открыть страницу входа") {
                                if let url = verifyURL { NSWorkspace.shared.open(url) }
                            }
                            Button(copied ? "Скопировано" : "Скопировать код") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(userCode, forType: .string)
                                copied = true
                            }
                        }
                        .controlSize(.large)

                        Button("Отмена", role: .cancel) {
                            auth.cancelAuthorization()
                            waiting = false
                            userCode = ""
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    }
                }
                .frame(minHeight: 170)
            } else {
                Button(action: login) {
                    Text("Войти")
                        .fontWeight(.semibold)
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }

            if let error = auth.authError {
                Text(error)
                    .font(.callout)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
            }

            Spacer(minLength: 20)
        }
        .frame(width: 480, height: 480)
        .onChange(of: auth.authError) { _, newValue in
            if newValue != nil { waiting = false }
        }
        .onChange(of: auth.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated { waiting = false }
        }
    }

    private func login() {
        waiting = true
        copied = false
        auth.authError = nil

        Task { @MainActor in
            do {
                let device = try await auth.startDeviceAuth()
                userCode = device.userCode
                verifyURL = device.verificationURL
                NSWorkspace.shared.open(device.verificationURL)
            } catch {
                waiting = false
                auth.authError = error.localizedDescription
            }
        }
    }
}
