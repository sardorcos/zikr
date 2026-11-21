import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var page = 0
    @State private var choice: StarterChoice? = .freeCount

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                feature(icon: "circle.hexagongrid.fill", title: "onboarding.1.title", body: "onboarding.1.body").tag(0)
                feature(icon: "hand.tap.fill", title: "onboarding.2.title", body: "onboarding.2.body").tag(1)
                feature(icon: "lock.shield.fill", title: "onboarding.3.title", body: "onboarding.3.body").tag(2)
                starter.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 3 {
                    withAnimation { page += 1 }
                } else {
                    store.completeOnboarding(with: choice)
                }
            } label: {
                Text(page < 3 ? store.t("common.continue") : store.t("onboarding.start"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            if page < 3 {
                Button(store.t("onboarding.skip")) { withAnimation { page = 3 } }
                    .padding(.bottom, 16)
            } else {
                Color.clear.frame(height: 36)
            }
        }
        .background(Color.zBackground.ignoresSafeArea())
    }

    private func feature(icon: String, title: String, body: String) -> some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Color.zPrimary)
                .accessibilityHidden(true)
            Text(store.t(title))
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(store.t(body))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var starter: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text(store.t("onboarding.4.title"))
                .font(.largeTitle.weight(.semibold))
            Text(store.t("onboarding.4.body"))
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                starterRow(.freeCount, icon: "infinity", title: "starter.free", detail: "starter.freeDetail")
                starterRow(.goal100, icon: "target", title: "starter.goal", detail: "starter.goalDetail")
                starterRow(.program, icon: "list.number", title: "starter.program", detail: "starter.programDetail")
                starterRow(nil, icon: "square.dashed", title: "starter.none", detail: "starter.noneDetail")
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func starterRow(_ value: StarterChoice?, icon: String, title: String, detail: String) -> some View {
        Button {
            choice = value
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 32)
                    .foregroundStyle(Color.zPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.t(title)).font(.headline).foregroundStyle(.primary)
                    Text(store.t(detail)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: choice == value ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(choice == value ? Color.zPrimary : Color.secondary)
            }
            .padding(14)
            .background(Color.zSurface, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(choice == value ? .isSelected : [])
    }
}
