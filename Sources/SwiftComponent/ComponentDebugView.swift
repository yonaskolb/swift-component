//
//  SwiftUIView.swift
//  
//
//  Created by Yonas Kolb on 21/10/2022.
//

import SwiftUI
import SwiftGUI
import CustomDump

struct ComponentDebugView<ComponentType: Component>: View {

    let viewModel: ViewModel<ComponentType>
    @Environment(\.dismiss) var dismiss

    @State var showStateEditor = false
    @State var showStateOutput = false
    @State var showEvents = false
    @State var eventTypes = EventSimpleType.set
    @AppStorage("showMutations") var showMutations = false
    @AppStorage("showBindings") var showBindings = true
    @AppStorage("showChildEvents") var showChildEvents = true

    var events: [AnyEvent] {
        componentEvents(for: viewModel.path, includeChildren: showChildEvents)
            .filter { eventTypes.contains($0.type.type) }
            .reversed()
    }

    var body: some View {
        NavigationView {
            Form {
                if let parent = viewModel.path.parent {
                    Section(header: Text("Parent")) {
                        Text(parent.string)
                            .lineLimit(2)
                            .truncationMode(.head)
                    }
                }

                Section(header: Text("State")) {
                    SwiftView(value: viewModel.binding(\.self), config: Config(editing: true))
//                    NavigationLink(destination: SwiftView(value: viewModel.binding(\.self), config: Config(editing: true)), isActive: $showStateEditor) {
//                        HStack {
//                            Text("State")
//                                .bold()
//                            Spacer()
//                            Text(dumpLine(viewModel.state))
//                                .lineLimit(1)
//                        }
//                    }
                }
                Section(header: eventsHeader) {
                    Toggle("Show Children", isOn: $showChildEvents)
                    Toggle("Show State Mutations", isOn: $showMutations)
                        HStack {
                            Text("Show Types")
                            Spacer()
                            ForEach(EventSimpleType.allCases, id: \.rawValue) { event in
                                Button {
                                    if eventTypes.contains(event) {
                                        eventTypes.remove(event)
                                    } else {
                                        eventTypes.insert(event)
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(event.emoji)
                                            .font(.system(size: 20))
                                            .padding(2)
                                    }
                                    .opacity(eventTypes.contains(event) ? 1 : 0.2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Section {
                    ComponentEventList(
                        viewModel: viewModel,
                        events: events,
                        showMutations: showMutations)
                }
            }
            .animation(.default, value: eventTypes)
            .animation(.default, value: showMutations)
            .animation(.default, value: showChildEvents)
            .navigationTitle(viewModel.componentName + " Component")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss ()}) {
                        Text("Close")
                    }
                }
            }
        }
    }

    var eventsHeader: some View {
        HStack {
            Text("Events")
            Spacer()
            Text(events.count.formatted())
        }
    }

    var componentHeader: some View {
        Text(viewModel.componentName)
            .bold()
            .textCase(.none)
            .font(.headline)
            .foregroundColor(.primary)
    }
}

extension ComponentView {

    func debugView() -> ComponentDebugView<C> {
        ComponentDebugView(viewModel: model)
    }
}

struct ComponentDebugView_Previews: PreviewProvider {

    static var previews: some View {
        viewModelEvents = previewEvents
        return ExampleView(model: .init(state: .init(name: "Hello")))
            .debugView()
    }
}
