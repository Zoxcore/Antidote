# Reboot of the Tox Messenger for the IPhone

<img src="https://raw.githubusercontent.com/Zoxcore/Antidote/develop/Antidote/appstore.png" width=100>&nbsp;&nbsp;<img src="https://raw.githubusercontent.com/Zoxcore/Antidote/develop/Antidote/old_antidote_logo_with_text.png" width=100>

[Tox](https://tox.chat/) client for iOS

[![Release](https://img.shields.io/github/v/release/Zoxcore/Antidote.svg)](https://github.com/Zoxcore/Antidote/releases/latest/)
[![Translations](https://hosted.weblate.org/widgets/antidote/-/svg-badge.svg)](https://hosted.weblate.org/engage/antidote/)
[![License: GPL v3](https://img.shields.io/badge/License-MPL_2.0-blue.svg)](https://opensource.org/licenses/MPL-2.0)
[![Android CI](https://github.com/Zoxcore/Antidote/workflows/Nightly/badge.svg)](https://github.com/Zoxcore/Antidote/actions?query=workflow%3A%22Nightly%22)
[![Android CI](https://github.com/Zoxcore/Antidote/workflows/PullRequest/badge.svg)](https://github.com/Zoxcore/Antidote/actions?query=workflow%3A%22PullRequest%22)

## FAQ

See [FAQ](FAQ/en.md).

## Help Translate the App in your Language

Use Weblate:
https://hosted.weblate.org/engage/antidote/

## Get in touch
* <a href="https://matrix.to/#/#antidote:libera.chat">Join discussion on Matrix</a><br>

## Usage

#### Install from the App Store
* <a href="https://apps.apple.com/us/app/antidote-tox-client/id1592895292">Antidote - Tox Client</a><br>


#### Manual Installation

Clone repo, install pods and open `Antidote.xcworkspace` file with Xcode 12+.

```
git clone https://github.com/Antidote-for-Tox/Antidote.git
cd Antidote
pod install
open Antidote.xcworkspace
```

#### Compile on the Commandline
Clone repo, install pods and install Xcode 12+

```
git clone https://github.com/Antidote-for-Tox/Antidote.git
cd Antidote
pod install
env NSUnbufferedIO=YES xcodebuild -workspace ./Antidote.xcworkspace -scheme Antidote -destination 'platform=iOS Simulator,id=EAB9614F-3485-4A6D-8EFB-FC2B5EFB0243'
```

## Features

See [CHANGELOG](CHANGELOG.md) for list of notable changes (unreleased, current and previous versions).

-  one to one conversations
-  typing notification
-  emoticons
-  spell check
-  reading/scanning Tox ID via QR code
-  file transfer
-  read receipts
-  multiple profiles
-  tox_save import/export
-  avatars
-  audio calls
-  video calls

## License

Antidote is available under Mozilla Public License Version 2.0. See the [LICENSE](LICENSE) file for more info.

## Links

- [icons8](http://icons8.com/) - icons used in app
- new icon https://icons8.com/icon/jQvC2IpxYkR6/key


