import SwiftUI

/// The TEST chip that marks a test call.
struct TestTag: View {
    var body: some View {
        Chip("TEST", .test)
    }
}
