import Foundation

/// Catalogue de démonstration (pièces uniques de seconde main).
enum MockCatalogue {
    private struct Seed {
        let title: String
        let brand: String
        let size: String
        let gender: Gender
        let category: GarmentCategory
        let condition: GarmentCondition
        let color: GarmentColor
        let price: Int
        let carts: Int
        let summary: String
        let details: String
        let measurements: String?
    }

    static func makeGarments() -> [Garment] {
        seeds.enumerated().map { index, seed in
            Garment(
                id: String(format: "g%03d", index + 1),
                title: seed.title,
                brand: seed.brand,
                summary: seed.summary,
                details: seed.details,
                measurements: seed.measurements,
                size: seed.size,
                gender: seed.gender,
                category: seed.category,
                condition: seed.condition,
                color: seed.color,
                priceCents: seed.price * 100,
                photos: placeholderPhotos(category: seed.category, color: seed.color),
                cartCount: seed.carts,
                status: .available
            )
        }
    }

    static func placeholderPhotos(category: GarmentCategory, color: GarmentColor) -> [PhotoSource] {
        ["Vue de face", "Vue de dos", "Détail", "Étiquette"].enumerated().map { index, caption in
            .placeholder(symbol: category.symbol, tint: color, caption: caption, variant: index)
        }
    }

    static func makePastOrders() -> [Order] {
        let date = Calendar.current.date(byAdding: .day, value: -12, to: Date()) ?? Date()
        let garment = Garment(
            id: "past-001",
            title: "Chemise en jean western",
            brand: "Wrangler",
            summary: "Chemise western à boutons pression nacrés.",
            details: "Chemise en denim délavé, boutons pression nacrés, coupe droite.",
            measurements: nil,
            size: "M",
            gender: .men,
            category: .shirts,
            condition: .veryGood,
            color: .blue,
            priceCents: 2800,
            photos: placeholderPhotos(category: .shirts, color: .blue),
            cartCount: 3,
            status: .sold
        )
        let timeline = OrderStatus.allCases.enumerated().map { index, status in
            OrderStatusEvent(status: status, date: date.addingTimeInterval(Double(index) * 14 * 3600))
        }
        return [
            Order(
                id: "order-041",
                number: "SM-2026-0041",
                createdAt: date,
                items: [garment],
                subtotalCents: 2800,
                shippingCents: ServerPricing.shipping(for: .relayPoint),
                serviceFeeCents: ServerPricing.serviceFee(subtotal: 2800),
                deliveryMethod: .relayPoint,
                shippingAddress: ShippingAddress(line1: "12 rue des Lilas", postalCode: "75011", city: "Paris"),
                relayPoint: "Tabac Le Balto – 75011 Paris",
                paymentSummary: "Visa •••• 4242",
                trackingNumber: "8R482913377FR",
                status: .delivered,
                timeline: timeline
            )
        ]
    }

