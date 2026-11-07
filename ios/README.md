# iPhone app (v0)

What it does today:

- **The keyboard (main way to use it):** tap the message box and switch to the Coax keyboard. While it's open, take a screenshot of the chat and Coax reads it by itself (plus the screenshots before it, if you picked 2 or 3), then shows 3 replies with a small tag each ("playful", "direct"). Tap one to type it into the message box. The blue **Last N** button reads your latest screenshots on demand, the clipboard button replies to what you copied, and the keyboard icon goes back to typing. Funnier / Flirtier / Shorter redo the replies. Typing works without Full Access; replies need it.
- **In Messages:** tap **+** next to the text box, then **Coax** (under More if you don't see it). It waits for a screenshot of the chat, reads it, and shows 3 replies. Tap one and it lands in the Messages text box, ready to send. No Full Access needed.
- **In the app:** pick up to 5 screenshots of a chat (or paste one), and it shows 3 suggested replies. Tap a reply to copy it.
- **From the share sheet:** take a screenshot, tap Share, choose **Coax**, and the replies appear right there.
- It reads the screenshot on the phone with Apple's text recognition. Right-hand bubbles are "you", left-hand are "them", centered text (times, "Delivered") is skipped. If it gets one wrong, tap that message to switch who sent it.
- **Replies are samples for now.** The app talks to the reply engine through one switch (`AppConfig.replyAPIURL` in `Shared/ReplyService.swift`). When the engine is hosted, that gets set and real replies appear.

| Folder | What's in it |
| --- | --- |
| `ReplyAssistant/` | The app's screens |
| `Keyboard/` | The keyboard |
| `ShareExtension/` | The share-sheet item |
| `Shared/` | Used by both: reading screenshots, talking to the backend, the replies screen |
| `ReplyAssistantTests/` | Checks for the you/them/centered logic |

## Put it on your iPhone (about 30 minutes the first time)

You need a Mac, your iPhone, and its cable. A free Apple ID is enough for now; the paid developer account ($99/yr) is only needed for TestFlight in Sprint 3.

**1. Install Xcode** (once)
1. Open the **App Store** on your Mac, search **Xcode**, click **Get**. It's large; give it a while.
2. Open Xcode. If it asks to install components or "iOS", click **Install** and wait.

**2. Sign Xcode in to your Apple ID** (once)
1. In the menu bar: **Xcode > Settings…** then the **Accounts** tab.
2. Click **+** at the bottom left, choose **Apple ID**, sign in. Close the window.

**3. Get the code**
1. Go to github.com/vchev/rizz, click the green **Code** button, click **Download ZIP**.
2. Double-click the ZIP in Downloads to unzip it.
3. Open the unzipped folder, then the **ios** folder, and double-click **ReplyAssistant.xcodeproj**.

**4. Tell Xcode who's signing the app** (once per download)
1. In the left sidebar, click the very top item, **ReplyAssistant** (blue icon).
2. In the middle area, under **TARGETS**, click **ReplyAssistant**, then the **Signing & Capabilities** tab.
3. Next to **Team**, choose your name ("… (Personal Team)").
4. Under **TARGETS**, click **ShareExtension** and set the same **Team**. Do the same for **Keyboard** and **MessagesExtension**.
5. If you see red text saying the bundle identifier isn't available, change `com.vchev` to something only you would use (for example `com.vanessa`) in **Bundle Identifier** for all three targets. Keep the `.ShareExtension` and `.Keyboard` endings.

**5. Try it on the Mac first (optional)**
1. At the top of the Xcode window, click the device name and pick an iPhone simulator, e.g. **iPhone 16**.
2. Click the **▶** button (or press Cmd-R). A phone appears on screen.
3. Drag a chat screenshot from Finder onto the simulated phone; it lands in its Photos. Then tap **Choose screenshots** in the app.

**6. Put it on your iPhone**
1. Plug the iPhone into the Mac. On the iPhone, tap **Trust** and enter your passcode.
2. On the iPhone: **Settings > Privacy & Security > Developer Mode**, turn it on, and let it restart. (Only appears after step 1.)
3. In Xcode, click the device name at the top and choose your iPhone. Click **▶**.
4. The first time, the iPhone says the developer isn't trusted. On the iPhone: **Settings > General > VPN & Device Management**, tap your Apple ID, tap **Trust**. Click **▶** in Xcode again.

**7. Turn on the keyboard** (once)
1. Open the app and tap **Open Settings**, then **Keyboards**.
2. Turn on **Coax**, then **Allow Full Access**, and tap **Allow** on the warning.
3. In any chat, tap the message box, hold the 🌐 key, and pick **Coax**.

**8. Add it to the share sheet** (optional, once)
1. Take a screenshot of a chat, tap the little preview, then tap the **Share** button.
2. Scroll the row of app icons to the end, tap **More**, then **Edit**, and turn on **Coax**.

With a free Apple ID the app stops opening after 7 days. Plug in and click **▶** again to refresh it. This goes away with TestFlight.

## For Claude: regenerating the Xcode project

The project file is generated. After adding or removing a Swift file:

```
gem install xcodeproj
ruby ios/generate_project.rb
```

GitHub Actions (`.github/workflows/ios-build.yml`) builds the app and runs the tests on every push that touches `ios/`.

## For Claude: the paywall (subscription)

- Rules live in `Shared/Access.swift`: mode A (launch default) = 3 free days from the first real
  chat, then subscribe; mode B = 5 free new chats a day. `AccessPolicy.abTestOn` turns the A/B split on.
- Buying and restoring: `ReplyAssistant/Purchases.swift` (StoreKit 2). Products
  `com.vchev.coax.weekly` ($4.99/week) and `com.vchev.coax.yearly` ($99/year), each with a 7-day
  free trial as the introductory offer.
- Running from Xcode uses `ios/Coax.storekit` (set in the shared scheme), so the paywall works
  without App Store Connect. For TestFlight and the App Store, create the same two products in
  App Store Connect (one subscription group, "Coax").
- Until the App Group exists (paid developer account), the app, keyboard and Messages app keep
  separate free-tier counters; the subscription itself is read from Apple in each.
