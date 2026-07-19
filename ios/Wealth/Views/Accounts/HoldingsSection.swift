import SwiftUI

/// Read-only list of the securities held in ONE investment account, fetched
/// live from the server (not persisted). The call site is a single line — the
/// guard for "is this a linked investment account?" lives here, so for cash /
/// credit / loan accounts (or manual ones) this renders nothing.
struct HoldingsSection: View {
    let account: Account

    @State private var rows: [HoldingRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    /// Only linked investment-category accounts have holdings to show.
    private var isEligible: Bool {
        account.plaidItemId != nil && account.type.category == .investment
    }

    var body: some View {
        if isEligible {
            Section("Holdings") {
                if isLoading && rows.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading holdings…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if rows.isEmpty {
                    Text("No holdings reported for this account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        HoldingRowView(row: row)
                    }
                }
            }
            .task {
                await loadIfNeeded()
            }
        }
    }

    private func loadIfNeeded() async {
        guard !didLoad, let itemId = account.plaidItemId else { return }
        didLoad = true
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await InvestmentsAPIClient.fetchHoldings(itemId: itemId)
            let securitiesById = Dictionary(
                response.securities.map { ($0.securityId, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let mine = response.holdings.filter { $0.accountId == account.plaidAccountId }
            rows = mine.map { holding in
                HoldingRow(holding: holding, security: securitiesById[holding.securityId])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A holding joined with its security, ready to display.
private struct HoldingRow: Identifiable {
    let id = UUID()
    let holding: PlaidHolding
    let security: PlaidSecurity?

    var title: String {
        if let ticker = security?.tickerSymbol, !ticker.isEmpty { return ticker }
        if let name = security?.name, !name.isEmpty { return name }
        return "Holding"
    }

    /// Subtitle shown under the ticker: the full name, if we have both.
    var subtitle: String? {
        guard let name = security?.name, !name.isEmpty else { return nil }
        if let ticker = security?.tickerSymbol, !ticker.isEmpty, ticker != name {
            return name
        }
        return nil
    }

    var quantityString: String? {
        guard let quantity = holding.quantity else { return nil }
        return String(format: "%.4g", quantity)
    }

    var valueString: String? {
        guard let value = holding.institutionValue else { return nil }
        return HoldingsSectionFormat.money(value).currencyString
    }
}

private struct HoldingRowView: View {
    let row: HoldingRow

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let quantity = row.quantityString {
                    Text("\(quantity) shares")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let value = row.valueString {
                Text(value)
                    .font(.callout.monospacedDigit())
            }
        }
    }
}

/// Same string-rounding money conversion as SyncEngine.money, duplicated here
/// so the view is self-contained: rounds a JSON Double to cents via string,
/// avoiding binary-float residue like 42.500000000000004.
private enum HoldingsSectionFormat {
    static func money(_ value: Double) -> Decimal {
        Decimal(string: String(format: "%.2f", value)) ?? Decimal(value)
    }
}
