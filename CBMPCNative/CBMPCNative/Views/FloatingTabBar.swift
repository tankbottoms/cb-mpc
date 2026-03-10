import SwiftUI

struct FloatingTabBar: View {
    @Binding var selection: Int
    @Binding var isHidden: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                Color.clear

                if isHidden {
                    // Collapsed: key icon with shadow background peeking from right edge
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            isHidden = false
                        }
                    } label: {
                        HStack(spacing: 0) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                        }
                        .frame(width: 42, height: 42)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .shadow(radius: 8)
                    }
                    .offset(x: 14) // Partially off-screen
                    .padding(.bottom, 4)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    // Expanded tab bar
                    HStack(spacing: 14) {
                        TabBarButton(icon: "key.fill", isSelected: selection == 0) { selection = 0 }
                        TabBarButton(icon: "antenna.radiowaves.left.and.right", isSelected: selection == 1) { selection = 1 }
                        TabBarButton(icon: "clock.fill", isSelected: selection == 2) { selection = 2 }
                        TabBarButton(icon: "arrow.left.arrow.right", isSelected: selection == 3) { selection = 3 }
                        TabBarButton(icon: "play.circle.fill", isSelected: selection == 4) { selection = 4 }
                        TabBarButton(icon: "gearshape.fill", isSelected: selection == 5) { selection = 5 }

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                isHidden = true
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray.opacity(0.6))
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                    }
                    .frame(height: 42)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .shadow(radius: 8)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(height: 56)
    }
}

struct TabBarButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(isSelected ? .white : .gray)
        }
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        Color.gray.opacity(0.1)
            .ignoresSafeArea()

        FloatingTabBar(selection: .constant(2), isHidden: .constant(false))
    }
}
