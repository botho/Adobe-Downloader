//
//  Adobe Downloader
//
//  Created by X1a0He on 2024/10/30.
//

import SwiftUI
import Sparkle
import Combine

struct PulsingCircle: View {
    let color: Color
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(scale)
            .animation(
                Animation.easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true),
                value: scale
            )
            .onAppear {
                scale = 1.5
            }
    }
}

struct AboutView: View {
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    var body: some View {
        TabView {
            GeneralSettingsView(updater: updater)
                .tabItem {
                    Label("通用", systemImage: "gear")
                }
                .id("general_settings")

            AboutAppView()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
                .id("about_app")
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(width: 600)
    }
}

final class GeneralSettingsViewModel: ObservableObject {
    @Published var setupVersion: String = ""
    @Published var isDownloadingSetup = false
    @Published var setupDownloadProgress = 0.0
    @Published var setupDownloadStatus = ""
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var isSuccess = false
    @Published var showDownloadAlert = false
    @Published var showLanguagePicker = false
    @Published var showDownloadConfirmAlert = false
    @Published var showReprocessConfirmAlert = false
    @Published var isProcessing = false
    @Published var helperConnectionStatus: HelperConnectionStatus = .connecting
    @Published var downloadAppleSilicon: Bool {
        didSet {
            UserDefaults.standard.set(downloadAppleSilicon, forKey: "downloadAppleSilicon")
        }
    }

    @AppStorage("defaultLanguage") var defaultLanguage: String = "ALL"
    @AppStorage("defaultDirectory") var defaultDirectory: String = ""
    @AppStorage("useDefaultLanguage") var useDefaultLanguage: Bool = true
    @AppStorage("useDefaultDirectory") var useDefaultDirectory: Bool = true
    @AppStorage("confirmRedownload") var confirmRedownload: Bool = true

    @Published var automaticallyChecksForUpdates: Bool
    @Published var automaticallyDownloadsUpdates: Bool

    @Published var isCancelled = false

    private var cancellables = Set<AnyCancellable>()
    let updater: SPUUpdater

    enum HelperConnectionStatus {
        case connected
        case connecting
        case disconnected
        case checking
    }

    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        self.downloadAppleSilicon = UserDefaults.standard.bool(forKey: "downloadAppleSilicon")

        self.helperConnectionStatus = .connecting

        PrivilegedHelperManager.shared.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .connected:
                    self?.helperConnectionStatus = .connected
                case .disconnected:
                    self?.helperConnectionStatus = .disconnected
                case .connecting:
                    self?.helperConnectionStatus = .connecting
                }
            }
            .store(in: &cancellables)

        DispatchQueue.main.async {
            PrivilegedHelperManager.shared.executeCommand("whoami") { _ in }
        }
    }

    deinit {
        cancellables.removeAll()
    }

    func updateAutomaticallyChecksForUpdates(_ newValue: Bool) {
        automaticallyChecksForUpdates = newValue
        updater.automaticallyChecksForUpdates = newValue
    }

    func updateAutomaticallyDownloadsUpdates(_ newValue: Bool) {
        automaticallyDownloadsUpdates = newValue
        updater.automaticallyDownloadsUpdates = newValue
    }

    var isAutomaticallyDownloadsUpdatesDisabled: Bool {
        !automaticallyChecksForUpdates
    }

    func cancelDownload() {
        isCancelled = true
    }
}

struct GeneralSettingsView: View {
    @StateObject private var viewModel: GeneralSettingsViewModel
    @State private var showHelperAlert = false
    @State private var helperAlertMessage = ""
    @State private var helperAlertSuccess = false
    @EnvironmentObject private var networkManager: NetworkManager

    init(updater: SPUUpdater) {
        _viewModel = StateObject(wrappedValue: GeneralSettingsViewModel(updater: updater))
    }

