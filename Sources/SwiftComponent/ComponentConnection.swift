import Foundation
import SwiftUI
import CasePaths

public struct ModelConnection<From: ComponentModel, To: ComponentModel> {

    let id = UUID()
    var output: OutputHandler<From, To>
    var environment: EnvironmentHandler
    var action: ActionHandler<From, To>?
    var setDependencies: (From, inout DependencyValues) -> Void = { _, _ in }
    
    public typealias EnvironmentHandler = @MainActor (From, AnyHashable?) -> To.Environment

    public init(output: OutputHandler<From, To>, environment: @escaping EnvironmentHandler) {
        self.output = output
        self.environment = environment
    }

    public init() where To.Output == Never, From.Environment == To.Environment {
        self.init(output: .ignore) { model, _ in model.environment }
    }
    
    public init() where To.Output == Never, From.Environment.Parent == To.Environment {
        self.init(output: .ignore) { model, _ in model.environment.parent }
    }

    public init(environment: @escaping EnvironmentHandler) where To.Output == Never {
        self.init(output: .ignore, environment: environment)
    }

    public init(output: OutputHandler<From, To>) where From.Environment == To.Environment {
        self.init(output: output) { model, _ in model.environment }
    }
    
    public init(output: OutputHandler<From, To>) where From.Environment.Parent == To.Environment {
        self.init(output: output) { model, _ in model.environment.parent }
    }
    
    public init(output: @escaping (To.Output) -> From.Input) where From.Environment == To.Environment {
        self.init(output: .input(output)) { model, _ in model.environment }
    }
    
    public init(output: @escaping (To.Output) -> From.Input) where From.Environment.Parent == To.Environment {
        self.init(output: .input(output)) { model, _ in model.environment.parent }
    }
    
    public init(output: @escaping (To.Output) -> From.Input, environment: @escaping EnvironmentHandler) {
        self.init(output: .input(output), environment: environment)
    }

    public init(_ output: @MainActor @escaping (ConnectionOutputContext<From, To>) async -> Void) where From.Environment == To.Environment {
        self.init(output: .handle(output)) { model, _ in model.environment }
    }
    
    public init(_ output: @MainActor @escaping (ConnectionOutputContext<From, To>) async -> Void) where From.Environment.Parent == To.Environment {
        self.init(output: .handle(output)) { model, _ in model.environment.parent }
    }

    @MainActor
    func connectedStore(from: ComponentStore<From>, state: ScopedState<From.State, To.State>, id: AnyHashable? = nil) -> ComponentStore<To> {
        let connectionID = ConnectionID(
            connectionID: self.id,
            storeID: from.id,
            childTypeName: String(describing: To.self),
            stateID: state.id,
            customID: id
        )
        if let existingStore = from.children[connectionID]?.value as? ComponentStore<To> {
            return existingStore
        }
        var childStore = from.scope(
            state: state,
            environment: self.environment(from.model, id),
            output: self.output
        )
        
        // set dependencies
        setDependencies(from.model, &childStore.dependencies.dependencyValues)
        
        from.children[connectionID] = .init(childStore)

        if let actionHandler = self.action {
            childStore = childStore
                .onAction { @MainActor action, _ in
                    switch actionHandler {
                    case .output(let toOutput):
                        let output = toOutput(action)
                        from.output(output, source: .capture())
                    case .input(let toInput):
                        let input = toInput(action)
                        from.processInput(input, source: .capture())
                    case .handle(let handler):
                        from.addTask {
                            await handler((action: action, model: from.model))
                        }
                    }
                }
        }

        return childStore
    }

    public func onAction(_ handle: @MainActor @escaping (ConnectionActionContext<From, To>) -> Void) -> Self {
        self.onAction(.handle(handle))
    }
    
    public func onAction(_ action: ActionHandler<From, To>) -> Self {
        var copy = self
        copy.action = action
        return copy
    }
    
    public func dependency<T>(_ keyPath: WritableKeyPath<DependencyValues, T>, value: T) -> Self {
        dependency(keyPath) { _ in value }
    }
    
