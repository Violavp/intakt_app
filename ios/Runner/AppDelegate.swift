import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
  private var recordingBackgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var photoPickerResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "intakt_app/recording_background",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "startRecordingBackgroundTask":
          self?.startRecordingBackgroundTask()
          result(nil)
        case "stopRecordingBackgroundTask":
          self?.stopRecordingBackgroundTask()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    if let controller = window?.rootViewController as? FlutterViewController {
      let photoChannel = FlutterMethodChannel(
        name: "intakt_app/horse_photo",
        binaryMessenger: controller.binaryMessenger
      )
      photoChannel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "pickHorsePhoto":
          self?.presentHorsePhotoPicker(result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func startRecordingBackgroundTask() {
    if recordingBackgroundTask != .invalid {
      return
    }
    recordingBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "recording") {
      self.stopRecordingBackgroundTask()
    }
  }

  private func stopRecordingBackgroundTask() {
    guard recordingBackgroundTask != .invalid else {
      return
    }
    UIApplication.shared.endBackgroundTask(recordingBackgroundTask)
    recordingBackgroundTask = .invalid
  }

  private func presentHorsePhotoPicker(result: @escaping FlutterResult) {
    guard photoPickerResult == nil else {
      result(FlutterError(code: "picker_busy", message: "Fotoauswahl läuft bereits.", details: nil))
      return
    }
    guard let controller = window?.rootViewController else {
      result(FlutterError(code: "no_controller", message: "Kein Root-Controller verfügbar.", details: nil))
      return
    }
    guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
      result(FlutterError(code: "unavailable", message: "Fotomediathek nicht verfügbar.", details: nil))
      return
    }

    photoPickerResult = result
    let picker = UIImagePickerController()
    picker.sourceType = .photoLibrary
    picker.delegate = self
    picker.modalPresentationStyle = .fullScreen
    controller.present(picker, animated: true)
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
    photoPickerResult?(nil)
    photoPickerResult = nil
  }

  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
  ) {
    let result = photoPickerResult
    photoPickerResult = nil
    picker.dismiss(animated: true)

    guard let image = info[.originalImage] as? UIImage,
          let data = image.jpegData(compressionQuality: 0.9) else {
      result?(FlutterError(code: "image_failed", message: "Bild konnte nicht gelesen werden.", details: nil))
      return
    }

    do {
      let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
      let horsesDir = documents.appendingPathComponent("horses", isDirectory: true)
      try FileManager.default.createDirectory(at: horsesDir, withIntermediateDirectories: true)
      let fileUrl = horsesDir.appendingPathComponent("horse_\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
      try data.write(to: fileUrl, options: .atomic)
      result?(fileUrl.path)
    } catch {
      result?(FlutterError(code: "save_failed", message: "Bild konnte nicht gespeichert werden.", details: error.localizedDescription))
    }
  }
}