    var body: some View {
        Form {
            DownloadSettingsView(viewModel: viewModel)

            OtherSettingsView(viewModel: viewModel,
                            showHelperAlert: $showHelperAlert,
                            helperAlertMessage: $helperAlertMessage,
                            helperAlertSuccess: $helperAlertSuccess)

            UpdateSettingsView(viewModel: viewModel)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert(helperAlertSuccess ? "操作成功" : "操作失败", isPresented: $showHelperAlert) {
            Button("确定") { }
        } message: {
            Text(helperAlertMessage)
        }
        .alert("需要下载 Setup 组件", isPresented: $viewModel.showDownloadAlert) {
            Button("取消", role: .cancel) { }
            Button("下载") {
                Task {
                    viewModel.isDownloadingSetup = true
                    viewModel.isCancelled = false
                    do {
                        try await networkManager.downloadUtils.downloadSetupComponents(
                            progressHandler: { progress, status in
                                viewModel.setupDownloadProgress = progress
                                viewModel.setupDownloadStatus = status
                            },
                            cancellationHandler: { viewModel.isCancelled }
                        )
                        viewModel.setupVersion = ModifySetup.checkComponentVersion()
                        viewModel.isSuccess = true
                        viewModel.alertMessage = "Setup 组件安装成功"
                    } catch NetworkError.cancelled {
                        viewModel.isSuccess = false
                        viewModel.alertMessage = "下载已取消"
                    } catch {
                        viewModel.isSuccess = false
                        viewModel.alertMessage = error.localizedDescription
                    }
                    viewModel.showAlert = true
                    viewModel.isDownloadingSetup = false
                }
            }
        } message: {
            Text("检测到系统中不存在 Setup 组件，需要先下载组件才能继续操作。")
        }
        .alert("确认下载", isPresented: $viewModel.showDownloadConfirmAlert) {
            Button("取消", role: .cancel) { }
            Button("确定") {
                Task {
                    viewModel.isDownloadingSetup = true
                    viewModel.isCancelled = false
                    do {
                        try await networkManager.downloadUtils.downloadSetupComponents(
                            progressHandler: { progress, status in
                                viewModel.setupDownloadProgress = progress
                                viewModel.setupDownloadStatus = status
                            },
                            cancellationHandler: { viewModel.isCancelled }
                        )
                        viewModel.setupVersion = ModifySetup.checkComponentVersion()
                        viewModel.isSuccess = true
                        viewModel.alertMessage = "Setup 组件安装成功"
                    } catch NetworkError.cancelled {
                        viewModel.isSuccess = false
                        viewModel.alertMessage = "下载已取消"
                    } catch {
                        viewModel.isSuccess = false
                        viewModel.alertMessage = error.localizedDescription
                    }
                    viewModel.showAlert = true
                    viewModel.isDownloadingSetup = false
                }
            }
        } message: {
            Text("确定要下载并安装 Setup 组件吗?")
        }
        .alert("确认重新处理", isPresented: $viewModel.showReprocessConfirmAlert) {
            Button("取消", role: .cancel) { }
            Button("确定") {
                viewModel.isProcessing = true
                ModifySetup.backupAndModifySetupFile { success, message in
                    viewModel.isProcessing = false
                    viewModel.isSuccess = success
                    viewModel.alertMessage = message
                    viewModel.showAlert = true
                }
            }
        } message: {
            Text("确定要重新处理 Setup 组件吗?")
        }
        .alert(viewModel.isSuccess ? "操作成功" : "操作失败", isPresented: $viewModel.showAlert) {
            Button("确定") { }
        } message: {
            Text(viewModel.alertMessage)
        }
        .task {
            viewModel.setupVersion = ModifySetup.checkComponentVersion()
            networkManager.updateAllowedPlatform(useAppleSilicon: viewModel.downloadAppleSilicon)
        }
    }
}

struct DownloadSettingsView: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel

    var body: some View {
        GroupBox(label: Text("下载设置").padding(.bottom, 8)) {
            VStack(alignment: .leading, spacing: 12) {
                LanguageSettingRow(viewModel: viewModel)
                Divider()
                DirectorySettingRow(viewModel: viewModel)
                Divider()
                RedownloadConfirmRow(viewModel: viewModel)
                Divider()
                ArchitectureSettingRow(viewModel: viewModel)
            }
            .padding(8)
        }
    }
}

