import SwiftUI

// MARK: - PremiumGate
// Оборачивает платную функцию. Пока подписки нет (FeatureGate.paywallEnabled == false),
// показывает содержимое как есть. Когда подписка появится — для бесплатного тарифа
// содержимое размывается и поверх него появляется замок.
struct PremiumGate<Content: View>: View {
    let feature: Feature
    let plan: Plan
    private let content: Content

    @State private var showPaywall = false

    init(feature: Feature, plan: Plan, @ViewBuilder content: () -> Content) {
        self.feature = feature
        self.plan = plan
        self.content = content()
    }

    var body: some View {
        if FeatureGate.isAvailable(feature, plan: plan) {
            content
        } else {
            content
                .blur(radius: 7)
                .allowsHitTesting(false)
                .overlay {
                    Button {
                        showPaywall = true
                    } label: {
                        VStack(spacing: AppSpacing.s) {
                            Image(systemName: "lock.fill")
                                .font(.title2)
                            Text("Spinnet Pro")
                                .font(.headline)
                            Text(feature.title)
                                .font(.caption)
                                .foregroundColor(AppColor.textSecondary)
                        }
                        .foregroundColor(AppColor.textPrimary)
                        .padding(AppSpacing.l)
                        .background(.regularMaterial)
                        .cornerRadius(AppRadius.large)
                    }
                    .buttonStyle(.plain)
                }
                .sheet(isPresented: $showPaywall) {
                    PaywallView()
                }
        }
    }
}

// MARK: - Экран подписки (заглушка)
// Оплата подключается позже; экран нужен, чтобы замок вёл куда-то осмысленное.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.xl) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 56))
                    .foregroundColor(AppColor.primary)
                    .padding(.top, AppSpacing.xxl)

                Text("Spinnet Pro")
                    .font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: AppSpacing.m) {
                    ForEach(Feature.allCases.filter { $0.requiredPlan == .pro }, id: \.self) { feature in
                        Label(feature.title, systemImage: "checkmark.circle.fill")
                            .foregroundColor(AppColor.textPrimary)
                    }
                }
                .padding(.horizontal, AppSpacing.xl)

                Text("Подписка появится позже. Пока всё доступно бесплатно.")
                    .font(.subheadline)
                    .foregroundColor(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }
}
