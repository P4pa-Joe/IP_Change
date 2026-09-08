import AppKit

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate

// Menu bar only: no Dock icon, no app switcher entry, no main window.
app.setActivationPolicy(.accessory)

app.run()