    public func dependency<T>(_ keyPath: WritableKeyPath<DependencyValues, T>, getValue: @escaping (From) -> T) -> Self {
        var copy = self
        let originalSetDependencies = copy.setDependencies
        copy.setDependencies = { model, dependencies in
            originalSetDependencies(model, &dependencies)
            dependencies[keyPath: keyPath] = getValue(model)
        }
        return copy
    }
}

public typealias ConnectionOutputContext<Parent: ComponentModel, Child: ComponentModel> = (output: Child.Output, model: Parent)
public typealias ConnectionActionContext<Parent: ComponentModel, Child: ComponentModel> = (action: Child.Action, model: Parent)

struct ConnectionID: Hashable {
    let connectionID: UUID
    let storeID: UUID
    let childTypeName: String
    let stateID: AnyHashable?
    let customID: AnyHashable?
}

extension ViewModel {

    @dynamicMemberLookup
    public struct Connections {

        let model: ViewModel<Model>

        @MainActor
        public subscript<Child: ComponentModel>(dynamicMember keyPath: KeyPath<Model.Connections, EmbeddedComponentConnection<Model, Child>>) -> ViewModel<Child> {
            model.connectedModel(keyPath)
        }
    }

    public var connections: Connections { Connections(model: self) }
    
    @dynamicMemberLookup
    public struct Presentations {

        let model: ViewModel<Model>

        @MainActor
        public subscript<Child: ComponentModel>(dynamicMember keyPath: KeyPath<Model.Connections, PresentedComponentConnection<Model, Child>>) -> Binding<ViewModel<Child>?> {
            model.presentedModel(keyPath)
        }
        
        @MainActor
        public subscript<Child: ComponentModel, Case: CasePathable>(dynamicMember keyPath: KeyPath<Model.Connections, PresentedCaseComponentConnection<Model, Child, Case>>) -> Binding<ViewModel<Child>?> {
            model.presentedModel(keyPath)
        }
    }

    public var presentations: Presentations { Presentations(model: self) }
}

extension ComponentView {

    public var connections: ViewModel<Model>.Connections { model.connections }
}

extension ViewModel { 

    @MainActor
    func connect<Child: ComponentModel>(to connectionPath: KeyPath<Model.Connections, ModelConnection<Model, Child>>, state: ScopedState<Model.State, Child.State>, id: AnyHashable? = nil) -> ViewModel<Child> {
        let connection = store.model.connections[keyPath: connectionPath]
        let store = connection.connectedStore(from: store, state: state, id: id)
        
        // cache view models
        if let model = children[store.id]?.value as? ViewModel<Child> {
            return model
        } else {
            let model = store.viewModel()
            children[store.id] = .init(model)
            return model
        }
    }
}

extension ViewModel {

    @MainActor
    public func connectedModel<Child: ComponentModel>(_ connection: KeyPath<Model.Connections, ModelConnection<Model, Child>>, state: Child.State, id: AnyHashable?) -> ViewModel<Child> {
        connect(to: connection, state: .value(state), id: id)
    }
    
    @MainActor
    public func connectedModel<Child: ComponentModel>(_ connection: KeyPath<Model.Connections, ModelConnection<Model, Child>>, state: Child.State) -> ViewModel<Child> where Child.State: Hashable {
        connect(to: connection, state: .value(state), id: state)
    }

    @MainActor
    public func connectedModel<Child: ComponentModel>(_ connection: KeyPath<Model.Connections, ModelConnection<Model, Child>>, state: Binding<Child.State>) -> ViewModel<Child> {
        connect(to: connection, state: .binding(state))
    }

    @MainActor
    public func connectedModel<Child: ComponentModel>(_ connectionPath: KeyPath<Model.Connections, EmbeddedComponentConnection<Model, Child>>) -> ViewModel<Child> {
        let connection = store.model.connections[keyPath: connectionPath]
        return connect(to: connectionPath.appending(path: \.connection), state: .keyPath(connection.state))
    }

