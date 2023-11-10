//
//  Data.swift
//  flowrlSDK
//
//  Created by Alexey Primechaev on 14.09.2023.
//

import UIKit
import Combine

extension Notification.Name {
    static let flowRLConfigurationDidUpdate = Notification.Name("flowRLConfigurationDidUpdate")
}

enum FlowRLErrors: String, Error {
    case noKey = "No API key provided"
    case config = "No ConfigurationSpace found"
    case invalidResponse = "Invalid server response"
}


private struct APIClient {
    let baseURL: URL
    var apiKey: String?
    
    func send<T: Encodable>(_ data: T, endpoint: String) async throws {
        guard let apiKey = apiKey else {
            throw FlowRLErrors.noKey
        }
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
                
        let encodedData = try JSONEncoder().encode(data)
        request.httpBody = encodedData
        
        if let jsonString = String(data: encodedData, encoding: .utf8) {
            print("Outgoing JSON:", jsonString)
        }
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Damn", response)
            throw FlowRLErrors.invalidResponse
        }
    }
    
    func fetchConfiguration(for userId: String) async throws -> Configuration {
        var components = URLComponents(url: baseURL.appendingPathComponent("get_config"), resolvingAgainstBaseURL: false)

        components?.queryItems = [URLQueryItem(name: "user_id", value: userId)]

        guard let url = components?.url else {
            throw NSError(domain: "Invalid URL", code: 0, userInfo: nil)
        }

        var request = URLRequest(url: url)
        print("URL", url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Validate HTTP response
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            // Handle error
            throw NSError(domain: "Invalid response", code: httpResponse.statusCode, userInfo: nil)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(Configuration.self, from: data)
    }



}


private class EventSender {
    static var shared = EventSender()
    
    private var cancellables: Set<AnyCancellable> = []
    
    func startTimer(interval: TimeInterval, code: @escaping () -> ()) {
        Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                code()
            }
            .store(in: &cancellables)
    }
    
    func stopTimer() {
        cancellables.removeAll()
    }
}

@MainActor
public class FlowRL: ObservableObject {
    public static var instance: FlowRL = FlowRL(name: "default", apiKey: nil)
    
    private var name: String
    private var apiKey: String?
    
    private lazy var apiClient = APIClient(baseURL: URL(string: "https://api.flowrl.ai/")!, apiKey: apiKey)
    
    @Published var configuration: Configuration? {
        didSet {
            NotificationCenter.default.post(name: .flowRLConfigurationDidUpdate, object: nil)
        }
    }
    
    private var isConfigured: Bool = false
        
    private var events: Set<Event> = []
    
    private var packageSendSuccessful: Bool? = nil
    
    private var overrideUserId: String?
    
    private let defaultIdKey: String = "FlowRLDefaultIdKey"
    
    private var eventSender = EventSender.shared
    
    private var defaultId: UUID {
        if let savedUUIDString = UserDefaults.standard.string(forKey: defaultIdKey),
           let savedUUID = UUID(uuidString: savedUUIDString) {
            return savedUUID
        } else {
            let newUUID = UUID()
            UserDefaults.standard.set(newUUID.uuidString, forKey: defaultIdKey)
            return newUUID
        }
    }
    
    private var userId: String {
        if let overrideUserId {
            return overrideUserId
        } else {
            return defaultId.uuidString
        }
    }
    
    private var cancellables: Set<AnyCancellable> = []
    
    private init(name: String, apiKey: String? = nil) {
        self.name = name
        self.apiKey = apiKey
        self.overrideUserId = nil
    }
    
    public func configure(name: String = "default", userId: String? = nil, apiKey: String) {
        self.apiKey = apiKey
        self.name = name
        self.overrideUserId = userId
        
        if !isConfigured {
            self.loadEventsFromStorage()
            Task {
                await self.loadConfiguration()
                await self.sendEventsToServer()
                self.eventSender.startTimer(interval: 60) {
                    Task {
                        await self.sendEventsToServer()
                    }
                }
            }
            
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
                .sink { [weak self] _ in
                    self?.handleAppDidEnterBackground()
                }
                .store(in: &cancellables)
        } else {
            self.loadEventsFromStorage()
            Task {
                await self.fetchConfigurationFromServer()
                await self.sendEventsToServer()
                self.eventSender.startTimer(interval: 60) {
                    Task {
                        await self.sendEventsToServer()
                    }
                }
            }
            
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
                .sink { [weak self] _ in
                    self?.handleAppDidEnterBackground()
                }
                .store(in: &cancellables)
        }
        
        self.isConfigured = true
        
    }
    
