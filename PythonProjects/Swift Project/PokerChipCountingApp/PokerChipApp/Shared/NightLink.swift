//
//  NightLink.swift
//  PokerChipApp
//
//  Compiled into the app and its widgets. The links the Lock Screen and the
//  widgets open: the night in progress, or the night in progress with its clock
//  put on a break (or taken off one). Taking a break only stops the clock, and the
//  night shows a button to start it again.
//

import Foundation

enum NightLink: Equatable {
    case openNight
    case takeBreak
    case resumePlay

    static let scheme = "chipcounter"

    var url: URL {
        let path: String
        switch self {
        case .openNight: path = ""
        case .takeBreak: path = "/break"
        case .resumePlay: path = "/resume"
        }
        return URL(string: "\(Self.scheme)://night\(path)") ?? URL(fileURLWithPath: "/")
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, url.host?.lowercased() == "night" else { return nil }
        switch url.path {
        case "", "/": self = .openNight
        case "/break": self = .takeBreak
        case "/resume": self = .resumePlay
        default: return nil
        }
    }
}
