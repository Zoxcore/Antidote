// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import UIKit

protocol FriendCardControllerDelegate: class {
    func friendCardControllerChangeNickname(_ controller: FriendCardController, forFriend friend: OCTFriend)
    func friendCardControllerOpenChat(_ controller: FriendCardController, forFriend friend: OCTFriend)
    func friendCardControllerCall(_ controller: FriendCardController, toFriend friend: OCTFriend)
    func friendCardControllerVideoCall(_ controller: FriendCardController, toFriend friend: OCTFriend)
}

class FriendCardController: StaticTableController {
    weak var delegate: FriendCardControllerDelegate?

    fileprivate weak var submanagerObjects: OCTSubmanagerObjects!

    fileprivate let friend: OCTFriend

    fileprivate let avatarManager: AvatarManager
    fileprivate var friendToken: RLMNotificationToken?

    fileprivate let avatarModel: StaticTableAvatarCellModel
    fileprivate let chatButtonsModel: StaticTableChatButtonsCellModel
    fileprivate let nicknameModel: StaticTableDefaultCellModel
    fileprivate let nameModel: StaticTableDefaultCellModel
    fileprivate let statusMessageModel: StaticTableDefaultCellModel
    fileprivate let publicKeyModel: StaticTableDefaultCellModel
    fileprivate let capabilitiesModel: StaticTableDefaultCellModel
    fileprivate let pushurlModel: StaticTableDefaultCellModel

    init(theme: Theme, friend: OCTFriend, submanagerObjects: OCTSubmanagerObjects) {
        self.submanagerObjects = submanagerObjects
        self.friend = friend

        self.avatarManager = AvatarManager(theme: theme)

        avatarModel = StaticTableAvatarCellModel()
        chatButtonsModel = StaticTableChatButtonsCellModel()
        nicknameModel = StaticTableDefaultCellModel()
        nameModel = StaticTableDefaultCellModel()
        statusMessageModel = StaticTableDefaultCellModel()
        publicKeyModel = StaticTableDefaultCellModel()
        capabilitiesModel = StaticTableDefaultCellModel()
        pushurlModel = StaticTableDefaultCellModel()

        super.init(theme: theme, style: .plain, model: [
            [
                avatarModel,
                chatButtonsModel,
            ],
            [
                nicknameModel,
                nameModel,
                statusMessageModel,
            ],
            [
                publicKeyModel,
            ],
            [
                capabilitiesModel,
            ],
            [
                pushurlModel,
            ],
        ])

        updateModels()
    }

    deinit {
        friendToken?.invalidate()
    }

    required convenience init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let predicate = NSPredicate(format: "uniqueIdentifier == %@", friend.uniqueIdentifier)
        let results = submanagerObjects.friends(predicate: predicate)
        friendToken = results.addNotificationBlock { [unowned self] change in
            switch change {
                case .initial:
                    break
                case .update:
                    self.updateModels()
                    self.reloadTableView()
                case .error(let error):
                    fatalError("\(error)")
            }
        }
    }
}

private extension FriendCardController {
    func updateModels() {
        title = friend.nickname

        if let data = friend.avatarData {
            avatarModel.avatar = UIImage(data: data)
        }
        else {
            avatarModel.avatar = avatarManager.avatarFromString(
                    friend.nickname,
                    diameter: StaticTableAvatarCellModel.Constants.AvatarImageSize)
        }
        avatarModel.userInteractionEnabled = false

        chatButtonsModel.chatButtonHandler = { [unowned self] in
            self.delegate?.friendCardControllerOpenChat(self, forFriend: self.friend)
        }
        chatButtonsModel.callButtonHandler = { [unowned self] in
            self.delegate?.friendCardControllerCall(self, toFriend: self.friend)
        }
        chatButtonsModel.videoButtonHandler = { [unowned self] in
            self.delegate?.friendCardControllerVideoCall(self, toFriend: self.friend)
        }
        chatButtonsModel.chatButtonEnabled = true
        chatButtonsModel.callButtonEnabled = friend.isConnected
        chatButtonsModel.videoButtonEnabled = friend.isConnected

        nicknameModel.title = String(localized: "nickname")
        nicknameModel.value = friend.nickname
        nicknameModel.rightImageType = .arrow
        nicknameModel.didSelectHandler = { [unowned self] _ -> Void in
            self.delegate?.friendCardControllerChangeNickname(self, forFriend: self.friend)
        }

        nameModel.title = String(localized: "name")
        nameModel.value = friend.name
        nameModel.userInteractionEnabled = false

        statusMessageModel.title = String(localized: "status_message")
        statusMessageModel.value = friend.statusMessage
        statusMessageModel.userInteractionEnabled = false

        publicKeyModel.title = String(localized: "public_key")
        publicKeyModel.value = friend.publicKey
        publicKeyModel.userInteractionEnabled = false
        publicKeyModel.canCopyValue = true

        capabilitiesModel.title = "Tox Capabilities"
        let capabilities = friend.capabilities2 ?? ""
        if (capabilities.count > 0) {
            let caps = NSNumber(value: UInt64(capabilities) ?? 0)
            capabilitiesModel.value = capabilitiesToString(caps)
        } else {
            capabilitiesModel.value = "BASIC"
        }
        capabilitiesModel.userInteractionEnabled = false

        pushurlModel.title = "Push URL"
        let pushtoken = friend.pushToken ?? ""
        if (pushtoken.count > 0) {
            pushurlModel.value = pushtoken
        } else {
            pushurlModel.value = ""
        }
        pushurlModel.userInteractionEnabled = false
    }

    func capabilitiesToString(_ cap: NSNumber) -> String {
        var ret: String = "BASIC"
        if ((UInt(cap) & 1) > 0) {
            ret = ret + " CAPABILITIES"
        }
        if ((UInt(cap) & 2) > 0) {
            ret = ret + " MSGV2"
        }
        if ((UInt(cap) & 4) > 0) {
            ret = ret + " H264"
        }
        if ((UInt(cap) & 8) > 0) {
            ret = ret + " MSGV3"
        }
        if ((UInt(cap) & 16) > 0) {
            ret = ret + " FTV2"
        }
        return ret;
    }

}
