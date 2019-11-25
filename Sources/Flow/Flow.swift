import Foundation
import Combine

public protocol FlowAction {}

public protocol FlowState {}

public struct Command<Action: FlowAction> {
    public let execute: (@escaping SendFunction<Action>) -> Void
    
    public init(_ execute: @escaping (@escaping SendFunction<Action>) -> Void) {
        self.execute = execute
    }
}

public struct Reducer<State: FlowState, Action: FlowAction> {
    let reduce: (inout State, Action) -> [Command<Action>]?
    
    public init(_ reduce: @escaping (inout State, Action) -> [Command<Action>]?) {
        self.reduce = reduce
    }
}

public typealias SendFunction<Action: FlowAction> = (Action) -> ()

public typealias Middleware<State: FlowState, Action: FlowAction> = (@escaping SendFunction<Action>, @escaping () -> State?) -> (@escaping SendFunction<Action>) -> SendFunction<Action>

public final class Store<State: FlowState, Action: FlowAction>: ObservableObject {
    @Published public private(set) var state: State
    
    private(set) var isSending = false
    
    private let reducer: Reducer<State, Action>
    private var sendFunction: SendFunction<Action>!

    public init(initialState: State, initialAction: Action, reducer: Reducer<State, Action>, middleware: [Middleware<State, Action>] = []) {
        self.state = initialState
        self.reducer = reducer
        self.sendFunction = buildSendFunction(middleware)
        send(initialAction)
    }
    
    public func send(_ action: Action) {
        sendFunction(action)
    }
    
    func sendAsync(_ action: Action) {
        DispatchQueue.main.async {
            self.send(action)
        }
    }
    
    private func internalSend(_ action: Action) {
        if isSending {
            fatalError("Action sent while the state is being processed")
        }
        // TODO: make it atomic (threadsafe)
        isSending = true
        let commands = reducer.reduce(&state, action) ?? []
        isSending = false
        
        for command in commands {
            command.execute(sendAsync)
        }
    }
    
    private func buildSendFunction(_ middleware: [Middleware<State, Action>]) -> SendFunction<Action> {
        return middleware.reversed().reduce({ [unowned self] action in
            return self.internalSend(action)
        }, { sendFunction, middleware in
            let send: SendFunction<Action> = { [weak self] in self?.sendFunction($0) }
            let getState = { [weak self] in self?.state }
            return middleware(send, getState)(sendFunction)
        })
    }
}
