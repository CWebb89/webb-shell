pragma Singleton
import QtQuick
import "../state"

// Weather — Open-Meteo forecast plus IP geolocation. Owns current conditions,
// a 7-day daily series and an hourly series for GlancePopup to render.
// Deliberately fetches only while Glance is open: nothing here polls in the
// background, and every failure path leaves the previously loaded data in
// place rather than blanking the popup.
QtObject {
    id: root

    property real temp: 0
    property real high: 0
    property real low: 0
    property string condition: "Loading..."
    property bool loaded: false
    property bool failed: false
    property bool refreshing: false
    property bool isDay: true
    property int humidity: 0
    property real windSpeed: 0
    property int precipProbability: 0
    property string sunriseText: "--:--"
    property string sunsetText: "--:--"
    property string location: ""
    property double updatedAt: 0

    property var coords: null
    property var hourly: []
    property var daily: []
    property int hourlySpan: 12
    property int staleAfterMs: 10 * 60 * 1000

    function pad2(n) {
        return n < 10 ? "0" + n : "" + n
    }

    function dateKey(d) {
        return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
    }

    function clockOf(iso) {
        return (iso && iso.length >= 16) ? iso.substring(11, 16) : "--:--"
    }

    function hour12(h) {
        const suffix = h < 12 ? "AM" : "PM"
        return (h % 12 === 0 ? 12 : h % 12) + " " + suffix
    }

    function clock12(hhmm) {
        if (!hhmm || hhmm.length < 5)
            return "--:--"
        const h = parseInt(hhmm.substring(0, 2), 10)
        const suffix = h < 12 ? "AM" : "PM"
        return (h % 12 === 0 ? 12 : h % 12) + ":" + hhmm.substring(3, 5) + " " + suffix
    }

    function conditionFromCode(code) {
        if (code === 0) return "Clear"
        if (code <= 3) return "Cloudy"
        if (code <= 48) return "Fog"
        if (code <= 57) return "Drizzle"
        if (code <= 67) return "Rain"
        if (code <= 77) return "Snow"
        if (code <= 82) return "Showers"
        if (code <= 86) return "Snow Showers"
        return "Storms"
    }

    function iconForCondition(cond, daylit) {
        if (cond === "Clear") return daylit ? "\uf185" : "\uf186"
        if (cond === "Cloudy") return "\uf0c2"
        if (cond === "Fog") return "\uf0c9"
        if (cond === "Drizzle") return "\uf0ed"
        if (cond === "Rain") return "\uf0ed"
        if (cond === "Showers") return "\uf2cc"
        if (cond === "Snow") return "\uf2dc"
        if (cond === "Snow Showers") return "\uf2dc"
        if (cond === "Storms") return "\uf0e7"
        return "\uf0c2"
    }

    function hourlyFor(dateStr, fromHour) {
        const out = []
        for (let i = 0; i < hourly.length; i++) {
            const entry = hourly[i]
            if (entry.date !== dateStr)
                continue
            if (fromHour >= 0 && entry.hour < fromHour)
                continue
            out.push(entry)
            if (out.length >= hourlySpan)
                break
        }
        return out
    }

    function dailyFor(dateStr) {
        for (let i = 0; i < daily.length; i++) {
            if (daily[i].date === dateStr)
                return daily[i]
        }
        return null
    }

    function applyPayload(payload) {
        const now = payload.current
        temp = Math.round(now.temperature_2m)
        condition = conditionFromCode(now.weather_code)
        isDay = now.is_day === 1
        humidity = Math.round(now.relative_humidity_2m)
        windSpeed = Math.round(now.wind_speed_10m)

        const day = payload.daily
        high = Math.round(day.temperature_2m_max[0])
        low = Math.round(day.temperature_2m_min[0])
        precipProbability = day.precipitation_probability_max
            ? day.precipitation_probability_max[0] : 0
        sunriseText = clock12(clockOf(day.sunrise ? day.sunrise[0] : ""))
        sunsetText = clock12(clockOf(day.sunset ? day.sunset[0] : ""))

        const hours = payload.hourly
        const parsedHours = []
        for (let i = 0; i < hours.time.length; i++) {
            const stamp = hours.time[i]
            parsedHours.push({
                stamp: stamp,
                date: stamp.substring(0, 10),
                hour: parseInt(stamp.substring(11, 13), 10),
                temp: Math.round(hours.temperature_2m[i]),
                precip: hours.precipitation_probability
                    ? hours.precipitation_probability[i] : 0,
                daylit: hours.is_day ? hours.is_day[i] === 1 : true,
                cond: conditionFromCode(hours.weather_code[i])
            })
        }
        hourly = parsedHours

        const parsedDays = []
        for (let i = 0; i < day.time.length; i++) {
            parsedDays.push({
                date: day.time[i],
                cond: conditionFromCode(day.weather_code[i]),
                max: Math.round(day.temperature_2m_max[i]),
                min: Math.round(day.temperature_2m_min[i]),
                precip: day.precipitation_probability_max
                    ? day.precipitation_probability_max[i] : 0,
                sunrise: clock12(clockOf(day.sunrise ? day.sunrise[i] : "")),
                sunset: clock12(clockOf(day.sunset ? day.sunset[i] : ""))
            })
        }
        daily = parsedDays

        loaded = true
        failed = false
        refreshing = false
        updatedAt = Date.now()
    }

    function fail(stage, detail) {
        console.log("Weather " + stage + " failed:", detail)
        refreshing = false
        failed = true
        if (!loaded)
            condition = "Unavailable"
        retryTimer.restart()
    }

    function fetchWeather(lat, lon) {
        refreshing = true
        const xhr = new XMLHttpRequest()
        const url = "https://api.open-meteo.com/v1/forecast?latitude=" + lat +
                    "&longitude=" + lon +
                    "&current=temperature_2m,weather_code,is_day,wind_speed_10m," +
                    "relative_humidity_2m" +
                    "&hourly=temperature_2m,weather_code,precipitation_probability,is_day" +
                    "&daily=weather_code,temperature_2m_max,temperature_2m_min," +
                    "precipitation_probability_max,sunrise,sunset" +
                    "&timezone=auto&forecast_days=7"

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status !== 200) {
                fail("request", "status " + xhr.status)
                return
            }
            try {
                applyPayload(JSON.parse(xhr.responseText))
            } catch (e) {
                fail("parse", e.message)
            }
        }

        xhr.onerror = function() {
            fail("network", "request error")
        }

        xhr.open("GET", url)
        xhr.send()
    }

    function fetchLocation() {
        refreshing = true
        const xhr = new XMLHttpRequest()

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status !== 200) {
                fail("location", "status " + xhr.status)
                return
            }
            try {
                const data = JSON.parse(xhr.responseText)
                location = data.city || data.region || data.country || ""
                coords = { lat: data.latitude, lon: data.longitude }
                fetchWeather(data.latitude, data.longitude)
            } catch (e) {
                fail("location parse", e.message)
            }
        }

        xhr.onerror = function() {
            fail("location network", "request error")
        }

        xhr.open("GET", "https://ipwho.is/")
        xhr.send()
    }

    function refresh() {
        if (coords)
            fetchWeather(coords.lat, coords.lon)
        else
            fetchLocation()
    }

    function ensureLoaded() {
        if (!loaded || Date.now() - updatedAt > staleAfterMs)
            refresh()
    }

    property Timer retryTimer: Timer {
        interval: 2 * 60 * 1000
        running: false
        repeat: false
        onTriggered: {
            if (Popups.glanceOpen)
                refresh()
        }
    }

    property Timer refreshTimer: Timer {
        interval: 30 * 60 * 1000
        repeat: true
        running: Popups.glanceOpen
        onTriggered: refresh()
    }
}
