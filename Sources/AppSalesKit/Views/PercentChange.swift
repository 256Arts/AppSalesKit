import SwiftUI

/// A change on the period before: an arrow and an unsigned percentage, green up and red down.
public struct PercentChange: View {

    let change: Double

    public init(change: Double) {
        self.change = change
    }

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.negativePrefix = ""
        return formatter
    }()

    public var body: some View {
        Text("\(Image(systemName: change < 0 ? "arrow.down.forward" : "arrow.up.forward"))\(Self.percentFormatter.string(from: NSNumber(value: change)) ?? "")", bundle: #bundle)
            .foregroundStyle(change < 0 ? Color.red : Color.green)
    }
}
