import SwiftUI

// MARK: - Настройки → Приватность
struct PrivacySettingsView: View {
    @ObservedObject var authService: AuthService

    @State private var settings = PrivacySettings()
    @State private var isLoaded = false
    @State private var saveFailed = false

    var body: some View {
        List {
            Section {
                Toggle("Статистика и графики", isOn: binding(\.showStats))
                Toggle("Матчи и соперники", isOn: binding(\.showMatchHistory))
                    .disabled(!settings.showStats)
                Toggle("Турниры", isOn: binding(\.showTournaments))
            } header: {
                Text("Что видят другие игроки")
            } footer: {
                Text("Вы всегда видите всё о себе. Если выключить статистику, другие не увидят ни графики, ни список матчей, ни число сыгранных игр.")
            }

            Section {
                Toggle("Уточнения по встречам", isOn: binding(\.allowClarifications))
            } header: {
                Text("Сообщения")
            } footer: {
                Text("Если выключить, партнёр по игре не сможет начать с вами уточнение времени и места. Бронировать заявки и вносить счёт по-прежнему можно. Уже начатые диалоги сохраняются.")
            }

            Section {
                Toggle("Когда я был(а) в сети", isOn: binding(\.showLastSeen))
            } header: {
                Text("Присутствие")
            } footer: {
                Text("Если выключить, другие игроки не увидят, что вы в сети, и точное время визита: им будет показано только «был(а) недавно».")
            }

            Section {
                Label("Имя, город, уровень и отзывы видны всегда: на них держится доверие между игроками.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundColor(AppColor.textSecondary)
            }
        }
        .disabled(!isLoaded)
        .navigationTitle("Приватность")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Не удалось сохранить", isPresented: $saveFailed) {
            Button("OK") {}
        } message: {
            Text("Проверьте интернет и попробуйте ещё раз.")
        }
        .onAppear { load() }
    }

    private func binding(_ keyPath: WritableKeyPath<PrivacySettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                settings[keyPath: keyPath] = newValue
                save()
            }
        )
    }

    private func load() {
        guard let userId = authService.currentUserId else { return }
        UserService.shared.fetchUser(id: userId) { data in
            settings = PrivacySettings(userData: data)
            isLoaded = true
        }
    }

    private func save() {
        guard let userId = authService.currentUserId else { return }
        UserService.shared.updateProfile(userId: userId, fields: ["privacy": settings.firestoreMap]) { error in
            if error != nil {
                saveFailed = true
                load()      // вернуть то, что реально сохранено
            }
        }
    }
}
