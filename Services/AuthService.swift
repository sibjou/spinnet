import SwiftUI
import Combine
import FirebaseAuth      // Firebase модуль для авторизации (вход, регистрация, сброс пароля)
import FirebaseFirestore  // Firebase модуль для базы данных (хранение профилей, заявок и тд)

// MARK: - AuthService
// Этот класс отвечает за ВСЮ работу с авторизацией.
// ObservableObject — значит SwiftUI-экраны автоматически обновляются,
// когда данные в этом классе меняются (например, isLoggedIn стал true → экран переключится)
class AuthService: ObservableObject {
    
    // @Published — когда это значение меняется, все экраны которые «наблюдают»
    // за этим сервисом автоматически перерисовываются
    @Published var isLoggedIn = false         // Вошёл ли пользователь
    @Published var currentUserId: String? = nil // ID текущего пользователя в Firebase
    @Published var isLoading = false          // Показывать ли индикатор загрузки
    @Published var errorMessage: String? = nil // Сообщение об ошибке (если есть)
    
    // Ссылка на базу данных Firestore
    // Через неё мы читаем и записываем данные
    private let db = Firestore.firestore()
    
    // MARK: - init (Инициализация)
    // При запуске приложения проверяем: авторизован ли пользователь
    // И проверяем что его аккаунт ещё существует в базе
    init() {
        if let user = Auth.auth().currentUser {
            self.isLoggedIn = true
            self.currentUserId = user.uid
            // Проверяем что пользователь не был удалён администратором
            verifyCurrentUser()
        }
    }
    
    // MARK: - Регистрация нового пользователя
    // 1. Создаёт аккаунт в Firebase Auth (email + пароль)
    // 2. Сохраняет профиль (имя, город, уровень и тд) в Firestore
    func register(email: String, password: String, firstName: String, lastName: String,
                  city: String, skillLevel: String, grip: String, playStyle: String) {
        isLoading = true    // Включаем индикатор загрузки
        errorMessage = nil  // Сбрасываем предыдущую ошибку
        
        // Шаг 1: Создаём аккаунт в Firebase Auth
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            // [weak self] — предотвращает утечку памяти (стандартная практика в Swift)
            
            DispatchQueue.main.async {
                // DispatchQueue.main.async — переключаемся на главный поток
                // Это ОБЯЗАТЕЛЬНО для обновления UI (правило iOS)
                
                if let error = error {
                    // Если ошибка — показываем на русском и останавливаемся
                    self?.isLoading = false
                    self?.errorMessage = self?.russianError(error)
                    return
                }
                
                // Шаг 2: Аккаунт создан, получаем ID пользователя
                guard let userId = result?.user.uid else {
                    self?.isLoading = false
                    return
                }
                
                // Шаг 3: Формируем данные профиля для сохранения в Firestore
                let userData: [String: Any] = [
                    "firstName": firstName,
                    "lastName": lastName,
                    "email": email,
                    "city": city,
                    "skillLevel": skillLevel,
                    "grip": grip,
                    "playStyle": playStyle,
                    "ratingLink": "",
                    "createdAt": Timestamp() // Время создания аккаунта
                ]
                
                // Шаг 4: Сохраняем профиль в коллекцию "users" в Firestore
                // document(userId) — ID документа = ID пользователя (чтобы легко находить)
                self?.db.collection("users").document(userId).setData(userData) { error in
                    DispatchQueue.main.async {
                        self?.isLoading = false
                        if let error = error {
                            self?.errorMessage = self?.russianError(error)
                        } else {
                            // Всё успешно — пользователь вошёл
                            self?.currentUserId = userId
                            self?.isLoggedIn = true
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Вход существующего пользователя
    func login(email: String, password: String) {
        isLoading = true
        errorMessage = nil
        
        // Firebase Auth проверяет email и пароль
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = self?.russianError(error)
                } else {
                    self?.currentUserId = result?.user.uid
                    self?.isLoggedIn = true
                }
            }
        }
    }
    
    // MARK: - Выход из аккаунта
    func logout() {
            try? Auth.auth().signOut() // Выходим из Firebase Auth
            isLoggedIn = false
            currentUserId = nil
        }
    
    // MARK: - Сброс пароля
        // Отправляем общее сообщение, не раскрывая существует ли email в базе
        func resetPassword(email: String) {
            isLoading = true
            errorMessage = nil
            
            Auth.auth().sendPasswordReset(withEmail: email) { [weak self] error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    
                    // Безопасное сообщение: не раскрываем существует ли аккаунт
                    // Это защищает от атак перебора email-адресов
                    if let error = error, (error as NSError).code == 17008 {
                        // Только если email совсем некорректный (неверный формат)
                        self?.errorMessage = "Неверный формат email"
                    } else {
                        // Во всех остальных случаях — общее сообщение
                        self?.errorMessage = "Если аккаунт существует, письмо отправлено на \(email)"
                    }
                }
            }
        }
    
    // MARK: - Перевод ошибок Firebase на русский
    // Firebase возвращает ошибки на английском — мы переводим их
    // Каждый код ошибки соответствует определённой ситуации
    func russianError(_ error: Error) -> String {
           let code = (error as NSError).code
           switch code {
           case 17008:
               return "Неверный формат email"
           case 17009:
               return "Неверный пароль"
           case 17011:
               return "Пользователь с таким email не найден"
           case 17007:
               return "Этот email уже зарегистрирован"
           case 17026:
               return "Пароль должен быть не менее 6 символов"
           case 17010:
               return "Слишком много попыток. Попробуйте позже"
           case 17020:
               return "Нет подключения к интернету"
           case 17999:
               return "Ошибка соединения. Проверьте интернет и попробуйте снова"
           case 17004:
               return "Неверный email или пароль"
           default:
               return "Произошла ошибка. Попробуйте ещё раз"
           }
       }
    
    // MARK: - Проверка что пользователь ещё существует в базе
        // Вызывается при запуске приложения — если аккаунт удалён в FB,
        // автоматически разлогиниваем пользователя
        func verifyCurrentUser() {
            guard let userId = currentUserId else { return }
            
            db.collection("users").document(userId).getDocument { [weak self] doc, error in
                DispatchQueue.main.async {
                    // Если документа пользователя нет в Firestore — значит аккаунт удалён
                    if doc?.exists == false {
                        self?.logout()
                    }
                }
            }
        }
}