    // swiftlint:disable line_length
    private static let seeds: [Seed] = [
        Seed(title: "Veste en jean Type III", brand: "Levi's", size: "M", gender: .unisex, category: .jackets, condition: .veryGood, color: .blue, price: 65, carts: 14,
             summary: "Délavage vintage années 90, coupe trucker iconique.",
             details: "Veste trucker en denim 100 % coton, délavage clair naturel. Boutons cuivre d'origine, aucune tache ni accroc. Taille un peu grand, parfaite en oversize.",
             measurements: "Épaules 46 cm · Longueur 62 cm · Manches 61 cm"),
        Seed(title: "Robe midi fleurie", brand: "Sézane", size: "S", gender: .women, category: .dresses, condition: .newWithTags, color: .multicolor, price: 89, carts: 9,
             summary: "Imprimé fleuri, manches bouffantes, jamais portée.",
             details: "Robe midi en viscose écoresponsable, boutonnée sur le devant, ceinture amovible. Encore avec l'étiquette, achetée la mauvaise taille.",
             measurements: "Poitrine 44 cm · Longueur 118 cm"),
        Seed(title: "Sweat Reverse Weave", brand: "Champion", size: "L", gender: .unisex, category: .sweatshirts, condition: .good, color: .grey, price: 38, carts: 6,
             summary: "Gris chiné, molleton épais, logo brodé.",
             details: "Le sweat culte au tissage inversé qui ne rétrécit pas. Légère bouloche sous les bras, rien de visible porté.",
             measurements: "Aisselle à aisselle 60 cm · Longueur 70 cm"),
        Seed(title: "Air Max 90", brand: "Nike", size: "42", gender: .men, category: .shoes, condition: .veryGood, color: .white, price: 85, carts: 16,
             summary: "Coloris Infrared, semelle propre, boîte d'origine.",
             details: "Portées une dizaine de fois, nettoyées. Bulle d'air intacte, pas de jaunissement. Livrées avec la boîte et les lacets de rechange.",
             measurements: nil),
        Seed(title: "Pull col roulé mérinos", brand: "COS", size: "M", gender: .women, category: .knitwear, condition: .veryGood, color: .beige, price: 42, carts: 3,
             summary: "Laine mérinos fine, très douce, coupe ajustée.",
             details: "Maille fine 100 % mérinos, idéale en sous-couche. Lavé à la main uniquement, aucune bouloche.",
             measurements: "Poitrine 47 cm · Longueur 60 cm"),
        Seed(title: "Chemise Oxford", brand: "Ralph Lauren", size: "L", gender: .men, category: .shirts, condition: .veryGood, color: .blue, price: 35, carts: 4,
             summary: "Oxford bleu ciel, col boutonné, petit logo brodé.",
             details: "Coupe Custom Fit, coton Oxford épais. Col et poignets impeccables.",
             measurements: "Poitrine 58 cm · Longueur 78 cm"),
        Seed(title: "Trench classique", brand: "Burberry", size: "S", gender: .women, category: .coats, condition: .good, color: .beige, price: 290, carts: 12,
             summary: "Trench iconique en gabardine, doublure check.",
             details: "Modèle Kensington, ceinture et boutons d'origine. Petite trace d'usure au col (voir photo détail). Une pièce intemporelle.",
             measurements: "Épaules 39 cm · Longueur 104 cm"),
        Seed(title: "Jean 501 brut", brand: "Levi's", size: "W32", gender: .men, category: .jeans, condition: .good, color: .navy, price: 45, carts: 7,
             summary: "Coupe droite originale, denim brut patiné.",
             details: "Le 501 original à braguette boutonnée. Belles patines naturelles sur les cuisses. Longueur L32.",
             measurements: "Taille 41 cm à plat · Entrejambe 81 cm"),
        Seed(title: "T-shirt Nirvana 1993", brand: "Vintage", size: "L", gender: .unisex, category: .tshirts, condition: .good, color: .black, price: 55, carts: 11,
             summary: "Tee de tournée original, single stitch.",
             details: "Véritable t-shirt vintage à couture simple, sérigraphie craquelée par le temps. Noir passé, tombé parfait.",
             measurements: "Aisselle à aisselle 55 cm · Longueur 72 cm"),
        Seed(title: "Jupe plissée satinée", brand: "& Other Stories", size: "S", gender: .women, category: .skirts, condition: .newWithoutTags, color: .green, price: 32, carts: 2,
             summary: "Satin vert sapin, plis fluides, taille élastiquée.",
             details: "Jupe midi plissée au tombé fluide. Portée une seule fois pour un mariage.",
             measurements: "Taille 34 cm · Longueur 80 cm"),
        Seed(title: "Doudoune Nuptse 700", brand: "The North Face", size: "M", gender: .unisex, category: .jackets, condition: .veryGood, color: .black, price: 160, carts: 18,
             summary: "Duvet 700, capuche intégrée dans le col.",
             details: "La Nuptse rétro, ultra chaude et compressible. Aucune perte de plumes, fermetures en parfait état.",
             measurements: "Aisselle à aisselle 64 cm · Longueur 68 cm"),
        Seed(title: "Cabas en cuir camel", brand: "Longchamp", size: SizeCatalog.oneSize, gender: .women, category: .bags, condition: .veryGood, color: .brown, price: 120, carts: 5,
             summary: "Cuir pleine fleur, grand format, poche intérieure.",
             details: "Cabas en cuir patiné, anses solides, intérieur propre. Peut accueillir un ordinateur 13 pouces.",
             measurements: "38 × 30 × 14 cm"),
        Seed(title: "Pantalon cargo", brand: "Carhartt WIP", size: "W30", gender: .men, category: .trousers, condition: .good, color: .green, price: 48, carts: 6,
             summary: "Toile ripstop kaki, poches latérales.",
             details: "Coupe Regular, toile robuste. Légère décoloration au niveau des poches, très bon look workwear.",
             measurements: "Taille 39 cm à plat · Entrejambe 79 cm"),
        Seed(title: "Short en lin", brand: "Uniqlo", size: "M", gender: .women, category: .shorts, condition: .veryGood, color: .white, price: 15, carts: 1,
             summary: "Lin blanc cassé, taille haute.",
             details: "Short léger parfait pour l'été, taille élastiquée au dos, deux poches.",
             measurements: nil),
        Seed(title: "Polo L.12.12", brand: "Lacoste", size: "L", gender: .men, category: .tshirts, condition: .good, color: .green, price: 30, carts: 3,
             summary: "Piqué de coton vert, crocodile brodé.",
             details: "Le polo classique en petit piqué. Couleur légèrement passée, aucun trou.",
             measurements: "Aisselle à aisselle 56 cm · Longueur 74 cm"),
        Seed(title: "Cardigan grand-père", brand: "Vintage", size: "XL", gender: .unisex, category: .knitwear, condition: .good, color: .brown, price: 28, carts: 2,
             summary: "Grosse maille torsadée, boutons en cuir.",
             details: "Cardigan chiné des années 80, laine mélangée. Boutons tressés en cuir d'origine.",
             measurements: nil),
        Seed(title: "Blazer oversize", brand: "Zara", size: "M", gender: .women, category: .jackets, condition: .newWithTags, color: .black, price: 40, carts: 4,
             summary: "Épaulettes structurées, coupe droite.",
             details: "Blazer noir doublé, un bouton. Neuf avec étiquette.",
             measurements: "Épaules 44 cm · Longueur 76 cm"),
        Seed(title: "Boots 1460", brand: "Dr. Martens", size: "39", gender: .unisex, category: .shoes, condition: .good, color: .black, price: 70, carts: 8,
             summary: "Cuir lisse, 8 œillets, déjà assouplies.",
             details: "La boot culte, déjà faite au pied (fini les ampoules !). Semelle AirWair peu usée, cuir nourri.",
             measurements: nil),
        Seed(title: "Hoodie Stock Logo", brand: "Stüssy", size: "L", gender: .unisex, category: .sweatshirts, condition: .veryGood, color: .navy, price: 75, carts: 10,
             summary: "Bleu marine, logo signature brodé.",
             details: "Hoodie épais, cordons d'origine, intérieur gratté encore doux.",
             measurements: "Aisselle à aisselle 61 cm · Longueur 71 cm"),
        Seed(title: "Lunettes Wayfarer", brand: "Ray-Ban", size: SizeCatalog.oneSize, gender: .unisex, category: .accessories, condition: .veryGood, color: .black, price: 60, carts: 4,
             summary: "Monture noire, verres G-15 sans rayure.",
             details: "Modèle RB2140, étui et chiffonnette inclus.",
             measurements: "50 □ 22"),
        Seed(title: "Robe nuisette en soie", brand: "Rouje", size: "XS", gender: .women, category: .dresses, condition: .veryGood, color: .red, price: 95, carts: 7,
             summary: "Soie rouge cerise, fines bretelles réglables.",
             details: "Robe slip en soie, coupe en biais très flatteuse. Portée deux fois.",
             measurements: "Longueur 110 cm"),
        Seed(title: "Manteau long en laine", brand: "Max Mara", size: "M", gender: .women, category: .coats, condition: .good, color: .grey, price: 240, carts: 9,
             summary: "Laine et cachemire, coupe peignoir.",
             details: "Manteau ceinturé gris chiné. Doublure impeccable, légère bouloche aux poignets.",
             measurements: "Épaules 42 cm · Longueur 115 cm"),
        Seed(title: "Chemise hawaïenne", brand: "Vintage", size: "XL", gender: .men, category: .shirts, condition: .good, color: .multicolor, price: 22, carts: 0,
             summary: "Imprimé tropical, rayonne fluide.",
             details: "Chemise manches courtes années 90, boutons en coco.",
             measurements: nil),
        Seed(title: "Mom jean taille haute", brand: "Weekday", size: "W28", gender: .women, category: .jeans, condition: .veryGood, color: .blue, price: 30, carts: 5,
             summary: "Denim bleu moyen, jambe fuselée.",
             details: "Coupe mom, coton bio rigide. Ourlet brut.",
             measurements: "Taille 35 cm à plat · Entrejambe 72 cm"),
        Seed(title: "Veste Detroit", brand: "Carhartt", size: "L", gender: .men, category: .jackets, condition: .fair, color: .brown, price: 110, carts: 13,
             summary: "Canvas usé à souhait, col en velours côtelé.",
             details: "Vraie veste de travail vintage, doublure couverture. Usure marquée aux poignets et au col : tout son charme.",
             measurements: "Aisselle à aisselle 63 cm · Longueur 66 cm"),
        Seed(title: "Baskets 550", brand: "New Balance", size: "44", gender: .unisex, category: .shoes, condition: .veryGood, color: .white, price: 75, carts: 6,
             summary: "Cuir blanc et vert, style basket rétro.",
             details: "Portées quelques fois, aucune pliure marquée.",
             measurements: nil),
        Seed(title: "Écharpe en cachemire", brand: "Éric Bompard", size: SizeCatalog.oneSize, gender: .unisex, category: .accessories, condition: .newWithoutTags, color: .red, price: 45, carts: 2,
             summary: "Cachemire rouge profond, ultra douce.",
             details: "Écharpe 100 % cachemire, jamais portée, reçue en cadeau.",
             measurements: "180 × 30 cm"),
        Seed(title: "Pull marinière", brand: "Saint James", size: "M", gender: .unisex, category: .knitwear, condition: .veryGood, color: .navy, price: 50, carts: 3,
             summary: "Rayures marine et écru, laine épaisse.",
             details: "Le pull marin breton authentique, encolure bateau.",
             measurements: "Aisselle à aisselle 52 cm · Longueur 64 cm"),
        Seed(title: "Pantalon de tailleur", brand: "Sandro", size: "S", gender: .women, category: .trousers, condition: .veryGood, color: .black, price: 55, carts: 2,
             summary: "Coupe droite, pli marqué, taille haute.",
             details: "Pantalon fluide et chic, se porte aussi bien au bureau qu'en soirée.",
             measurements: "Taille 34 cm à plat · Entrejambe 78 cm"),
        Seed(title: "Casquette trucker", brand: "Patagonia", size: SizeCatalog.oneSize, gender: .unisex, category: .accessories, condition: .good, color: .beige, price: 18, carts: 1,
             summary: "Patch P-6, filet à l'arrière.",
             details: "Casquette ajustable par pression, légèrement délavée.",
             measurements: nil),
        Seed(title: "Bomber MA-1", brand: "Alpha Industries", size: "L", gender: .men, category: .jackets, condition: .good, color: .green, price: 80, carts: 7,
             summary: "Nylon kaki, doublure orange réversible.",
             details: "Le bomber militaire original, réversible. Zip YKK en parfait état.",
             measurements: "Aisselle à aisselle 62 cm · Longueur 66 cm"),
        Seed(title: "Mini sac Le Chiquito", brand: "Jacquemus", size: SizeCatalog.oneSize, gender: .women, category: .bags, condition: .veryGood, color: .pink, price: 290, carts: 15,
             summary: "Cuir rose poudré, bandoulière amovible.",
             details: "Le mini sac culte avec sa poignée haute. Livré avec dust bag et facture.",
             measurements: "18 × 12 × 8 cm")
    ]
    // swiftlint:enable line_length
}
