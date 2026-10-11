import CoreLocation
import Foundation
import PickleCore
import WeatherKit

protocol WeatherProvider: Sendable {
    func conditions(at point: GeoPoint) async throws -> WeatherConditions
}

/// Production provider. Requires the WeatherKit capability (paid Apple Developer Program).
struct WeatherKitProvider: WeatherProvider {
    func conditions(at point: GeoPoint) async throws -> WeatherConditions {
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let now = Date()
        let (current, hourly) = try await WeatherService.shared.weather(
            for: location,
            including: .current, .hourly(startDate: now.addingTimeInterval(-3 * 3600), endDate: now.addingTimeInterval(14 * 3600)))
        let mph = { (m: Measurement<UnitSpeed>) in m.converted(to: .milesPerHour).value }
        let past = hourly.forecast.filter { $0.date <= now }
        let recentRainMm = past.reduce(0) { $0 + $1.precipitationAmount.converted(to: .millimeters).value }
        let next = hourly.forecast.first { $0.date > now.addingTimeInterval(-1800) }
        return WeatherConditions(
            observedAt: current.date,
            temperatureF: current.temperature.converted(to: .fahrenheit).value,
            apparentTemperatureF: current.apparentTemperature.converted(to: .fahrenheit).value,
            windMph: mph(current.wind.speed),
            gustMph: current.wind.gust.map(mph),
            precipitationChance: next?.precipitationChance ?? 0,
            precipitationLast3hMm: recentRainMm,
            isDaylight: current.isDaylight,
            summary: current.condition.description,
            hourly: hourly.forecast.filter { $0.date >= now.addingTimeInterval(-1800) }.map {
                HourlyWeather(date: $0.date, temperatureF: $0.temperature.converted(to: .fahrenheit).value,
                              windMph: mph($0.wind.speed), gustMph: $0.wind.gust.map(mph),
                              precipitationChance: $0.precipitationChance, isDaylight: $0.isDaylight)
            })
    }
}

/// Development fallback while WeatherKit isn't available on a free developer account.
/// Free, keyless, includes sustained wind and gusts. See docs/ARCHITECTURE.md [D4].
struct OpenMeteoProvider: WeatherProvider {
    var session: URLSession = .shared

    private struct Response: Decodable {
        struct Current: Decodable {
            let time: TimeInterval
            let temperature2m: Double
            let apparentTemperature: Double?
            let windSpeed10m: Double
            let windGusts10m: Double?
            let isDay: Int
        }
        struct Hourly: Decodable {
            let time: [TimeInterval]
            let temperature2m: [Double?]
            let precipitationProbability: [Double?]
            let precipitation: [Double?]
            let windSpeed10m: [Double?]
            let windGusts10m: [Double?]
            let isDay: [Int?]
        }
        let current: Current
        let hourly: Hourly
    }

    func conditions(at point: GeoPoint) async throws -> WeatherConditions {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.3f", point.latitude)),
            .init(name: "longitude", value: String(format: "%.3f", point.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,wind_speed_10m,wind_gusts_10m,is_day"),
            .init(name: "hourly", value: "temperature_2m,precipitation_probability,precipitation,wind_speed_10m,wind_gusts_10m,is_day"),
            .init(name: "temperature_unit", value: "fahrenheit"),
            .init(name: "wind_speed_unit", value: "mph"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "past_hours", value: "3"),
            .init(name: "forecast_hours", value: "15"),
        ]
        let (data, response) = try await session.data(from: c.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.network("weather unavailable") }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let r = try decoder.decode(Response.self, from: data)
        let now = Date()
        var hourly: [HourlyWeather] = []
        var recentRain = 0.0
        var nextChance = 0.0
        for (i, t) in r.hourly.time.enumerated() {
            let date = Date(timeIntervalSince1970: t)
            if date <= now, date > now.addingTimeInterval(-3 * 3600) { recentRain += r.hourly.precipitation[safe: i].flatMap { $0 } ?? 0 }
            guard date >= now.addingTimeInterval(-1800) else { continue }
            let chance = (r.hourly.precipitationProbability[safe: i].flatMap { $0 } ?? 0) / 100
            if hourly.isEmpty { nextChance = chance }
            hourly.append(HourlyWeather(date: date, temperatureF: r.hourly.temperature2m[safe: i].flatMap { $0 } ?? r.current.temperature2m,
                                        windMph: r.hourly.windSpeed10m[safe: i].flatMap { $0 } ?? 0,
                                        gustMph: r.hourly.windGusts10m[safe: i].flatMap { $0 },
                                        precipitationChance: chance,
                                        isDaylight: (r.hourly.isDay[safe: i].flatMap { $0 } ?? 1) == 1))
        }
        return WeatherConditions(observedAt: Date(timeIntervalSince1970: r.current.time), temperatureF: r.current.temperature2m,
                                 apparentTemperatureF: r.current.apparentTemperature, windMph: r.current.windSpeed10m,
                                 gustMph: r.current.windGusts10m, precipitationChance: nextChance,
                                 precipitationLast3hMm: recentRain, isDaylight: r.current.isDay == 1, hourly: hourly)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// Weather for outdoor facilities, cached per ~5 km cell for 15 minutes so map panning never refetches.
actor ConditionsService {
    private let primary: WeatherProvider?
    private let fallback: WeatherProvider?
    private var cache: [String: (WeatherConditions, Date)] = [:]
    private var inFlight: [String: Task<WeatherConditions?, Never>] = [:]
    private var primaryFailed = false
    private let ttl: TimeInterval = 900

    init(primary: WeatherProvider?, fallback: WeatherProvider?) {
        self.primary = primary
        self.fallback = fallback
    }

    static func cellKey(_ p: GeoPoint) -> String { GeoMath.geohash(p, precision: 5) }

    func cached(at p: GeoPoint) -> WeatherConditions? {
        guard let (w, at) = cache[Self.cellKey(p)], Date().timeIntervalSince(at) < ttl else { return nil }
        return w
    }

    func conditions(at p: GeoPoint) async -> WeatherConditions? {
        let key = Self.cellKey(p)
        if let (w, at) = cache[key], Date().timeIntervalSince(at) < ttl { return w }
        if let task = inFlight[key] { return await task.value }
        let task = Task { () -> WeatherConditions? in
            if let primary, !primaryFailed {
                do { return try await primary.conditions(at: p) } catch { primaryFailed = true }
            }
            return try? await fallback?.conditions(at: p)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { cache[key] = (result, Date()) }
        return result
    }
}