    @MainActor
    public func connectedModel<Child: ComponentModel>(_ connectionPath: KeyPath<Model.Connections, PresentedComponentConnection<Model, Child>>, state: Child.State) -> ViewModel<Child> {
        let connection = store.model.connections[keyPath: connectionPath]
        return connect(to: connectionPath.appending(path: \.connection), state: .optionalKeyPath(connection.state, fallback: state))
    }
    
    @MainActor
    public func connectedModel<Child: ComponentModel, Case: CasePathable>(_ connectionPath: KeyPath<Model.Connections, PresentedCaseComponentConnection<Model, Child, Case>>, state: Child.State) -> ViewModel<Child> {
        let connection = store.model.connections[keyPath: connectionPath]
        return connect(to: connectionPath.appending(path: \.connection), state: store.caseScopedState(state: connection.state, case: connection.casePath, value: state))
    }
}

// presentation binding
extension ViewModel {

    @MainActor
    public func presentedModel<Child: ComponentModel>(_ connectionPath: KeyPath<Model.Connections, PresentedComponentConnection<Model, Child>>) -> Binding<ViewModel<Child>?> {
        let connection = store.model.connections[keyPath: connectionPath]
        return presentedModel(connectionPath.appending(path: \.connection), state: connection.state)
    }
    
    @MainActor
    public func presentedModel<Child: ComponentModel, Case: CasePathable>(_ connectionPath: KeyPath<Model.Connections, PresentedCaseComponentConnection<Model, Child, Case>>) -> Binding<ViewModel<Child>?> {
        let connection = store.model.connections[keyPath: connectionPath]
        return presentedModel(connectionPath.appending(path: \.connection), state: connection.state, case: connection.casePath)
    }
    
    @MainActor
    public func presentedModel<Child: ComponentModel>(_ connection: KeyPath<Model.Connections, ModelConnection<Model, Child>>, state: WritableKeyPath<Model.State, Child.State?>) -> Binding<ViewModel<Child>?> {
        Binding(
            get: {
                if let presentedState = self.store.state[keyPath: state] {
                    return self.connect(to: connection, state: .optionalKeyPath(state, fallback: presentedState))
                } else {
                    return nil
                }
            },
            set: { model in
                if model == nil, self.state[keyPath: state] != nil {
                    self.state[keyPath: state] = nil
                }
            }
        )
    }
    
    @MainActor
    public func presentedModel<Child: ComponentModel, StateEnum: CasePathable>(_ connection: KeyPath<Model.Connections, ModelConnection<Model, Child>>, state statePath: WritableKeyPath<Model.State, StateEnum?>, case casePath: CaseKeyPath<StateEnum, Child.State>) -> Binding<ViewModel<Child>?> {
        Binding<ViewModel<Child>?>(
            get: {
                if let enumCase = self.store.state[keyPath: statePath],
                   let presentedState = enumCase[case: casePath] {
                    return self.connect(to: connection, state: self.store.caseScopedState(state: statePath, case: casePath, value: presentedState))
                } else {
                    return nil
                }
            },
            set: { model in
                if model == nil, self.state[keyPath: statePath] != nil {
                    self.state[keyPath: statePath] = nil
                }
            }
        )
    }
}

extension ComponentModel {

    public func connection<To: ComponentModel>(_ connectionPath: KeyPath<Connections, ModelConnection<Self, To>>, state: ScopedState<State, To.State>, id: AnyHashable? = nil, update: @MainActor (To) async -> Void) async {
        let connection = self.connections[keyPath: connectionPath]
        let store = connection.connectedStore(from: store, state: state, id: id)
        await update(store.model)
    }

    public func connection<To: ComponentModel>(_ connectionPath: KeyPath<Connections, EmbeddedComponentConnection<Self, To>>, id: AnyHashable? = nil, _ update: @MainActor (To) async -> Void) async {
        let connection = store.model.connections[keyPath: connectionPath]
        await self.connection(connectionPath.appending(path: \.connection), state: .keyPath(connection.state), id: id, update: update)
    }

