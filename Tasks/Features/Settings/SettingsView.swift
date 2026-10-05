import PhotosUI
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var nameFocused: Bool
    @State private var showingPhotos = false
    @State private var showingMemoji = false
    @State private var photo: PhotosPickerItem?
    @State private var cropDraft: AvatarCropDraft?
    @State private var loadingAvatar = false
    @State private var avatarFailed = false

    var body: some View {
        @Bindable var preferences = preferences
        NavigationStack {
            Form {
                Section("Perfil") {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
                        : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.md))
                    layout {
                        ProfileAvatar(size: Theme.Metrics.profileAvatarSize)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            TextField("Seu nome", text: $preferences.displayName)
                                .frame(minHeight: Theme.Metrics.minTouchTarget)
                                .textContentType(.name)
                                .textInputAutocapitalization(.words)
                                .focused($nameFocused)
                                .submitLabel(.done)
                                .onSubmit { nameFocused = false }
                                .accessibilityIdentifier("settings.profileName")
                            Menu {
                                Button("Escolher Memoji", systemImage: "face.smiling") {
                                    nameFocused = false
                                    showingMemoji = true
                                }
                                Button("Escolher em Fotos", systemImage: "photo") {
                                    nameFocused = false
                                    showingPhotos = true
                                }
                                if preferences.avatarData != nil {
                                    Button("Remover avatar", systemImage: "trash", role: .destructive) {
                                        do { try preferences.removeAvatar() }
                                        catch { avatarFailed = true }
                                    }
                                }
                            } label: {
                                Label("Editar avatar", systemImage: "pencil")
                                    .font(Theme.Typography.metadata)
                                    .frame(minHeight: Theme.Metrics.minTouchTarget)
                            }
                            .disabled(loadingAvatar)
                            .accessibilityIdentifier("settings.editAvatar")
                        }
                        if loadingAvatar { ProgressView().accessibilityLabel("Carregando avatar") }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                    .listRowBackground(Theme.surface)
                }
                NotificationSettingsSection()
                Section("Aparência") {
                    Picker("Tema", selection: $preferences.appearance) {
                        ForEach(AppPreferences.Appearance.allCases) { appearance in
                            Text(LocalizedStringKey(appearance.titleKey)).tag(appearance)
                        }
                    }
                    .accessibilityIdentifier("settings.theme")
                    .listRowBackground(Theme.surface)
                }
                Section("Idioma") {
                    Picker("Idioma do app", selection: $preferences.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(LocalizedStringKey(language.titleKey)).tag(language)
                        }
                    }
                    .accessibilityIdentifier("settings.language")
                    .listRowBackground(Theme.surface)
                }
            }
            .contentMargins(.horizontal, Theme.pageMargin, for: .scrollContent)
            .listRowInsets(Theme.listRowInsets)
            .environment(\.defaultMinListRowHeight, Theme.Metrics.rowMinHeight)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .foregroundStyle(Theme.textPrimary)
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Concluir") { dismiss() }.tint(Theme.textPrimary)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Concluir") { nameFocused = false }.tint(Theme.textPrimary)
                }
            }
        }
        .tint(Theme.accent)
        .photosPicker(isPresented: $showingPhotos, selection: $photo, matching: .images)
        .sheet(isPresented: $showingMemoji) { MemojiAvatarPicker(onSelect: preferences.setAvatar) }
        .sheet(item: $cropDraft) { draft in AvatarCropView(image: draft.image, onSave: preferences.setAvatar) }
        .task(id: photo) {
            guard let photo else { return }
            loadingAvatar = true
            defer { loadingAvatar = false; self.photo = nil }
            do {
                guard let data = try await photo.loadTransferable(type: Data.self) else {
                    avatarFailed = true
                    return
                }
                try Task.checkCancellation()
                cropDraft = try AvatarCropDraft(data: data)
            } catch is CancellationError {} catch { avatarFailed = true }
        }
        .alert("Não foi possível atualizar o avatar.", isPresented: $avatarFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("Tente escolher a imagem novamente.") }
    }
}

struct ProfileAvatar: View {
    let size: CGFloat
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        Group {
            if let data = preferences.avatarData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: size, height: size)
        .background(Theme.surfaceSecondary, in: Circle())
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct ProfileSettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) { ProfileAvatar(size: Theme.Metrics.minTouchTarget) }
            .buttonStyle(.plain)
            .accessibilityLabel("Ajustes e perfil")
            .accessibilityIdentifier("settings.open")
    }
}
