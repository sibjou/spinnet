import SwiftUI

struct ClarificationListView: View {
    @ObservedObject var authService: AuthService
    @Binding var isTabBarVisible: Bool
    @EnvironmentObject var appState: AppState
    @StateObject private var service = ClarificationService()

    private var currentUserId: String { authService.currentUserId ?? "" }

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading {
                    ProgressView("Загрузка...")
                } else if service.clarifications.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Уточнения")
            .task { service.startListening(userId: currentUserId) }
            .onDisappear { service.stopListening() }
            .refreshable { service.startListening(userId: currentUserId) }
            // Автооткрытие диалога если пришли из BookedGameDetailView
            .navigationDestination(isPresented: Binding(
                get: { appState.clarificationToOpen != nil },
                set: { if !$0 { appState.clarificationToOpen = nil } }
            )) {
                if let clar = appState.clarificationToOpen {
                    ClarificationDetailView(clarification: clar, authService: authService)
                        .onAppear  { isTabBarVisible = false }
                        .onDisappear { isTabBarVisible = true }
                }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(service.clarifications) { clar in
                NavigationLink {
                    ClarificationDetailView(clarification: clar, authService: authService)
                        .onAppear  { isTabBarVisible = false }
                        .onDisappear { isTabBarVisible = true }
                } label: {
                    clarificationRow(clar)
                }
            }
            .onDelete { indexSet in
                indexSet.forEach { i in
                    guard i < service.clarifications.count else { return }
                    service.deleteClarification(id: service.clarifications[i].id)
                }
            }
        }
        .listStyle(.plain)
    }

    private func clarificationRow(_ clar: MeetingClarification) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(clar.partnerName(currentUserId: currentUserId))
                    .fontWeight(.semibold)
                Spacer()
                Text(clar.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.green).font(.caption)
                Text(clar.sparringCity).font(.caption).foregroundColor(.secondary)
                Text("·").foregroundColor(.secondary)
                Text(clar.sparringTimeSlot).font(.caption).foregroundColor(.secondary)
            }
            Text(formattedDate(clar.sparringDate))
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checklist")
                .font(.system(size: 50)).foregroundColor(.gray)
            Text("Нет активных уточнений")
                .font(.headline).foregroundColor(.secondary)
            Text("Здесь появятся детали\nпо забронированным встречам")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }
}
