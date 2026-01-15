import UIKit
import Flutter
import workmanager // 追加
import GoogleMaps 

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        GMSServices.provideAPIKey("AIzaSyDHksjA7SYjKKoNe9iu7Y6hmCtxCFqu1GY")

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
