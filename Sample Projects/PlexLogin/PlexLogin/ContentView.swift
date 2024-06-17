import SwiftUI
import AuthenticationServices

struct WebAuthenticationSessionExample: View {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        Button("Sign In") {
            Task {
                do {
//                    curl 'https://clients.plex.tv/api/v2/pins/info?code=xp0nasyeqv2gdnm20jjbtnrs4&X-Plex-Product=Chromatix&X-Plex-Client-Identifier=chromatix.app' \
//                    -H 'Host: clients.plex.tv' \
//                    -H 'Connection: keep-alive' \
//                    -H 'sec-ch-ua: "Not)A;Brand";v="24", "Chromium";v="116"' \
//                    -H 'Accept: application/json' \
//                    -H 'sec-ch-ua-mobile: ?0' \
//                    -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chromatix/0.1.3 Chrome/116.0.5845.228 Electron/26.6.10 Safari/537.36' \
//                    -H 'sec-ch-ua-platform: "macOS"' \
//                    -H 'Origin: https://app.plex.tv' \
//                    -H 'Sec-Fetch-Site: same-site' \
//                    -H 'Sec-Fetch-Mode: cors' \
//                    -H 'Sec-Fetch-Dest: empty' \
//                    -H 'Referer: https://app.plex.tv/' \
//                    -H 'Accept-Language: en-US' \
//                    --proxy http://localhost:9090
                    let urlWithToken = try await webAuthenticationSession.authenticate(using: URL(string: "https://app.plex.tv/auth/#?clientID=70834FA5-ACED-4F74-9B07-10C62DD6CA42&code=yj9vz6bqjolufa5unpvzmju67")!, callback: .customScheme("me"), preferredBrowserSession: .ephemeral, additionalHeaderFields: [:])

                    print(urlWithToken)
//                    try await signIn(using: urlWithToken) // defined elsewhere
                } catch {
                    print(error.localizedDescription)
                    // code to handle authentication errors
                }
            }
        }
    }
}
