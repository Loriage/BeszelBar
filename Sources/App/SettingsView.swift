import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var appState: AppState
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    TabButton(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            Group {
                switch selectedTab {
                case .general:
                    GeneralView()
                case .hubs:
                    HubsView(appState: appState)
                case .about:
                    AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 500, height: 420)
    }
}

struct PillButtonStyle: ButtonStyle {
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(isPrimary ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundColor(isPrimary ? .white : .primary)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct DestructivePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.15))
            .foregroundColor(.red)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct TabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 44, height: 44)
                    }
                    Image(systemName: tab.icon)
                        .font(.system(size: 22))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .frame(width: 44, height: 44)

                Text(tab.title)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

enum SettingsTab: CaseIterable {
    case general
    case hubs
    case about

    var title: String {
        switch self {
        case .general: return "General"
        case .hubs: return "Hubs"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .hubs: return "server.rack"
        case .about: return "info.circle"
        }
    }
}

struct HubsView: View {
    var appState: AppState
    @State private var showingAddSheet = false
    @State private var instanceToEdit: Instance?

    var body: some View {
        VStack(spacing: 0) {
            if appState.instances.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No Hubs Configured")
                        .font(.headline)
                    Text("Add a Beszel hub to start monitoring your servers")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Add Hub") {
                        showingAddSheet = true
                    }
                    .buttonStyle(PillButtonStyle(isPrimary: true))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.instances) { instance in
                        InstanceRow(appState: appState, instance: instance) {
                            instanceToEdit = instance
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            appState.removeInstance(appState.instances[index])
                        }
                    }
                }
                .listStyle(.inset)

                HStack {
                    Text("\(appState.instances.count) hub\(appState.instances.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Add Hub") {
                        showingAddSheet = true
                    }
                    .buttonStyle(PillButtonStyle(isPrimary: true))
                }
                .padding(12)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddHubSheet(appState: appState)
        }
        .sheet(item: $instanceToEdit) { instance in
            EditHubSheet(appState: appState, instance: instance)
        }
    }
}

struct InstanceRow: View {
    var appState: AppState
    let instance: Instance
    let onEdit: () -> Void

    var isSelected: Bool {
        instance.id == appState.selectedInstance?.id
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isSelected ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(instance.name)
                    .font(.system(size: 13, weight: .medium))
                Text(instance.url)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isSelected {
                Text("Active")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Button("Edit") {
                onEdit()
            }
            .buttonStyle(PillButtonStyle())
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            appState.selectInstance(instance)
        }
    }
}

struct AddHubSheet: View {
    var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var url = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Beszel Hub")
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Form {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField("URL", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)

                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.escape)

                Spacer()

                Button(action: testAndSave) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Add Hub")
                    }
                }
                .buttonStyle(PillButtonStyle(isPrimary: true))
                .disabled(name.isEmpty || url.isEmpty || email.isEmpty || password.isEmpty || isLoading)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 380, height: 320)
    }

    private func testAndSave() {
        isLoading = true
        errorMessage = nil

        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingSuffix("/")

        Task {
            do {
                let testInstance = Instance(
                    name: name,
                    url: cleanURL,
                    email: email,
                    credential: password
                )

                let service = BeszelAPIService(instance: testInstance)
                _ = try await service.fetchSystems()

                await MainActor.run {
                    let instance = Instance(name: name, url: cleanURL, email: email, credential: password)
                    appState.addInstance(instance)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Connection failed: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

struct EditHubSheet: View {
    var appState: AppState
    @Environment(\.dismiss) var dismiss

    let instance: Instance

    @State private var name: String
    @State private var url: String
    @State private var email: String
    @State private var password: String
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(appState: AppState, instance: Instance) {
        self.appState = appState
        self.instance = instance
        _name = State(initialValue: instance.name)
        _url = State(initialValue: instance.url)
        _email = State(initialValue: instance.email)
        _password = State(initialValue: KeychainService.shared.loadCredential(for: instance.id.uuidString) ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Edit Hub")
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Form {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField("URL", text: $url)
                    .textFieldStyle(.roundedBorder)

                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Spacer()

            HStack {
                Button("Delete") {
                    appState.removeInstance(instance)
                    dismiss()
                }
                .buttonStyle(DestructivePillButtonStyle())

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.escape)

                Button("Save") {
                    testAndSave()
                }
                .buttonStyle(PillButtonStyle(isPrimary: true))
                .disabled(name.isEmpty || url.isEmpty || email.isEmpty || isLoading)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 380, height: 340)
    }

    private func testAndSave() {
        isLoading = true
        errorMessage = nil

        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingSuffix("/")

        Task {
            do {
                let testInstance = Instance(
                    name: name,
                    url: cleanURL,
                    email: email,
                    credential: password.isEmpty ? instance.credential : password
                )

                let service = BeszelAPIService(instance: testInstance)
                _ = try await service.fetchSystems()

                await MainActor.run {
                    var updated = instance
                    updated.name = name
                    updated.url = cleanURL
                    updated.email = email
                    if !password.isEmpty {
                        updated.credential = password
                    }
                    appState.updateInstance(updated)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Connection failed: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

struct GeneralView: View {
    @AppStorage("refreshInterval") private var refreshInterval = 30
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "SYSTEM")

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Start at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            setLaunchAtLogin(newValue)
                        }
                    Text("Automatically open BeszelBar when you start your Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider()
                    .padding(.horizontal, 20)

                SectionHeader(title: "REFRESH")

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Refresh interval")
                        Spacer()
                        Picker("", selection: $refreshInterval) {
                            Text("10 sec").tag(10)
                            Text("30 sec").tag(30)
                            Text("1 min").tag(60)
                            Text("2 min").tag(120)
                            Text("5 min").tag(300)
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    Text("How often BeszelBar polls your hubs for updates.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Quit BeszelBar") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(PillButtonStyle(isPrimary: true))
            }
            .padding(12)
            .background(.bar)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
        }
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.8), Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "server.rack")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 80, height: 80)

            Text("BeszelBar")
                .font(.title2)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Monitor your Beszel servers from the menu bar.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(spacing: 8) {
                if let beszelURL = URL(string: "https://github.com/henrygd/beszel") {
                    Link(destination: beszelURL) {
                        Label("Beszel", systemImage: "link")
                    }
                }

                if let githubURL = URL(string: "https://github.com/brunooctet/BeszelBar") {
                    Link(destination: githubURL) {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }
            .padding(.top, 8)

            Spacer()

            Text("© 2026 Bruno DURAND. MIT License.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        if hasSuffix(suffix) {
            return String(dropLast(suffix.count))
        }
        return self
    }
}
