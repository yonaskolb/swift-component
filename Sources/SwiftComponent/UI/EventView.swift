import Foundation
import SwiftUI
import SwiftGUI

struct ComponentEventList: View {

    let events: [ComponentEvent]
    let allEvents: [ComponentEvent]
    var depth: Int = 0
    @State var showEvent: UUID?
    @State var showMutation: UUID?

    func eventDepth(_ event: ComponentEvent) -> Int {
        max(0, event.depth - depth)
    }

    var body: some View {
        ForEach(events) { event in
            NavigationLink(tag: event.id, selection: $showEvent, destination: {
                EventView(event: event, allEvents: allEvents)
            }) {
                HStack {
//                    if eventDepth(event) > 0 {
//                        Image(systemName: "arrow.turn.down.right")
//                            .opacity(0.3)
//                            .font(.system(size: 14))
//                            .padding(.top, 14)
//                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.componentPath.string)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.leading, 18)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(event.type.color)
                                .frame(width: 12)
                            Text(event.type.title)
                                .bold()
                        }
                    }
                    .font(.footnote)
                    Spacer()
                    Text(event.type.details)
                        .font(.footnote)
                }
                .padding(.leading, 16*Double(max(0, eventDepth(event)))) // inset children
            }
        }
    }
}

struct EventView: View {

    let event: ComponentEvent
    var allEvents: [ComponentEvent]
    var childEvents: [ComponentEvent] { allEvents.filter { $0.start > event.start && $0.end < event.end } }
    var parentEvents: [ComponentEvent] { allEvents.filter { $0.start < event.start && $0.end > event.end } }
    @State var showValue = false
    @State var showMutation: UUID?

    var body: some View {
        Form {
            if !event.type.detailsTitle.isEmpty || !event.type.details.isEmpty || !event.type.valueTitle.isEmpty {
                Section {
                    if !event.type.detailsTitle.isEmpty || !event.type.details.isEmpty {
                        line(event.type.detailsTitle) {
                            Text(event.type.details)
                        }
                    }
                    if !event.type.valueTitle.isEmpty {
                        NavigationLink(isActive: $showValue) {
                            SwiftView(value: .constant(event.type.value), config: Config(editing: false))
                        } label: {
                            line(event.type.valueTitle) {
                                Text(dumpLine(event.type.value))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            Section {
                if let path = event.componentPath.parent {
                    line("Path") {
                        Text(path.string)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                line("Component") {
                    Text(event.componentName)
                }
                line("Started") {
                    Text(event.start.formatted())
                }
                line("Duration") {
                    Text(event.duration)
                }
                line("Location") {
                    Text(verbatim: "\(event.source.file)#\(event.source.line.formatted())")
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                line("Depth") {
                    Text(event.depth.formatted())
                }
            }
            if !parentEvents.isEmpty {
                Section("Parents") {
                    ComponentEventList(events: parentEvents, allEvents: allEvents, depth: 0)
                }
            }
            if !childEvents.isEmpty {
                Section("Children") {
                    ComponentEventList(events: childEvents, allEvents: allEvents, depth: event.depth + 1)
                }
            }
        }
        .navigationTitle(Text(event.type.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    func line<Content: View>(_ name: String, content: () -> Content) -> some View {
        HStack {
            Text(name)
                .bold()
            Spacer()
            content()
        }
    }
}

let previewEvents: [ComponentEvent] = [
        ComponentEvent(
            type: .appear(first: true),
            componentPath: .init([ExampleComponent.self]),
            start: Date().addingTimeInterval(-1.05),
            end: Date(),
            mutations: [
                Mutation(keyPath: \ExampleComponent.State.name, value: "new1"),
                Mutation(keyPath: \ExampleComponent.State.name, value: "new2"),
            ],
            depth: 0,
            source: .capture()
        ),

        ComponentEvent(
            type: .action(ExampleComponent.Action.tap(2)),
            componentPath: .init([ExampleComponent.self, ExampleSubComponent.self]),
            start: Date(),
            end: Date(),
            mutations: [
                Mutation(keyPath: \ExampleComponent.State.name, value: "new1"),
                Mutation(keyPath: \ExampleComponent.State.name, value: "new2"),
            ],
            depth: 0,
            source: .capture()
        ),

        ComponentEvent(
            type: .binding(Mutation(keyPath: \ExampleComponent.State.name, value: "Hello")),
            componentPath: .init(ExampleComponent.self),
            start: Date(),
            end: Date(),
            mutations: [Mutation(keyPath: \ExampleComponent.State.name, value: "Hello")],
            depth: 1,
            source: .capture()
        ),

        ComponentEvent(
            type: .mutation(Mutation(keyPath: \ExampleComponent.State.name, value: "Hello")),
            componentPath: .init(ExampleComponent.self),
            start: Date(),
            end: Date(),
            mutations: [Mutation(keyPath: \ExampleComponent.State.name, value: "Hello")],
            depth: 2,
            source: .capture()
        ),

        ComponentEvent(
            type: .task(TaskResult.init(name: "get item", result: .success(()))),
            componentPath: .init(ExampleComponent.self),
            start: Date().addingTimeInterval(-2.3),
            end: Date(),
            mutations: [],
            depth: 0,
            source: .capture()
        ),

        ComponentEvent(
            type: .output(ExampleComponent.Output.finished),
            componentPath: .init(ExampleComponent.self),
            start: Date(),
            end: Date(),
            mutations: [],
            depth: 2,
            source: .capture()
        ),
    ]

struct EventView_Previews: PreviewProvider {
    static var previews: some View {
        EventStore.shared.events = previewEvents
        return Group {
            NavigationView {
                EventView(event: previewEvents[1], allEvents: previewEvents)
            }
            .navigationViewStyle(.stack)
            ExampleView(model: .init(state: .init(name: "Hello")))
                .debugView()
                .navigationViewStyle(.stack)
        }

    }
}
