import Observation
import RevenueCat

@Observable
class SubscriptionService {
    var isEnabled: Bool = true

    func setup() async {
            Purchases.logLevel = .debug
            Purchases.configure(withAPIKey: "appl_ukLcssJkMdgCvraYWRsnWlqegvP")
        // Using Swift Concurrency
        do {
            let offerings = try await Purchases.shared.offerings()
            // Display current offering with offerings.current
            print(offerings)
        } catch let error {
            // handle error
            print(error)
        }
    }

    func getOfferings() async throws -> Offerings? {
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

    func checkStatus() async {
//        let customerInfo = try await Purchases.shared.customerInfo()
//        if customerInfo.entitlements.all[<your_entitlement_id>]?.isActive == true {
//            // User is "premium"
//        }
    }
}

