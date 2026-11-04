import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var chromeChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    title = "Корректа"
    titlebarAppearsTransparent = true
    if #available(macOS 11.0, *) { titlebarSeparatorStyle = .none }
    chromeChannel = FlutterMethodChannel(name: "korrekta/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    chromeChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "colors" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let colors = call.arguments as? [Int], colors.count == 2 else {
        result(FlutterError(code: "arguments", message: "Нужны два цвета", details: nil))
        return
      }
      let rgb = colors[0]
      self?.backgroundColor = NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
        green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
      self?.appearance = NSAppearance(named: rgb == 0x282828 ? .darkAqua : .aqua)
      result(nil)
    }

    super.awakeFromNib()
  }
}
