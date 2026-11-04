import SwiftUI

/// Menu des filtres : genre, catégories, tailles, état, couleurs, prix…
struct FiltersView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft = FeedFilters()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Genre") {
                    FlowLayout {
                        ForEach(Gender.allCases) { gender in
                            SelectableChip(title: gender.label, isSelected: draft.genders.contains(gender)) {
                                draft.genders.toggle(gender)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    FlowLayout {
                        ForEach(GarmentCategory.allCases) { category in
                            SelectableChip(
                                title: category.label,
                                isSelected: draft.categories.contains(category)
                            ) {
                                draft.categories.toggle(category)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Catégories")
                } footer: {
                    Text("Aucune sélection = toutes les catégories.")
                }

                Section("Tailles") {
                    sizeGroup("Hauts, robes & vestes", SizeCatalog.clothing)
                    sizeGroup("Jeans & pantalons", SizeCatalog.waist)
                    sizeGroup("Chaussures", SizeCatalog.shoes)
                    sizeGroup("Sacs & accessoires", [SizeCatalog.oneSize])
                }

                Section("État") {
                    FlowLayout {
                        ForEach(GarmentCondition.allCases) { condition in
                            SelectableChip(title: condition.label, isSelected: draft.conditions.contains(condition)) {
                                draft.conditions.toggle(condition)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Couleurs") {
                    FlowLayout {
                        ForEach(GarmentColor.allCases) { color in
                            SelectableChip(title: color.label, swatch: color.swatch, isSelected: draft.colors.contains(color)) {
                                draft.colors.toggle(color)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Prix") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(draft.priceRangeLabel)
                            .font(.headline)
                        LabeledContent("Min") {
                            Slider(value: minPrice, in: 0...Double(FeedFilters.priceCeiling), step: 5)
                        }
                        LabeledContent("Max") {
                            Slider(value: maxPrice, in: 0...Double(FeedFilters.priceCeiling), step: 5)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle(isOn: $draft.hotOnly) {
                        Label("Uniquement les pièces HOT", systemImage: "flame.fill")
                    }
                    .tint(.orange)
                } footer: {
                    Text("Une pièce devient HOT quand au moins \(Garment.hotThreshold) personnes l'ont dans leur panier.")
                }

                Section {
                    Button("Réinitialiser les filtres", role: .destructive) {
                        withAnimation { draft = FeedFilters() }
                    }
                    .disabled(draft == FeedFilters())
                }
            }
            .navigationTitle("Filtres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Appliquer") {
                        let filters = draft
                        Task { await store.apply(filters) }
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                guard !loaded else { return }
                draft = store.filters
                loaded = true
            }
        }
    }

    private func sizeGroup(_ title: String, _ sizes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(sizes, id: \.self) { size in
                    SelectableChip(
                        title: size == SizeCatalog.oneSize ? "Taille unique" : size,
                        isSelected: draft.sizes.contains(size)
                    ) {
                        draft.sizes.toggle(size)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var minPrice: Binding<Double> {
        Binding(
            get: { Double(draft.minPrice) },
            set: { draft.minPrice = min(Int($0), draft.maxPrice) }
        )
    }

    private var maxPrice: Binding<Double> {
        Binding(
            get: { Double(draft.maxPrice) },
            set: { draft.maxPrice = max(Int($0), draft.minPrice) }
        )
    }
}
