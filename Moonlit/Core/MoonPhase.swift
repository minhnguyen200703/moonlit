import Foundation

struct MoonPhase {
    let name: String
    let symbol: String
    let illumination: Int

    static func current(on date: Date = .now) -> MoonPhase {
        let referenceNewMoon = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2000, month: 1, day: 6, hour: 18, minute: 14
        ).date ?? .distantPast
        let lunarCycle = 29.53058867
        let days = date.timeIntervalSince(referenceNewMoon) / 86_400
        let age = ((days.truncatingRemainder(dividingBy: lunarCycle)) + lunarCycle)
            .truncatingRemainder(dividingBy: lunarCycle)
        let fraction = age / lunarCycle
        let illumination = Int(((1 - cos(2 * .pi * fraction)) / 2 * 100).rounded())

        switch fraction {
        case 0..<0.03, 0.97...1: return MoonPhase(name: "New moon", symbol: "moonphase.new.moon", illumination: illumination)
        case 0.03..<0.22: return MoonPhase(name: "Waxing crescent", symbol: "moonphase.waxing.crescent", illumination: illumination)
        case 0.22..<0.28: return MoonPhase(name: "First quarter", symbol: "moonphase.first.quarter", illumination: illumination)
        case 0.28..<0.47: return MoonPhase(name: "Waxing gibbous", symbol: "moonphase.waxing.gibbous", illumination: illumination)
        case 0.47..<0.53: return MoonPhase(name: "Full moon", symbol: "moonphase.full.moon", illumination: illumination)
        case 0.53..<0.72: return MoonPhase(name: "Waning gibbous", symbol: "moonphase.waning.gibbous", illumination: illumination)
        case 0.72..<0.78: return MoonPhase(name: "Last quarter", symbol: "moonphase.last.quarter", illumination: illumination)
        default: return MoonPhase(name: "Waning crescent", symbol: "moonphase.waning.crescent", illumination: illumination)
        }
    }
}
