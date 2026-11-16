import SwiftUI
import Combine

class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    @Published var isCarPlayConnected: Bool = false
}

struct MainTabView: View {
    @StateObject private var appState = AppStateManager.shared
    @AppStorage("appThemeMode") private var appThemeMode: Int = 0

    var body: some View {
        TabView {
            HomeDashboardView()
                .tabItem { Label("Trang chủ", systemImage: "house.fill") }

            NavigationView { InCarSettingsView() }
                .tabItem { Label("Trên xe", systemImage: "car.fill") }

            NavigationView {
                SplitScreenWorkspaceView()
                    .navigationTitle("Mô phỏng")
            }
            .tabItem { Label("Mô phỏng", systemImage: "play.rectangle.fill") }

            NavigationView { GeneralSettingsView() }
                .tabItem { Label("Cài đặt", systemImage: "gearshape.fill") }
        }
        .preferredColorScheme(
            appThemeMode == 1 ? .light : (appThemeMode == 2 ? .dark : nil)
        )
    }
}

struct HomeDashboardView: View {
    @ObservedObject private var appState = AppStateManager.shared

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: appState.isCarPlayConnected ? "car.2.fill" : "cable.connector")
                            .font(.title2)
                            .foregroundColor(appState.isCarPlayConnected ? .green : .blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appState.isCarPlayConnected ? "Đã kết nối CarPlay" : "Sẵn sàng cho CarPlay")
                                .font(.headline)
                            Text(appState.isCarPlayConnected ? "Đang hiển thị trên màn hình xe" : "Cắm CarPlay hoặc dùng tab Mô phỏng để kiểm tra")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("XemYouTube 2.1.3")
        }
    }
}

struct InCarSettingsView: View {
    @AppStorage("autoOpenOnCarPlay") private var autoOpenOnCarPlay: Bool = true
    @AppStorage("autoDimScreen") private var autoDimScreen: Bool = false
    @AppStorage("showSpeedBubble") private var showSpeedBubble: Bool = true
    @AppStorage("autoHideDockSeconds") private var autoHideDockSeconds: Double = 5.0

    var body: some View {
        Form {
            Section("CARPLAY") {
                Toggle("Mở khi kết nối CarPlay", isOn: $autoOpenOnCarPlay)
                Toggle("Tự làm tối màn hình", isOn: $autoDimScreen)
            }
            Section("TÙY CHỈNH") {
                Toggle("Bong bóng tốc độ GPS", isOn: $showSpeedBubble)
                Picker("Thanh tab ứng dụng", selection: $autoHideDockSeconds) {
                    Text("3 giây").tag(3.0)
                    Text("5 giây").tag(5.0)
                    Text("10 giây").tag(10.0)
                    Text("Luôn hiện").tag(0.0)
                }
            }
        }
        .navigationTitle("Trên xe")
    }
}

struct GeneralSettingsView: View {
    @AppStorage("appThemeMode") private var appThemeMode: Int = 0

    var body: some View {
        Form {
            Section("GIAO DIỆN") {
                Picker("Chế độ hiển thị", selection: $appThemeMode) {
                    Text("Tự động").tag(0)
                    Text("Sáng").tag(1)
                    Text("Tối").tag(2)
                }
            }
            Section("THÔNG TIN") {
                HStack {
                    Text("Phiên bản")
                    Spacer()
                    Text("2.1.3").foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Cài đặt")
    }
}