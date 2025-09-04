import SwiftUI
import HealthKit
import CoreLocation
import WeatherKit
import UniformTypeIdentifiers
import Charts

// MARK: - Models
enum Symptom: String, CaseIterable, Codable {
    case shortnessOfBreath = "Shortness of Breath"
    case chestTightness = "Chest Tightness"
    case lightHeaded = "Light Headed"
    case dizzy = "Dizzy"
    case headache = "Headache"
    case chestPain = "Chest Pain"
    case other = "Other"
    
    var emoji: String {
        switch self {
        case .shortnessOfBreath: return "🫁"
        case .chestTightness: return "🫸"
        case .lightHeaded: return "😵‍💫"
        case .dizzy: return "🌀"
        case .headache: return "🤕"
        case .chestPain: return "💔"
        case .other: return "❓"
        }
    }
}

struct OpenMeteoResponse: Codable {
    let current: CurrentWeather
}

struct CurrentWeather: Codable {
    let temperature_2m: Double
    let weather_code: Int
}

struct BPEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let systolic: Double?
    let diastolic: Double?
    let pulse: Double?
    let spo2: Double?  // Blood oxygen saturation
    let bodyTemperature: Double?  // Body temperature from HealthKit
    let respiratoryRate: Double?  // Breaths per minute
    let hrvSDNN: Double?  // Heart Rate Variability (SDNN)
    let restingHeartRate: Double?  // Resting heart rate
    let walkingHeartRate: Double?  // Walking heart rate average
    let temperatureC: Double?  // Weather temperature
    let conditions: String?
    let aqi: Double?
    let pm25: Double?  // PM2.5 particulate matter
    let pm10: Double?  // PM10 particulate matter
    let note: String
    let latitude: Double?
    let longitude: Double?
    let symptoms: [Symptom]
}

// MARK: - ViewModel
@MainActor
final class BPLoggerViewModel: NSObject, ObservableObject {
    let healthStore = HKHealthStore()
    private let weatherService = WeatherService.shared
    private let locationManager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    // PurpleAir API configuration
    private let purpleAirAPIKey: String = "AAA3D79E-81BC-11EE-A8AF-42010A80000A"

    @Published var systolic: Double?
    @Published var diastolic: Double?
    @Published var pulse: Double?
    @Published var spo2: Double?
    @Published var bodyTemperature: Double?
    @Published var respiratoryRate: Double?
    @Published var hrvSDNN: Double?
    @Published var restingHeartRate: Double?
    @Published var walkingHeartRate: Double?
    @Published var temperatureC: Double?
    @Published var conditions: String?
    @Published var aqi: Double?
    @Published var pm25: Double?
    @Published var pm10: Double?
    @Published var note: String = ""
    @Published var selectedSymptoms: Set<Symptom> = []
    @Published var otherSymptomText: String = ""

    @Published var entries: [BPEntry] = []
    @Published var errorMessage: String?
    @Published var showingExportSheet = false
    @Published var showingChartsView = false
    @Published var showingSettingsSheet = false
    @Published var showingSensorSelectionSheet = false
    @Published var availableSensors: [PurpleAirSensor] = []
    @Published var selectedSensorID: Int?
    
    // User preferences
    @Published var useFahrenheit = true  // Default to Fahrenheit
    @Published var showBloodPressure = true
    @Published var showHeartRate = true
    @Published var showSpO2 = true
    @Published var showBodyTemperature = true
    @Published var showRespiratoryRate = true
    @Published var showHRV = true
    @Published var showRestingHeartRate = false  // Less common, default off
    @Published var showWalkingHeartRate = false  // Less common, default off
    @Published var showWeatherTemp = true
    @Published var showAirQuality = true

    private let saveURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("bp_entries.json")
    }()

    override init() {
        super.init()
        locationManager.delegate = self
        loadEntries()
        loadPreferences()
    }
    
    // MARK: - User Preferences
    private func loadPreferences() {
        useFahrenheit = UserDefaults.standard.object(forKey: "useFahrenheit") as? Bool ?? true
        showBloodPressure = UserDefaults.standard.object(forKey: "showBloodPressure") as? Bool ?? true
        showHeartRate = UserDefaults.standard.object(forKey: "showHeartRate") as? Bool ?? true
        showSpO2 = UserDefaults.standard.object(forKey: "showSpO2") as? Bool ?? true
        showBodyTemperature = UserDefaults.standard.object(forKey: "showBodyTemperature") as? Bool ?? true
        showRespiratoryRate = UserDefaults.standard.object(forKey: "showRespiratoryRate") as? Bool ?? true
        showHRV = UserDefaults.standard.object(forKey: "showHRV") as? Bool ?? true
        showRestingHeartRate = UserDefaults.standard.object(forKey: "showRestingHeartRate") as? Bool ?? false
        showWalkingHeartRate = UserDefaults.standard.object(forKey: "showWalkingHeartRate") as? Bool ?? false
        selectedSensorID = UserDefaults.standard.object(forKey: "selectedSensorID") as? Int
        showWeatherTemp = UserDefaults.standard.object(forKey: "showWeatherTemp") as? Bool ?? true
        showAirQuality = UserDefaults.standard.object(forKey: "showAirQuality") as? Bool ?? true
    }
    
    func savePreferences() {
        UserDefaults.standard.set(useFahrenheit, forKey: "useFahrenheit")
        UserDefaults.standard.set(showBloodPressure, forKey: "showBloodPressure")
        UserDefaults.standard.set(showHeartRate, forKey: "showHeartRate")
        UserDefaults.standard.set(showSpO2, forKey: "showSpO2")
        UserDefaults.standard.set(showBodyTemperature, forKey: "showBodyTemperature")
        UserDefaults.standard.set(showRespiratoryRate, forKey: "showRespiratoryRate")
        UserDefaults.standard.set(showHRV, forKey: "showHRV")
        UserDefaults.standard.set(showRestingHeartRate, forKey: "showRestingHeartRate")
        UserDefaults.standard.set(showWalkingHeartRate, forKey: "showWalkingHeartRate")
        UserDefaults.standard.set(selectedSensorID, forKey: "selectedSensorID")
        UserDefaults.standard.set(showWeatherTemp, forKey: "showWeatherTemp")
        UserDefaults.standard.set(showAirQuality, forKey: "showAirQuality")
    }
    
    // MARK: - Temperature Conversion
    func celsiusToFahrenheit(_ celsius: Double) -> Double {
        return celsius * 9.0 / 5.0 + 32.0
    }
    
    private func fahrenheitToCelsius(_ fahrenheit: Double) -> Double {
        return (fahrenheit - 32.0) * 5.0 / 9.0
    }
    
    func displayTemperature(_ celsius: Double?) -> String {
        guard let temp = celsius else { return "—" }
        if useFahrenheit {
            let fahrenheit = celsiusToFahrenheit(temp)
            return String(format: "%.1f°F", fahrenheit)
        } else {
            return String(format: "%.1f°C", temp)
        }
    }

    func requestPermissionsAndRefresh() {
        Task { await authorizeHealthIfNeeded() }
        requestLocation()
        
        // For simulator testing, set default location after a delay if no real location is obtained
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.currentLocation == nil {
                print("No location obtained, using default for testing...")
                self.currentLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
                Task { await self.fetchWeatherAndAQI() }
            }
        }
    }

    func refreshLatest() {
        Task { await fetchLatestHealthMetrics() }
        Task { await fetchWeatherAndAQI() }
    }
    
    func refreshAllData() {
        // Refresh health metrics from Apple Health
        Task { await fetchLatestHealthMetrics() }
        
        // Refresh weather and air quality
        refreshWeatherAndAQI()
        
        print("Refreshing all health data, weather, and air quality...")
    }
    
    func refreshAllDataAsync() async {
        // Refresh health metrics from Apple Health
        await fetchLatestHealthMetrics()
        
        // Refresh weather and air quality
        await fetchWeatherAndAQI()
        
        print("Refreshing all health data, weather, and air quality...")
    }
    
    func refreshWeatherAndAQI() {
        self.errorMessage = "🔄 Starting refresh..."
        
        if currentLocation == nil {
            self.errorMessage = "📍 No location - requesting..."
            requestLocation()
            // For simulator testing, set a default location after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.currentLocation == nil {
                    print("Setting default location for simulator testing...")
                    // Default to San Francisco for testing
                    self.currentLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
                    Task { await self.fetchWeatherAndAQI() }
                }
            }
        } else {
            self.errorMessage = "📍 Location available - fetching data..."
            Task { await fetchWeatherAndAQI() }
        }
    }
    
    // Debug function to test PurpleAir API directly
    func testPurpleAirAPI() async {
        await MainActor.run {
            self.errorMessage = "🔍 Testing PurpleAir API..."
        }
        
        guard let location = currentLocation else {
            await MainActor.run {
                self.errorMessage = "❌ No location available. Please enable location services."
            }
            return
        }
        
        await MainActor.run {
            self.errorMessage = "📍 Testing from location: \(String(format: "%.4f", location.coordinate.latitude)), \(String(format: "%.4f", location.coordinate.longitude))"
        }
        
        // Test the API call with basic parameters
        let testURL = "https://api.purpleair.com/v1/sensors?fields=sensor_index,latitude,longitude,pm2.5&location_type=0&max_age=3600&nwlat=\(location.coordinate.latitude + 0.1)&nwlng=\(location.coordinate.longitude - 0.1)&selat=\(location.coordinate.latitude - 0.1)&selng=\(location.coordinate.longitude + 0.1)"
        
        guard let url = URL(string: testURL) else {
            await MainActor.run {
                self.errorMessage = "❌ Invalid URL format"
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(purpleAirAPIKey, forHTTPHeaderField: "X-API-Key")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                
                if statusCode == 200 {
                    // Try to parse response
                    if let responseString = String(data: data, encoding: .utf8) {
                        let preview = String(responseString.prefix(200))
                        await MainActor.run {
                            self.errorMessage = "✅ API Success! Status: \(statusCode)\nResponse preview: \(preview)..."
                        }
                    }
                } else {
                    // Show error status
                    if let responseString = String(data: data, encoding: .utf8) {
                        let preview = String(responseString.prefix(150))
                        await MainActor.run {
                            self.errorMessage = "❌ API Error \(statusCode): \(preview)"
                        }
                    } else {
                        await MainActor.run {
                            self.errorMessage = "❌ API returned error status: \(statusCode)"
                        }
                    }
                }
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "❌ Network error: \(error.localizedDescription)"
            }
        }
    }
    
    // Test location availability
    func testLocation() {
        if let location = currentLocation {
            self.errorMessage = "✅ Location available:\nLatitude: \(String(format: "%.6f", location.coordinate.latitude))\nLongitude: \(String(format: "%.6f", location.coordinate.longitude))\nAccuracy: \(String(format: "%.1f", location.horizontalAccuracy))m"
        } else {
            self.errorMessage = "❌ No location available.\n\nPlease check:\n1. Location services enabled in iOS Settings\n2. ENVHealth has location permission\n3. Try refreshing location data"
        }
    }

    func saveEntry() {
        let entry = BPEntry(
            id: UUID(),
            date: Date(),
            systolic: systolic,
            diastolic: diastolic,
            pulse: pulse,
            spo2: spo2,
            bodyTemperature: bodyTemperature,
            respiratoryRate: respiratoryRate,
            hrvSDNN: hrvSDNN,
            restingHeartRate: restingHeartRate,
            walkingHeartRate: walkingHeartRate,
            temperatureC: temperatureC,
            conditions: conditions,
            aqi: aqi,
            pm25: pm25,
            pm10: pm10,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: currentLocation?.coordinate.latitude,
            longitude: currentLocation?.coordinate.longitude,
            symptoms: Array(selectedSymptoms)
        )
        entries.insert(entry, at: 0)
        note = ""
        selectedSymptoms.removeAll()
        otherSymptomText = ""
        persistEntries()
    }

    // MARK: - PurpleAir AQI
    func fetchNearbySensors() async {
        guard let location = currentLocation else {
            print("No location available for sensor search")
            return
        }
        
        // 100km radius for search
        let fields = "sensor_index,name,location_type,latitude,longitude,altitude,last_seen,pm2.5,pm2.5_10minute,pm2.5_30minute,pm2.5_60minute,temperature,humidity"
        
        let urlString = "https://api.purpleair.com/v1/sensors?fields=\(fields)&location_type=0&max_age=3600&nwlng=\(location.coordinate.longitude - 0.9)&nwlat=\(location.coordinate.latitude + 0.9)&selng=\(location.coordinate.longitude + 0.9)&selat=\(location.coordinate.latitude - 0.9)"
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL for sensor search")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(purpleAirAPIKey, forHTTPHeaderField: "X-API-Key")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(PurpleAirSensorsResponse.self, from: data)
            
            var sensors: [PurpleAirSensor] = []
            
            for sensorData in response.data {
                if sensorData.count >= response.fields.count {
                    do {
                        // Create a dictionary from the fields and data
                        var sensorDict: [String: Any] = [:]
                        for (index, field) in response.fields.enumerated() {
                            if index < sensorData.count {
                                switch sensorData[index] {
                                case .int(let value):
                                    sensorDict[field] = value
                                case .double(let value):
                                    sensorDict[field] = value
                                case .string(let value):
                                    sensorDict[field] = value
                                case .null:
                                    sensorDict[field] = NSNull()
                                }
                            }
                        }
                        
                        // Convert to JSON data and decode as PurpleAirSensor
                        let jsonData = try JSONSerialization.data(withJSONObject: sensorDict)
                        var sensor = try JSONDecoder().decode(PurpleAirSensor.self, from: jsonData)
                        
                        // Calculate distance
                        let sensorLocation = CLLocation(latitude: sensor.latitude, longitude: sensor.longitude)
                        sensor.distance = location.distance(from: sensorLocation) / 1000 // Convert to km
                        
                        // Only include outdoor sensors with recent data
                        if sensor.isOutdoor && Date().timeIntervalSince(sensor.lastSeenDate) < 3600 {
                            sensors.append(sensor)
                        }
                    } catch {
                        print("Error decoding sensor: \(error)")
                    }
                }
            }
            
            // Sort by distance
            sensors.sort { ($0.distance ?? Double.infinity) < ($1.distance ?? Double.infinity) }
            
            await MainActor.run {
                self.availableSensors = sensors
                print("Found \(sensors.count) nearby sensors")
            }
            
        } catch {
            print("Error fetching sensors: \(error.localizedDescription)")
        }
    }

