import Foundation

enum DrinkPresetGroup: String, CaseIterable, Identifiable {
    case beer
    case wine
    case spirits
    case cocktails
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beer: return L10n.tr("Пиво и эль")
        case .wine: return L10n.tr("Вино")
        case .spirits: return L10n.tr("Крепкие")
        case .cocktails: return L10n.tr("Коктейли")
        case .light: return L10n.tr("Легкие напитки")
        }
    }
}

struct DrinkPresetModel: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let category: DrinkEntry.Category
    let volumeMl: Double
    let abv: Double
    let group: DrinkPresetGroup
}

enum DrinkCatalog {
    static let defaults: [DrinkPresetModel] = [
        .init(id: "lager-500-5", title: "Lager", subtitle: "Светлое пиво", category: .beer, volumeMl: 500, abv: 5.0, group: .beer),
        .init(id: "pilsner-500-48", title: "Pilsner", subtitle: "Светлое пиво", category: .beer, volumeMl: 500, abv: 4.8, group: .beer),
        .init(id: "ipa-500-65", title: "IPA", subtitle: "Хмельной эль", category: .beer, volumeMl: 500, abv: 6.5, group: .beer),
        .init(id: "wheat-500-52", title: "Пшеничное", subtitle: "Пиво", category: .beer, volumeMl: 500, abv: 5.2, group: .beer),
        .init(id: "stout-440-6", title: "Stout", subtitle: "Темное пиво", category: .beer, volumeMl: 440, abv: 6.0, group: .beer),
        .init(id: "craft-can-330-7", title: "Крафтовое", subtitle: "Банка", category: .beer, volumeMl: 330, abv: 7.0, group: .beer),

        .init(id: "red-wine-150-13", title: "Красное вино", subtitle: "Бокал", category: .wine, volumeMl: 150, abv: 13.0, group: .wine),
        .init(id: "white-wine-150-12", title: "Белое вино", subtitle: "Бокал", category: .wine, volumeMl: 150, abv: 12.0, group: .wine),
        .init(id: "rose-wine-150-115", title: "Розе", subtitle: "Бокал", category: .wine, volumeMl: 150, abv: 11.5, group: .wine),
        .init(id: "sparkling-150-12", title: "Игристое", subtitle: "Бокал", category: .wine, volumeMl: 150, abv: 12.0, group: .wine),
        .init(id: "fortified-90-18", title: "Крепленое вино", subtitle: "Небольшой бокал", category: .wine, volumeMl: 90, abv: 18.0, group: .wine),

        .init(id: "vodka-50-40", title: "Водка", subtitle: "Шот", category: .spirits, volumeMl: 50, abv: 40.0, group: .spirits),
        .init(id: "whiskey-50-40", title: "Виски", subtitle: "Шот", category: .spirits, volumeMl: 50, abv: 40.0, group: .spirits),
        .init(id: "bourbon-50-40", title: "Бурбон", subtitle: "Шот", category: .spirits, volumeMl: 50, abv: 40.0, group: .spirits),
        .init(id: "tequila-50-38", title: "Текила", subtitle: "Шот", category: .spirits, volumeMl: 50, abv: 38.0, group: .spirits),
        .init(id: "rum-50-40", title: "Ром", subtitle: "Шот", category: .spirits, volumeMl: 50, abv: 40.0, group: .spirits),
        .init(id: "gin-50-40", title: "Джин", subtitle: "Шот", category: .spirits, volumeMl: 50, abv: 40.0, group: .spirits),
        .init(id: "brandy-50-40", title: "Бренди", subtitle: "Шот", category: .spirits, volumeMl: 50, abv: 40.0, group: .spirits),

        .init(id: "aperol-300-11", title: "Aperol Spritz", subtitle: "Коктейль", category: .cocktail, volumeMl: 300, abv: 11.0, group: .cocktails),
        .init(id: "mojito-300-10", title: "Mojito", subtitle: "Коктейль", category: .cocktail, volumeMl: 300, abv: 10.0, group: .cocktails),
        .init(id: "gin-tonic-250-10", title: "Gin Tonic", subtitle: "Коктейль", category: .cocktail, volumeMl: 250, abv: 10.0, group: .cocktails),
        .init(id: "cuba-libre-250-12", title: "Cuba Libre", subtitle: "Коктейль", category: .cocktail, volumeMl: 250, abv: 12.0, group: .cocktails),
        .init(id: "margarita-180-20", title: "Margarita", subtitle: "Коктейль", category: .cocktail, volumeMl: 180, abv: 20.0, group: .cocktails),
        .init(id: "daiquiri-140-22", title: "Daiquiri", subtitle: "Коктейль", category: .cocktail, volumeMl: 140, abv: 22.0, group: .cocktails),
        .init(id: "negroni-90-24", title: "Negroni", subtitle: "Крепкий коктейль", category: .cocktail, volumeMl: 90, abv: 24.0, group: .cocktails),
        .init(id: "old-fashioned-120-28", title: "Old Fashioned", subtitle: "Крепкий коктейль", category: .cocktail, volumeMl: 120, abv: 28.0, group: .cocktails),
        .init(id: "long-island-220-22", title: "Long Island", subtitle: "Крепкий коктейль", category: .cocktail, volumeMl: 220, abv: 22.0, group: .cocktails),
        .init(id: "espresso-martini-160-18", title: "Espresso Martini", subtitle: "Коктейль", category: .cocktail, volumeMl: 160, abv: 18.0, group: .cocktails),

        .init(id: "cider-500-45", title: "Сидр", subtitle: "Бутылка", category: .cider, volumeMl: 500, abv: 4.5, group: .light),
        .init(id: "dry-cider-500-6", title: "Сухой сидр", subtitle: "Бутылка", category: .cider, volumeMl: 500, abv: 6.0, group: .light),
        .init(id: "seltzer-330-45", title: "Hard Seltzer", subtitle: "Банка", category: .seltzer, volumeMl: 330, abv: 4.5, group: .light),
        .init(id: "seltzer-500-55", title: "Hard Seltzer Strong", subtitle: "Банка", category: .seltzer, volumeMl: 500, abv: 5.5, group: .light),
        .init(id: "liqueur-60-25", title: "Ликер", subtitle: "Шот", category: .liqueur, volumeMl: 60, abv: 25.0, group: .light),
        .init(id: "amaro-60-28", title: "Amaro", subtitle: "Дижестив", category: .liqueur, volumeMl: 60, abv: 28.0, group: .light),
        .init(id: "vermouth-90-16", title: "Вермут", subtitle: "Аперитив", category: .other, volumeMl: 90, abv: 16.0, group: .light)
    ]

    static var groupedDefaults: [(DrinkPresetGroup, [DrinkPresetModel])] {
        DrinkPresetGroup.allCases.compactMap { group in
            let values = defaults.filter { $0.group == group }
            return values.isEmpty ? nil : (group, values)
        }
    }
}
