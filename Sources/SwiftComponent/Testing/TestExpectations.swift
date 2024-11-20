import Foundation

extension TestStep {

    public func expectOutput(_ output: Model.Output, file: StaticString = #filePath, line: UInt = #line) -> Self {
        addExpectation(title: "Expect Output", details: getEnumCase(output).name, file: file, line: line) { context in

            let foundOutput: Model.Output? = context.findEventValue { event in
                if case .output(let output) = event.type, let output = output as? Model.Output {
                    return output
                }
                return nil
            }
            if let foundOutput {
                if let difference = StateDump.diff(foundOutput, output) {
                    context.error("Unexpected output value \(getEnumCase(foundOutput).name.quoted)", diff: difference)
                }
            } else {
                context.error("Output \(getEnumCase(output).name.quoted) was not sent")
            }
        }
    }

    private func expectTask(name: String, successful: Bool?, file: StaticString = #filePath, line: UInt = #line) -> Self {
        let result: String
        switch successful {
        case .none:
            result = ""
        case false:
            result = "failure"
        case true:
            result = " success"
        default:
            result = ""
        }
        return addExpectation(title: "Expect Task", details: "\(name.quoted)\(result)", file: file, line: line) { context in
            let result: TaskResult? = context.findEventValue { event in
                if case .task(let taskResult) = event.type, taskResult.name == name {
                    return taskResult
                }
                return nil
            }
            if let result {
                switch result.result {
                    case .failure:
                        if successful == true {
                            context.error("Expected \(name.quoted) task to succeed, but it failed")
                        }
                    case .success:
                        if successful == false {
                            context.error("Expected \(name.quoted) task to fail, but it succeeded")
                        }
                }
            } else {
                context.error("Task \(name.quoted) was not sent")
            }
        }
    }

    public func expectTask(_ taskID: Model.Task, successful: Bool? = nil, file: StaticString = #filePath, line: UInt = #line) -> Self {
        expectTask(name: taskID.taskName, successful: successful, file: file, line: line)
    }

    public func expectDependency<Value>(_ keyPath: KeyPath<DependencyValues, Value>, file: StaticString = #filePath, line: UInt = #line) -> Self {
        addExpectation(title: "Expect dependency", details: keyPath.propertyName, file: file, line: line) { context in
            if let name = keyPath.propertyName {
                if !context.model.dependencies.accessedDependencies.contains(name) {
                    context.error("Expected accessed dependency \(name)")
                    context.model.dependencies.accessedDependencies.remove(name)
                }
            }
        }
    }

    //TODO: also clear mutation assertions
    public func expectResourceTask<R>(_ keyPath: KeyPath<Model.State, ResourceState<R>>, successful: Bool? = nil, file: StaticString = #filePath, line: UInt = #line) -> Self {
        expectTask(name: getResourceTaskName(keyPath), successful: successful, file: file, line: line)
            .expectState(keyPath.appending(path: \.isLoading), false, file: file, line: line)
    }

    public func expectEmptyRoute(file: StaticString = #filePath, line: UInt = #line) -> Self {
        addExpectation(title: "Expect empty route", file: file, line: line) { context in
            context.findEventValue { event in
                if case .dismissRoute = event.type {
                    return ()
                }
                return nil
            }
            if let route = context.model.route {
                context.error("Unexpected Route \(getEnumCase(route).name.quoted)")
            }
        }
    }

    public func expectRoute<Child: ComponentModel>(_ path: CasePath<Model.Route, ComponentRoute<Child>>, state expectedState: Child.State, childRoute: Child.Route? = nil, file: StaticString = #filePath, line: UInt = #line) -> Self {
        addExpectation(title: "Expect route", details: Child.baseName, file: file, line: line) { context in
            let foundRoute: Model.Route? = context.findEventValue { event in
                if case .route(let route) = event.type, let route = route as? Model.Route {
                    return route
                }
                return nil
            }
            if let route = foundRoute {
                if let foundComponentRoute = path.extract(from: route) {
                    if let difference = StateDump.diff(expectedState, foundComponentRoute.state) {
                        context.error("Unexpected state in route \(getEnumCase(route).name.quoted)", diff: difference)
                    }
                    // TODO: compare nested route
                } else {
                    context.error("Unexpected route \(getEnumCase(route).name.quoted)")
                }

            } else {
                context.error("Unexpected empty route")
            }
        }
    }

