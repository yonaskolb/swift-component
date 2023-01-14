import Foundation
import SwiftUI
import SwiftGUI
import SwiftPreview

public protocol ComponentView: View {

    associatedtype Model: ComponentModel
    associatedtype ComponentView: View
    associatedtype DestinationView: View
    associatedtype Style = Never
    var model: ViewModel<Model> { get }
    init(model: ViewModel<Model>)
    @ViewBuilder @MainActor var view: Self.ComponentView { get }
    @ViewBuilder @MainActor func routeView(_ route: Model.Route) -> DestinationView
    @MainActor func presentation(for route: Model.Route) -> Presentation
}

public extension ComponentView {

    func presentation(for route: Model.Route) -> Presentation {
        .sheet
    }
}

public extension ComponentView where Model.Route == Never {
    func routeView(_ route: Model.Route) -> EmptyView {
        EmptyView()
    }
}

struct ComponentViewContainer<Model: ComponentModel, Content: View>: View {

    let model: ViewModel<Model>
    let view: Content
    @State var showDebug = false
    @State var viewModes: [ComponentViewMode] = [.view]
    @Environment(\.isPreviewReference) var isPreviewReference

    enum ComponentViewMode: String, Identifiable {
        case view
        case data
        case history
        case editor
        case debug

        var id: String { rawValue }
    }

    var body: some View {
        view
        .task { @MainActor in
            // don't call this for other reference views
            if !isPreviewReference {
                await model.appear()
            }
        }
#if DEBUG
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            showDebug = !showDebug
        }
        .sheet(isPresented: $showDebug) {
            if #available(iOS 16.0, *) {
                ComponentDebugView(viewModel: model)
                    .presentationDetents([.medium, .large])
            } else {
                ComponentDebugView(viewModel: model)
            }
        }
#endif
    }
}

public extension ComponentView {

    @MainActor
    private var currentPresentation: Presentation? {
        model.route.map { presentation(for: $0) }
    }

    @MainActor
    private func presentationBinding(_ presentation: Presentation) -> Binding<Bool> {
        Binding(
            get: {
                currentPresentation == presentation
            },
            set: { present in
                if !present {
                    self.model.route = nil
                }
            }
        )
    }

    @MainActor
    var body: some View {
        ComponentViewContainer(model: model, view: view)
            .background {
                NavigationLink(isActive: presentationBinding(.push) ) {
                    if let route = model.route {
                        routeView(route)
                    }
                } label: {
                    EmptyView()
                }
            }
            .sheet(isPresented: presentationBinding(.sheet)) {
                if let route = model.route {
                    routeView(route)
                }
            }
            .fullScreenCover(isPresented: presentationBinding(.fullScreenCover)) {
                if let route = model.route {
                    routeView(route)
                }
            }
    }

    func task() async {

    }

    func binding<Value>(_ keyPath: WritableKeyPath<Model.State, Value>) -> Binding<Value> {
        model.binding(keyPath)
    }

    var state: Model.State { model.state }
}

//extension View {
//
//    func style<V: ComponentView>(_ view: V.Type, _ style: (inout V.Style) -> Void) -> some View {
//        self.environment(\., <#T##value: V##V#>)
//    }
//}