    public func connection<To: ComponentModel>(_ connectionPath: KeyPath<Connections, PresentedComponentConnection<Self, To>>, id: AnyHashable? = nil, _ update: @MainActor (To) async -> Void) async {
        let connection = store.model.connections[keyPath: connectionPath]
        guard let state = self.store.state[keyPath: connection.state] else { return }
        await self.connection(connectionPath.appending(path: \.connection), state: .optionalKeyPath(connection.state, fallback: state), id: id, update: update)
    }
    
    public func connection<To: ComponentModel, Case: CasePathable>(_ connectionPath: KeyPath<Connections, PresentedCaseComponentConnection<Self, To, Case>>, id: AnyHashable? = nil, _ update: @MainActor (To) async -> Void) async {
        let connection = store.model.connections[keyPath: connectionPath]
        guard let `case` = self.store.state[keyPath: connection.state], let state = `case`[case: connection.casePath] else { return }
        await self.connection(connectionPath.appending(path: \.connection), state: self.store.caseScopedState(state: connection.state, case: connection.casePath, value: state), id: id, update: update)
    }

    public func connection<To: ComponentModel>(_ connectionPath: KeyPath<Connections, ModelConnection<Self, To>>, state: WritableKeyPath<Self.State, To.State?>, id: AnyHashable? = nil, _ update: @MainActor (To) async -> Void) async {
        guard let childState = store.state[keyPath: state] else { return }
        await self.connection(connectionPath, state: .optionalKeyPath(state, fallback: childState), id: id, update: update)
    }
    
    public func connection<To: ComponentModel>(_ connectionPath: KeyPath<Connections, ModelConnection<Self, To>>, state: To.State, id: AnyHashable? = nil, _ update: @MainActor (To) async -> Void) async {
        await self.connection(connectionPath, state: .value(state), id: id, update: update)
    }
}

public enum OutputHandler<Parent: ComponentModel, Child: ComponentModel> {
    case output((Child.Output) -> Parent.Output)
    case input((Child.Output) -> Parent.Input)
    case handle((ConnectionOutputContext<Parent, Child>) async -> Void)
    case ignore
}

public enum ActionHandler<Parent: ComponentModel, Child: ComponentModel> {
    case output((Child.Action) -> Parent.Output)
    case input((Child.Action) -> Parent.Input)
    case handle((ConnectionActionContext<Parent, Child>) async -> Void)
}

// ModelConnection
extension TestStep {

    @MainActor
    public static func connection<Child: ComponentModel>(
        _ connection: KeyPath<Model.Connections, ModelConnection<Model, Child>>,
        state: Child.State,
        file: StaticString = #filePath,
        line: UInt = #line,
        @TestStepBuilder<Child> steps: @escaping () -> [TestStep<Child>]
    ) -> Self {
        Self.connection(connection, state: .value(state), file: file, line: line, steps: steps)
    }

    @MainActor
    public static func connection<Child: ComponentModel>(
        _ connection: KeyPath<Model.Connections, ModelConnection<Model, Child>>,
        state: ScopedState<Model.State, Child.State>,
        file: StaticString = #filePath,
        line: UInt = #line,
        @TestStepBuilder<Child> steps: @escaping () -> [TestStep<Child>]
    ) -> Self {
        .init(
            title: "Connection",
            details: "\(Child.baseName)",
            file: file,
            line: line
        ) { context in
            if context.delay > 0 {
                try? await Task.sleep(nanoseconds: context.delayNanoseconds)
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000.0 * 0.35)) // wait for typical presentation animation duration
            }

