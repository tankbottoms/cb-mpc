import SwiftUI

struct FloatingTabBar: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 28) {
            TabBarButton(
                icon: "key.fill",
                isSelected: selection == 0,
                action: { selection = 0 }
            )

            TabBarButton(
                icon: "clock.fill",
                isSelected: selection == 1,
                action: { selection = 1 }
            )

            TabBarButton(
                icon: "qrcode.viewfinder",
                isSelected: selection == 2,
                action: { selection = 2 }
            )

            TabBarButton(
                icon: "gearshape.fill",
                isSelected: selection == 3,
                action: { selection = 3 }
            )
        }
        .frame(height: 50)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(.ultraThinMaterial))
        .shadow(radius: 12)
    }
}

struct TabBarButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(isSelected ? .white : .gray)
        }
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        VStack {
            Text("Content Area")
                .font(.headline)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.gray.opacity(0.1))

        FloatingTabBar(selection: .constant(0))
            .padding(.bottom, 8)
    }
}