struct OtherSettingsView: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel
    @Binding var showHelperAlert: Bool
    @Binding var helperAlertMessage: String
    @Binding var helperAlertSuccess: Bool

    var body: some View {
        GroupBox(label: Text("其他设置").padding(.bottom, 8)) {
            VStack(alignment: .leading, spacing: 12) {
                HelperStatusRow(viewModel: viewModel, showHelperAlert: $showHelperAlert,
                              helperAlertMessage: $helperAlertMessage,
                              helperAlertSuccess: $helperAlertSuccess)
                Divider()
                SetupComponentRow(viewModel: viewModel)
            }
            .padding(8)
        }
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel

    var body: some View {
        GroupBox(label: Text("更新设置").padding(.bottom, 8)) {
            VStack(alignment: .leading, spacing: 12) {
                AutoUpdateRow(viewModel: viewModel)
                Divider()
                AutoDownloadRow(viewModel: viewModel)
            }
            .padding(8)
        }
    }
}

struct AboutAppView: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        // let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        // return "Version \(version) (\(build))"
        return "\(version)"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Adobe Downloader \(appVersion)")
                .font(.title2)
                .bold()

            Text("By X1a0He. ❤️ Love from China. ❤️")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Link("联系 @X1a0He",
                 destination: URL(string: "https://t.me/X1a0He")!)
                .font(.caption)
                .foregroundColor(.blue)
            Link("Github: Adobe Downloader",
                 destination: URL(string: "https://github.com/X1a0He/Adobe-Downloader")!)
                .font(.caption)
                .foregroundColor(.blue)

            Link("感谢 Drovosek01: adobe-packager",
                 destination: URL(string: "https://github.com/Drovosek01/adobe-packager")!)
                .font(.caption)
                .foregroundColor(.blue)

            Link("感谢 QiuChenly: InjectLib",
                 destination: URL(string: "https://github.com/QiuChenly/InjectLib")!)
                .font(.caption)
                .foregroundColor(.blue)

            Text("GNU通用公共许可证GPL v3.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("About Tab") {
    AboutAppView()
}

#Preview("General Settings") {
    let networkManager = NetworkManager()
    VStack {
        GeneralSettingsView(updater: PreviewUpdater())
            .environmentObject(networkManager)
    }
}

private class PreviewUpdater: SPUUpdater {
    init() {
        let hostBundle = Bundle.main
        let applicationBundle = Bundle.main
        let userDriver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)

        super.init(
            hostBundle: hostBundle,
            applicationBundle: applicationBundle,
            userDriver: userDriver,
            delegate: nil
        )
    }

    override var automaticallyChecksForUpdates: Bool {
        get { true }
        set { }
    }

    override var automaticallyDownloadsUpdates: Bool {
        get { true }
        set { }
    }
}

struct LanguageSettingRow: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel

    var body: some View {
        HStack {
            Toggle("使用默认语言", isOn: $viewModel.useDefaultLanguage)
                .padding(.leading, 5)
            Spacer()
            Text(getLanguageName(code: viewModel.defaultLanguage))
                .foregroundColor(.secondary)
            Button("选择") {
                viewModel.showLanguagePicker = true
            }
            .padding(.trailing, 5)
        }
        .sheet(isPresented: $viewModel.showLanguagePicker) {
            LanguagePickerView(languages: AppStatics.supportedLanguages) { language in
                viewModel.defaultLanguage = language
                viewModel.showLanguagePicker = false
            }
        }
    }

    private func getLanguageName(code: String) -> String {
        AppStatics.supportedLanguages.first { $0.code == code }?.name ?? code
    }
}

struct DirectorySettingRow: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel

    var body: some View {
        HStack {
            Toggle("使用默认目录", isOn: $viewModel.useDefaultDirectory)
                .padding(.leading, 5)
            Spacer()
            Text(formatPath(viewModel.defaultDirectory))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("选择") {
                selectDirectory()
            }
            .padding(.trailing, 5)
        }
    }

    private func formatPath(_ path: String) -> String {
        if path.isEmpty { return String(localized: "未设置") }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择默认下载目录"
        panel.canCreateDirectories = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK {
            viewModel.defaultDirectory = panel.url?.path ?? ""
            viewModel.useDefaultDirectory = true
        }
    }
}

struct RedownloadConfirmRow: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel

    var body: some View {
        HStack {
            Toggle("重新下载时需要确认", isOn: $viewModel.confirmRedownload)
                .padding(.leading, 5)
            Spacer()
        }
    }
}

