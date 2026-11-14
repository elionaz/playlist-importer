import Foundation
import StoreKit

// MARK: - EntitlementManager

@MainActor
@Observable final class EntitlementManager {

    // MARK: - Configuration

    static let proProductID    = "com.playlistimporter.app.pro_unlock"
    static let freeImportLimit = 5

    // MARK: - State

    private(set) var isPro: Bool = false
    private(set) var freeImportsUsed: Int = 0
    private(set) var proProduct: Product?
    private(set) var isLoadingProducts: Bool = false
    var purchaseError: String?

    // MARK: - Derived

    var freeImportsRemaining: Int { max(0, Self.freeImportLimit - freeImportsUsed) }
    var canImport: Bool { isPro || freeImportsUsed < Self.freeImportLimit }
    var formattedPrice: String { proProduct?.displayPrice ?? "—" }

    // MARK: - Internals

    private static let freeImportsKey = "playlistimporter.freeImportsUsed"

    // MARK: - Init

    init() {
        self.freeImportsUsed = UserDefaults.standard.integer(forKey: Self.freeImportsKey)
        print("[Entitlement] init — freeImportsUsed=\(freeImportsUsed)")

        // El listener vive durante toda la vida de la app — usa weak self
        // para no retenerse a sí mismo. No hace falta cancelar en deinit.
        Task { [weak self] in
            for await update in Transaction.updates {
                print("[Entitlement] Transaction update received")
                await self?.handle(verification: update)
            }
        }

        Task { [weak self] in
            print("[Entitlement] bootstrap() starting")
            await self?.bootstrap()
            print("[Entitlement] bootstrap() finished. isPro=\(self?.isPro ?? false) product=\(self?.proProduct?.id ?? "nil")")
        }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        await refreshProducts()
        await refreshEntitlements()
    }

    func refreshProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            print("[Entitlement] Requesting product: \(Self.proProductID)")
            let products = try await Product.products(for: [Self.proProductID])
            print("[Entitlement] Got \(products.count) product(s): \(products.map(\.id))")
            self.proProduct = products.first
            if products.isEmpty {
                purchaseError = "Product not found. Check StoreKit configuration in scheme (Run → Options)."
            } else {
                purchaseError = nil
            }
        } catch {
            print("[Entitlement] Product load error: \(error)")
            purchaseError = "Could not load products: \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productID == Self.proProductID,
               tx.revocationDate == nil {
                pro = true
            }
        }
        self.isPro = pro
    }

    // MARK: - Purchase

    @discardableResult
    func buyPro() async -> Bool {
        if proProduct == nil { await refreshProducts() }
        guard let product = proProduct else {
            purchaseError = "Product not available. Check your internet connection."
            return false
        }
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification: verification)
                return isPro
            case .userCancelled:
                return false
            case .pending:
                purchaseError = "Purchase is pending approval"
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPro {
                purchaseError = "No previous purchase found for this Apple ID."
            }
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Free counter

    func recordImportCompleted() {
        guard !isPro else { return }
        let next = min(freeImportsUsed + 1, Self.freeImportLimit + 1)
        freeImportsUsed = next
        UserDefaults.standard.set(next, forKey: Self.freeImportsKey)
    }

    // MARK: - Private

    private func handle(verification: VerificationResult<Transaction>) async {
        guard case .verified(let tx) = verification else { return }
        if tx.productID == Self.proProductID {
            isPro = tx.revocationDate == nil
        }
        await tx.finish()
    }
}