private func fetchAQIFromPurpleAir() async throws -> AirQualityData? {
    guard let location = currentLocation else {
        print("AQI fetch failed: No location available")
        return nil
    }
    
    // Use selected sensor if available, otherwise find nearest
    let sensorID: Int
    if let selectedID = selectedSensorID {
        sensorID = selectedID
        print("Using user-selected sensor: \(selectedID)")
    } else {
        guard let nearestSensorID = try await findNearestPurpleAirSensor(location: location) else {
            print("AQI fetch failed: No nearby sensors found")
            return nil
        }
        sensorID = nearestSensorID
        print("Using nearest sensor: \(nearestSensorID)")
    }
    
    print("Using PurpleAir sensor ID: \(sensorID)")
    
    // Build request for the selected sensor
    guard let url = URL(string: "https://api.purpleair.com/v1/sensors/\(sensorID)?fields=pm2.5,pm2.5_10minute,pm10.0,pm10.0_10minute,stats") else {
        return nil
    }
    var req = URLRequest(url: url)
    req.addValue(purpleAirAPIKey, forHTTPHeaderField: "X-API-Key")

    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else { 
        print("AQI fetch failed: Invalid response")
        return nil 
    }
    
    print("PurpleAir sensor response status: \(http.statusCode)")
    
    guard (200...299).contains(http.statusCode) else { 
        if let responseString = String(data: data, encoding: .utf8) {
            print("PurpleAir API error response: \(responseString)")
        }
        return nil 
    }

    // Decode just enough of PurpleAir’s shape to get PM2.5
    struct PAResponse: Decodable {
        let sensor: PASensor?
        struct PASensor: Decodable {
            // Prefer 10-minute averaged values if present
            let pm2_5_10minute: Double?
            let pm2_5: Double?
            let pm10_0_10minute: Double?
            let pm10_0: Double?
            let stats: Stats?
            struct Stats: Decodable {
                let pm2_5_10minute: Double?
                let pm2_5: Double?
                let pm10_0_10minute: Double?
                let pm10_0: Double?
                
                private enum CodingKeys: String, CodingKey {
                    case pm2_5_10minute = "pm2.5_10minute"
                    case pm2_5 = "pm2.5"
                    case pm10_0_10minute = "pm10.0_10minute"
                    case pm10_0 = "pm10.0"
                }
            }

            // Map PurpleAir field names that contain dots / unusual keys:
            private enum CodingKeys: String, CodingKey {
                case pm2_5_10minute = "pm2.5_10minute"
                case pm2_5 = "pm2.5"
                case pm10_0_10minute = "pm10.0_10minute"
                case pm10_0 = "pm10.0"
                case stats
            }
        }
    }

    let resp2 = try JSONDecoder().decode(PAResponse.self, from: data)
    let sensor = resp2.sensor

    // Try to extract PM2.5 with preference order:
    let pm25: Double? = sensor?.pm2_5_10minute
        ?? sensor?.stats?.pm2_5_10minute
        ?? sensor?.pm2_5
        ?? sensor?.stats?.pm2_5

    // Try to extract PM10 with preference order:
    let pm10: Double? = sensor?.pm10_0_10minute
        ?? sensor?.stats?.pm10_0_10minute
        ?? sensor?.pm10_0
        ?? sensor?.stats?.pm10_0

    guard let pm25Value = pm25 else { 
        print("AQI fetch failed: No PM2.5 data in sensor response")
        return nil 
    }
    
    let aqi = pm25ToUSAQI(pm25Value)
    print("Calculated AQI: \(aqi) from PM2.5: \(pm25Value), PM10: \(pm10 ?? 0)")
    
    return AirQualityData(aqi: aqi, pm25: pm25Value, pm10: pm10)
}

// Find the nearest PurpleAir sensor to current location
private func findNearestPurpleAirSensor(location: CLLocation) async throws -> Int? {
    let lat = location.coordinate.latitude
    let lon = location.coordinate.longitude
    
    // Search within 100km radius
    let nwLat = lat + 0.9  // ~100km north
    let nwLon = lon - 0.9  // ~100km west  
    let seLat = lat - 0.9  // ~100km south
    let seLon = lon + 0.9  // ~100km east
    
    guard let url = URL(string: "https://api.purpleair.com/v1/sensors?fields=sensor_index,latitude,longitude,pm2.5&location_type=0&nwlat=\(nwLat)&nwlng=\(nwLon)&selat=\(seLat)&selng=\(seLon)&max_age=3600") else {
        return nil
    }
    
    var req = URLRequest(url: url)
    req.addValue(purpleAirAPIKey, forHTTPHeaderField: "X-API-Key")
    
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { 
        if let responseString = String(data: data, encoding: .utf8) {
            print("PurpleAir search API error: \(responseString)")
        }
        return nil 
    }
    
    struct SensorSearchResponse: Decodable {
        let data: [[Double?]]?  // Array of sensor data arrays
        let fields: [String]?   // Field names
    }
    
    let searchResponse = try JSONDecoder().decode(SensorSearchResponse.self, from: data)
    
    guard let sensorsData = searchResponse.data,
          let fields = searchResponse.fields,
          let indexIdx = fields.firstIndex(of: "sensor_index"),
          let latIdx = fields.firstIndex(of: "latitude"),
          let lonIdx = fields.firstIndex(of: "longitude") else {
        print("No sensors found or invalid response format")
        return nil
    }
    
    // Find the closest sensor
    var closestSensorID: Int?
    var closestDistance: Double = Double.infinity
    
    for sensorData in sensorsData {
        guard sensorData.count > max(indexIdx, latIdx, lonIdx),
              let sensorID = sensorData[indexIdx],
              let sensorLat = sensorData[latIdx],
              let sensorLon = sensorData[lonIdx] else {
            continue
        }
        
        let sensorLocation = CLLocation(latitude: sensorLat, longitude: sensorLon)
        let distance = location.distance(from: sensorLocation)
        
        if distance < closestDistance {
            closestDistance = distance
            closestSensorID = Int(sensorID)
        }
    }
    
    if let sensorID = closestSensorID {
        print("Found nearest sensor \(sensorID) at distance: \(closestDistance/1000) km")
    }
    
    return closestSensorID
}

