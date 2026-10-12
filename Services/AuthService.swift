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

    init() {
        if let user = Auth.auth().currentUser {
            self.isLoggedIn = true
            self.currentUserId = user.uid
            verifyCurrentUser()
            loadUserProfile(userId: user.uid)     // загружаем профиль при старте
        }
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
                    "city": city, "skillLevel": skillLevel, "grip": grip,
                    "playStyle": playStyle, "ratingLink": ratingLink,
                    "createdAt": Timestamp()
                ]

                self?.db.collection("users").document(userId).setData(userData) { error in
                    DispatchQueue.main.async {
                        self?.isLoading = false
                        if let error = error {
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

    func verifyCurrentUser() {
        guard let userId = currentUserId else { return }
        db.collection("users").document(userId).getDocument { [weak self] doc, _ in
            DispatchQueue.main.async {
                if doc?.exists == false { self?.logout() }
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