            let steps = steps()
            let model = context.model.connect(to: connection, state: state)
            var childContext = TestContext<Child>(model: model, delay: context.delay, assertions: context.assertions, state: model.state)
            for step in steps {
                let results = await step.runTest(context: &childContext)
                context.childStepResults.append(results)
            }
        }
    }

    @MainActor
    public static func connection<Child: ComponentModel>(
        _ connection: KeyPath<Model.Connections, ModelConnection<Model, Child>>,
        state: ScopedState<Model.State, Child.State>,
        output: Child.Output,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        .init(
            title: "Connection Output",
            details: "\(Child.baseName).\(getEnumCase(output).name)",
            file: file,
            line: line
        ) { context in
            let model = context.model.connect(to: connection, state: state)
            await model.store.outputAndWait(output, source: .capture(file: file, line: line))
        }
    }

    @MainActor
    public static func connection<Child: ComponentModel>(
        _ connection: KeyPath<Model.Connections, ModelConnection<Model, Child>>,
        state keyPath: WritableKeyPath<Model.State, Child.State?>,
        output: Child.Output,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        .init(
            title: "Connection Output",
            details: "\(Child.baseName).\(getEnumCase(output).name)",
            file: file,
            line: line
        ) { context in
            guard let state = context.model.state[keyPath: keyPath] else {
                context.stepErrors.append(.init(error: "\(keyPath.propertyName ?? Child.baseName) not connected", source: .init(file: file, line: line)))
                return
            }
            let model = context.model.connect(to: connection, state: .optionalKeyPath(keyPath, fallback: state))
            await model.store.outputAndWait(output, source: .capture(file: file, line: line))
        }
    }
    
    @MainActor
    public static func connection<Child: ComponentModel, Case: CasePathable>(
        _ connection: KeyPath<Model.Connections, ModelConnection<Model, Child>>,
        state keyPath: WritableKeyPath<Model.State, Case?>,
        case casePath: CaseKeyPath<Case, Child.State>,
        output: Child.Output,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        .init(
            title: "Connection Output",
            details: "\(Child.baseName).\(getEnumCase(output).name)",
            file: file,
            line: line
        ) { context in
            guard let `case` = context.model.state[keyPath: keyPath], let state = `case`[case: casePath] else {
                context.stepErrors.append(.init(error: "\(keyPath.propertyName ?? Child.baseName) not connected", source: .init(file: file, line: line)))
                return
            }
            let model = context.model.connect(to: connection, state: context.model.store.caseScopedState(state: keyPath, case: casePath, value: state))
            await model.store.outputAndWait(output, source: .capture(file: file, line: line))
        }
    }
    
    @MainActor
    public static func connection<Child: ComponentModel, Case: CasePathable>(
        _ connection: KeyPath<Model.Connections, ModelConnection<Model, Child>>,
        state keyPath: WritableKeyPath<Model.State, Case?>,
        case casePath: CaseKeyPath<Case, Child.State>,
        file: StaticString = #filePath,
        line: UInt = #line,
        @TestStepBuilder<Child> steps: @escaping () -> [TestStep<Child>]
    ) -> Self {
        .init(
            title: "Connection",
            details: "\(Child.baseName)",
            file: file,
            line: line
        ) { context in
            guard let `case` = context.model.state[keyPath: keyPath], let state = `case`[case: casePath] else {
                context.stepErrors.append(.init(error: "\(keyPath.propertyName ?? Child.baseName) not connected", source: .init(file: file, line: line)))
                return
            }

            if context.delay > 0 {
                try? await Task.sleep(nanoseconds: context.delayNanoseconds)
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000.0 * 0.35)) // wait for typical presentation animation duration
            }

            let steps = steps()
            let model = context.model.connect(to: connection, state: context.model.store.caseScopedState(state: keyPath, case: casePath, value: state))
            var childContext = TestContext<Child>(model: model, delay: context.delay, assertions: context.assertions, state: model.state)
            for step in steps {
                let results = await step.runTest(context: &childContext)
                context.childStepResults.append(results)
            }
        }
    }

    @MainActor
    public static func connection<Child: ComponentModel>(
        _ connection: KeyPath<Model.Connections, ModelConnection<Model, Child>>,
        state keyPath: WritableKeyPath<Model.State, Child.State?>,
        file: StaticString = #filePath,
        line: UInt = #line,
        @TestStepBuilder<Child> steps: @escaping () -> [TestStep<Child>]
    ) -> Self {
        .init(
            title: "Connection",
            details: "\(Child.baseName)",
            file: file,
            line: line
        ) { context in
            guard let state = context.model.state[keyPath: keyPath] else {
                context.stepErrors.append(.init(error: "\(keyPath.propertyName ?? Child.baseName) not connected", source: .init(file: file, line: line)))
                return
            }

            if context.delay > 0 {
                try? await Task.sleep(nanoseconds: context.delayNanoseconds)
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000.0 * 0.35)) // wait for typical presentation animation duration
            }

            let steps = steps()
            let model = context.model.connect(to: connection, state: .optionalKeyPath(keyPath, fallback: state))
            var childContext = TestContext<Child>(model: model, delay: context.delay, assertions: context.assertions, state: model.state)
            for step in steps {
                let results = await step.runTest(context: &childContext)
                context.childStepResults.append(results)
            }
        }
    }
}

