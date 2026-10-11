import Foundation

/// Provider-neutral weather snapshot (WeatherKit in production, Open-Meteo fallback in development).
public struct WeatherConditions: Codable, Hashable, Sendable {
    public var observedAt: Date
    public var temperatureF: Double
    public var apparentTemperatureF: Double?
    public var windMph: Double
    public var gustMph: Double?
    public var precipitationChance: Double      // 0...1, next hour
    public var precipitationLast3hMm: Double    // observed/estimated recent rain
    public var isDaylight: Bool
    public var sunset: Date?
    public var summary: String?
    public var hourly: [HourlyWeather]

    public init(observedAt: Date = Date(), temperatureF: Double, apparentTemperatureF: Double? = nil,
                windMph: Double, gustMph: Double? = nil, precipitationChance: Double = 0,
                precipitationLast3hMm: Double = 0, isDaylight: Bool = true, sunset: Date? = nil,
                summary: String? = nil, hourly: [HourlyWeather] = []) {
        self.observedAt = observedAt; self.temperatureF = temperatureF
        self.apparentTemperatureF = apparentTemperatureF; self.windMph = windMph; self.gustMph = gustMph
        self.precipitationChance = precipitationChance; self.precipitationLast3hMm = precipitationLast3hMm
        self.isDaylight = isDaylight; self.sunset = sunset; self.summary = summary; self.hourly = hourly
    }
}

public struct HourlyWeather: Codable, Hashable, Sendable {
    public var date: Date
    public var temperatureF: Double
    public var windMph: Double
    public var gustMph: Double?
    public var precipitationChance: Double
    public var isDaylight: Bool

    public init(date: Date, temperatureF: Double, windMph: Double, gustMph: Double? = nil,
                precipitationChance: Double = 0, isDaylight: Bool = true) {
        self.date = date; self.temperatureF = temperatureF; self.windMph = windMph; self.gustMph = gustMph
        self.precipitationChance = precipitationChance; self.isDaylight = isDaylight
    }
}
