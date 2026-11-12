import SwiftUI

/// Удаление аккаунта: что исчезнет, пароль для подтверждения, кнопка.
/// Пароль — это и подтверждение намерения, и «свежий вход», без которого вход не удаляется.
struct DeleteAccountView: View {
    @ObservedObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var isDeleting = false
    @State private var errorText: String? = nil
    @State private var showFinalConfirm = false
    @FocusState private var passwordFocused: Bool

    private let service = AccountDeletionService()

    var body: some View {
        Form {
            Section {
                ForEach(AccountDeletionRules.consequences, id: \.self) { line in
                    Label {
                        Text(line)
                            .font(.subheadline)
                            .foregroundColor(AppColor.textPrimary)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundColor(AppColor.textSecondary)
                            .padding(.top, 6)
                    }
                }
            } header: {
                Text("Что произойдёт")
            }

            Section {
                SecureField("Пароль", text: $password)
                    .textContentType(.password)
                    .focused($passwordFocused)
                    .submitLabel(.done)
                    .disabled(isDeleting)
            } header: {
                Text("Подтверждение")
            } footer: {
                Text("Введите пароль от аккаунта, чтобы подтвердить удаление. Отменить его будет нельзя.")
            }

            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundColor(AppColor.danger)
                }
            }

            Section {
                Button(role: .destructive) {
                    passwordFocused = false
                    showFinalConfirm = true
                } label: {
                    HStack {
                        if isDeleting { ProgressView() }
                        Text(isDeleting ? "Удаляем…" : "Удалить аккаунт навсегда")
                            .frame(maxWidth: isDeleting ? nil : .infinity)
                    }
                }
                .disabled(!AccountDeletionRules.canSubmit(password: password) || isDeleting)
            }
        }
        .navigationTitle("Удаление аккаунта")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isDeleting)
        .alert("Удалить аккаунт навсегда?", isPresented: $showFinalConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) { performDelete() }
        } message: {
            Text("Это действие нельзя отменить.")
        }
    }

    private func performDelete() {
        isDeleting = true
        errorText = nil
        service.delete(password: password, authService: authService) { failure in
            isDeleting = false
            if let failure {
                errorText = failure
            }
            // Успех: AuthService снял вход, приложение само вернётся на экран входа
        }
    }
}
