//
//  SwiftUIImplementation.swift
//  flowrlSDK
//
//  Created by Alexey Primechaev on 14.09.2023.
//

import SwiftUI

struct SelectedVariantKey: EnvironmentKey {
    static var defaultValue: String? = nil
}

extension EnvironmentValues {
    var selectedVariant: String? {
        get { self[SelectedVariantKey.self] }
        set { self[SelectedVariantKey.self] = newValue }
    }
}


public struct PickVariant<Content: View>: View {
    private let content: Content
    private var test: String
    
    @ObservedObject var flowRL = FlowRL.instance
    
    var configurationChoice: ConfigurationChoice? {
        flowRL.configuration?.configurationChoices.first { $0.test == test }
    }
    
    var defaultVariant: String
    
    var selectedVariant: String {
        if let selectedVariant = configurationChoice?.selectedVariant {
            return selectedVariant
        } else {
            return defaultVariant
        }
    }
    
    @State private var localVariants: Set<String> = []
    
    public init(_ test: String, defaultVariant: String, @ViewBuilder content: () -> Content) {
        self.test = test
        self.defaultVariant = defaultVariant
        self.content = content()
    }
    
    public var body: some View {
        content
            .environment(\.selectedVariant, selectedVariant)
    }
}

public struct Variant<Content: View>: View {
    
    @Environment(\.selectedVariant) var selectedVariant
    
    private var variant: String
    private var content: Content
    private var isShowing: Bool {
        selectedVariant == variant
    }
    
    public init(_ variant: String, @ViewBuilder content: () -> Content) {
        self.variant = variant
        self.content = content()
        
    }
    
    public var body: some View {
        if isShowing {
            content
        }
    }
}
