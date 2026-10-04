//
//  SceneDelegate.swift
//  Ashvale
//
//  Creates the full-screen landscape window hosting the game and forwards
//  lifecycle events (pause + save when the app leaves the foreground).
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var game: GameViewController? { window?.rootViewController as? GameViewController }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: windowScene)
        w.rootViewController = GameViewController()
        w.makeKeyAndVisible()
        window = w
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func sceneWillResignActive(_ scene: UIScene) {
        game?.appWillResignActive()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        game?.appWillResignActive()
        SaveSystem.flush()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        UIApplication.shared.isIdleTimerDisabled = true
    }
}
