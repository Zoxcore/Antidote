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
        
        //var gradient_colors = [UIColor(red: 255.0/255.0, green: 200.0/255.0, blue: 0.0/255.0, alpha: 1.0).cgColor, UIColor(red: 255.0/255.0, green: 0.0/255.0, blue: 200.0/255.0, alpha: 1.0).cgColor];
        if let theme = theme {
        // show userstatus aswell as connectionstatus
        //       for now rather show connectionstatus
/*
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
*/
            
            var background = showExternalCircle ? theme.colorForType(.StatusBackground) : .clear
            
            switch connectionStatus {
                case .tcp:
                    background = theme.colorForType(.LoginToxLogo)
                    switch userStatus {
                        case .online:
                            roundView?.setStaticBackgroundColor(theme.colorForType(.OnlineStatus))
                            //gradient_colors = [theme.colorForType(.OnlineStatus).cgColor, theme.colorForType(.LockGradientTop).cgColor]
                        case .away:
                            roundView?.setStaticBackgroundColor(theme.colorForType(.AwayStatus))
                            //gradient_colors = [theme.colorForType(.AwayStatus).cgColor, theme.colorForType(.LockGradientTop).cgColor]
                        case .busy:
                            roundView?.setStaticBackgroundColor(theme.colorForType(.BusyStatus))
                            //gradient_colors = [theme.colorForType(.BusyStatus).cgColor, theme.colorForType(.LockGradientTop).cgColor]
                        case .offline:
                            fallthrough
                        default:
                            roundView?.setStaticBackgroundColor(theme.colorForType(.OfflineStatus))
                            //gradient_colors = [theme.colorForType(.OfflineStatus).cgColor, theme.colorForType(.LockGradientTop).cgColor]
                    }
                case .udp:
                    switch userStatus {
                        case .online:
                            roundView?.setStaticBackgroundColor(theme.colorForType(.OnlineStatus))
                            //gradient_colors = [theme.colorForType(.OnlineStatus).cgColor, theme.colorForType(.OnlineStatus).cgColor]
                        case .away:
                            roundView?.setStaticBackgroundColor(theme.colorForType(.AwayStatus))
                            //gradient_colors = [theme.colorForType(.AwayStatus).cgColor, theme.colorForType(.AwayStatus).cgColor]
                        case .busy:
                            roundView?.setStaticBackgroundColor(theme.colorForType(.BusyStatus))
                            //gradient_colors = [theme.colorForType(.BusyStatus).cgColor, theme.colorForType(.BusyStatus).cgColor]
                        case .offline:
                            fallthrough
                        default:
                            roundView?.setStaticBackgroundColor(theme.colorForType(.OfflineStatus))
                            //gradient_colors = [theme.colorForType(.OfflineStatus).cgColor, theme.colorForType(.OfflineStatus).cgColor]
                    }
                case .none:
                    fallthrough
                default:
                roundView?.setStaticBackgroundColor(theme.colorForType(.OfflineStatus))
                //gradient_colors = [theme.colorForType(.OfflineStatus).cgColor, theme.colorForType(.OfflineStatus).cgColor]
            }
            
            //TODO(Tha14): Fix this, when applied status is always red
/*
            let gradientLayer = CAGradientLayer()
            gradientLayer.frame = roundView!.bounds
            gradientLayer.colors = gradient_colors
            gradientLayer.locations = [0.3, 1.0]
            roundView?.layer.insertSublayer(gradientLayer, at:0)
*/
            
            
            setStaticBackgroundColor(background)
        }

        layer.cornerRadius = frame.size.width / 2

        roundView?.layer.cornerRadius = roundView!.frame.size.width / 2

    }
}
