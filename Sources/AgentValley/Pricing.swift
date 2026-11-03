import Foundation

/// Dollars for a million tokens of each kind.
struct Price: Equatable {
    let input, write5m, write1h, read, output: Double
}

/// What an answer would cost at Anthropic's API prices. Whoever pays by plan pays something
/// else: this is a measure to compare work by, and is said to be one wherever it is shown.
enum Pricing {
    /// When the table was last checked against https://platform.claude.com/docs/en/about-claude/pricing.md
    static let checkedOn = "Oct 15, 2026"
    static let perSearch = 10.0 / 1000
    /// Haiku 5.5 costs more once a prompt passes this many tokens.
    static let longPrompt = 100_000

    private struct Model {
        let id: String
        let price: Price
        /// The price past `longPrompt`, for a model priced so.
        var long: Price?
        /// What fast mode multiplies the price by. nil where fast mode has no price.
        var fast: Double?
    }

    private static let opus = Price(input: 5, write5m: 6.25, write1h: 10, read: 0.5, output: 25)
    private static let opusFour = Price(input: 15, write5m: 18.75, write1h: 30, read: 1.5, output: 75)
    private static let sonnetFour = Price(input: 3, write5m: 3.75, write1h: 6, read: 0.3, output: 15)

    private static let models: [Model] = [
        Model(id: "claude-fable-5-1", price: Price(input: 10, write5m: 12.5, write1h: 20, read: 0.25, output: 50)),
        Model(id: "claude-fable-5", price: Price(input: 10, write5m: 12.5, write1h: 20, read: 1, output: 50)),
        Model(id: "claude-opus-5-5", price: Price(input: 4, write5m: 5, write1h: 8, read: 0.2, output: 20), fast: 2),
        Model(id: "claude-opus-5", price: opus, fast: 2),
        Model(id: "claude-opus-4-8", price: opus, fast: 2),
        Model(id: "claude-opus-4-7", price: opus),
        // Asked for fast, it runs at standard speed and is billed so.
        Model(id: "claude-opus-4-6", price: opus, fast: 1),
        Model(id: "claude-opus-4-5", price: opus),
        Model(id: "claude-opus-4-1", price: opusFour),
        Model(id: "claude-opus-4", price: opusFour),
        Model(id: "claude-sonnet-5-5", price: Price(input: 2, write5m: 2.5, write1h: 4, read: 0.1, output: 10)),
        Model(id: "claude-sonnet-5", price: Price(input: 2, write5m: 2.5, write1h: 4, read: 0.2, output: 10)),
        Model(id: "claude-sonnet-4-6", price: sonnetFour),
        Model(id: "claude-sonnet-4-5", price: sonnetFour),
        Model(id: "claude-sonnet-4", price: sonnetFour),
        Model(id: "claude-haiku-5-5", price: Price(input: 0.1, write5m: 0.125, write1h: 0.2, read: 0.01, output: 0.5),
              long: Price(input: 0.5, write5m: 0.625, write1h: 1, read: 0.05, output: 2.5)),
        Model(id: "claude-haiku-4-5", price: Price(input: 1, write5m: 1.25, write1h: 2, read: 0.1, output: 5)),
    ]

    private static let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

    /// The model an id names: the id itself, or the id with a date after it, as
    /// "claude-haiku-4-5-20251001". A newer model is not taken for an older one of the same
    /// line: "claude-opus-5-7" has no price until the table has it.
    private static func model(_ id: String) -> Model? {
        if let model = byID[id] { return model }
        // A cloud platform's name for it: "us.anthropic.claude-opus-5-5-v1:0" on Bedrock, or an
        // ARN that ends so, and "claude-opus-5-5@20261001" on Vertex.
        var bare = Substring(id)
        if let prefix = bare.range(of: "anthropic.", options: .backwards) { bare = bare[prefix.upperBound...] }
        if let at = bare.firstIndex(of: "@") { bare = bare[..<at] }
        if let version = bare.range(of: #"-v\d+(:\d+)?$"#, options: .regularExpression) { bare = bare[..<version.lowerBound] }
        if bare != id { return model(String(bare)) }
        guard let dash = id.lastIndex(of: "-") else { return nil }
        let date = id[id.index(after: dash)...]
        guard date.count == 8, date.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return byID[String(id[..<dash])]
    }

    /// In dollars, or nil when the table does not know the model, or knows no price for it in
    /// fast mode.
    static func cost(of answer: LedgerAnswer) -> Double? {
        guard let model = model(answer.model) else { return nil }
        let price = answer.prompt > longPrompt ? model.long ?? model.price : model.price
        var times = answer.us ? 1.1 : 1
        if answer.fast {
            guard let fast = model.fast else { return nil }
            times *= fast
        }
        let millions = Double(answer.input) * price.input + Double(answer.write5m) * price.write5m
            + Double(answer.write1h) * price.write1h + Double(answer.read) * price.read + Double(answer.output) * price.output
        return millions / 1_000_000 * times + Double(answer.searches) * perSearch
    }
}
