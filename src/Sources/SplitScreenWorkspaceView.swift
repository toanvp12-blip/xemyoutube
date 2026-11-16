import SwiftUI
import WebKit
import CoreLocation
import Combine

struct SplitScreenWorkspaceView: View {
    @State private var splitRatio: CGFloat = 0.5
    @State private var leftAppTitle: String = "YouTube"
    @State private var rightAppTitle: String = "Bản đồ"
    @AppStorage("showSpeedBubble") private var showSpeedBubble: Bool = true
    @AppStorage("autoHideDockSeconds") private var autoHideDockSeconds: Double = 5.0
    @State private var isDockVisible: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    WindowPaneView(title: leftAppTitle, onClose: { leftAppTitle = "Trống" })
                        .frame(width: max(120, geo.size.width * splitRatio - 6))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 12, height: 60)
                        .overlay(
                            Image(systemName: "line.3.horizontal")
                                .rotationEffect(.degrees(90))
                                .font(.caption2)
                        )
                        .padding(.horizontal, 2)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let newRatio = (geo.size.width * splitRatio + value.translation.width) / geo.size.width
                                    splitRatio = min(max(newRatio, 0.25), 0.75)
                                }
                        )

                    WindowPaneView(title: rightAppTitle, onClose: { rightAppTitle = "Trống" })
                        .frame(maxWidth: .infinity)
                }
                .padding(8)

                if showSpeedBubble {
                    SpeedometerBubbleView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(16)
                }

                if isDockVisible {
                    QuickDockBar(
                        onSelectLeft: { leftAppTitle = $0 },
                        onSelectRight: { rightAppTitle = $0 }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 10)
                }
            }
            .onTapGesture {
                withAnimation { isDockVisible.toggle() }
                scheduleDockAutoHide()
            }
            .onAppear { scheduleDockAutoHide() }
        }
    }

    private func scheduleDockAutoHide() {
        guard autoHideDockSeconds > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideDockSeconds) {
            withAnimation { isDockVisible = false }
        }
    }
}

struct WindowPaneView: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.caption.bold())
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))

            if title == "YouTube" {
                YouTubeWebPlayerView(urlString: "https://m.youtube.com")
            } else if title == "Bản đồ" {
                YouTubeWebPlayerView(urlString: "https://www.google.com/maps")
            } else {
                ZStack {
                    Color(.systemBackground)
                    Text("Chọn ứng dụng từ thanh Dock bên dưới")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )
    }
}

struct YouTubeWebPlayerView: UIViewRepresentable {
    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

class SpeedLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var speedKmh: Int = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.speed >= 0 else {
            speedKmh = 0
            return
        }
        speedKmh = Int((latest.speed * 3.6).rounded())
    }
}

struct SpeedometerBubbleView: View {
    @StateObject private var locationManager = SpeedLocationManager()
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(locationManager.speedKmh)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("km/h").font(.caption2).foregroundColor(.secondary)
            }
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.25), style: StrokeStyle(lineWidth: 4, dash: [4, 4]))
                Circle()
                    .trim(from: 0, to: min(CGFloat(locationManager.speedKmh) / 120.0, 1.0))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(locationManager.speedKmh)").font(.caption.bold())
            }
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .offset(dragOffset)
        .gesture(DragGesture().onChanged { dragOffset = $0.translation })
    }
}

struct QuickDockBar: View {
    let onSelectLeft: (String) -> Void
    let onSelectRight: (String) -> Void
    private let apps = ["YouTube", "Bản đồ"]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(apps, id: \.self) { app in
                Button(action: { onSelectLeft(app) }) {
                    Text(app)
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}