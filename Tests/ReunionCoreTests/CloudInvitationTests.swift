import XCTest
@testable import ReunionCore

final class CloudInvitationTests: XCTestCase {
    func testAcceptsOnlyHTTPSCloudShareLinks() {
        XCTAssertNotNil(CloudInvitation.url(" https://www.icloud.com/share/invitation-token "))
        XCTAssertNotNil(CloudInvitation.url("https://icloud.com/share/invitation-token"))
        for link in [
            "123456", "http://icloud.com/share/token", "https://icloud.com.attacker.com/share/token",
            "https://example.com/share/token", "https://icloud.com/share/", "https://icloud.com/photos/token",
            "https://user:pass@icloud.com/share/token", "https://icloud.com:8443/share/token",
        ] {
            XCTAssertNil(CloudInvitation.url(link), link)
        }
    }
}