struct ArchitectureSettingRow: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel
    @EnvironmentObject private var networkManager: NetworkManager

    var body: some View {
        HStack {
            Toggle("下载 Apple Silicon 架构", isOn: $viewModel.downloadAppleSilicon)
                .padding(.leading, 5)
            Spacer()
            Text("当前架构: \(AppStatics.cpuArchitecture)")
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .onChange(of: viewModel.downloadAppleSilicon) { newValue in
            networkManager.updateAllowedPlatform(useAppleSilicon: newValue)
        }
    }
}

struct HelperStatusRow: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel
    @Binding var showHelperAlert: Bool
    @Binding var helperAlertMessage: String
    @Binding var helperAlertSuccess: Bool
    @State private var isReinstallingHelper = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Helper 安装状态: ")
                if PrivilegedHelperManager.getHelperStatus {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("已安装")
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("未安装")
                        .foregroundColor(.red)
                }
                Spacer()

                if isReinstallingHelper {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                }

                Button(action: {
                    isReinstallingHelper = true
                    PrivilegedHelperManager.shared.reinstallHelper { success, message in
                        helperAlertSuccess = success
                        helperAlertMessage = message
                        showHelperAlert = true
                        isReinstallingHelper = false
                    }
                }) {
                    Text("重新安装")
                }
                .disabled(isReinstallingHelper)
            }

            if !PrivilegedHelperManager.getHelperStatus {
                Text("Helper未安装将导致无法执行需要管理员权限的操作")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Divider()
            HStack {
                Text("Helper 当前状态: ")
                PulsingCircle(color: helperStatusColor)
                    .padding(.horizontal, 4)
                Text(helperStatusText)
                    .foregroundColor(helperStatusColor)

                Spacer()

                Button(action: {
                    PrivilegedHelperManager.shared.reconnectHelper { success, message in
                        helperAlertSuccess = success
                        helperAlertMessage = message
                        showHelperAlert = true
                    }
                }) {
                    Text("重新连接Helper")
                }
                .disabled(isReinstallingHelper)
            }
        }
    }

    private var helperStatusColor: Color {
        switch viewModel.helperConnectionStatus {
        case .connected: return .green
        case .connecting, .checking: return .orange
        case .disconnected: return .red
        }
    }

    private var helperStatusText: String {
        switch viewModel.helperConnectionStatus {
        case .connected: return "运行正常"
        case .connecting: return "正在连接"
        case .checking: return "检查中"
        case .disconnected: return "连接断开"
        }
    }
}

struct SetupComponentRow: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Setup 组件状态: ")
                if ModifySetup.isSetupBackup() {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("已备份处理")
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("(将导致无法使用安装功能)")
                }
                Spacer()

                Button(action: {
                    if !ModifySetup.isSetupExists() {
                        viewModel.showDownloadAlert = true
                    } else {
                        viewModel.showReprocessConfirmAlert = true
                    }
                }) {
                    Text("重新处理")
                }
            }
            Divider()
            HStack {
                Text("Setup 组件版本: \(viewModel.setupVersion)")
                Spacer()

                if viewModel.isDownloadingSetup {
                    ProgressView(value: viewModel.setupDownloadProgress) {
                        Text(viewModel.setupDownloadStatus)
                            .font(.caption)
                    }
                    .frame(width: 150)
                    Button("取消") {
                        viewModel.cancelDownload()
                    }
                } else {
                    Button(action: {
                        viewModel.showDownloadConfirmAlert = true
                    }) {
                        Text("从 GitHub 下载 Setup 组件")
                    }
                }
            }
        }
    }
}

struct AutoUpdateRow: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel

    var body: some View {
        HStack {
            Toggle("自动检查更新版本", isOn: Binding(
                get: { viewModel.automaticallyChecksForUpdates },
                set: { viewModel.updateAutomaticallyChecksForUpdates($0) }
            ))
            Spacer()
            CheckForUpdatesView(updater: viewModel.updater)
        }
    }
}

struct AutoDownloadRow: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel

    var body: some View {
        Toggle("自动下载最新版本", isOn: Binding(
            get: { viewModel.automaticallyDownloadsUpdates },
            set: { viewModel.updateAutomaticallyDownloadsUpdates($0) }
        ))
        .disabled(viewModel.isAutomaticallyDownloadsUpdatesDisabled)
    }
}
