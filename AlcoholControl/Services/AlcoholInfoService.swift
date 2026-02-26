import Foundation

struct AlcoholDrinkInfo: Sendable {
    let name: String
    let type: String?
    let abvPercent: Double?
    let composition: String?
}

actor AlcoholInfoService {
    static let shared = AlcoholInfoService()

    private var presetCache: [String: AlcoholDrinkInfo] = [:]
    private var missingPresetIDs: Set<String> = []
    private var didWarmupCatalog = false

    func warmupCatalogIfNeeded() async {
        guard !didWarmupCatalog else { return }
        didWarmupCatalog = true

        let presets = await MainActor.run { DrinkCatalog.defaults }
        await withTaskGroup(of: Void.self) { group in
            for preset in presets {
                group.addTask {
                    _ = await self.info(for: preset)
                }
            }
        }
    }

    func info(for preset: DrinkPresetModel) async -> AlcoholDrinkInfo? {
        if let cached = presetCache[preset.id] {
            return cached
        }
        if missingPresetIDs.contains(preset.id) {
            return nil
        }

        if let drinkInfo = await fetchCocktailByName(for: preset) {
            presetCache[preset.id] = drinkInfo
            return drinkInfo
        }

        for ingredient in ingredientQueries(for: preset) {
            if let ingredientInfo = await fetchIngredientInfo(for: ingredient, fallbackName: preset.title) {
                presetCache[preset.id] = ingredientInfo
                return ingredientInfo
            }
        }

        missingPresetIDs.insert(preset.id)
        return nil
    }

    private func fetchCocktailByName(for preset: DrinkPresetModel) async -> AlcoholDrinkInfo? {
        guard preset.category == .cocktail else { return nil }
        guard let encoded = preset.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        guard let url = URL(string: "https://www.thecocktaildb.com/api/json/v1/1/search.php?s=\(encoded)") else { return nil }

        guard
            let root = await requestJSON(url: url),
            let drinks = root["drinks"] as? [[String: Any]],
            let first = drinks.first
        else {
            return nil
        }

        let name = (first["strDrink"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let alcoholic = (first["strAlcoholic"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = (first["strCategory"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        var ingredients: [String] = []
        for index in 1...15 {
            let key = "strIngredient\(index)"
            if let value = first[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    ingredients.append(trimmed)
                }
            }
        }

        let composition = ingredients.isEmpty ? nil : ingredients.joined(separator: ", ")
        let type = [category, alcoholic].compactMap { $0 }.joined(separator: " / ")

        return AlcoholDrinkInfo(
            name: name?.isEmpty == false ? name! : preset.title,
            type: type.isEmpty ? nil : type,
            abvPercent: nil,
            composition: composition
        )
    }

    private func fetchIngredientInfo(for ingredient: String, fallbackName: String) async -> AlcoholDrinkInfo? {
        guard let encoded = ingredient.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        guard let url = URL(string: "https://www.thecocktaildb.com/api/json/v1/1/search.php?i=\(encoded)") else { return nil }

        guard
            let root = await requestJSON(url: url),
            let ingredients = root["ingredients"] as? [[String: Any]],
            let first = ingredients.first
        else {
            return nil
        }

        let name = (first["strIngredient"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = (first["strType"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawABV = (first["strABV"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (first["strDescription"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let abv = rawABV.flatMap(Double.init)

        return AlcoholDrinkInfo(
            name: name?.isEmpty == false ? name! : fallbackName,
            type: type?.isEmpty == true ? nil : type,
            abvPercent: abv,
            composition: description?.isEmpty == true ? nil : description
        )
    }

    private func requestJSON(url: URL) async -> [String: Any]? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode),
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return nil
            }
            return root
        } catch {
            return nil
        }
    }

    private func ingredientQueries(for preset: DrinkPresetModel) -> [String] {
        var queries: [String] = []
        queries.append(preset.title)

        switch preset.category {
        case .cocktail:
            queries.append(contentsOf: ["Vodka", "Gin", "Rum", "Tequila"])
        case .beer:
            queries.append(contentsOf: ["Beer", "Lager", "Ale"])
        case .wine:
            queries.append(contentsOf: ["Wine", "Red wine", "White wine"])
        case .spirits:
            queries.append(contentsOf: ["Whiskey", "Bourbon", "Vodka", "Rum", "Gin", "Tequila"])
        case .cider:
            queries.append(contentsOf: ["Cider", "Apple cider"])
        case .seltzer:
            queries.append(contentsOf: ["Soda water", "Carbonated water"])
        case .liqueur:
            queries.append(contentsOf: ["Liqueur", "Amaretto", "Vermouth"])
        case .other:
            queries.append(contentsOf: ["Alcohol", "Brandy", "Bitters"])
        }

        var seen = Set<String>()
        return queries.filter { seen.insert($0.lowercased()).inserted }
    }
}
