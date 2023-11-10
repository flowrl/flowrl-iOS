//
//  UIKitImplementation.swift
//  flowrlSDK
//
//  Created by Alexey Primechaev on 14.09.2023.
//

import SwiftUI

class PickVariantView: UIView {

    var id: String
    var configurationChoice: ConfigurationChoice? {
        didSet {
            updateVisibleSubview()
        }
    }
    var variantViews: [VariantView]

    init(_ id: String, variantViews: [VariantView]) {
        
        
        
        self.id = id
        self.variantViews = variantViews
        super.init(frame: .zero)
        NotificationCenter.default.addObserver(self, selector: #selector(configurationDidUpdate), name: .flowRLConfigurationDidUpdate, object: nil)
        
        configurationChoice = FlowRL.instance.configuration?.configurationChoices.first { $0.test == id }
        
        let selectedVariantId: String
        
        if let id = configurationChoice?.selectedVariant {
            selectedVariantId = id
        } else {
            selectedVariantId = configurationChoice?.variants.first ?? variantViews.first?.id ?? ""
        }
        
        
        for variantView in variantViews {
            addSubview(variantView)
            if variantView.id == selectedVariantId {
                variantView.isHidden = false
            } else {
                variantView.isHidden = true
            }
        }
        
    
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }


    private func updateVisibleSubview() {
        // Hide all subviews
        
        let selectedVariantId: String
        
        if let id = configurationChoice?.selectedVariant {
            selectedVariantId = id
        } else {
            selectedVariantId = configurationChoice?.variants.first ?? variantViews.first?.id ?? ""
        }
        
        for variantView in variantViews {
            
            
            if variantView.id == selectedVariantId {
                variantView.isHidden = false
            } else {
                variantView.isHidden = true
            }

        }
        
    }

    // MARK: - FlowRLDelegate
    @objc func configurationDidUpdate() {
        configurationChoice = FlowRL.instance.configuration?.configurationChoices.first { $0.test == id }
    }
}

class VariantView: UIView {
    
    var id: String
    var containedSubview: UIView
    
    init(id: String, subview: UIView) {
        self.id = id
        self.containedSubview = subview
        super.init(frame: containedSubview.frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        addSubview(containedSubview)
        containedSubview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            containedSubview.topAnchor.constraint(equalTo: self.topAnchor),
            containedSubview.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            containedSubview.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            containedSubview.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])
    }
    
    override var intrinsicContentSize: CGSize {
        return containedSubview.intrinsicContentSize
    }
}

struct PickVariantViewRepresentable: UIViewControllerRepresentable {
    var id: String
    var variantViews: [VariantView]

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.addSubview(PickVariantView(id, variantViews: variantViews))
        return viewController
    }
    
    init(_ id: String, variantViews: [VariantView]) {
        self.id = id
        self.variantViews = variantViews
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
           DispatchQueue.main.async {
               context.coordinator.updateSize(uiViewController)
           }
       }

       func makeCoordinator() -> Coordinator {
           Coordinator(self)
       }

       class Coordinator: NSObject {
           var parent: PickVariantViewRepresentable

           init(_ parent: PickVariantViewRepresentable) {
               self.parent = parent
           }

           func updateSize(_ viewController: UIViewController) {
               viewController.view.frame.size = viewController.preferredContentSize
           }
       }
}
