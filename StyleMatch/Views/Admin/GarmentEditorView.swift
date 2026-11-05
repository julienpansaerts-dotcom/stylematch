import PhotosUI
import SwiftUI
import UIKit

/// Création / modification d'une pièce par la boutique.
struct GarmentEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State var draft: GarmentDraft
    let onSaved: (Garment) -> Void

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let maxPhotos = 8

    var body: some View {
        NavigationStack {
            Form {
                photosSection

                Section("Infos principales") {
                    TextField("Titre (ex. Veste en jean Type III)", text: $draft.title)
                    TextField("Marque", text: $draft.brand)
                    HStack {
                        TextField("Prix", text: $draft.priceEuros)
                            .keyboardType(.decimalPad)
                        Text("€").foregroundStyle(.secondary)
                    }
                }

                Section("Description") {
                    TextField("Court descriptif (affiché sur la carte)", text: $draft.summary, axis: .vertical)
                        .lineLimit(2...3)
                    TextField("Description complète", text: $draft.details, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Mesures (ex. Épaules 46 cm · Longueur 62 cm)", text: $draft.measurements, axis: .vertical)
                }

                Section("Caractéristiques") {
                    Picker("Catégorie", selection: $draft.category) {
                        ForEach(GarmentCategory.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Taille", selection: $draft.size) {
                        ForEach(sizeOptions, id: \.self) { size in
                            Text(size == SizeCatalog.oneSize ? "Taille unique" : size).tag(size)
                        }
                    }
                    Picker("Genre", selection: $draft.gender) {
                        ForEach(Gender.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("État", selection: $draft.condition) {
                        ForEach(GarmentCondition.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Couleur", selection: $draft.color) {
                        ForEach(GarmentColor.allCases) { Text($0.label).tag($0) }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.pass) }
                }
            }
            .navigationTitle(draft.id == nil ? "Nouvelle pièce" : "Modifier la pièce")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.id == nil ? "Publier" : "Enregistrer", action: save)
                        .fontWeight(.bold)
                        .disabled(!draft.isValid || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Envoi des photos…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onChange(of: draft.category) { _, _ in
                if !sizeOptions.contains(draft.size) { draft.size = sizeOptions.first ?? "M" }
            }
            .onChange(of: pickerItems) { _, items in
                Task { await importPhotos(items) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(
                    onImage: { image in
                        if let data = ImageProcessing.jpeg(from: image) { draft.newPhotos.append(data) }
                    },
                    onDone: { showCamera = false }
                )
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Photos

    private var photosSection: some View {
        Section {
            if draft.photoCount > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(draft.existingPhotos.indices, id: \.self) { index in
                            thumbnail(PhotoView(source: .remote(draft.existingPhotos[index]), compact: true)) {
                                if draft.existingPhotos.indices.contains(index) { draft.existingPhotos.remove(at: index) }
                            }
                        }
                        ForEach(draft.newPhotos.indices, id: \.self) { index in
                            thumbnail(newPhotoImage(draft.newPhotos[index])) {
                                if draft.newPhotos.indices.contains(index) { draft.newPhotos.remove(at: index) }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            if draft.photoCount < maxPhotos {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: maxPhotos - draft.photoCount,
                    matching: .images
                ) {
                    Label("Ajouter depuis la photothèque", systemImage: "photo.on.rectangle.angled")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Prendre une photo", systemImage: "camera.fill")
                    }
                }
            }
        } header: {
            Text("Photos (\(draft.photoCount)/\(maxPhotos))")
        } footer: {
            Text("La première photo est celle de la carte. Face, dos, détails, étiquette : plus il y a de photos, plus ça rassure.")
        }
    }

    private func thumbnail(_ content: some View, onDelete: @escaping () -> Void) -> some View {
        content
            .frame(width: 84, height: 105)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.ink)
                }
                .buttonStyle(.plain)
                .padding(4)
            }
    }

    @ViewBuilder
    private func newPhotoImage(_ data: Data) -> some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Color.gray
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            guard draft.photoCount < maxPhotos,
                  let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = ImageProcessing.jpeg(from: image) else { continue }
            draft.newPhotos.append(jpeg)
        }
        pickerItems = []
    }

    // MARK: - Tailles

    private var sizeOptions: [String] {
        var options: [String]
        switch draft.category {
        case .shoes: options = SizeCatalog.shoes
        case .bags, .accessories: options = [SizeCatalog.oneSize]
        case .jeans, .trousers, .shorts: options = SizeCatalog.waist + SizeCatalog.clothing
        default: options = SizeCatalog.clothing
        }
        if !options.contains(draft.size) && draft.id != nil { options.insert(draft.size, at: 0) }
        return options
    }

    // MARK: - Enregistrement

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let saved = try await store.saveGarment(draft)
                onSaved(saved)
                Haptics.success()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

/// Redimensionne et compresse les photos avant l'envoi.
enum ImageProcessing {
    static func jpeg(from image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

/// Appareil photo (UIKit) pour prendre une pièce en photo directement.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.onDone()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onDone()
        }
    }
}
