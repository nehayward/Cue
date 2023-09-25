import Observation
import RevenueCat

@Observable
class SubscriptionService {
    var isEnabled: Bool = true
    var isConfigured: Bool = false

    func setup() async {
        guard !isConfigured else { return }
        Purchases.logLevel = .error
        Purchases.configure(withAPIKey: "appl_ukLcssJkMdgCvraYWRsnWlqegvP")
        isConfigured = true
    }

    func getOfferings() async throws -> Offerings? {
        await setup()
        do {
            let offerings = try await Purchases.shared.offerings()
            // Display current offering with offerings.current
            print(offerings)
            return offerings
        } catch let error {
            // handle error
            print(error)
        }
        return nil
    }

    func pay(package: Package) async throws -> Bool {
        let response = try await Purchases.shared.purchase(package: package)
        if !response.userCancelled {
            return false
        }

        print(response.customerInfo)
        return true
    }

    func checkStatus() async throws {
        let customerInfo = try await Purchases.shared.customerInfo()
        print(customerInfo)
    }
}

