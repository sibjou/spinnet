import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

class AuthService: ObservableObject {

    @Published var isLoggedIn = false
    @Published var currentUserId: String? = nil
    @Published var userProfile: UserProfile? = nil
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    private let db = Firestore.firestore()

    /// Проверка аккаунта не чаще раза в полминуты: на запуске её просят сразу несколько мест
    private var accountCheck = RefreshPolicy(minInterval: 30)

    init() {
        if let user = Auth.auth().currentUser {
            self.isLoggedIn = true
            self.currentUserId = user.uid
            // Одно чтение документа: оно и проверяет, что аккаунт жив, и заполняет профиль
            verifyCurrentUser()
        }
        Perf.mark("вход: состояние определено")
    }

    // MARK: - Регистрация

    func register(email: String, password: String, firstName: String, lastName: String,
                  city: String, skillLevel: String, grip: String, playStyle: String,
                  ratingLink: String = "") {
        isLoading = true
        errorMessage = nil

        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.isLoading = false
                    self?.errorMessage = self?.russianError(error)
                    return
                }
                guard let userId = result?.user.uid else { self?.isLoading = false; return }

                let userData: [String: Any] = [
                    "firstName": firstName, "lastName": lastName, "email": email,
                    "city": CityName.canonical(city), "skillLevel": skillLevel, "grip": grip,
                    "playStyle": playStyle, "ratingLink": ratingLink,
                    "createdAt": Timestamp()
                ]

                self?.db.collection("users").document(userId).setData(userData) { error in
                    DispatchQueue.main.async {
                        self?.isLoading = false
                        if let error = error {
                            // Профиль не записался — удаляем только что созданный аккаунт,
                            // иначе email окажется занятым, а войти будет нельзя
                            result?.user.delete { _ in }
                            self?.errorMessage = self?.russianError(error)
                        } else {
                            self?.currentUserId = userId
                            self?.userProfile = UserProfile(id: userId, data: userData)
                            self?.isLoggedIn = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Вход

    func login(email: String, password: String) {
        isLoading = true
        errorMessage = nil

        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = self?.russianError(error)
                } else if let uid = result?.user.uid {
                    self?.currentUserId = uid
                    self?.loadUserProfile(userId: uid)
                    self?.isLoggedIn = true
                }
            }
        }
    }

    // MARK: - Выход

    func logout() {
        // Отметка «не в сети» должна уйти, пока вход ещё не снят
        PresenceService.shared.goOffline(userId: currentUserId)
        BlockService.shared.reset()
        UserService.shared.clearNameCache()
        accountCheck.reset()
        try? Auth.auth().signOut()
        isLoggedIn = false
        currentUserId = nil
        userProfile = nil
    }

    // MARK: - Сброс пароля

    func resetPassword(email: String) {
        isLoading = true
        errorMessage = nil

        Auth.auth().sendPasswordReset(withEmail: email) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error, (error as NSError).code == 17008 {
                    self?.errorMessage = "Неверный формат email"
                } else {
                    self?.errorMessage = "Если аккаунт существует, письмо отправлено на \(email)"
                }
            }
        }
    }

    // MARK: - Обновить профиль (вызывать после EditProfileView)

    func refreshProfile() {
        guard let userId = currentUserId else { return }
        loadUserProfile(userId: userId)
    }

    // MARK: - Внутренние методы

    private func loadUserProfile(userId: String) {
        db.collection("users").document(userId).getDocument { [weak self] doc, _ in
            DispatchQueue.main.async {
                guard let data = doc?.data() else { return }
                self?.userProfile = UserProfile(id: userId, data: data)
            }
        }
    }

    /// Аккаунт на месте? Если профиль удалён — выходим. Тем же чтением обновляется `userProfile`.
    /// Без сети документ не приходит вовсе (`exists` остаётся nil) — тогда ничего не трогаем.
    func verifyCurrentUser(force: Bool = false) {
        guard let userId = currentUserId, accountCheck.shouldRun(force: force) else { return }
        db.collection("users").document(userId).getDocument { [weak self] doc, _ in
            DispatchQueue.main.async {
                guard let self, self.currentUserId == userId else { return }
                if doc?.exists == false {
                    self.logout()
                } else if let data = doc?.data() {
                    self.userProfile = UserProfile(id: userId, data: data)
                    Perf.mark("профиль пользователя загружен")
                }
            }
        }
    }

    func russianError(_ error: Error) -> String {
        switch (error as NSError).code {
        case 17008: return "Неверный формат email"
        case 17009: return "Неверный пароль"
        case 17011: return "Пользователь с таким email не найден"
        case 17007: return "Этот email уже зарегистрирован"
        case 17026: return "Пароль должен быть не менее 6 символов"
        case 17010: return "Слишком много попыток. Попробуйте позже"
        case 17020: return "Нет подключения к интернету"
        case 17004: return "Неверный email или пароль"
        default:    return "Произошла ошибка. Попробуйте ещё раз"
        }
    }
}
