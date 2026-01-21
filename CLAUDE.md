# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NEMA USA is a native iOS app built with SwiftUI for managing events, ticket purchases, and program registrations for the NEMA USA organization. The app features event browsing, calendar views, ticket purchasing with PayPal integration, biometric authentication, push notifications, and Core Data persistence.

## Build and Development Commands

### Building the App
```bash
# Build the project (Release configuration is default)
xcodebuild -project "NEMA USA.xcodeproj" -scheme "NEMA USA" -configuration Debug build

# Build for simulator
xcodebuild -project "NEMA USA.xcodeproj" -scheme "NEMA USA" -sdk iphonesimulator -configuration Debug

# Clean build folder
xcodebuild -project "NEMA USA.xcodeproj" -scheme "NEMA USA" clean
```

### Running the App
Open `NEMA USA.xcodeproj` in Xcode and run using Cmd+R or use:
```bash
# Run on simulator
xcodebuild -project "NEMA USA.xcodeproj" -scheme "NEMA USA" -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' run
```

**Note:** This project currently has no test suite. All testing is manual.

## Architecture Overview

### Pattern: MVVM + Repository Pattern
The app follows a hybrid MVVM architecture with Repository Pattern for data management:
- **Views**: SwiftUI declarative views
- **ViewModels**: Business logic and state management using `@Published` properties and `ObservableObject`
- **Repositories**: Abstract data sources (Network + Core Data sync)
- **Models**: Plain Swift structs (Codable) for domain objects

### Data Flow
```
Network API (nemausa.org)
    ↓
NetworkManager (Singleton)
    ↓
Repository Layer (EventRepository, MyEventsRepository)
    ↓ ↑ (sync)
Core Data (PersistenceController)
    ↓
ViewModel Layer
    ↓
Views (SwiftUI)
```

## Key Architectural Components

### Entry Point
**NEMA_USAApp.swift**: Main app entry point
- Configures Kingfisher image caching (7-day disk cache, 5-minute memory cache)
- Sets up global navigation bar appearance (orange theme, white text)
- Manages app-level state: authentication, deep linking, biometric setup, version checking
- Uses `@UIApplicationDelegateAdaptor` for lifecycle events (ServiceDelegate)

### Navigation Structure
**Tab-based primary navigation** with 4 tabs:
1. Dashboard - Event listing with search/filter
2. Calendar - Calendar-based event browsing
3. My Events - User's purchased tickets/registrations
4. Account - User profile and settings

**Deep linking support**:
- Universal links for password reset (`nemausa.org/user/reset_password`)
- Push notification deep links to specific events
- Handled in `NEMA_USAApp.swift` via `.onOpenURL()` and NotificationCenter observers

### Core Directories

#### `/Views` (17 files)
SwiftUI view components:
- **DashboardView**: Main events listing with search/filter
- **EventDetailView**: Detailed event display with sub-events support
- **EventRegistrationView**: Ticket purchase flow (ticketing system)
- **ProgramRegistrationView**: Competition/program registration
- **MyEventsView**: User's purchased tickets/registrations
- **LoginView**: Authentication UI with biometric support
- **AccountView**: User profile and settings
- **CalendarView**: Calendar-based event browsing
- **PurchaseDetailView**: Purchase confirmation details

#### `/Models` (11 files + Components subfolder)
Data models, ViewModels, and Repositories:
- **Data Models**: `Event.swift`, `MasterDataModel.swift` (UserProfile, FamilyMember), `TicketPurchaseDetailResponse.swift`
- **ViewModels**: `EventRegistrationViewModel.swift`, `MyEventsViewModel.swift`, `PurchaseDetailViewModel.swift`
- **Repositories**: `EventRepository.swift`, `MyEventsRepository.swift` (handle Core Data sync)
- **/Components**: Reusable model components (EventCard, EventTicketType, Panthi, Participant, etc.)

