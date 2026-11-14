import SwiftUI
import StoreKit

// MARK: - PaywallView

struct PaywallView: View {
    @Environment(EntitlementManager.self) private var entitlement
    @Environment(\.dismiss) private var dismiss

    @State private var isProcessing = false

    var body: some View {
        VStack(spacing: 0) {
            // Close
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Hero
            VStack(spacing: 14) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor.gradient)

                Text("Unlock Music2PLX Pro")
                    .font(.largeTitle.bold())

                Text("Import unlimited playlists from Music to Plex.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            // Features
            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(icon: "infinity",
                           title: "Unlimited imports",
                           subtitle: "Import as many playlists as you want.")
                FeatureRow(icon: "wand.and.stars",
                           title: "Smart matching",
                           subtitle: "Fuzzy matching by title, artist, album, duration.")
                FeatureRow(icon: "square.and.arrow.up",
                           title: "Export reports",
                           subtitle: "Save the import log as CSV.")
                FeatureRow(icon: "lock.shield",
                           title: "One-time purchase",
                           subtitle: "No subscription. Buy once, keep forever.")
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)

            Spacer(minLength: 16)

            // Price + actions
            VStack(spacing: 10) {
                if let product = entitlement.proProduct {
                    Text(product.displayPrice)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else if entitlement.isLoadingProducts {
                    ProgressView().controlSize(.small)
                } else {
                    Text("—")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await purchase() }
                } label: {
                    Group {
                        if isProcessing {
                            ProgressView().controlSize(.small)
                                .tint(.white)
                        } else if entitlement.proProduct == nil && entitlement.isLoadingProducts {
                            Text("Loading…").font(.headline)
                        } else if entitlement.proProduct == nil {
                            Text("Product Unavailable").font(.headline)
                        } else {
                            Text("Buy Pro").font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(entitlement.proProduct == nil || isProcessing)

                if entitlement.proProduct == nil && !entitlement.isLoadingProducts {
                    Button("Retry") {
                        Task { await entitlement.refreshProducts() }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }

                Button("Restore Purchases") {
                    Task { await restore() }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .disabled(isProcessing)

                if let error = entitlement.purchaseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(width: 440, height: 580)
        .onAppear {
            print("[Paywall] appeared. isPro=\(entitlement.isPro) product=\(entitlement.proProduct?.id ?? "nil") isLoading=\(entitlement.isLoadingProducts) error=\(entitlement.purchaseError ?? "nil")")
            if entitlement.proProduct == nil && !entitlement.isLoadingProducts {
                print("[Paywall] product is nil and not loading — triggering refresh")
                Task { await entitlement.refreshProducts() }
            }
        }
    }

    private func purchase() async {
        print("[Paywall] purchase() tapped. product=\(entitlement.proProduct?.id ?? "nil")")
        isProcessing = true
        defer { isProcessing = false }
        let ok = await entitlement.buyPro()
        print("[Paywall] purchase() result. ok=\(ok) isPro=\(entitlement.isPro)")
        if ok { dismiss() }
    }

    private func restore() async {
        isProcessing = true
        defer { isProcessing = false }
        await entitlement.restorePurchases()
        if entitlement.isPro { dismiss() }
    }
}

// MARK: - FeatureRow

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}
