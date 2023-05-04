import Foundation
import SwiftUI
import SwiftPreview
import SwiftGUI

struct ComponentDashboardView<ComponentType: Component>: View {

    @ObservedObject var model: ViewModel<ComponentType.Model>

    @AppStorage("componentPreview.showView") var showView = true
    @AppStorage("componentPreview.showComponent") var showComponent = true
    @AppStorage("previewTests") var previewTests = true
    @State var showTestEvents = true
    @State var autoRunTests = true
    @State var testRun: TestRun<ComponentType.Model> = TestRun()
    @State var runningTests = false
    @State var render = UUID()
    @State var previewTestDelay = 0.3
    @State var showEvents: Set<EventSimpleType> = Set(EventSimpleType.allCases)//.subtracting([.mutation, .binding])

    var events: [Event] {
        EventStore.shared.events
    }

    func clearEvents() {
        EventStore.shared.clear()
        render = UUID()
    }

    func runAllTests(delay: TimeInterval) {
        Task { @MainActor in
            await runAllTestsOnMain(delay: delay)
        }
    }

    @MainActor
    func runAllTestsOnMain(delay: TimeInterval) async {
        testRun.reset(ComponentType.tests)
        for test in ComponentType.tests {
            await runTest(test, delay: delay)
        }
    }

    @MainActor
    func runTest(_ test: Test<ComponentType.Model>, delay: TimeInterval) async {
        runningTests = true
        testRun.startTest(test)

        guard let state = ComponentType.state(for: test) else {
            testRun.testState[test.name] = .failedToRun(TestError(error: "Could not find state", source: test.source))
            return
        }

        let model: ViewModel<ComponentType.Model>
        if delay > 0 {
            model = self.model
        } else {
            model = ViewModel(state: state)
        }
        let result = await model.runTest(test, initialState: state, assertions: ComponentType.testAssertions, delay: delay, sendEvents: delay > 0 && showTestEvents)
        testRun.completeTest(test, result: result)
        runningTests = false
    }

    func selectTest(_ test: Test<ComponentType.Model>) {
        clearEvents()
        Task { @MainActor in
            await runTest(test, delay: previewTestDelay)
        }
    }

    func selectState(_ state: ComponentState<ComponentType.Model>) {
        withAnimation {
            model.state = state.state
        }
        if let route = state.route {
            model.store.present(route, source: .capture())
        } else {
            model.store.dismissRoute(source: .capture())
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if showView {
                ComponentType.view(model: model)
//                ViewPreviewer(content: ComponentType.view(model: model), showEnvironmentPickers: false)
//                    .padding()
                    .frame(maxWidth: .infinity)
//                    .transition(.move(edge: .leading).animation(.default)) // won't animate for some reason
            }
            Divider()
            if showComponent {
                NavigationView {
                    form
                }
                .navigationViewStyle(.stack)
                .frame(maxWidth: .infinity)
//                .transition(.move(edge: .trailing).animation(.default)) // won't animate for some reason
            }
        }
        .task {
            runAllTests(delay: 0)
        }
//        .toolbar {
//            ToolbarItem(placement: .navigationBarLeading) {
//                Button(action: { withAnimation {
//                    showView.toggle()
//                    if !showComponent && !showView {
//                        showComponent = true
//                    }
//
//                }}) {
//                    Image(systemName: "rectangle.leadinghalf.inset.filled")
//                    Text("View")
//                }
//            }
//            ToolbarItem(placement: .navigationBarTrailing) {
//                Button(action: { withAnimation {
//                    showComponent.toggle()
//                    if !showComponent && !showView {
//                        showView = true
//                    }
//                }}) {
//                    Text("Model")
//                    Image(systemName: "rectangle.trailinghalf.inset.filled")
//                }
//            }
//        }
    }

    var form: some View {
        Form {
            if !ComponentType.states.isEmpty {
                statesSection
            }
            stateSection
            routeSection
            if !ComponentType.tests.isEmpty {
//                testSettingsSection
                testSection
            }
            eventsSection
        }
        .animation(.default, value: events.count + (model.route == nil ? 1 : 0))
    }

