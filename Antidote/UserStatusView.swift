// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import UIKit
import SnapKit

class UserStatusView: StaticBackgroundView {
    struct Constants {
        static let DefaultSize = 14.0
    }

    fileprivate var roundView: StaticBackgroundView?

    var theme: Theme? {
        didSet {
            userStatusWasUpdated()
        }
    }

    var showExternalCircle: Bool = true {
        didSet {
            userStatusWasUpdated()
        }
    }

    var userStatus: UserStatus = .offline {
        didSet {
            userStatusWasUpdated()
        }
    }

    var connectionStatus: ConnectionStatus = .none {
        didSet {
            userStatusWasUpdated()
        }
    }

    init() {
        super.init(frame: CGRect.zero)

        createRoundView()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        userStatusWasUpdated()
    }

    override var frame: CGRect {
        didSet {
            userStatusWasUpdated()
        }
    }
}

private extension UserStatusView {
    func createRoundView() {
        roundView = StaticBackgroundView()
        roundView!.layer.masksToBounds = true
        addSubview(roundView!)

        roundView!.snp.makeConstraints {
            $0.center.equalTo(self)
            $0.size.equalTo(self).offset(-4.0)
        }
    }

    func userStatusWasUpdated() {
        if let theme = theme {

        // TODO: show userstatus as well as connectionstatus
        // Currently showing the userstatus when debug mode is off, otherwise the connection status

            if (UserDefaultsManager().DebugMode == false) {
                //Default user status indicator
                switch userStatus {
                    case .offline:
                        roundView?.setStaticBackgroundColor(theme.colorForType(.OfflineStatus))
                    case .online:
                        roundView?.setStaticBackgroundColor(theme.colorForType(.OnlineStatus))
                    case .away:
                        roundView?.setStaticBackgroundColor(theme.colorForType(.AwayStatus))
                    case .busy:
                        roundView?.setStaticBackgroundColor(theme.colorForType(.BusyStatus))
                }
            } else {
                //Debug connection status indicator
                switch connectionStatus {
                    case .tcp:
                        roundView?.setStaticBackgroundColor(theme.colorForType(.AwayStatus))
                    case .udp:
                        roundView?.setStaticBackgroundColor(theme.colorForType(.OnlineStatus))
                    case .none:
                    fallthrough
                    default:
                        roundView?.setStaticBackgroundColor(theme.colorForType(.OfflineStatus))
                }
            }
            
            let background = showExternalCircle ? theme.colorForType(.StatusBackground) : .clear
            setStaticBackgroundColor(background)
        }

        layer.cornerRadius = frame.size.width / 2

        roundView?.layer.cornerRadius = roundView!.frame.size.width / 2
    }
}