    public func validateDependency<T>(_ error: String, _ keyPath: KeyPath<DependencyValues, T>, _ validateDependency: @escaping (T) -> Bool, file: StaticString = #filePath, line: UInt = #line) -> Self {
        addExpectation(title: "Validate dependency", details: String(describing: T.self).quoted, file: file, line: line) { context in
            let dependency = context.model.dependencies[dynamicMember: keyPath]
            let valid = validateDependency(dependency)
            if !valid {
                context.error("Invalid \(dependency): \(error)")
            }
        }
    }

    /// validate some properties on state by returning a boolean
    public func validateState(_ name: String, file: StaticString = #filePath, line: UInt = #line, _ validateState: @escaping (Model.State) -> Bool) -> Self {
        addExpectation(title: "Validate", details: name, file: file, line: line) { context in
            let valid = validateState(context.model.state)
            if !valid {
                context.error("Invalid State \(name.quoted)")
            }
        }
    }

    /// expect state to have certain properties set. Set any properties on the state that should be set. Any properties left out fill not fail the test
    public func expectState(file: StaticString = #filePath, line: UInt = #line, _ modify: @escaping (inout Model.State) -> Void) -> Self {
        addExpectation(title: "Expect State", file: file, line: line) { context in
            let currentState = context.model.state
            var expectedState = currentState
            modify(&expectedState)
            modify(&context.testContext.state)
            if let difference = StateDump.diff(expectedState, currentState) {
                context.error("Unexpected State", diff: difference)
            }
        }
    }

    // Used for getters
    /// expect state to have a keypath set to a value.
    public func expectState<Value>(_ keyPath: KeyPath<Model.State, Value>, _ value: Value, file: StaticString = #filePath, line: UInt = #line) -> Self {
        addExpectation(title: "Expect \(keyPath.propertyName ?? "State")", file: file, line: line) { context in
            let currentState = context.model.state[keyPath: keyPath]
            if let difference = StateDump.diff(value, currentState) {
                context.error("Unexpected \(keyPath.propertyName?.quoted ?? "State")", diff: difference)
            }
        }
    }

    // Used for instance variables
    /// expect state to have a keypath set to a value.
    public func expectState<Value>(_ keyPath: WritableKeyPath<Model.State, Value>, _ value: Value, file: StaticString = #filePath, line: UInt = #line) -> Self {
        addExpectation(title: "Expect \(keyPath.propertyName ?? "State")", file: file, line: line) { context in
            let currentState = context.model.state
            var expectedState = currentState
            expectedState[keyPath: keyPath] = value
            context.testContext.state[keyPath: keyPath] = value
            if let difference = StateDump.diff(expectedState, currentState) {
                context.error("Unexpected \(keyPath.propertyName?.quoted ?? "State")", diff: difference)
            }
        }
    }
    
    // Used for getters
    /// expect environment to have a keypath set to a value.
    public func expectEnvironment<Value>(_ keyPath: KeyPath<Model.Environment, Value>, _ value: Value, file: StaticString = #filePath, line: UInt = #line) -> Self {
        addExpectation(title: "Expect \(keyPath.propertyName ?? "Environment")", file: file, line: line) { context in
            let currentState = context.model.environment[keyPath: keyPath]
            if let difference = StateDump.diff(value, currentState) {
                context.error("Unexpected \(keyPath.propertyName?.quoted ?? "Environment")", diff: difference)
            }
        }
    }

}
