# Unhooked!

[![GitHub stars](https://img.shields.io/github/stars/seancajigal/h4h?style=for-the-badge)](https://github.com/seancajigal/h4h/stargazers)

[![GitHub forks](https://img.shields.io/github/forks/seancajigal/h4h?style=for-the-badge)](https://github.com/seancajigal/h4h/network)

[![GitHub issues](https://img.shields.io/github/issues/seancajigal/h4h?style=for-the-badge)](https://github.com/seancajigal/h4h/issues)

[![License](https://img.shields.io/badge/License-Unspecified-lightgrey?style=for-the-badge)](LICENSE) <!-- TODO: Add actual license -->

**Taking the Bait Out of Phishing — For Good**

</div>

## 📖 Overview

"Unhooked!" is a multi-platform application designed to combat phishing attacks by empowering users to identify and mitigate threats. Leveraging advanced Optical Character Recognition (OCR) technology, the application can analyze visual content to extract text, which is then processed to detect phishing indicators. Developed with Flutter, it aims to provide a seamless and consistent experience across mobile, web, and desktop environments, making it a robust tool in the fight against online fraud.

## ✨ Features

-   🎯 **Phishing Detection:** Analyzes input content to identify and flag potential phishing attempts.
-   👁️ **Optical Character Recognition (OCR):** Extracts text from images and screenshots using a powerful Node.js-based Tesseract.js utility, enabling analysis of visual phishing tactics.
-   📱 **Cross-Platform Compatibility:** Available on Android, iOS, Web, Windows, macOS, and Linux through a unified Flutter codebase.
-   📄 **Input/Output Processing:** Processes various forms of input (e.g., text, images) and generates structured analysis results, likely in JSON format.
-   ⚡ **Integrated Utility:** A local Node.js utility handles heavy-duty OCR processing, ensuring efficient and reliable text extraction.

## 🖥️ Screenshots

<!-- TODO: Add actual screenshots of the application on various platforms -->

![Screenshot 1](path-to-screenshot-mobile.png)

![Screenshot 2](path-to-screenshot-desktop.png)

## 🛠️ Tech Stack

**Mobile/Frontend:**
-   ![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
-   ![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)

**Backend/Utility:**
-   ![Node.js](https://img.shields.io/badge/Node.js-339933?style=for-the-badge&logo=node.js&logoColor=white)
-   ![Tesseract.js](https://img.shields.io/badge/Tesseract.js-F6F6F6?style=for-the-badge&logo=javascript&logoColor=black)

**Dev Tools:**
-   ![Gradle](https://img.shields.io/badge/Gradle-02303A?style=for-the-badge&logo=gradle&logoColor=white) (for Android builds)
-   ![Xcode](https://img.shields.io/badge/Xcode-007AFF?style=for-the-badge&logo=xcode&logoColor=white) (for iOS builds)

## 🚀 Quick Start

Follow these steps to get your development environment set up.

### Prerequisites
Before you begin, ensure you have the following installed:
-   **Flutter SDK:** [Installation Guide](https://flutter.dev/docs/get-started/install)
-   **Node.js:** (LTS version recommended) [Download Page](https://nodejs.org/en/download/)

### Installation

1.  **Clone the repository**
    ```bash
    git clone https://github.com/seancajigal/h4h.git
    cd h4h
    ```

2.  **Install Flutter dependencies**
    ```bash
    flutter pub get
    ```

3.  **Install Node.js dependencies for OCR utility**
    ```bash
    npm install
    ```

### Start Development Server

1.  **Run the Flutter application**
    ```bash
    flutter run
    ```
    This command will launch the application on a connected device, simulator, or browser, depending on your setup.

2.  **Using the OCR Utility (if standalone execution is desired)**
    The Node.js `wrapper.js` script is typically invoked by the Flutter app. If you need to run it independently for testing or development, use:
    ```bash
    node wrapper.js
    ```
    *Note: The Flutter application will likely communicate with this utility internally, so running `flutter run` is usually sufficient.*

## 📁 Project Structure

```
h4h/
├── .dart_tool/                  # Flutter toolchain artifacts
├── .flutter-plugins-dependencies # Cached Flutter plugin info
├── .gitignore                   # Git ignore rules
├── .idea/                       # IDE (IntelliJ/Android Studio) project files
├── .metadata                    # Flutter project metadata
├── analysis_options.yaml        # Dart static analysis configuration
├── android/                     # Android specific project files
├── build/                       # Build output directory
├── input.txt                    # Example input file
├── ios/                         # iOS specific project files
├── lib/                         # **Flutter application source code (Dart)**
│   └── main.dart                # Main application entry point
├── linux/                       # Linux specific project files
├── macos/                       # macOS specific project files
├── node_modules/                # Node.js dependencies
├── ocr/                         # OCR-related assets or scripts
├── output.json                  # Example output file
├── package-lock.json            # Node.js dependency lock file
├── package.json                 # Node.js project metadata
├── pubspec.lock                 # Dart/Flutter dependency lock file
├── pubspec.yaml                 # Dart/Flutter project metadata
├── test/                        # Flutter test files
├── web/                         # Web specific project files
├── windows/                     # Windows specific project files
└── wrapper.js                   # Node.js script for OCR utility
```

## ⚙️ Configuration

### Dart Analyzer Configuration
The `analysis_options.yaml` file at the project root defines the static analysis rules for the Dart codebase.

### Project Dependencies
-   **Flutter:** `pubspec.yaml` manages Dart/Flutter dependencies and project metadata.
-   **Node.js Utility:** `package.json` manages Node.js dependencies, specifically `tesseract.js` for OCR.

## 🔧 Development

### Available Scripts

| Command              | Description                                        |

|----------------------|----------------------------------------------------|

| `flutter run`        | Runs the Flutter application on a connected device/emulator. |

| `flutter pub get`    | Fetches all Dart/Flutter dependencies.             |

| `npm install`        | Installs Node.js dependencies for the OCR utility. |

| `node wrapper.js`    | Executes the Node.js OCR utility script.           |

| `npm run test`       | Runs the placeholder Node.js test script.          |

| `flutter test`       | Runs the Flutter application tests.                |

| `flutter build <platform>` | Builds the Flutter app for a specific platform (e.g., `web`, `apk`, `ios`). |

### Development Workflow
The primary development workflow involves running the Flutter application using `flutter run`. The Node.js OCR utility is typically integrated and called by the Flutter app as needed. Ensure all dependencies for both Flutter and Node.js are installed before running.

## 🧪 Testing

### Flutter Application Tests
To run tests for the Flutter application:
```bash
flutter test
```

### Node.js Utility Tests
The `package.json` includes a placeholder test script for the Node.js utility:
```bash
npm run test
```
*Note: This is a placeholder and may not contain actual tests.*

## 🚀 Deployment

### Production Build
To create a production-ready build of the Flutter application for a specific platform:
```bash

# For Android
flutter build apk

# For iOS
flutter build ios --release

# For Web
flutter build web

# For Windows
flutter build windows

# For macOS
flutter build macos

# For Linux
flutter build linux
```

### Deployment Options
Build artifacts for each platform will be generated in the `build/` directory, ready for deployment to respective app stores or hosting services.

## 🤝 Contributing

We welcome contributions to Unhooked! Please consider reviewing the existing codebase and issues.

### Development Setup for Contributors
Follow the [Quick Start](#🚀-quick-start) guide to set up your local development environment.

## 📄 License

This project is currently without a specified license. Please refer to the repository owner for licensing information.

## 🙏 Acknowledgments

-   **Tesseract.js**: For enabling robust Optical Character Recognition within the Node.js utility.

## 📞 Support & Contact

-   🐛 Issues: [GitHub Issues](https://github.com/seancajigal/h4h/issues)

---

<div align="center">

**⭐ Star this repo if you find it helpful!**

Made with ❤️ by seancajigal

</div>