private func pm25ToUSAQI(_ pm: Double) -> Double {
    // US EPA AQI breakpoints for PM2.5 (µg/m³)
    // [Clow, Chigh, Ilow, Ihigh]
    let table: [(Double, Double, Double, Double)] = [
        (0.0,   12.0,   0,   50),
        (12.1,  35.4,  51,  100),
        (35.5,  55.4, 101,  150),
        (55.5, 150.4, 151,  200),
        (150.5,250.4, 201,  300),
        (250.5,350.4, 301,  400),
        (350.5,500.4, 401,  500)
    ]

    for (Clow, Chigh, Ilow, Ihigh) in table {
        if pm >= Clow && pm <= Chigh {
            // AQI linear interpolation
            let aqi = (Ihigh - Ilow) / (Chigh - Clow) * (pm - Clow) + Ilow
            return aqi
        }
    }
    // Above table max — cap at 500
    return 500
}


    // MARK: HealthKit
    private func authorizeHealthIfNeeded() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let readTypes: Set = [
            HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!,
            HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .bodyTemperature)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .walkingHeartRateAverage)!
        ]
        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            await fetchLatestHealthMetrics()
        } catch {
            errorMessage = "Health authorization failed: \(error.localizedDescription)"
        }
    }

    func fetchLatestHealthMetrics() async {
        do {
            // Define all health metric types
            let sysType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic)!
            let diaType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic)!
            let pulseType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
            let spo2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!
            let bodyTempType = HKQuantityType.quantityType(forIdentifier: .bodyTemperature)!
            let respRateType = HKQuantityType.quantityType(forIdentifier: .respiratoryRate)!
            let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
            let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
            let walkingHRType = HKQuantityType.quantityType(forIdentifier: .walkingHeartRateAverage)!

            // Fetch all metrics concurrently
            async let sys = latestQuantitySample(for: sysType)
            async let dia = latestQuantitySample(for: diaType)
            async let hr = latestQuantitySample(for: pulseType)
            async let spo2Sample = latestQuantitySample(for: spo2Type)
            async let bodyTempSample = latestQuantitySample(for: bodyTempType)
            async let respRateSample = latestQuantitySample(for: respRateType)
            async let hrvSample = latestQuantitySample(for: hrvType)
            async let restingHRSample = latestQuantitySample(for: restingHRType)
            async let walkingHRSample = latestQuantitySample(for: walkingHRType)

            let (s, d, p, spo2, bodyTemp, respRate, hrv, restingHR, walkingHR) = try await (
                sys, dia, hr, spo2Sample, bodyTempSample, respRateSample, hrvSample, restingHRSample, walkingHRSample
            )
            
            // Update all metrics
            self.systolic = s?.quantity.doubleValue(for: .millimeterOfMercury())
            self.diastolic = d?.quantity.doubleValue(for: .millimeterOfMercury())
            self.pulse = p?.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
            // SpO2 from HealthKit comes as a fraction (0.0-1.0), convert to percentage (0-100)
            if let spo2Value = spo2?.quantity.doubleValue(for: .percent()) {
                self.spo2 = spo2Value * 100
            } else {
                self.spo2 = nil
            }
            self.bodyTemperature = bodyTemp?.quantity.doubleValue(for: .degreeCelsius())
            self.respiratoryRate = respRate?.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
            self.hrvSDNN = hrv?.quantity.doubleValue(for: .secondUnit(with: .milli))
            self.restingHeartRate = restingHR?.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
            self.walkingHeartRate = walkingHR?.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
            
        } catch {
            errorMessage = "Failed to fetch health metrics: \(error.localizedDescription)"
        }
    }

    private func latestQuantitySample(for type: HKQuantityType) async throws -> HKQuantitySample? {
        // Search for data within the last 30 days for more relevant recent values
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: Date(), options: [])
        
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error = error { 
                    print("Error fetching \(type.identifier): \(error.localizedDescription)")
                    cont.resume(throwing: error)
                    return 
                }
                let sample = samples?.first as? HKQuantitySample
                if let sample = sample {
                    print("Found latest \(type.identifier): \(sample.quantity) from \(sample.endDate)")
                } else {
                    print("No recent data found for \(type.identifier)")
                }
                cont.resume(returning: sample)
            }
            healthStore.execute(q)
        }
    }

    // MARK: WeatherKit
    private func requestLocation() {
        let status = locationManager.authorizationStatus
        print("Location authorization status: \(status.rawValue)")
        
        switch status {
        case .notDetermined:
            print("Requesting location permission...")
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.errorMessage = "Location access denied. Please enable in Settings > Privacy & Security > Location Services"
            }
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location authorized, starting location updates...")
            locationManager.startUpdatingLocation()
        @unknown default:
            print("Unknown location authorization status")
        }
    }


    private func fetchWeatherAndAQI() async {
        guard let loc = currentLocation else { 
            await MainActor.run {
                self.errorMessage = "Location not available. Please enable location services."
            }
            return 
        }
        
        // Try WeatherKit first, fall back to OpenWeatherMap if it fails
        var weatherSuccess = false
        
        // Try WeatherKit (Apple's service)
        do {
            let w = try await weatherService.weather(for: loc)
            await MainActor.run {
                self.temperatureC = w.currentWeather.temperature.converted(to: .celsius).value
                self.conditions = w.currentWeather.condition.description
                print("Weather updated via WeatherKit: \(self.temperatureC ?? 0)°C, \(self.conditions ?? "No conditions")")
            }
            weatherSuccess = true
        } catch {
            print("WeatherKit failed: \(error.localizedDescription)")
            // Don't show error to user yet, try fallback first
        }
        
        // If WeatherKit failed, try free alternative
        if !weatherSuccess {
            do {
                try await fetchWeatherFromOpenMeteo(location: loc)
                await MainActor.run {
                    print("Weather updated via OpenMeteo: \(self.temperatureC ?? 0)°C, \(self.conditions ?? "No conditions")")
                }
                weatherSuccess = true
            } catch {
                await MainActor.run {
                    self.errorMessage = "Weather services unavailable. Please try again later."
                    print("All weather services failed: \(error)")
                }
            }
        }

        // AQI from PurpleAir (PM2.5 -> US EPA AQI)
        do {
            if let airQualityData = try await fetchAQIFromPurpleAir() {
                await MainActor.run {
                    self.aqi = airQualityData.aqi
                    self.pm25 = airQualityData.pm25
                    self.pm10 = airQualityData.pm10
                    print("Air quality updated - AQI: \(airQualityData.aqi), PM2.5: \(airQualityData.pm25), PM10: \(airQualityData.pm10 ?? 0)")
                }
            } else {
                await MainActor.run {
                    print("No AQI data available from PurpleAir")
                }
                
                // Try fallback air quality API when no PurpleAir sensors found
                do {
                    if let fallbackAirQuality = try await fetchFallbackAirQuality(location: loc) {
                        await MainActor.run {
                            self.aqi = fallbackAirQuality.aqi
                            self.pm25 = fallbackAirQuality.pm25
                            self.pm10 = fallbackAirQuality.pm10
                            print("Air quality updated via fallback API - AQI: \(fallbackAirQuality.aqi), PM2.5: \(fallbackAirQuality.pm25)")
                        }
                    } else {
                        await MainActor.run {
                            self.errorMessage = "⚠️ No air quality sensors found nearby"
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = "⚠️ No air quality sensors found nearby"
                    }
                }
            }
        } catch {
            await MainActor.run {
                print("AQI fetch failed (non-critical): \(error.localizedDescription)")
            }
            
            // Try fallback air quality API
            do {
                if let fallbackAirQuality = try await fetchFallbackAirQuality(location: loc) {
                    await MainActor.run {
                        self.aqi = fallbackAirQuality.aqi
                        self.pm25 = fallbackAirQuality.pm25
                        self.pm10 = fallbackAirQuality.pm10
                        print("Air quality updated via fallback API - AQI: \(fallbackAirQuality.aqi), PM2.5: \(fallbackAirQuality.pm25)")
                    }
                } else {
                    await MainActor.run {
                        self.errorMessage = "❌ No air quality data available from any source"
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "❌ All air quality services failed: \(error.localizedDescription)"
                }
            }
        }
        
        // Show success message if we got some data
        await MainActor.run {
            if weatherSuccess || self.aqi != nil {
                var successParts: [String] = []
                if weatherSuccess {
                    successParts.append("Weather: \(self.displayTemperature(self.temperatureC))")
                }
                if let aqi = self.aqi, let pm25 = self.pm25 {
                    successParts.append("AQI: \(Int(aqi)), PM2.5: \(String(format: "%.1f", pm25))")
                }
                if !successParts.isEmpty {
                    self.errorMessage = "✅ Updated: \(successParts.joined(separator: ", "))"
                }
            }
        }
    }
    
    // MARK: - Fallback Air Quality Service
    private func fetchFallbackAirQuality(location: CLLocation) async throws -> AirQualityData? {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        
        // OpenWeatherMap Air Pollution API (free with registration, but we'll try without API key first)
        // Using WAQI.info API which is free for basic usage
        let urlString = "https://api.waqi.info/feed/geo:\(lat);\(lon)/?token=demo"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        // Parse WAQI response
        struct WAQIResponse: Decodable {
            let status: String
            let data: WAQIData?
            
            struct WAQIData: Decodable {
                let aqi: Int
                let iaqi: WAQIComponents?
                
                struct WAQIComponents: Decodable {
                    let pm25: WAQIValue?
                    let pm10: WAQIValue?
                    
                    private enum CodingKeys: String, CodingKey {
                        case pm25 = "pm25"
                        case pm10 = "pm10"
                    }
                    
                    struct WAQIValue: Decodable {
                        let v: Double
                    }
                }
            }
        }
        
        let waqi = try JSONDecoder().decode(WAQIResponse.self, from: data)
        
        guard waqi.status == "ok", let data = waqi.data else {
            return nil
        }
        
        let aqi = Double(data.aqi)
        let pm25 = data.iaqi?.pm25?.v
        let pm10 = data.iaqi?.pm10?.v
        
        return AirQualityData(aqi: aqi, pm25: pm25 ?? 0, pm10: pm10)
    }
    
    // MARK: - Fallback Weather Service
    private func fetchWeatherFromOpenMeteo(location: CLLocation) async throws {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        
        // Open-Meteo API (free, no API key required)
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code&timezone=auto"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let weatherResponse = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        
        await MainActor.run {
            self.temperatureC = weatherResponse.current.temperature_2m
            self.conditions = weatherCodeToDescription(weatherResponse.current.weather_code)
        }
    }
    
    private func weatherCodeToDescription(_ code: Int) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1, 2, 3: return "Partly cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Snow grains"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "Unknown"
        }
    }


    // MARK: - Export Helper Functions
    // Function to aggregate entries by hour, keeping the most complete record
    private func aggregateEntriesByHour(_ entries: [BPEntry]) -> [BPEntry] {
        let calendar = Calendar.current
        
        // Group entries by hour
        let groupedByHour = Dictionary(grouping: entries) { entry in
            calendar.dateInterval(of: .hour, for: entry.date)?.start ?? entry.date
        }
        
        // For each hour, select the most complete entry
        return groupedByHour.compactMap { (hour, entriesInHour) in
            return findMostCompleteEntry(from: entriesInHour)
        }.sorted { $0.date < $1.date }
    }
    
    // Function to determine which entry is most complete based on data availability
    private func findMostCompleteEntry(from entries: [BPEntry]) -> BPEntry? {
        guard !entries.isEmpty else { return nil }
        
        // If only one entry, return it
        if entries.count == 1 { return entries.first }
        
        // Score each entry based on how much data it contains
        let scoredEntries = entries.map { entry in
            (entry: entry, score: calculateCompletenessScore(for: entry))
        }
        
        // Return the entry with the highest completeness score
        return scoredEntries.max { $0.score < $1.score }?.entry
    }
    
    // Calculate a completeness score for an entry
    private func calculateCompletenessScore(for entry: BPEntry) -> Int {
        var score = 0
        
        // Health metrics (weight these more heavily)
        if entry.systolic != nil { score += 3 }
        if entry.diastolic != nil { score += 3 }
        if entry.pulse != nil { score += 3 }
        if entry.spo2 != nil { score += 3 }
        if entry.bodyTemperature != nil { score += 2 }
        if entry.respiratoryRate != nil { score += 2 }
        if entry.hrvSDNN != nil { score += 2 }
        if entry.restingHeartRate != nil { score += 2 }
        if entry.walkingHeartRate != nil { score += 2 }
        
        // Environmental data
        if entry.temperatureC != nil { score += 2 }
        if entry.conditions != nil { score += 1 }
        if entry.aqi != nil { score += 2 }
        if entry.pm25 != nil { score += 2 }
        if entry.pm10 != nil { score += 1 }
        
        // Symptoms (higher weight as they're user-specific)
        if !entry.symptoms.isEmpty { score += 4 }
        
        // Notes and location
        if !entry.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 3 }
        if entry.latitude != nil && entry.longitude != nil { score += 1 }
        
        return score
    }

    // MARK: Export
    func generateCSV() -> String {
        var csv = "Date,Time,Systolic (mmHg),Diastolic (mmHg),Pulse (bpm),SpO2 (%),Body Temp (°C),Respiratory Rate (bpm),HRV SDNN (ms),Resting HR (bpm),Walking HR (bpm),Weather Temp (°C),Weather Conditions,AQI,PM2.5 (µg/m³),PM10 (µg/m³),Notes,Symptoms,Latitude,Longitude\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .medium
        
        // Use hourly aggregated entries
        let aggregatedEntries = aggregateEntriesByHour(entries)
        
        for entry in aggregatedEntries.sorted(by: { $0.date < $1.date }) {
            let date = dateFormatter.string(from: entry.date)
            let time = timeFormatter.string(from: entry.date)
            let systolic = entry.systolic?.description ?? ""
            let diastolic = entry.diastolic?.description ?? ""
            let pulse = entry.pulse?.description ?? ""
            let spo2 = entry.spo2?.description ?? ""
            let bodyTemp = entry.bodyTemperature?.description ?? ""
            let respRate = entry.respiratoryRate?.description ?? ""
            let hrv = entry.hrvSDNN?.description ?? ""
            let restingHR = entry.restingHeartRate?.description ?? ""
            let walkingHR = entry.walkingHeartRate?.description ?? ""
            let weatherTemp = entry.temperatureC?.description ?? ""
            let conditions = entry.conditions?.replacingOccurrences(of: ",", with: ";") ?? ""
            let aqi = entry.aqi?.description ?? ""
            let pm25 = entry.pm25?.description ?? ""
            let pm10 = entry.pm10?.description ?? ""
            let notes = entry.note.replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\n", with: " ")
            let symptoms = entry.symptoms.map { $0.rawValue }.joined(separator: "; ").replacingOccurrences(of: ",", with: ";")
            let lat = entry.latitude?.description ?? ""
            let lon = entry.longitude?.description ?? ""
            
            csv += "\(date),\(time),\(systolic),\(diastolic),\(pulse),\(spo2),\(bodyTemp),\(respRate),\(hrv),\(restingHR),\(walkingHR),\(weatherTemp),\(conditions),\(aqi),\(pm25),\(pm10),\(notes),\(symptoms),\(lat),\(lon)\n"
        }
        
        return csv
    }
    
    func exportCSV() -> URL? {
        let csvContent = generateCSV()
        let fileName = "ENVHealth_Export_\(DateFormatter().string(from: Date())).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            errorMessage = "Failed to create CSV: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Persistence
    private func loadEntries() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let data = try Data(contentsOf: saveURL)
            self.entries = try JSONDecoder().decode([BPEntry].self, from: data)
        } catch {
            self.errorMessage = "Failed to load entries: \(error.localizedDescription)"
        }
    }

    func persistEntries() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: saveURL, options: [.atomic])
        } catch {
            self.errorMessage = "Failed to save entries: \(error.localizedDescription)"
        }
    }
}