    var testSettingsSection: some View {
        Section(header: Text("Test Settings")) {
            Toggle("Auto Run Tests", isOn: $autoRunTests)
            Toggle("Preview Tests", isOn: $previewTests)
            Toggle("Show Test Events", isOn: $showTestEvents)
        }
    }

    var statesSection: some View {
        Section(header: Text("States")) {
            ForEach(ComponentType.states, id: \.name) { state in
                Button {
                    selectState(state)
                } label: {
                    Text(state.name)
                }
            }
        }
    }

    var stateSection: some View {
        Section(header: Text("State")) {
            SwiftView(value: model.binding(\.self), config: Config(editing: true))
                .showRootNavTitle(false)
        }
    }

    @ViewBuilder
    var routeSection: some View {
        if ComponentType.Model.Route.self != Never.self {
            Section(header: Text("Route")) {
                if let route = model.route {
                    HStack {
                        Text(getEnumCase(route).name)
                        Spacer()
                        Button(action: { withAnimation { model.route = nil } }) {
                            Text("Dismiss")
                        }
                    }
                } else {
                    Text("none")
                }
            }
        }
    }

    var testSection: some View {
        Section(header: testHeader) {
            ForEach(ComponentType.tests, id: \.name) { test in
                let testResult = testRun.getTestState(test)
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        selectTest(test)
                    } label: {
                        VStack(alignment: .leading) {
                            HStack(spacing: 8) {
                                ZStack {
                                    ProgressView().hidden()
                                    switch testResult {
                                        case .running:
                                            ProgressView().progressViewStyle(CircularProgressViewStyle())
                                        case .failedToRun:
                                            Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                                        case .complete(let result):
                                            if result.success {
                                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                            } else {
                                                Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                                            }
                                        case .notRun:
                                            Image(systemName: "circle")
                                        case .pending:
                                            Image(systemName: "play.circle").foregroundColor(.gray)
                                    }
                                }
                                .foregroundColor(testResult.color)
                                Text(test.name)
                                    .foregroundColor(testResult.color)
                                Spacer()
                                if let error = testResult.errors?.first {
                                    Text(error.error).foregroundColor(.red)
                                        .lineLimit(1)
                                }
                                Image(systemName: "play.circle")
                                    .font(.title3)
                                    .disabled(runningTests)
                            }
                            .animation(nil)
                            if let error = testResult.errors?.first {
                                VStack(alignment: .leading) {
                                    //                                    Text(error.error)
                                    //                                        .foregroundColor(.red)
                                    //                                        .lineLimit(1)
                                    //                                        .padding(.leading, 20)
                                    if let diff = error.diff {
                                        VStack(alignment: .leading) {
                                            diff
                                                .diffText()
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .textContainer()
                                                .cornerRadius(8)
                                        }
                                        .padding(4)
                                    }
                                }
                            }
                        }
                    }
                }

            }
        }
        .disabled(runningTests)
    }

    var testHeader: some View {
        HStack {
            Text("Tests")
            Spacer()
            Button {
                runAllTests(delay: previewTestDelay)
            } label: {
                Text("Play all")
            }
            .buttonStyle(.plain)
        }
    }

    var eventsSection: some View {
        Section(header: eventsHeader) {
            ComponentEventList(
                events: Array(events
                    .filter { showEvents.contains($0.type.type) }
                    .sorted { $0.start > $1.start }
                    .prefix(500)
                ),
                allEvents: events.sorted { $0.start > $1.start },
                indent: false)
                .id(render)
        }
        .onReceive(EventStore.shared.eventPublisher) { _ in
            render = UUID()
        }
    }

    var eventsHeader: some View {
        HStack {
            Text("Events")
            Spacer()
            Button(action: clearEvents) {
                Text("Clear")
            }
            .buttonStyle(.plain)
        }
    }
}

struct ComponentDashboard_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ComponentDashboardView<ExampleComponent>(model: ExampleComponent.states[0].viewModel())
        }
        .navigationViewStyle(.stack)
        .previewDevice(.largestDevice)
    }
}