#### `/Services` (3 files)
Singleton services for cross-cutting concerns:
- **ServiceDelegate.swift**: UIApplicationDelegate for app lifecycle, notifications (OneSignal + local), deep linking
- **EventStatusService.swift**: Caches user registration/purchase status for events (5-minute TTL, performance optimization)
- **VersionConfigHelper.swift**: Version management utilities

#### `/Utils` (13 files)
Utility managers and helpers:
- **NetworkManager.swift**: Central networking layer (99.9KB - extensive)
  - Handles both **Laravel HTML scraping** AND **JSON API** calls (dual authentication system)
  - **Laravel Session Token** (for legacy endpoints) + **JWT Token** (for newer RESTful endpoints)
  - Auto-refreshes JWT when expired with automatic retry
  - All API endpoints (events, tickets, programs, purchases, payments)
- **PersistenceController.swift**: Core Data stack setup
- **DatabaseManager.swift**: UserDefaults wrapper (tokens, user profile, preferences)
- **KeychainManager.swift**: Secure credential storage for biometric login
- **BiometricAuthManager.swift**: Face ID/Touch ID authentication
- **NotificationManager.swift**: Local notification scheduling and management
- **PaymentManager.swift**: Payment processing logic
- **PayPalView.swift**: PayPal integration UI
- **AppVersionManager.swift**: Force update checking
- **MapAppLauncher.swift**: External map app integration

## Data Persistence

### Two-Tier Persistence Strategy

#### Core Data (Primary) - Complex, relational data
**PersistenceController.swift** manages the Core Data stack:
- Model: `NEMAAppDataModelNew.xcdatamodeld/NEMAAppDataModelNew.xcdatamodel`
- **Entities**:
  - `CDEvent`: Events with relationships to tickets, programs, panthis
  - `CDEventTicketType`: Ticket types with pricing (member vs public, early bird)
  - `CDPanthi`: Time slots for events
  - `CDEventProgram` + `CDProgramCategory`: Competition programs with categories
  - `CDPurchaseRecord`: User's purchase history

**Sync Strategy**:
- **Delta sync** using `lastUpdatedAt` timestamps
- Network-first, fall back to Core Data
- Repositories orchestrate the sync (EventRepository, MyEventsRepository)
- Background merging enabled: `automaticallyMergesChangesFromParent = true`

#### UserDefaults + Keychain (Secondary) - Simple data
**DatabaseManager.swift** wraps UserDefaults for:
- Session tokens (Laravel + JWT + Refresh)
- Current user profile (JSON encoded)
- Family members list
- Notification preferences
- Biometric preferences
- Sync timestamps

**KeychainManager.swift** for sensitive data:
- User credentials for biometric login (email + password)
- Uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for security

## Key Dependencies (Swift Package Manager)

The project uses the following SPM packages (resolved automatically on build):
- **Kingfisher** (8.5.0): Image downloading and caching
- **OneSignalFramework** (5.2.14): Push notifications
- **SwiftSoup** (2.11.0): HTML parsing for Laravel endpoint scraping
- **LRUCache** (1.1.2): Supporting dependency for Kingfisher
- **swift-atomics** (1.3.0): Supporting dependency for OneSignal

## Important Patterns and Conventions

### Async/Await Throughout
- All network calls use modern Swift Concurrency
- ViewModels marked with `@MainActor` for UI updates
- Repository methods are `async func`

### NotificationCenter for Decoupling
Custom notifications for cross-view communication:
- `.didReceiveJWT` - Login success
- `.didSessionExpire` - Session timeout (triggers global logout)
- `.didUpdateBiometricSettings` - Biometric settings changed
- `.didUserLogout` - User logout event
- `.didDeepLinkToEvent` - Deep link to specific event

### Singleton Services
Used for app-wide services:
- `NetworkManager.shared`
- `DatabaseManager.shared`
- `BiometricAuthManager.shared`
- `EventStatusService.shared`
- `NotificationManager.shared`
- `PersistenceController.shared`