extension TestStep {
    
    @MainActor
    public static func connection<Child: ComponentModel>(
        _ connection: KeyPath<Model.Connections, ModelConnection<Model, Child>>,
        file: StaticString = #filePath,
        line: UInt = #line,
        steps: @escaping () -> [TestStep<Child>],
        createModel: @escaping (inout TestContext<Model>) -> (ViewModel<Child>?)
    ) -> Self {
        .steps(
            title: "Connection",
            details: "\(Child.baseName)",
            file: file,
            line: line,
            steps: steps,
            createModel: createModel
        )
    }
    
    @MainActor
    public static func connection<Child: ComponentModel>(
        _ connection: KeyPath<Model.Connections, ModelConnection<Model, Child>>,
        file: StaticString = #filePath,
        line: UInt = #line,
        output: Child.Output,
        createModel: @escaping (inout TestContext<Model>) -> ViewModel<Child>?
    ) -> Self {
        .init(
            title: "Connection",
            details: "\(Child.baseName)",
            file: file,
            line: line
        ) { context in
            guard let model = createModel(&context) else { return }
            await model.store.outputAndWait(output, source: .capture(file: file, line: line))
        }
    }
}

// ModelConnection.connected
extension TestStep {
    
    @MainActor
    public static func connection<Child: ComponentModel>(
        _ connectionPath: KeyPath<Model.Connections, EmbeddedComponentConnection<Model, Child>>,
        output: Child.Output,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        self.connection(connectionPath.appending(path: \.connection), output: output) { context in
            let connection = context.model.store.model.connections[keyPath: connectionPath]
            return context.model.connect(to: connectionPath.appending(path: \.connection), state: .keyPath(connection.state))
        }

    }

    @MainActor
    public static func connection<Child: ComponentModel>(
        _ connectionPath: KeyPath<Model.Connections, EmbeddedComponentConnection<Model, Child>>,
        file: StaticString = #filePath,
        line: UInt = #line,
        @TestStepBuilder<Child> steps: @escaping () -> [TestStep<Child>]
    ) -> Self {
        self.connection(connectionPath.appending(path: \.connection), steps: steps) { context in
            let connection = context.model.store.model.connections[keyPath: connectionPath]
            return context.model.connect(to: connectionPath.appending(path: \.connection), state: .keyPath(connection.state))
        }
    }

    @MainActor
    public static func connection<Child: ComponentModel>(
        _ connectionPath: KeyPath<Model.Connections, PresentedComponentConnection<Model, Child>>,
        file: StaticString = #filePath,
        line: UInt = #line,
        @TestStepBuilder<Child> steps: @escaping () -> [TestStep<Child>]
    ) -> Self {
        self.connection(connectionPath.appending(path: \.connection), steps: steps) { context in
            let connection = context.model.store.model.connections[keyPath: connectionPath]
            guard let state = context.model.state[keyPath: connection.state] else {
                context.stepErrors.append(.init(error: "\(connection.state.propertyName ?? Child.baseName) not connected", source: .init(file: file, line: line)))
                return nil
            }

            return context.model.connect(to: connectionPath.appending(path: \.connection), state: .optionalKeyPath(connection.state, fallback: state))
        }
    }