// MARK: - CLLocationDelegate
extension BPLoggerViewModel: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("Location authorization changed to: \(status.rawValue)")
        DispatchQueue.main.async {
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                print("Location authorized, starting updates...")
                manager.startUpdatingLocation()
            case .denied, .restricted:
                self.errorMessage = "Location access denied. Please enable in Settings to get weather data."
            case .notDetermined:
                print("Location permission not determined yet")
            @unknown default:
                break
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            print("Location updated: \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
            currentLocation = loc
            manager.stopUpdatingLocation() // Stop after getting location to save battery
            Task { await fetchWeatherAndAQI() }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.errorMessage = "Location error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Charts View
struct ChartsView: View {
    let entries: [BPEntry]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    if !bloodPressureEntries.isEmpty {
                        bloodPressureChart
                    }
                    
                    if !pulseEntries.isEmpty {
                        pulseChart
                    }
                    
                    if !spo2Entries.isEmpty {
                        spo2Chart
                    }
                    
                    if !bodyTemperatureEntries.isEmpty {
                        bodyTemperatureChart
                    }
                    
                    if !respiratoryRateEntries.isEmpty {
                        respiratoryRateChart
                    }
                    
                    if !hrvEntries.isEmpty {
                        hrvChart
                    }
                    
                    if !temperatureEntries.isEmpty {
                        temperatureChart
                    }
                    
                    if !aqiEntries.isEmpty {
                        aqiChart
                    }
                }
                .padding()
            }
            .navigationTitle("Health Charts")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    private var bloodPressureEntries: [BPEntry] {
        entries.filter { $0.systolic != nil && $0.diastolic != nil }
            .sorted { $0.date < $1.date }
            .suffix(30)
            .map { $0 }
    }
    
    private var temperatureEntries: [BPEntry] {
        entries.filter { $0.temperatureC != nil }
            .sorted { $0.date < $1.date }
            .suffix(30)
            .map { $0 }
    }
    
    private var aqiEntries: [BPEntry] {
        entries.filter { $0.aqi != nil }
            .sorted { $0.date < $1.date }
            .suffix(30)
            .map { $0 }
    }
    
    private var pulseEntries: [BPEntry] {
        entries.filter { $0.pulse != nil }
            .sorted { $0.date < $1.date }
            .suffix(30)
            .map { $0 }
    }
    
    private var spo2Entries: [BPEntry] {
        entries.filter { $0.spo2 != nil }
            .sorted { $0.date < $1.date }
            .suffix(30)
            .map { $0 }
    }
    
    private var bodyTemperatureEntries: [BPEntry] {
        entries.filter { $0.bodyTemperature != nil }
            .sorted { $0.date < $1.date }
            .suffix(30)
            .map { $0 }
    }
    
    private var respiratoryRateEntries: [BPEntry] {
        entries.filter { $0.respiratoryRate != nil }
            .sorted { $0.date < $1.date }
            .suffix(30)
            .map { $0 }
    }
    
    private var hrvEntries: [BPEntry] {
        entries.filter { $0.hrvSDNN != nil }
            .sorted { $0.date < $1.date }
            .suffix(30)
            .map { $0 }
    }
    
    private var bloodPressureChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Blood Pressure Trends")
                .font(.headline)
                .foregroundColor(.primary)
            
            Chart(bloodPressureEntries) { entry in
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Systolic", entry.systolic ?? 0)
                )
                .foregroundStyle(.red)
                .symbol(.circle)
                
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Diastolic", entry.diastolic ?? 0)
                )
                .foregroundStyle(.blue)
                .symbol(.square)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .chartLegend(position: .bottom) {
                HStack {
                    Label("Systolic", systemImage: "circle.fill")
                        .foregroundColor(.red)
                    Label("Diastolic", systemImage: "square.fill")
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var temperatureChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Temperature Trends")
                .font(.headline)
                .foregroundColor(.primary)
            
            Chart(temperatureEntries) { entry in
                AreaMark(
                    x: .value("Date", entry.date),
                    y: .value("Temperature", entry.temperatureC ?? 0)
                )
                .foregroundStyle(.orange.gradient)
                
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Temperature", entry.temperatureC ?? 0)
                )
                .foregroundStyle(.orange)
                .symbol(.circle)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var aqiChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Air Quality Index Trends")
                .font(.headline)
                .foregroundColor(.primary)
            
            Chart(aqiEntries) { entry in
                BarMark(
                    x: .value("Date", entry.date),
                    y: .value("AQI", entry.aqi ?? 0)
                )
                .foregroundStyle(aqiColor(entry.aqi ?? 0))
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var pulseChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart Rate Trends")
                .font(.headline)
                .foregroundColor(.primary)
            
            Chart(pulseEntries) { entry in
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Pulse", entry.pulse ?? 0)
                )
                .foregroundStyle(.pink)
                .symbol(.circle)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var spo2Chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Blood Oxygen Saturation (SpO2)")
                .font(.headline)
                .foregroundColor(.primary)
            
            Chart(spo2Entries) { entry in
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("SpO2", entry.spo2 ?? 0)
                )
                .foregroundStyle(.blue)
                .symbol(.circle)
            }
            .frame(height: 200)
            .chartYScale(domain: 90...100)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var bodyTemperatureChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Body Temperature")
                .font(.headline)
                .foregroundColor(.primary)
            
            Chart(bodyTemperatureEntries) { entry in
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Temperature", entry.bodyTemperature ?? 0)
                )
                .foregroundStyle(.purple)
                .symbol(.circle)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var respiratoryRateChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Respiratory Rate")
                .font(.headline)
                .foregroundColor(.primary)
            
            Chart(respiratoryRateEntries) { entry in
                BarMark(
                    x: .value("Date", entry.date),
                    y: .value("Rate", entry.respiratoryRate ?? 0)
                )
                .foregroundStyle(.cyan)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var hrvChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart Rate Variability (HRV)")
                .font(.headline)
                .foregroundColor(.primary)
            
            Chart(hrvEntries) { entry in
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("HRV", entry.hrvSDNN ?? 0)
                )
                .foregroundStyle(.indigo)
                .symbol(.square)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func aqiColor(_ aqi: Double) -> Color {
        switch aqi {
        case 0...50: return .green
        case 51...100: return .yellow
        case 101...150: return .orange
        case 151...200: return .red
        case 201...300: return .purple
        default: return .brown
        }
    }
}

// MARK: - View
struct ContentView: View {
    @StateObject private var vm = BPLoggerViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Header with current status
                    currentStatusCard
                    
                    // Action buttons
                    actionButtonsCard
                    
                    // Recent entries
                    if !vm.entries.isEmpty {
                        recentEntriesCard
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .refreshable {
                await vm.refreshAllDataAsync()
            }
            .navigationTitle("ENVHealth")
            .navigationBarTitleDisplayMode(.large)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            vm.showingChartsView = true
                        } label: {
                            Label("View Charts", systemImage: "chart.line.uptrend.xyaxis")
                        }
                        
                        Button {
                            vm.showingExportSheet = true
                        } label: {
                            Label("Export Data", systemImage: "square.and.arrow.up")
                        }
                        
                        Button {
                            vm.showingSettingsSheet = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        
                        Button {
                            vm.refreshLatest()
                        } label: {
                            Label("Refresh All", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear { vm.requestPermissionsAndRefresh() }
            .sheet(isPresented: $vm.showingChartsView) {
                ChartsView(entries: vm.entries)
            }
            .sheet(isPresented: $vm.showingExportSheet) {
                ExportView(viewModel: vm)
            }
            .sheet(isPresented: $vm.showingSettingsSheet) {
                SettingsView(viewModel: vm)
            }
            .sheet(isPresented: $vm.showingSensorSelectionSheet) {
                SensorSelectionView(viewModel: vm)
            }
            .alert("Debug Info", isPresented: .constant(vm.errorMessage != nil)) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }
    
    private var currentStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Current Status")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "heart.circle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                if vm.showBloodPressure {
                    StatusTile(
                        title: "Blood Pressure",
                        value: bloodPressureString,
                        icon: "heart.fill",
                        color: .red
                    )
                }
                if vm.showHeartRate {
                    StatusTile(
                        title: "Heart Rate",
                        value: valueString(vm.pulse, suffix: "bpm"),
                        icon: "waveform.path.ecg",
                        color: .pink
                    )
                }
                if vm.showSpO2 {
                    StatusTile(
                        title: "SpO2",
                        value: valueString(vm.spo2, suffix: "%"),
                        icon: "lungs.fill",
                        color: .blue
                    )
                }
                if vm.showBodyTemperature {
                    StatusTile(
                        title: "Body Temp",
                        value: vm.displayTemperature(vm.bodyTemperature),
                        icon: "thermometer.medium",
                        color: .purple
                    )
                }
                if vm.showRespiratoryRate {
                    StatusTile(
                        title: "Respiratory Rate",
                        value: valueString(vm.respiratoryRate, suffix: "bpm"),
                        icon: "wind",
                        color: .cyan
                    )
                }
                if vm.showHRV {
                    StatusTile(
                        title: "HRV",
                        value: valueString(vm.hrvSDNN, suffix: "ms"),
                        icon: "heart.text.square",
                        color: .indigo
                    )
                }
                if vm.showRestingHeartRate {
                    StatusTile(
                        title: "Resting HR",
                        value: valueString(vm.restingHeartRate, suffix: "bpm"),
                        icon: "bed.double.fill",
                        color: .mint
                    )
                }
                if vm.showWalkingHeartRate {
                    StatusTile(
                        title: "Walking HR",
                        value: valueString(vm.walkingHeartRate, suffix: "bpm"),
                        icon: "figure.walk",
                        color: .teal
                    )
                }
                if vm.showWeatherTemp {
                    StatusTile(
                        title: "Weather Temp",
                        value: vm.displayTemperature(vm.temperatureC),
                        icon: "thermometer",
                        color: .orange
                    )
                }
                if vm.showAirQuality {
                    StatusTile(
                        title: "Air Quality",
                        value: aqiString,
                        icon: "aqi.medium",
                        color: aqiColor(vm.aqi ?? 0)
                    )
                    .onTapGesture {
                        Task {
                            await vm.fetchNearbySensors()
                        }
                        vm.showingSensorSelectionSheet = true
                    }
                }
            }
            
            if let conditions = vm.conditions {
                HStack {
                    Image(systemName: "cloud.sun.fill")
                        .foregroundColor(.blue)
                    Text(conditions)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            // Manual refresh button for all data
            VStack(spacing: 8) {
                Button(action: vm.refreshAllData) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh All Data")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                if vm.currentLocation == nil {
                    Text("📍 Enable location for weather data")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private var actionButtonsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Add New Entry")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            // Note input
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextEditor(text: $vm.note)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                hideKeyboard()
                            }
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
            }
            
            // Symptom selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Symptoms")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                    ForEach(Symptom.allCases, id: \.self) { symptom in
                        SymptomToggleView(
                            symptom: symptom,
                            isSelected: vm.selectedSymptoms.contains(symptom),
                            onToggle: { isSelected in
                                if isSelected {
                                    vm.selectedSymptoms.insert(symptom)
                                } else {
                                    vm.selectedSymptoms.remove(symptom)
                                }
                            }
                        )
                    }
                }
                
                // Other symptom text field (only show if "Other" is selected)
                if vm.selectedSymptoms.contains(.other) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Specify other symptom:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Describe other symptom", text: $vm.otherSymptomText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
            }
            
            Button {
                vm.saveEntry()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Save Entry")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private var recentEntriesCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Recent Entries")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(vm.entries.count) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ForEach(vm.entries.prefix(5)) { entry in
                EntryRowView(entry: entry, viewModel: vm)
                if entry.id != vm.entries.prefix(5).last?.id {
                    Divider()
                }
            }
            
            if vm.entries.count > 5 {
                NavigationLink(destination: HistoryView(entries: vm.entries, viewModel: vm)) {
                    Text("View All Entries")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private var bloodPressureString: String {
        if let sys = vm.systolic, let dia = vm.diastolic {
            return "\(Int(sys))/\(Int(dia))"
        }
        return "—"
    }
    
    private var aqiString: String {
        guard let aqi = vm.aqi else { return "—" }
        
        var components: [String] = []
        
        // AQI with category
        let category = aqiCategory(aqi)
        components.append("\(Int(aqi)) • \(category)")
        
        // PM2.5 reading
        if let pm25 = vm.pm25 {
            components.append("PM2.5: \(String(format: "%.1f", pm25))")
        }
        
        // PM10 reading
        if let pm10 = vm.pm10 {
            components.append("PM10: \(String(format: "%.1f", pm10))")
        }
        
        return components.joined(separator: "\n")
    }
    
    private func aqiCategory(_ aqi: Double) -> String {
        switch aqi {
        case 0...50: return "Good"
        case 51...100: return "Moderate"
        case 101...150: return "Unhealthy for Sensitive Groups"
        case 151...200: return "Unhealthy"
        case 201...300: return "Very Unhealthy"
        default: return "Hazardous"
        }
    }
    
    private func aqiColor(_ aqi: Double) -> Color {
        switch aqi {
        case 0...50: return .green
        case 51...100: return .yellow
        case 101...150: return .orange
        case 151...200: return .red
        case 201...300: return .purple
        default: return .brown
        }
    }

    private func valueString(_ value: Double?, suffix: String) -> String {
        value.map { String(format: "%.0f %@", $0, suffix) } ?? "—"
    }
}

// MARK: - Status Tile
struct StatusTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Entry Row View
struct EntryRowView: View {
    let entry: BPEntry
    let viewModel: BPLoggerViewModel
    @State private var showingEditSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.date, style: .date)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                if let sys = entry.systolic, let dia = entry.diastolic {
                    MetricView(title: "BP", value: "\(Int(sys))/\(Int(dia))", unit: "mmHg", color: .red)
                }
                if let pulse = entry.pulse {
                    MetricView(title: "HR", value: "\(Int(pulse))", unit: "bpm", color: .pink)
                }
                if let spo2 = entry.spo2 {
                    MetricView(title: "SpO2", value: String(format: "%.0f", spo2), unit: "%", color: .blue)
                }
                if let bodyTemp = entry.bodyTemperature {
                    let tempString = viewModel.useFahrenheit ? 
                        String(format: "%.1f°F", viewModel.celsiusToFahrenheit(bodyTemp)) :
                        String(format: "%.1f°C", bodyTemp)
                    MetricView(title: "Body", value: tempString, unit: "", color: .purple)
                }
                if let respRate = entry.respiratoryRate {
                    MetricView(title: "Resp", value: "\(Int(respRate))", unit: "bpm", color: .cyan)
                }
                if let hrv = entry.hrvSDNN {
                    MetricView(title: "HRV", value: String(format: "%.0f", hrv), unit: "ms", color: .indigo)
                }
                if let temp = entry.temperatureC {
                    let tempString = viewModel.useFahrenheit ? 
                        String(format: "%.1f°F", viewModel.celsiusToFahrenheit(temp)) :
                        String(format: "%.1f°C", temp)
                    MetricView(title: "Weather", value: tempString, unit: "", color: .orange)
                }
                if let aqi = entry.aqi {
                    MetricView(title: "AQI", value: "\(Int(aqi))", unit: "", color: aqiColor(aqi))
                }
                if let pm25 = entry.pm25 {
                    MetricView(title: "PM2.5", value: String(format: "%.1f", pm25), unit: "µg/m³", color: .brown)
                }
                if let pm10 = entry.pm10 {
                    MetricView(title: "PM10", value: String(format: "%.1f", pm10), unit: "µg/m³", color: .gray)
                }
            }
            
            // Display symptoms if any
            if !entry.symptoms.isEmpty {
                HStack {
                    Text("Symptoms:")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 4) {
                    ForEach(entry.symptoms, id: \.self) { symptom in
                        HStack(spacing: 4) {
                            Text(symptom.emoji)
                                .font(.caption2)
                            Text(symptom.rawValue)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            
            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .overlay(
            HStack {
                Spacer()
                Image(systemName: "pencil.circle")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
            .padding(.trailing, 8)
        )
        .onTapGesture {
            showingEditSheet = true
        }
        .sheet(isPresented: $showingEditSheet) {
            EditEntryView(entry: entry, viewModel: viewModel)
        }
    }
    
    private func aqiColor(_ aqi: Double) -> Color {
        switch aqi {
        case 0...50: return .green
        case 51...100: return .yellow
        case 101...150: return .orange
        case 151...200: return .red
        case 201...300: return .purple
        default: return .brown
        }
    }
}

// MARK: - Edit Entry View
struct EditEntryView: View {
    let entry: BPEntry
    let viewModel: BPLoggerViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var systolic: String
    @State private var diastolic: String
    @State private var pulse: String
    @State private var spo2: String
    @State private var bodyTemperature: String
    @State private var respiratoryRate: String
    @State private var note: String
    @State private var selectedSymptoms: Set<Symptom>
    @State private var otherSymptomText: String
    @State private var showingDeleteAlert = false
    
    init(entry: BPEntry, viewModel: BPLoggerViewModel) {
        self.entry = entry
        self.viewModel = viewModel
        
        _systolic = State(initialValue: entry.systolic?.description ?? "")
        _diastolic = State(initialValue: entry.diastolic?.description ?? "")
        _pulse = State(initialValue: entry.pulse?.description ?? "")
        _spo2 = State(initialValue: entry.spo2.map { String(format: "%.1f", $0) } ?? "")
        _bodyTemperature = State(initialValue: entry.bodyTemperature?.description ?? "")
        _respiratoryRate = State(initialValue: entry.respiratoryRate?.description ?? "")
        _note = State(initialValue: entry.note)
        _selectedSymptoms = State(initialValue: Set(entry.symptoms))
        _otherSymptomText = State(initialValue: "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Health Metrics") {
                    HStack {
                        Text("Blood Pressure")
                        Spacer()
                        TextField("Systolic", text: $systolic)
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                        Text("/")
                        TextField("Diastolic", text: $diastolic)
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                    }
                    
                    HStack {
                        Text("Heart Rate")
                        Spacer()
                        TextField("bpm", text: $pulse)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("SpO2")
                        Spacer()
                        TextField("%", text: $spo2)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("Body Temperature")
                        Spacer()
                        TextField("°C", text: $bodyTemperature)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("Respiratory Rate")
                        Spacer()
                        TextField("bpm", text: $respiratoryRate)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                    }
                }
                
                Section("Symptoms") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                        ForEach(Symptom.allCases, id: \.self) { symptom in
                            SymptomToggleView(
                                symptom: symptom,
                                isSelected: selectedSymptoms.contains(symptom),
                                onToggle: { isSelected in
                                    if isSelected {
                                        selectedSymptoms.insert(symptom)
                                    } else {
                                        selectedSymptoms.remove(symptom)
                                    }
                                }
                            )
                        }
                    }
                    
                    // Other symptom text field (only show if "Other" is selected)
                    if selectedSymptoms.contains(.other) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Specify other symptom:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Describe other symptom", text: $otherSymptomText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                }
                
                Section("Notes") {
                    TextEditor(text: $note)
                        .frame(minHeight: 100)
                }
                
                Section("Environmental Data") {
                    HStack {
                        Text("Weather Temperature")
                        Spacer()
                        if let temp = entry.temperatureC {
                            Text(viewModel.useFahrenheit ? 
                                String(format: "%.1f°F", viewModel.celsiusToFahrenheit(temp)) :
                                String(format: "%.1f°C", temp))
                                .foregroundColor(.secondary)
                        } else {
                            Text("—")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Air Quality Index")
                        Spacer()
                        if let aqi = entry.aqi {
                            Text("\(Int(aqi))")
                                .foregroundColor(.secondary)
                        } else {
                            Text("—")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("PM2.5")
                        Spacer()
                        if let pm25 = entry.pm25 {
                            Text(String(format: "%.1f µg/m³", pm25))
                                .foregroundColor(.secondary)
                        } else {
                            Text("—")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("PM10")
                        Spacer()
                        if let pm10 = entry.pm10 {
                            Text(String(format: "%.1f µg/m³", pm10))
                                .foregroundColor(.secondary)
                        } else {
                            Text("—")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Weather Conditions")
                        Spacer()
                        if let conditions = entry.conditions {
                            Text(conditions)
                                .foregroundColor(.secondary)
                        } else {
                            Text("—")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Entry Info") {
                    HStack {
                        Text("Date")
                        Spacer()
                        Text(entry.date, style: .date)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Time")
                        Spacer()
                        Text(entry.date, style: .time)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Delete Entry", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteEntry()
                }
            } message: {
                Text("Are you sure you want to delete this entry? This action cannot be undone.")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Delete", role: .destructive) {
                        showingDeleteAlert = true
                    }
                }
            }
        }
    }
    
    private func saveChanges() {
        // Create updated entry
        let updatedEntry = BPEntry(
            id: entry.id,
            date: entry.date,
            systolic: Double(systolic),
            diastolic: Double(diastolic),
            pulse: Double(pulse),
            spo2: Double(spo2),
            bodyTemperature: Double(bodyTemperature),
            respiratoryRate: Double(respiratoryRate),
            hrvSDNN: entry.hrvSDNN,
            restingHeartRate: entry.restingHeartRate,
            walkingHeartRate: entry.walkingHeartRate,
            temperatureC: entry.temperatureC,
            conditions: entry.conditions,
            aqi: entry.aqi,
            pm25: entry.pm25,
            pm10: entry.pm10,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: entry.latitude,
            longitude: entry.longitude,
            symptoms: Array(selectedSymptoms)
        )
        
        // Find and replace the entry
        if let index = viewModel.entries.firstIndex(where: { $0.id == entry.id }) {
            viewModel.entries[index] = updatedEntry
            viewModel.persistEntries()
        }
        
        dismiss()
    }
    
    private func deleteEntry() {
        viewModel.entries.removeAll { $0.id == entry.id }
        viewModel.persistEntries()
        dismiss()
    }
}

// MARK: - Metric View
struct MetricView: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(color)
                .fontWeight(.medium)
            HStack(alignment: .bottom, spacing: 2) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - History View
struct HistoryView: View {
    let entries: [BPEntry]
    let viewModel: BPLoggerViewModel
    
    var body: some View {
        List(entries) { entry in
            EntryRowView(entry: entry, viewModel: viewModel)
        }
        .navigationTitle("All Entries")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Air Quality Data
struct AirQualityData {
    let aqi: Double
    let pm25: Double
    let pm10: Double?
}

// MARK: - PurpleAir Sensor Model
struct PurpleAirSensor: Identifiable, Codable {
    let id: Int
    let name: String
    let location_type: Int
    let latitude: Double
    let longitude: Double
    let altitude: Int?
    let last_seen: Int
    let pm2_5: Double?
    let pm2_5_10minute: Double?
    let pm2_5_30minute: Double?
    let pm2_5_60minute: Double?
    let temperature: Double?
    let humidity: Double?
    
    var sensorIndex: Int { id }
    var displayName: String { name.isEmpty ? "Sensor #\(id)" : name }
    var isOutdoor: Bool { location_type == 0 }
    var lastSeenDate: Date { Date(timeIntervalSince1970: TimeInterval(last_seen)) }
    
    var distance: Double?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        location_type = try container.decodeIfPresent(Int.self, forKey: .location_type) ?? 0
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        altitude = try container.decodeIfPresent(Int.self, forKey: .altitude)
        last_seen = try container.decode(Int.self, forKey: .last_seen)
        pm2_5 = try container.decodeIfPresent(Double.self, forKey: .pm2_5)
        pm2_5_10minute = try container.decodeIfPresent(Double.self, forKey: .pm2_5_10minute)
        pm2_5_30minute = try container.decodeIfPresent(Double.self, forKey: .pm2_5_30minute)
        pm2_5_60minute = try container.decodeIfPresent(Double.self, forKey: .pm2_5_60minute)
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        humidity = try container.decodeIfPresent(Double.self, forKey: .humidity)
        distance = nil
    }
    
    private enum CodingKeys: String, CodingKey {
        case id = "sensor_index"
        case name
        case location_type
        case latitude
        case longitude
        case altitude
        case last_seen
        case pm2_5
        case pm2_5_10minute
        case pm2_5_30minute
        case pm2_5_60minute
        case temperature
        case humidity
    }
}

struct PurpleAirSensorsResponse: Codable {
    let data: [[AnyValue]]
    let fields: [String]
    
    enum AnyValue: Codable {
        case int(Int)
        case double(Double)
        case string(String)
        case null
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intValue = try? container.decode(Int.self) {
                self = .int(intValue)
            } else if let doubleValue = try? container.decode(Double.self) {
                self = .double(doubleValue)
            } else if let stringValue = try? container.decode(String.self) {
                self = .string(stringValue)
            } else if container.decodeNil() {
                self = .null
            } else {
                throw DecodingError.typeMismatch(AnyValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode value"))
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .int(let value):
                try container.encode(value)
            case .double(let value):
                try container.encode(value)
            case .string(let value):
                try container.encode(value)
            case .null:
                try container.encodeNil()
            }
        }
        
        var intValue: Int? {
            if case .int(let value) = self { return value }
            if case .double(let value) = self { return Int(value) }
            return nil
        }
        
        var doubleValue: Double? {
            if case .double(let value) = self { return value }
            if case .int(let value) = self { return Double(value) }
            return nil
        }
        
        var stringValue: String? {
            if case .string(let value) = self { return value }
            return nil
        }
    }
}

// MARK: - Health Data Point for Historical Export
struct HealthDataPoint {
    let date: Date
    var systolic: Double?
    var diastolic: Double?
    var heartRate: Double?
    var spo2: Double?
    var bodyTemperature: Double?
    var respiratoryRate: Double?
    var hrv: Double?
    var restingHeartRate: Double?
    var walkingHeartRate: Double?
}

// MARK: - Export View
struct ExportView: View {
    @ObservedObject var viewModel: BPLoggerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var csvURL: URL?
    @State private var exportAllHealthData = false
    @State private var isExporting = false
    @State private var exportError: String?
    
    // Export preferences
    @State private var selectedDays = 30
    @State private var includeBloodPressure = true
    @State private var includeHeartRate = true
    @State private var includeSpO2 = true
    @State private var includeBodyTemperature = true
    @State private var includeRespiratoryRate = true
    @State private var includeHRV = true
    @State private var includeRestingHeartRate = false
    @State private var includeWalkingHeartRate = false
    @State private var includeWeatherTemp = true
    @State private var includeAirQuality = true
    @State private var includeNotes = true
    @State private var includeSymptoms = true
    @State private var includeLocation = true
    
    private var filteredEntries: [BPEntry] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -selectedDays, to: Date()) ?? Date.distantPast
        let rawEntries = viewModel.entries.filter { $0.date >= cutoffDate }
        return aggregateEntriesByHour(rawEntries)
    }
    
    // Function to aggregate entries by hour, keeping the most complete record
    private func aggregateEntriesByHour(_ entries: [BPEntry]) -> [BPEntry] {
        let calendar = Calendar.current
        
        // Group entries by hour
        let groupedByHour = Dictionary(grouping: entries) { entry in
            calendar.dateInterval(of: .hour, for: entry.date)?.start ?? entry.date
        }
        
        // For each hour, select the most complete entry
        return groupedByHour.compactMap { (hour, entriesInHour) in
            return findMostCompleteEntry(from: entriesInHour)
        }.sorted { $0.date < $1.date }
    }
    
    // Function to determine which entry is most complete based on data availability
    private func findMostCompleteEntry(from entries: [BPEntry]) -> BPEntry? {
        guard !entries.isEmpty else { return nil }
        
        // If only one entry, return it
        if entries.count == 1 { return entries.first }
        
        // Score each entry based on how much data it contains
        let scoredEntries = entries.map { entry in
            (entry: entry, score: calculateCompletenessScore(for: entry))
        }
        
        // Return the entry with the highest completeness score
        return scoredEntries.max { $0.score < $1.score }?.entry
    }
    
    // Calculate a completeness score for an entry
    private func calculateCompletenessScore(for entry: BPEntry) -> Int {
        var score = 0
        
        // Health metrics (weight these more heavily)
        if entry.systolic != nil { score += 3 }
        if entry.diastolic != nil { score += 3 }
        if entry.pulse != nil { score += 3 }
        if entry.spo2 != nil { score += 3 }
        if entry.bodyTemperature != nil { score += 2 }
        if entry.respiratoryRate != nil { score += 2 }
        if entry.hrvSDNN != nil { score += 2 }
        if entry.restingHeartRate != nil { score += 2 }
        if entry.walkingHeartRate != nil { score += 2 }
        
        // Environmental data
        if entry.temperatureC != nil { score += 2 }
        if entry.conditions != nil { score += 1 }
        if entry.aqi != nil { score += 2 }
        if entry.pm25 != nil { score += 2 }
        if entry.pm10 != nil { score += 1 }
        
        // Symptoms (higher weight as they're user-specific)
        if !entry.symptoms.isEmpty { score += 4 }
        
        // Notes and location
        if !entry.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 3 }
        if entry.latitude != nil && entry.longitude != nil { score += 1 }
        
        return score
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                        
                        Text("Export Health Data")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Customize your export with date range and metric selection")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Date Range Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("📅 Export Options")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Toggle("Export all health data (not just logged entries)", isOn: $exportAllHealthData)
                            .font(.subheadline)
                        
                        Picker("Date Range", selection: $selectedDays) {
                            Text("Last 1 day").tag(1)
                            Text("Last 7 days").tag(7)
                            Text("Last 30 days").tag(30)
                        }
                        .pickerStyle(.segmented)
                        
                        if exportAllHealthData {
                            Text("Will export all health data from Apple Health for the selected range")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("\(filteredEntries.count) logged entries found in the selected range")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Health Metrics Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("🩺 Health Metrics")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                            ExportToggleRow(
                                title: "Blood Pressure",
                                icon: "heart.fill",
                                isOn: $includeBloodPressure
                            )
                            ExportToggleRow(
                                title: "Heart Rate",
                                icon: "waveform.path.ecg",
                                isOn: $includeHeartRate
                            )
                            ExportToggleRow(
                                title: "SpO2",
                                icon: "lungs.fill",
                                isOn: $includeSpO2
                            )
                            ExportToggleRow(
                                title: "Body Temperature",
                                icon: "thermometer.medium",
                                isOn: $includeBodyTemperature
                            )
                            ExportToggleRow(
                                title: "Respiratory Rate",
                                icon: "wind",
                                isOn: $includeRespiratoryRate
                            )
                            ExportToggleRow(
                                title: "HRV",
                                icon: "heart.text.square",
                                isOn: $includeHRV
                            )
                            ExportToggleRow(
                                title: "Resting HR",
                                icon: "bed.double.fill",
                                isOn: $includeRestingHeartRate
                            )
                            ExportToggleRow(
                                title: "Walking HR",
                                icon: "figure.walk",
                                isOn: $includeWalkingHeartRate
                            )
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Environmental & Other Data
                    VStack(alignment: .leading, spacing: 12) {
                        Text("🌡️ Environmental & Other")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                            ExportToggleRow(
                                title: "Weather Temp",
                                icon: "thermometer.sun",
                                isOn: $includeWeatherTemp
                            )
                            ExportToggleRow(
                                title: "Air Quality",
                                icon: "aqi.medium",
                                isOn: $includeAirQuality
                            )
                            ExportToggleRow(
                                title: "Notes",
                                icon: "note.text",
                                isOn: $includeNotes
                            )
                            ExportToggleRow(
                                title: "Symptoms",
                                icon: "medical.thermometer",
                                isOn: $includeSymptoms
                            )
                            ExportToggleRow(
                                title: "Location",
                                icon: "location.fill",
                                isOn: $includeLocation
                            )
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Export Button
                    Button {
                        exportCustomCSV()
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            if exportAllHealthData {
                                Text(isExporting ? "Exporting..." : "Export All Health Data (Last \(selectedDays) days)")
                                    .fontWeight(.semibold)
                            } else {
                                Text(isExporting ? "Exporting..." : "Export CSV (\(filteredEntries.count) entries)")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background((exportAllHealthData || !filteredEntries.isEmpty) && !isExporting ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled((!exportAllHealthData && filteredEntries.isEmpty) || isExporting)
                    
                    // Error message display
                    if let error = exportError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let csvURL = csvURL {
                    ShareSheet(activityItems: [csvURL])
                }
            }
        }
    }
    
    private func exportCustomCSV() {
        isExporting = true
        exportError = nil
        
        if exportAllHealthData {
            // Export all health data from HealthKit
            Task {
                do {
                    if let url = await generateHistoricalHealthCSV() {
                        await MainActor.run {
                            csvURL = url
                            showingShareSheet = true
                            isExporting = false
                        }
                    } else {
                        await MainActor.run {
                            exportError = "Failed to generate CSV file. Please try again."
                            isExporting = false
                        }
                    }
                }
            }
        } else {
            // Export logged entries only
            if let url = generateCustomCSV() {
                csvURL = url
                showingShareSheet = true
                isExporting = false
            } else {
                exportError = "Failed to generate CSV file. Please try again."
                isExporting = false
            }
        }
    }
    
    private func generateCustomCSV() -> URL? {
        // Build custom header based on selected metrics
        var headers = ["Date", "Time"]
        
        if includeBloodPressure {
            headers.append(contentsOf: ["Systolic (mmHg)", "Diastolic (mmHg)"])
        }
        if includeHeartRate {
            headers.append("Pulse (bpm)")
        }
        if includeSpO2 {
            headers.append("SpO2 (%)")
        }
        if includeBodyTemperature {
            headers.append(viewModel.useFahrenheit ? "Body Temp (°F)" : "Body Temp (°C)")
        }
        if includeRespiratoryRate {
            headers.append("Respiratory Rate (bpm)")
        }
        if includeHRV {
            headers.append("HRV SDNN (ms)")
        }
        if includeRestingHeartRate {
            headers.append("Resting HR (bpm)")
        }
        if includeWalkingHeartRate {
            headers.append("Walking HR (bpm)")
        }
        if includeWeatherTemp {
            headers.append(viewModel.useFahrenheit ? "Weather Temp (°F)" : "Weather Temp (°C)")
        }
        if includeAirQuality {
            headers.append(contentsOf: ["Weather Conditions", "AQI", "PM2.5 (µg/m³)", "PM10 (µg/m³)"])
        }
        if includeNotes {
            headers.append("Notes")
        }
        if includeSymptoms {
            headers.append("Symptoms")
        }
        if includeLocation {
            headers.append(contentsOf: ["Latitude", "Longitude"])
        }
        
        var csv = headers.joined(separator: ",") + "\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .medium
        
        for entry in filteredEntries.sorted(by: { $0.date < $1.date }) {
            var row: [String] = []
            
            row.append(dateFormatter.string(from: entry.date))
            row.append(timeFormatter.string(from: entry.date))
            
            if includeBloodPressure {
                row.append(entry.systolic.map { "\($0)" } ?? "")
                row.append(entry.diastolic.map { "\($0)" } ?? "")
            }
            if includeHeartRate {
                row.append(entry.pulse.map { "\($0)" } ?? "")
            }
            if includeSpO2 {
                row.append(entry.spo2.map { String(format: "%.1f", $0) } ?? "")
            }
            if includeBodyTemperature {
                if let temp = entry.bodyTemperature {
                    let displayTemp = viewModel.useFahrenheit ? viewModel.celsiusToFahrenheit(temp) : temp
                    row.append(String(format: "%.1f", displayTemp))
                } else {
                    row.append("")
                }
            }
            if includeRespiratoryRate {
                row.append(entry.respiratoryRate.map { String(format: "%.1f", $0) } ?? "")
            }
            if includeHRV {
                row.append(entry.hrvSDNN.map { String(format: "%.1f", $0) } ?? "")
            }
            if includeRestingHeartRate {
                row.append(entry.restingHeartRate.map { "\($0)" } ?? "")
            }
            if includeWalkingHeartRate {
                row.append(entry.walkingHeartRate.map { "\($0)" } ?? "")
            }
            if includeWeatherTemp {
                if let temp = entry.temperatureC {
                    let displayTemp = viewModel.useFahrenheit ? viewModel.celsiusToFahrenheit(temp) : temp
                    row.append(String(format: "%.1f", displayTemp))
                } else {
                    row.append("")
                }
            }
            if includeAirQuality {
                row.append("\"\(entry.conditions ?? "")\"")
                row.append(entry.aqi.map { String(format: "%.1f", $0) } ?? "")
                row.append(entry.pm25.map { String(format: "%.1f", $0) } ?? "")
                row.append(entry.pm10.map { String(format: "%.1f", $0) } ?? "")
            }
            if includeNotes {
                row.append("\"\(entry.note)\"")
            }
            if includeSymptoms {
                let symptomsText = entry.symptoms.map { $0.rawValue }.joined(separator: "; ")
                row.append("\"\(symptomsText)\"")
            }
            if includeLocation {
                row.append(entry.latitude.map { String(format: "%.6f", $0) } ?? "")
                row.append(entry.longitude.map { String(format: "%.6f", $0) } ?? "")
            }
            
            csv += row.joined(separator: ",") + "\n"
        }
        
        let fileName = "ENVHealth_Export_\(selectedDays)days_\(DateFormatter().string(from: Date())).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("Failed to create CSV: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func generateHistoricalHealthCSV() async -> URL? {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -selectedDays, to: endDate) ?? endDate
        
        // Build custom header based on selected metrics
        var headers = ["Date", "Time"]
        
        if includeBloodPressure {
            headers.append(contentsOf: ["Systolic (mmHg)", "Diastolic (mmHg)"])
        }
        if includeHeartRate {
            headers.append("Pulse (bpm)")
        }
        if includeSpO2 {
            headers.append("SpO2 (%)")
        }
        if includeBodyTemperature {
            headers.append(viewModel.useFahrenheit ? "Body Temp (°F)" : "Body Temp (°C)")
        }
        if includeRespiratoryRate {
            headers.append("Respiratory Rate (bpm)")
        }
        if includeHRV {
            headers.append("HRV SDNN (ms)")
        }
        if includeRestingHeartRate {
            headers.append("Resting HR (bpm)")
        }
        if includeWalkingHeartRate {
            headers.append("Walking HR (bpm)")
        }
        
        var csv = headers.joined(separator: ",") + "\n"
        
        // Fetch all health data for the date range
        let healthData = await fetchAllHealthDataForDateRange(startDate: startDate, endDate: endDate)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .medium
        
        // Group data by date/time and create rows
        for data in healthData.sorted(by: { $0.date < $1.date }) {
            var row: [String] = []
            
            row.append(dateFormatter.string(from: data.date))
            row.append(timeFormatter.string(from: data.date))
            
            if includeBloodPressure {
                row.append(data.systolic.map { String(format: "%.0f", $0) } ?? "")
                row.append(data.diastolic.map { String(format: "%.0f", $0) } ?? "")
            }
            if includeHeartRate {
                row.append(data.heartRate.map { String(format: "%.0f", $0) } ?? "")
            }
            if includeSpO2 {
                row.append(data.spo2.map { String(format: "%.0f", $0) } ?? "")
            }
            if includeBodyTemperature {
                if let temp = data.bodyTemperature {
                    let displayTemp = viewModel.useFahrenheit ? viewModel.celsiusToFahrenheit(temp) : temp
                    row.append(String(format: "%.1f", displayTemp))
                } else {
                    row.append("")
                }
            }
            if includeRespiratoryRate {
                row.append(data.respiratoryRate.map { String(format: "%.0f", $0) } ?? "")
            }
            if includeHRV {
                row.append(data.hrv.map { String(format: "%.1f", $0) } ?? "")
            }
            if includeRestingHeartRate {
                row.append(data.restingHeartRate.map { String(format: "%.0f", $0) } ?? "")
            }
            if includeWalkingHeartRate {
                row.append(data.walkingHeartRate.map { String(format: "%.0f", $0) } ?? "")
            }
            
            csv += row.joined(separator: ",") + "\n"
        }
        
        let fileName = "ENVHealth_AllData_\(selectedDays)days_\(DateFormatter().string(from: Date())).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("Failed to create historical CSV: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func fetchAllHealthDataForDateRange(startDate: Date, endDate: Date) async -> [HealthDataPoint] {
        var healthDataPoints: [HealthDataPoint] = []
        
        // Define health data types to fetch
        let types = [
            (HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic)!, "systolic"),
            (HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic)!, "diastolic"),
            (HKQuantityType.quantityType(forIdentifier: .heartRate)!, "heartRate"),
            (HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!, "spo2"),
            (HKQuantityType.quantityType(forIdentifier: .bodyTemperature)!, "bodyTemperature"),
            (HKQuantityType.quantityType(forIdentifier: .respiratoryRate)!, "respiratoryRate"),
            (HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!, "hrv"),
            (HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!, "restingHeartRate"),
            (HKQuantityType.quantityType(forIdentifier: .walkingHeartRateAverage)!, "walkingHeartRate")
        ]
        
        // Fetch data for each type with timeout
        for (quantityType, identifier) in types {
            do {
                let samples = try await withTimeout(seconds: 30) {
                    await fetchHealthSamples(for: quantityType, startDate: startDate, endDate: endDate)
                }
                
                for sample in samples {
                    let value = getValueForHealthType(sample: sample, identifier: identifier)
                    
                    // Find existing data point for this date or create new one
                    if let existingIndex = healthDataPoints.firstIndex(where: { 
                        Calendar.current.isDate($0.date, equalTo: sample.endDate, toGranularity: .minute) 
                    }) {
                        // Update existing data point
                        updateHealthDataPoint(&healthDataPoints[existingIndex], identifier: identifier, value: value)
                    } else {
                        // Create new data point
                        var newDataPoint = HealthDataPoint(date: sample.endDate)
                        updateHealthDataPoint(&newDataPoint, identifier: identifier, value: value)
                        healthDataPoints.append(newDataPoint)
                    }
                }
            } catch {
                print("Timeout or error fetching \(identifier): \(error.localizedDescription)")
                // Continue with other data types even if one fails
            }
        }
        
        return healthDataPoints
    }
    
    private func fetchHealthSamples(for quantityType: HKQuantityType, startDate: Date, endDate: Date) async -> [HKQuantitySample] {
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    print("Error fetching \(quantityType.identifier): \(error.localizedDescription)")
                    continuation.resume(returning: [])
                } else {
                    continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
                }
            }
            
            viewModel.healthStore.execute(query)
        }
    }
    
    private func getValueForHealthType(sample: HKQuantitySample, identifier: String) -> Double {
        switch identifier {
        case "systolic", "diastolic":
            return sample.quantity.doubleValue(for: .millimeterOfMercury())
        case "heartRate", "restingHeartRate", "walkingHeartRate", "respiratoryRate":
            return sample.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
        case "spo2":
            return sample.quantity.doubleValue(for: .percent()) * 100 // Convert to percentage
        case "bodyTemperature":
            return sample.quantity.doubleValue(for: .degreeCelsius())
        case "hrv":
            return sample.quantity.doubleValue(for: .secondUnit(with: .milli))
        default:
            return 0
        }
    }
    
    private func updateHealthDataPoint(_ dataPoint: inout HealthDataPoint, identifier: String, value: Double) {
        switch identifier {
        case "systolic":
            dataPoint.systolic = value
        case "diastolic":
            dataPoint.diastolic = value
        case "heartRate":
            dataPoint.heartRate = value
        case "spo2":
            dataPoint.spo2 = value
        case "bodyTemperature":
            dataPoint.bodyTemperature = value
        case "respiratoryRate":
            dataPoint.respiratoryRate = value
        case "hrv":
            dataPoint.hrv = value
        case "restingHeartRate":
            dataPoint.restingHeartRate = value
        case "walkingHeartRate":
            dataPoint.walkingHeartRate = value
        default:
            break
        }
    }
    
    // MARK: - Timeout Helper
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Timeout Error
struct TimeoutError: Error {
    let localizedDescription = "Operation timed out"
}

// Helper view for toggle rows
struct ExportToggleRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(isOn ? .blue : .gray)
                .frame(width: 20)
            
            Text(title)
                .font(.caption)
                .foregroundColor(isOn ? .primary : .secondary)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .scaleEffect(0.8)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var viewModel: BPLoggerViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Temperature Unit")) {
                    Toggle("Use Fahrenheit", isOn: $viewModel.useFahrenheit)
                        .onChange(of: viewModel.useFahrenheit) { _, _ in
                            viewModel.savePreferences()
                        }
                }
                
                Section(header: Text("Health Metrics Display"), 
                       footer: Text("Choose which health metrics to show on the main screen")) {
                    Toggle("Blood Pressure", isOn: $viewModel.showBloodPressure)
                        .onChange(of: viewModel.showBloodPressure) { _, _ in
                            viewModel.savePreferences()
                        }
                    
                    Toggle("Heart Rate", isOn: $viewModel.showHeartRate)
                        .onChange(of: viewModel.showHeartRate) { _, _ in
                            viewModel.savePreferences()
                        }
                    
                    Toggle("SpO2", isOn: $viewModel.showSpO2)
                        .onChange(of: viewModel.showSpO2) { _, _ in
                            viewModel.savePreferences()
                        }
                    
                    Toggle("Body Temperature", isOn: $viewModel.showBodyTemperature)
                        .onChange(of: viewModel.showBodyTemperature) { _, _ in
                            viewModel.savePreferences()
                        }
                    
                    Toggle("Respiratory Rate", isOn: $viewModel.showRespiratoryRate)
                        .onChange(of: viewModel.showRespiratoryRate) { _, _ in
                            viewModel.savePreferences()
                        }
                    
                    Toggle("Heart Rate Variability", isOn: $viewModel.showHRV)
                        .onChange(of: viewModel.showHRV) { _, _ in
                            viewModel.savePreferences()
                        }
                    
                    Toggle("Resting Heart Rate", isOn: $viewModel.showRestingHeartRate)
                        .onChange(of: viewModel.showRestingHeartRate) { _, _ in
                            viewModel.savePreferences()
                        }
                    
                    Toggle("Walking Heart Rate", isOn: $viewModel.showWalkingHeartRate)
                        .onChange(of: viewModel.showWalkingHeartRate) { _, _ in
                            viewModel.savePreferences()
                        }
                }
                
                Section(header: Text("Environmental Data")) {
                    Toggle("Weather Temperature", isOn: $viewModel.showWeatherTemp)
                        .onChange(of: viewModel.showWeatherTemp) { _, _ in
                            viewModel.savePreferences()
                        }
                    
                    Toggle("Air Quality Index", isOn: $viewModel.showAirQuality)
                        .onChange(of: viewModel.showAirQuality) { _, _ in
                            viewModel.savePreferences()
                        }
                }
                
                Section(header: Text("Data Management")) {
                    Button("🔄 Refresh All Data") {
                        viewModel.refreshAllData()
                    }
                    
                    Button("🩺 Refresh Health Data Only") {
                        Task { await viewModel.fetchLatestHealthMetrics() }
                    }
                    
                    Button("🌡️ Refresh Weather & AQI Only") {
                        viewModel.refreshWeatherAndAQI()
                    }
                    
                    Button("🔍 Debug PurpleAir API") {
                        Task {
                            await viewModel.testPurpleAirAPI()
                        }
                    }
                    
                    Button("📍 Test Location") {
                        viewModel.testLocation()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - ShareSheet for Export
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - Sensor Selection View
struct SensorSelectionView: View {
    @ObservedObject var viewModel: BPLoggerViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("📡 Select Air Quality Sensor")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Choose a PurpleAir sensor near your location for more accurate air quality readings.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Sensor List
                    if viewModel.availableSensors.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            
                            Text("No sensors found")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Make sure location services are enabled and try again.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.availableSensors) { sensor in
                                SensorRowView(
                                    sensor: sensor,
                                    isSelected: viewModel.selectedSensorID == sensor.id,
                                    onSelect: {
                                        viewModel.selectedSensorID = sensor.id
                                        viewModel.savePreferences()
                                        
                                        // Refresh air quality with new sensor
                                        viewModel.refreshWeatherAndAQI()
                                        
                                        dismiss()
                                    }
                                )
                            }
                            
                            // Option to use automatic selection
                            SensorRowView(
                                sensor: nil,
                                isSelected: viewModel.selectedSensorID == nil,
                                onSelect: {
                                    viewModel.selectedSensorID = nil
                                    viewModel.savePreferences()
                                    
                                    // Refresh air quality with automatic selection
                                    viewModel.refreshWeatherAndAQI()
                                    
                                    dismiss()
                                }
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Air Quality Sensors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Refresh") {
                        Task {
                            await viewModel.fetchNearbySensors()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sensor Row View
struct SensorRowView: View {
    let sensor: PurpleAirSensor?
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.title2)
                
                sensorContent
                
                Spacer()
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private var sensorContent: some View {
        if let sensor = sensor {
            VStack(alignment: .leading, spacing: 4) {
                // Sensor name and ID
                HStack {
                    Text(sensor.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("#\(sensor.id)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)
                }
                
                // Distance and AQI
                HStack {
                    if let distance = sensor.distance {
                        Text(String(format: "%.1f km away", distance))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if let pm25 = sensor.pm2_5 {
                        Text("PM2.5: \(String(format: "%.1f", pm25))")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                // Last updated
                Text("Updated recently")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("🤖 Automatic Selection")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Always use the nearest available sensor")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Symptom Toggle View
struct SymptomToggleView: View {
    let symptom: Symptom
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        Button(action: {
            onToggle(!isSelected)
        }) {
            HStack {
                Text(symptom.emoji)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(symptom.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
                    .stroke(
                        isSelected ? Color.blue : Color(.systemGray4),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Keyboard Dismissal Extension
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
