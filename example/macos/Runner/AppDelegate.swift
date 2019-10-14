import Cocoa
import FlutterMacOS

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate  {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
}
