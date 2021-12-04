# Frequently Asked Questions

* [How do I import my profile to Antidote?](#how-do-i-import-my-profile-to-antidote)
* [How do I export my profile from Antidote?](#how-do-i-export-my-profile-from-antidote)
* [How to synchronize Tox ID between multiple devices?](#how-to-synchronize-tox-id-between-multiple-devices)
* [Why don't I receive push notifications in the background?](#why-dont-i-receive-push-notifications-in-the-background)
* [Can I send message to offline contacts?](#can-i-send-messages-to-offline-contacts)
* [How to enable PIN and Touch ID?](#how-to-enable-pin-and-touch-id)
* [Does Antidote connect to any third party servers?](#does-antidote-connect-to-any-third-party-servers)
* [More Questions?](#more-questions)
* [Translations](#translations)


## How do I import my profile to Antidote?

To import your profile to Antidote, do the following:

1. Send the .tox file to your device using any app (Mail, Dropbox, etc.).
2. Use `Open In` menu for this file.
3. Select Antidote in a list of available apps.
4. Check the name of your new profile and press OK.


## How do I export my profile from Antidote?

To export your profile from Antidote, do the following:

1. Open `Profile` tab
2. Select `Profile Details`
3. Select `Export Profile` option.


## How to synchronize Tox ID between multiple devices?

Multidevice support is being [developed](https://github.com/GrayHatter/toxcore/tree/multi-device) and is not yet complete. For now you can export your .tox profile from one device and import it to another using the guides above.


## Why don't I receive push notifications in the background?

Antidote works in the background for only 10 minutes, after that it will be suspended by iOS. Unfortunately, there is currently no way to extend this time.

However, we plan to support push notifications in the future. Please stay tuned!


## Can I send messages to offline contacts?

Offline messaging is now supported since version 1.4.2


## How to enable PIN and Touch ID?

You can protect your profile with PIN or Touch ID.
To do so:

1. Open `Profile` tab
2. Select `Profile Details`
3. Turn on `PIN Enabled` switch
4. Turn on `Touch ID Enabled` switch (if available).


## Does Antidote connect to any third party servers?

Antidote(exlcuding toxcore) uses the Google Firebase service and a third party server to deliver push notifications to other tox mobile users when they are offline. This makes it possible for Mobile devices to go into sleep mode and save battery and network bandwidth when there is no activity. Rest assured that the push notification does not contain any data, the request that comes from Antidote includes only the FCM token of your contact(s). No ToxID, name or message data is transfered in the process.


## More Questions?

Open an Issue in this Github repository https://github.com/Zoxcore/Antidote/issues


## Translations

Found any translation issues?

You can help translate Antidote to your language.

Learn more: https://hosted.weblate.org/engage/antidote/