    private func handleAppDidEnterBackground() {
        print("BACKGROUND")
    }
    
    private let configurationKey: String = "FlowRLConfiguration"
    
    
    private func saveConfigurationToCache() {
        do {
            let data = try JSONEncoder().encode(self.configuration)
            UserDefaults.standard.set(data, forKey: configurationKey)
            
        } catch {
            print("Failed to encode and save configuration: \(error)")
        }
    }
    
    private func loadConfiguration() async {
        var shouldFetchFromServer = true
        
        if let data = UserDefaults.standard.data(forKey: configurationKey) {
            do {
                let cachedConfiguration = try JSONDecoder().decode(Configuration.self, from: data)
                
                if Date() < cachedConfiguration.generatedAt.addingTimeInterval(60*60*24) {
                    self.configuration = cachedConfiguration
                    shouldFetchFromServer = false
                }
            } catch {
                print("Failed to decode configuration: \(error)")
            }
        }
        
        if shouldFetchFromServer {
            await self.fetchConfigurationFromServer()
        }
    }
    
    private let eventsKey: String = "FlowRLEvents"
    
    
    private func loadEventsFromStorage() {
        if let data = UserDefaults.standard.data(forKey: eventsKey) {
            do {
                let storedEvents = try JSONDecoder().decode(Set<Event>.self, from: data)
                self.events = storedEvents
            } catch {
                print("Failed to decode stored events: \(error)")
            }
        }
    }
    
    private func storeEventsToStorage() {
        do {
            let data = try JSONEncoder().encode(self.events)
            UserDefaults.standard.set(data, forKey: eventsKey)
        } catch {
            print("Failed to encode and store events: \(error)")
        }
    }
    
    private func clearEventsFromStorage() {
        UserDefaults.standard.removeObject(forKey: eventsKey)
    }
    
    
    public func logEvent(actionName: String, categoryName: String, screenName: String) {
        self.events.insert(
            Event(timestamp: Int(Date().timeIntervalSince1970 * 1000), userId: userId, category: __EventCategoryPlaceholder(string: categoryName), actionName: actionName, screenName: screenName, configuration: [__PlaceholderConfiguration(name: "placeholder", value: "placeholder")])
        )
        self.storeEventsToStorage()
    }
    
    private func fetchConfigurationFromServer() async {
        do {
            let fetchedConfiguration = try await apiClient.fetchConfiguration(for: userId)
            self.configuration = fetchedConfiguration
            self.saveConfigurationToCache()
            print("bam", configuration)
        } catch {
            print("Error fetching configuration: \(error)")
        }
    }
    
    private func sendEventsToServer() async {
        guard !events.isEmpty else { return }
        
        do {
            try await apiClient.send(events.first!, endpoint: "collect_event")
            events.removeAll()
            self.clearEventsFromStorage()
        } catch {
            print("Error sending events: \(error)")
            self.storeEventsToStorage()
        }
    }
    
    
    
    
}

struct Event: Equatable, Codable, Hashable {
    var timestamp: Int
    
    
    
    var companyId: Int = 1202
    var userId: String
    
    var category: __EventCategoryPlaceholder
    var actionName: String
    var screenName: String
    var configuration: [__PlaceholderConfiguration]
        
    enum CodingKeys: String, CodingKey {
        case timestamp = "timestamp"
        
        case companyId = "compan_id"
        case userId = "user_id"
        
        case category = "event_category"
        case actionName = "event_action"
        case screenName = "screen_name"
                
        case configuration = "flowrl_config"
    }
    
}

struct __EventCategoryPlaceholder: Equatable, Codable, Hashable {
    var string: String
}

struct Configuration: Equatable, Codable, Hashable {
    var generatedAt: Date
    var userId: String?
    var type: String?
    var configurationChoices: Set<ConfigurationChoice>
    
    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case userId = "user_id"
        case type = "type"
        case configurationChoices = "config"
    }
}

struct __PlaceholderConfiguration: Equatable, Codable, Hashable {
    var name: String
    var value: String
    
    enum CodingKeys: String, CodingKey {
        case name = "experiment_name"
        case value = "experiment_value"
    }
}

struct ConfigurationChoice: Equatable, Codable, Hashable {
    var test: String
    var selectedVariant: String?
    var variants: Set<String>
    
    enum CodingKeys: String, CodingKey {
        case test = "name"
        case selectedVariant = "selected_variant"
        case variants = "variants"
    }
    
}
