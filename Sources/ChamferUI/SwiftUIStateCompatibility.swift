import SwiftUI

// The Xcode 27 command-line tools expose SwiftUI's new `State` macro in the
// SDK but do not ship its macro plug-in. Chamfer uses the established property
// wrapper semantics, so keep that spelling bound to the public wrapper type.
typealias LegacyState<Value> = SwiftUI.State<Value>
