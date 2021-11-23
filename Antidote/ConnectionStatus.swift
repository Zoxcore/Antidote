// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation

enum ConnectionStatus {
    case none
    case tcp
    case udp

    init(connectionStatus: OCTToxConnectionStatus) {
        switch (connectionStatus) {
            case (.none):
                self = .none
            case (.TCP):
                self = .tcp
            case (.UDP):
                self = .udp
            default:
                self = .none
        }
    }
}
