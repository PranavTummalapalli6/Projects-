//
//  PokerAppearance.swift
//  PokerChipApp
//
//  UIKit-level styling SwiftUI can't reach on iOS 16: the navigation bar's
//  title fonts and its translucent-on-scroll background.
//

import UIKit

enum PokerAppearance {
    static func apply() {
        let titleColor = UIColor.white.withAlphaComponent(0.95)

        func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }

        // At the top of a screen the bar is invisible, so the content's own
        // gradient shows through; once content scrolls under it, a dark blur.
        let atEdge = UINavigationBarAppearance()
        atEdge.configureWithTransparentBackground()

        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithTransparentBackground()
        scrolled.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        scrolled.shadowColor = UIColor.white.withAlphaComponent(0.08)

        for appearance in [atEdge, scrolled] {
            appearance.titleTextAttributes = [.foregroundColor: titleColor, .font: rounded(17, .semibold)]
            appearance.largeTitleTextAttributes = [.foregroundColor: titleColor, .font: rounded(34, .heavy)]
        }

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = scrolled
        bar.compactAppearance = scrolled
        bar.scrollEdgeAppearance = atEdge

        // The tab bar: the app's near-black with a hairline, gold for where you are.
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = UIColor(red: 0.02, green: 0.015, blue: 0.035, alpha: 1)
        tabs.shadowColor = UIColor.white.withAlphaComponent(0.10)
        let resting = UIColor.white.withAlphaComponent(0.66)
        let current = UIColor(red: 0.96, green: 0.84, blue: 0.56, alpha: 1)
        for layout in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            layout.normal.iconColor = resting
            layout.normal.titleTextAttributes = [.foregroundColor: resting]
            layout.selected.iconColor = current
            layout.selected.titleTextAttributes = [.foregroundColor: current]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
    }
}
