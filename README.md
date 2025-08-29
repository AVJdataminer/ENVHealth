# ENVHealth - Environmental Health Tracking App

A comprehensive iOS health tracking application that correlates personal health metrics with environmental factors like air quality and weather conditions.

## 🌟 Features

### Health Monitoring
- **Blood pressure, heart rate, and SpO2 tracking**
- **Comprehensive symptom logging** with 7 predefined categories:
  - Shortness of Breath 🫁
  - Chest Tightness 🫸
  - Light Headed 😵‍💫
  - Dizzy 🌀
  - Headache 🤕
  - Chest Pain 💔
  - Other (custom input) ❓
- **Apple HealthKit integration** for seamless data collection
- **Body temperature and respiratory rate monitoring**
- **Heart rate variability (HRV) tracking**

### Environmental Monitoring
- **Real-time air quality data** from PurpleAir sensors
- **PM2.5 and PM10 particulate matter tracking**
- **Weather conditions integration** via Apple WeatherKit
- **Automatic location-based data collection**
- **100km sensor search radius** with fallback APIs
- **Manual sensor selection** for optimal data accuracy

### Data Export & Analysis
- **Smart hourly data aggregation** - keeps most complete record per hour
- **Comprehensive CSV exports** with customizable data selection
- **Symptom correlation analysis** with environmental factors
- **Historical data tracking** with configurable date ranges
- **Professional data formatting** for research and personal use

### User Experience
- **Intuitive symptom selection interface** with visual indicators
- **Real-time air quality status** with color-coded alerts
- **Custom app icon** and polished UI design
- **Comprehensive error handling** and user feedback
- **Offline data persistence** and sync capabilities

## 🛠 Technical Features

### Architecture
- **SwiftUI** for modern iOS interface
- **HealthKit** for health data integration
- **CoreLocation** for precise location services
- **WeatherKit** for weather data
- **URLSession** for API communications
- **JSON encoding/decoding** for data persistence

### API Integrations
- **PurpleAir API** for primary air quality data
- **WAQI.info API** as fallback air quality source
- **Apple WeatherKit** for weather conditions
- **Open-Meteo API** for backup weather data

### Data Management
- **Intelligent completeness scoring** for data aggregation
- **Hourly data deduplication** to optimize storage
- **Multi-format export options** (CSV with customizable columns)
- **Real-time data validation** and error recovery

## 📱 Requirements

- **iOS 18.5+**
- **Xcode 16.4+**
- **Swift 5.0+**
- **Apple Developer Account** (for HealthKit and WeatherKit)

## 🔧 Setup

1. **Clone the repository**
```bash
git clone https://github.com/AVJdataminer/ENVHealth.git
cd ENVHealth
```

2. **Configure API Keys**
   - Add your PurpleAir API key in `ContentView.swift`
   - Ensure HealthKit and WeatherKit entitlements are properly configured

3. **Build and Run**
   - Open `ENVHealth.xcodeproj` in Xcode
   - Select your target device
   - Build and run the project

## 📊 Export Features

The app generates CSV exports with the following data columns:
- **Date & Time** (hourly aggregated)
- **Health Metrics** (BP, pulse, SpO2, body temp, respiratory rate, HRV)
- **Environmental Data** (weather temp, conditions, AQI, PM2.5, PM10)
- **Symptom Logs** (all selected symptoms per entry)
- **Location Data** (latitude, longitude)
- **Personal Notes** (user annotations)

## 🎯 Use Cases

- **Personal health tracking** with environmental correlation
- **Medical research** into air quality health impacts
- **Chronic condition management** (asthma, COPD, cardiovascular)
- **Environmental health advocacy** and awareness
- **Clinical data collection** for healthcare providers

## 🏥 Health & Privacy

- **HealthKit secure integration** with user permission controls
- **Local data storage** with optional cloud sync
- **No personal data transmission** without explicit user consent
- **HIPAA-conscious design** for potential clinical use
- **Transparent data handling** with full user control

## 🚀 Recent Updates

### Version 2.0 Features
- ✅ **Comprehensive symptom tracking system**
- ✅ **Hourly data aggregation** for cleaner exports
- ✅ **Enhanced air quality monitoring** with 100km radius
- ✅ **Fallback API integration** for reliable data
- ✅ **Improved export functionality** with symptom inclusion
- ✅ **Custom app icon** and UI polish
- ✅ **Advanced debugging tools** for API connectivity

## 📈 Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

## 📄 License

This project is available under the MIT License. See LICENSE file for details.

## 👨‍💻 Author

**AVJdataminer** - Environmental health enthusiast and iOS developer

---

*Track your health, understand your environment, make informed decisions.* 🌱📱💚
