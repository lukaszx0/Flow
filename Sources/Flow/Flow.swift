import Foundation
import Combine

protocol FlowAction {}

protocol FlowState {}

struct Command<Action: FlowAction> {
    let execute: (SendFunction<Action>) -> Void
}

struct Reducer<State: FlowState, Action: FlowAction> {
    let reduce: (inout State, Action) -> [Command<Action>]?
}

typealias SendFunction<Action: FlowAction> = (Action) -> ()

typealias Middleware<State: FlowState, Action: FlowAction> = (@escaping SendFunction<Action>, @escaping () -> State?) -> (@escaping SendFunction<Action>) -> SendFunction<Action>

final class Store<State: FlowState, Action: FlowAction>: ObservableObject {
    @Published private(set) var state: State
    
    private(set) var isSending = false
    
    private let reducer: Reducer<State, Action>
    private var sendFunction: SendFunction<Action>!

    init(initialState: State, initialAction: Action, reducer: Reducer<State, Action>, middleware: [Middleware<State, Action>] = []) {
        self.state = initialState
        self.reducer = reducer
        self.sendFunction = buildSendFunction(middleware)
        send(initialAction)
    }
    
    func send(_ action: Action) {
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