    @MainActor
    public static func connection<Child: ComponentModel>(
        _ connectionPath: KeyPath<Model.Connections, PresentedComponentConnection<Model, Child>>,
        output: Child.Output,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        self.connection(connectionPath.appending(path: \.connection), output: output) { context in
            let connection = context.model.store.model.connections[keyPath: connectionPath]
            guard let state = context.model.state[keyPath: connection.state] else {
                context.stepErrors.append(.init(error: "\(connection.state.propertyName ?? Child.baseName) not connected", source: .init(file: file, line: line)))
                return nil
            }

            return context.model.connect(to: connectionPath.appending(path: \.connection), state: .optionalKeyPath(connection.state, fallback: state))
        }
    }
    
    @MainActor
    public static func connection<Child: ComponentModel, Case: CasePathable>(
        _ connectionPath: KeyPath<Model.Connections, PresentedCaseComponentConnection<Model, Child, Case>>,
        file: StaticString = #filePath,
        line: UInt = #line,
        @TestStepBuilder<Child> steps: @escaping () -> [TestStep<Child>]
    ) -> Self {
        self.connection(connectionPath.appending(path: \.connection), steps: steps) { context in
            let connection = context.model.store.model.connections[keyPath: connectionPath]
            guard let `case` = context.model.state[keyPath: connection.state], let state = `case`[case: connection.casePath] else {
                context.stepErrors.append(.init(error: "\(connection.state.propertyName ?? Child.baseName) not connected", source: .init(file: file, line: line)))
                return nil
            }
            return context.model.connect(to: connectionPath.appending(path: \.connection), state: context.model.store.caseScopedState(state: connection.state, case: connection.casePath, value: state))
        }
    }
    
    @MainActor
    public static func connection<Child: ComponentModel, Case: CasePathable>(
        _ connectionPath: KeyPath<Model.Connections, PresentedCaseComponentConnection<Model, Child, Case>>,
        output: Child.Output,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Self {
        self.connection(connectionPath.appending(path: \.connection), output: output) { context in
            let connection = context.model.store.model.connections[keyPath: connectionPath]
            guard let `case` = context.model.state[keyPath: connection.state], let state = `case`[case: connection.casePath] else {
                context.stepErrors.append(.init(error: "\(connection.state.propertyName ?? Child.baseName) not connected", source: .init(file: file, line: line)))
                return nil
            }
            return context.model.connect(to: connectionPath.appending(path: \.connection), state: context.model.store.caseScopedState(state: connection.state, case: connection.casePath, value: state))
        }
    }
}

public struct EmbeddedComponentConnection<From: ComponentModel, To: ComponentModel> {

    public let connection: ModelConnection<From, To>
    public let state: WritableKeyPath<From.State, To.State>
}

public struct PresentedComponentConnection<From: ComponentModel, To: ComponentModel> {

    public let connection: ModelConnection<From, To>
    public let state: WritableKeyPath<From.State, To.State?>
}

public struct PresentedCaseComponentConnection<From: ComponentModel, To: ComponentModel, Case: CasePathable> {

    public let connection: ModelConnection<From, To>
    public let state: WritableKeyPath<From.State, Case?>
    public let casePath: CaseKeyPath<Case, To.State>
}

extension ModelConnection {

    public func connect(state: WritableKeyPath<From.State, To.State>) -> EmbeddedComponentConnection<From, To> {
        EmbeddedComponentConnection(connection: self, state: state)
    }

    public func connect(state: WritableKeyPath<From.State, To.State?>) -> PresentedComponentConnection<From, To> {
        PresentedComponentConnection(connection: self, state: state)
    }
    
    public func connect<Case: CasePathable>(state: WritableKeyPath<From.State, Case?>, case casePath: CaseKeyPath<Case, To.State>) -> PresentedCaseComponentConnection<From, To, Case> {
        PresentedCaseComponentConnection(connection: self, state: state, casePath: casePath)
    }
}