### Caching Strategy
1. **Image Caching**: Kingfisher with 7-day disk cache (500MB limit), 5-minute memory cache
2. **Data Caching**: Core Data as persistent cache with delta sync
3. **Status Caching**: EventStatusService maintains in-memory cache with 5-minute TTL
4. **Debouncing**: Status updates debounced to 1 second to prevent cascading refreshes

### Performance Optimizations
- Lazy loading with `LazyVStack` in lists
- Image downsampling (1200x1200 max via Kingfisher)
- Batch processing for status checks (20 items per batch)
- Task cancellation in `deinit` to prevent memory leaks
- Fetch limits on Core Data queries (30 events default in EventRepository)

### Security Patterns
- Biometric authentication with fallback to passcode
- Keychain for credential storage (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- Session token refresh with automatic retry
- HTTPS-only with optional SSL pinning configuration (commented out for production)

### Error Handling
- Custom `NetworkError` enum for typed errors
- Published error messages in ViewModels (`@Published var lastSyncErrorMessage`)
- Alert presentations for user feedback
- Graceful degradation: show cached data on network failure

## Networking Details

### API Base URL
All network requests go to: `https://nemausa.org`

### Dual Authentication System
The app maintains two authentication mechanisms:
1. **Laravel Session Token**: Legacy HTML scraping endpoints
2. **JWT Token**: Modern JSON API endpoints
3. **Refresh Token**: Auto-refreshes JWT when expired (handled transparently)

### Key API Endpoints (NetworkManager.swift)
- `fetchEvents(since:)` - Delta sync for events
- `fetchTicketTypes(forEventId:)` - Ticket options for an event
- `fetchPanthis(forEventId:)` - Time slot selection
- `fetchPrograms(forEventId:)` - Competition categories
- `fetchSubEvents(forParentEventId:)` - Multi-day event support
- `fetchPurchaseRecords()` - User's purchase history
- `login()` / `loginJSON()` - Dual authentication methods
- Payment endpoints - PayPal integration

## Common Development Workflows

### Adding a New View
1. Create the SwiftUI view file in `/Views`
2. If needed, create a corresponding ViewModel in `/Models`
3. Use `@StateObject` for ViewModels (owns lifecycle)
4. Use `@Published` properties for reactive updates
5. Follow the existing navigation pattern (NavigationLink or sheet)

### Adding a New API Endpoint
1. Add the method to `NetworkManager.swift`
2. Use async/await pattern
3. Handle both success and `NetworkError` cases
4. If data should be cached, create/update a Repository
5. Update Core Data model if persistence is needed

### Modifying Core Data Schema
1. Edit `NEMAAppDataModelNew.xcdatamodeld`
2. Create a new model version (Editor > Add Model Version in Xcode)
3. Update `PersistenceController.swift` if migration needed
4. Update Repository sync methods to handle new fields
5. Update Model structs to match new schema

### Working with Biometric Authentication
- Check availability: `BiometricAuthManager.shared.isBiometricAvailable()`
- Check enrollment: `BiometricAuthManager.shared.isBiometricEnrolled()`
- Authenticate: `await BiometricAuthManager.shared.authenticate(reason:)`
- Credentials stored in Keychain via `KeychainManager.shared`

### Debugging Tips
- Network logs are extensive, search for `[NetworkManager]` or `[EventRepository]`
- Core Data logs: search for `✅`, `❌`, or `⚠️` prefixes
- Biometric logs: search for `[App]` or `FaceID`
- Session management: watch for `.didSessionExpire` notification logs
- Status caching: search for `[EventStatusService]`

## Version and Release Management

- Version checking is automatic on app launch via `AppVersionManager.shared`
- Force update support (mandatory vs optional updates)
- App Store version comparison using iTunes Search API
- Version info stored in `Info.plist`: `CFBundleShortVersionString`

## Git Workflow

Main branch: `main`

Recent commits show feature development pattern:
- Sub-events feature (v1.0.12)
- Ticket waitlist feature (v1.0.11)
- Login refresh from event registration view
- Membership renewal fixes

When committing: Follow existing commit message style (descriptive, feature-focused).
