import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

class AuthService: ObservableObject {
    @Published var isLoggedIn = false
    @Published var currentUserId: String? = nil
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    private let db = Firestore.firestore()
    
    init() {
        // Проверяем, вошёл ли пользователь ранее
        if let user = Auth.auth().currentUser {
            self.isLoggedIn = true
            self.currentUserId = user.uid
        }
    }
    
    func register(email: String, password: String, firstName: String, lastName: String,
                  city: String, skillLevel: String, grip: String, playStyle: String) {
        isLoading = true
        errorMessage = nil
        
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.isLoading = false
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                guard let userId = result?.user.uid else {
                    self?.isLoading = false
                    return
                }
                
                // Сохраняем профиль в Firestore
                let userData: [String: Any] = [
                    "firstName": firstName,
                    "lastName": lastName,
                    "email": email,
                    "city": city,
                    "skillLevel": skillLevel,
                    "grip": grip,
                    "playStyle": playStyle,
                    "ratingLink": "",
                    "createdAt": Timestamp()
                ]
                
                self?.db.collection("users").document(userId).setData(userData) { error in
                    DispatchQueue.main.async {
                        self?.isLoading = false
                        if let error = error {
                            self?.errorMessage = error.localizedDescription
                        } else {
                            self?.currentUserId = userId
                            self?.isLoggedIn = true
                        }
                    }
                }
            }
        }
    }
    
    func login(email: String, password: String) {
        isLoading = true
        errorMessage = nil
        
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                } else {
                    self?.currentUserId = result?.user.uid
                    self?.isLoggedIn = true
                }
            }
        }
    }
    
    func logout() {
        try? Auth.auth().signOut()
        isLoggedIn = false
        currentUserId = nil
    }
}
