import SwiftRex

/// Defines if the gate is active or bypassing actions.
/// When gate is active, the inner middleware will handle every action received. However, when gate is set to bypass, the inner middleware won't
/// receive most actions and will have no chance to start side-effects. The only exception is control actions, that will always be forwarded to the
/// inner middleware regardless of the gate state, so the middleware has opportunity to stop timers or any other async side-effect.
///
/// For more information, please check `GatedMiddleware`
public enum GateState: String, Codable, Equatable, Hashable {
    case active
    case bypass
}

private struct Gate<InputAction, OutputAction, State> {
    var shouldHandleAction: (InputAction, State) -> Bool
    var shouldDispatchAction: (OutputAction, State) -> Bool
}

extension Gate {
    static func byAction<ControlAction: Equatable>(
        controlActionMap: @escaping (InputAction) -> ControlAction?,
        turnOn: ControlAction,
        turnOff: ControlAction,
        initialState: GateState
    ) -> Gate {
        var currentState = initialState
        return .init(
            shouldHandleAction: { inputAction, _ in
                if let controlAction = controlActionMap(inputAction) {
                    switch controlAction {
                    case turnOn: currentState = .active
                    case turnOff: currentState = .bypass
                    default: break
                    }
                    return true
                }
                return currentState == .active
            },
            shouldDispatchAction: { _, _ in
                currentState == .active
            }
        )
    }
}

extension Gate {
    static func byState(
        stateMap: @escaping (State) -> GateState
    ) -> Gate {
        .init(
            shouldHandleAction: { _, state in
                stateMap(state) == .active
            },
            shouldDispatchAction: { _, state in
                stateMap(state) == .active
            }
        )
    }
}

/// Gated middleware is a middleware that holds an inner middleware that could be either active or not.
///
/// There are two gate variations that can be used: by action or by state.
///
/// GatedMiddleware by action:
///
/// It holds an internal state, called `gate state`, that determines whether or not the inner middleware should be in `active` or `bypass` mode.
/// This can be changed dynamically.
///
/// It starts with an initial gate state, called "default gate state". From that point on, it will evaluate all incoming actions to detect a "control
/// action", which is an action for switching on or off the gate state. This control action is detected thanks to a control action map closure or a
/// control action map KeyPath configured in the GatedMiddleware's init, which from a given input action allows the user to inform either or not this
/// is a control action, by returning an Optional instance of that ControlAction (or nil in case it's a regular action).
///
/// The init also requires some comparison values, for turnOn or turnOff the gate. If it's a control action, and it's equals to turn on, it will set
/// the inner middleware to active. If it's a control action, and it's equals to turn off, it will set the inner middleware to bypass. If it's not a
/// control action, or it's not equals to any of the comparison values, the gate will remain untouched.
///
/// The gated middleware by action will ALWAYS forward control actions to inner middlewares, regardless of their gate state (active or bypass) and
/// regardless of the turn on/turn off comparison result. This will allow important actions like disabling or enabling the inner middleware for
/// control actions, so for example, even for when we close the gate we still want to tell the inner middleware that it's gonna be bypassed and it
/// should kill all of its timers or async side-effects.
///
/// GatedMiddleware by state:
///
/// It won't hold any internal state, instead, it will use some state from your App Global State. You're responsible for mutating this state from your
/// own reducers. At any point that the state tells that this middleware is `active`, it's gonna handle actions and be able to dispatch new actions.
/// However, whenever the state is set to `bypass`, this middleware will ignore incoming actions and won't be able to dispatch any new action.
///
/// When handling actions, the state is evaluated before reducers, so whatever state is set BEFORE reducer, will define if the inner middleware will
/// be called before and after the reducer, even if the reducer changes that value. An action that changes the state from `active` to `bypass`, will
/// trigger inner middleware before and after the reducer, and after the reducer that value will be already set to `bypass`, so you can stop timers
/// and async tasks. An action that changes the state from `bypass` to `active`, will not trigger the inner middleware before the reducer nor after
/// it, so you may want to send a second action to start the middleware timers again, because the gated middleware can't do that for you.
public final class GatedMiddleware<M: Middleware>: Middleware {
    public typealias InputActionType = M.InputActionType
    public typealias OutputActionType = M.OutputActionType
    public typealias StateType = M.StateType

    private let middleware: M
    private let gate: Gate<InputActionType, OutputActionType, StateType>
    private var getState: GetState<StateType>?

    /// GatedMiddleware by action init with Closure variant
    /// - Parameters:
    ///   - middleware: a middleware to be contained by the gated middleware, allowing it to be bypassed or not
    ///   - controlActionMap: a closure that goes from incoming action to an optional control action. It result is nil, it means this is not a control
    ///                       action. Anything different than nil will be considered a control action and will be forwarded to the middleware
    ///                       regardless of its gate state (active/bypass). Furthermore, control actions will be compared to parameters `turnOn` and
    ///                       `turnOff` to allow mutating the gate state, that's why the `ControlAction` type must be `Equatable`.
    ///   - turnOn: a value to compare some `controlAction` and, in case `==` results to `true`, the gate state will mutate to `active`
    ///   - turnOff: a value to compare some `controlAction` and, in case `==` results to `true`, the gate state will mutate to `bypass`
    ///   - gateState: initial `gateState`, either `active` or `bypass`
    public init<ControlAction: Equatable>(
        middleware: M,
        controlActionMap: @escaping (M.InputActionType) -> ControlAction?,
        turnOn: ControlAction,
        turnOff: ControlAction,
        default gateState: GateState
    ) {
        self.middleware = middleware
        self.gate = .byAction(
            controlActionMap: controlActionMap,
            turnOn: turnOn,
            turnOff: turnOff,
            initialState: gateState
        )
    }

    /// GatedMiddleware by action init with KeyPath variant
    /// - Parameters:
    ///   - middleware: a middleware to be contained by the gated middleware, allowing it to be bypassed or not
    ///   - controlAction: a key-path that goes from incoming action to an optional control action. It result is nil, it means this is not a control
    ///                    action. Anything different than nil will be considered a control action and will be forwarded to the middleware regardless
    ///                    of its gate state (active/bypass). Furthermore, control actions will be compared to parameters `turnOn` and `turnOff` to
    ///                    allow mutating the gate state, that's why the `ControlAction` type must be `Equatable`.
    ///   - turnOn: a value to compare some `controlAction` and, in case `==` results to `true`, the gate state will mutate to `active`
    ///   - turnOff: a value to compare some `controlAction` and, in case `==` results to `true`, the gate state will mutate to `bypass`
    ///   - gateState: initial `gateState`, either `active` or `bypass`
    public convenience init<ControlAction: Equatable>(
        middleware: M,
        controlAction: KeyPath<M.InputActionType, ControlAction?>,
        turnOn: ControlAction,
        turnOff: ControlAction,
        default gateState: GateState
    ) {
        self.init(middleware: middleware, controlActionMap: { $0[keyPath: controlAction] }, turnOn: turnOn, turnOff: turnOff, default: gateState)
    }

    /// GatedMiddleware by state init with KeyPath variant
    /// - Parameters:
    ///   - middleware: a middleware to be contained by the gated middleware, allowing it to be bypassed or not
    ///   - stateMap: a closure that goes from global state to the value that determines whether or not our inner middleware should be `active`
    public init(
        middleware: M,
        stateMap: @escaping (StateType) -> GateState
    ) {
        self.middleware = middleware
        self.gate = .byState(stateMap: stateMap)
    }

    /// GatedMiddleware by state init with KeyPath variant
    /// - Parameters:
    ///   - middleware: a middleware to be contained by the gated middleware, allowing it to be bypassed or not
    ///   - state: a key-path that goes from global state to the value that determines whether or not our inner middleware should be `active`
    public convenience init(
        middleware: M,
        state: KeyPath<StateType, GateState>
    ) {
        self.init(middleware: middleware, stateMap: { $0[keyPath: state] })
    }

    /// Middleware setup. This function will be called before actions are handled to the middleware, so you can configure your middleware with the
    /// given parameters. You can hold any of them if you plan to read the state or dispatch new actions.
    /// You can initialize and start timers or async tasks in here or in the `handle(action:next)` function, but never before this function is called,
    /// otherwise the middleware would not yet be running from a store.
    /// Because no actions are delivered to this middleware before the `receiveContext(getState:output:)` is called, you can safely keep implicit
    /// unwrapped versions of `getState` and `output` as properties of your concrete middleware, and set them from the arguments of this function.
    ///
    /// This will be always forwarded to the inner middleware regardless of its gate state, another reason for you to never start side-effects on this
    /// event. However, this is proxied by the gated middleware, and output will only be forwarded to the store in case the gate state is active.
    ///
    /// - Parameters:
    ///   - getState: a closure that allows the middleware to read the current state at any point in time
    ///   - output: an action handler that allows the middleware to dispatch new actions at any point in time
    public func receiveContext(getState: @escaping GetState<M.StateType>, output: AnyActionHandler<M.OutputActionType>) {
        self.getState = getState
        middleware.receiveContext(getState: getState, output: .init { [weak self] outputAction, source in
            guard let self = self, self.gate.shouldDispatchAction(outputAction, getState()) else { return }
            output.dispatch(outputAction, from: source)
        })
    }

    /// Handles the incoming actions and may or not start async tasks, check the latest state at any point or dispatch additional actions.
    /// This is also a good place for analytics, tracking, logging and telemetry. You can schedule tasks to run after the reducer changed the global
    /// state if you want, and/or execute things before the reducer.
    /// This function is only called by the store after the `receiveContext(getState:output:)` was called, so if you saved the received context from
    /// there you can safely use it here to get the state or dispatch new actions.
    /// Setting the `afterReducer` in/out parameter is optional, if you don't set it, it defaults to `.doNothing()`.
    ///
    /// This will be handled by the gated middleware and only forwarded to the inner middleware in some cases.
    ///
    /// For gated middleware by action:
    /// - if its gate state is `active` or if it's receiving a control action (in that case, regardless of the gate state). Furthermore, when it's a
    ///   control action, the value will be compared to `turnOn` and `turnOff` templates, given in the `GatedMiddleware`'s `init`, and if it's
    ///   equals (`==`) to one of them, the gate state will change before the inner middleware call. The order doesn't matter too much because control
    ///   actions are always forwarded to the inner middleware.
    ///
    /// For gated middleware by state:
    /// - if the store `getState` returns `active` before the reducer, then the inner middleware will be called before and after the reducer,
    ///   regardless if the reducer changes this state to `bypass`. In that case, the inner middleware will be called afterReducer with state equals
    ///   to `bypass`. On the other hand, if the store `getState` returns `bypass` before the reducer, then the inner middleware won't be called for
    ///   this action at all, even in case that reducer changes it to `active`. The afterReducer won't be called.
    ///
    /// - Parameters:
    ///   - action: the action to be handled
    ///   - dispatcher: information about the action source, representing the entity that created and dispatched the action
    ///   - afterReducer: it can be set to perform any operation after the reducer has changed the global state. If the function ends before you set
    ///                   this in/out parameter, `afterReducer` will default to `.doNothing()`.
    public func handle(action: M.InputActionType, from dispatcher: ActionSource, afterReducer: inout AfterReducer) {
        guard let state = self.getState?(),
            gate.shouldHandleAction(action, state) else { return }

        middleware.handle(action: action, from: dispatcher, afterReducer: &afterReducer)
    }
}

extension Middleware {
    /// Gated middleware is a middleware that holds an inner middleware that could be either active or not.
    ///
    /// This creates a GatedMiddleware by action:
    ///
    /// It holds an internal state, called `gate state`, that determines whether or not the inner middleware should be in `active` or `bypass` mode.
    /// This can be changed dynamically.
    ///
    /// It starts with an initial gate state, called "default gate state". From that point on, it will evaluate all incoming actions to detect a "control
    /// action", which is an action for switching on or off the gate state. This control action is detected thanks to a control action map closure or a
    /// control action map KeyPath configured in the GatedMiddleware's init, which from a given input action allows the user to inform either or not this
    /// is a control action, by returning an Optional instance of that ControlAction (or nil in case it's a regular action).
    ///
    /// The init also requires some comparison values, for turnOn or turnOff the gate. If it's a control action, and it's equals to turn on, it will set
    /// the inner middleware to active. If it's a control action, and it's equals to turn off, it will set the inner middleware to bypass. If it's not a
    /// control action, or it's not equals to any of the comparison values, the gate will remain untouched.
    ///
    /// The gated middleware by action will ALWAYS forward control actions to inner middlewares, regardless of their gate state (active or bypass) and
    /// regardless of the turn on/turn off comparison result. This will allow important actions like disabling or enabling the inner middleware for
    /// control actions, so for example, even for when we close the gate we still want to tell the inner middleware that it's gonna be bypassed and it
    /// should kill all of its timers or async side-effects.
    ///
    /// - Parameters:
    ///   - controlAction: a key-path that goes from incoming action to an optional control action. It result is nil, it means this is not a control
    ///                    action. Anything different than nil will be considered a control action and will be forwarded to the middleware regardless
    ///                    of its gate state (active/bypass). Furthermore, control actions will be compared to parameters `turnOn` and `turnOff` to
    ///                    allow mutating the gate state, that's why the `ControlAction` type must be `Equatable`.
    ///   - turnOn: a value to compare some `controlAction` and, in case `==` results to `true`, the gate state will mutate to `active`
    ///   - turnOff: a value to compare some `controlAction` and, in case `==` results to `true`, the gate state will mutate to `bypass`
    ///   - gateState: initial `gateState`, either `active` or `bypass`
    /// - Returns: a `GatedMiddleware` containing internally this current middleware, allowing it to be bypassed or not.
    public func gated<ControlAction: Equatable>(
        controlAction: KeyPath<InputActionType, ControlAction?>,
        turnOn: ControlAction,
        turnOff: ControlAction,
        default gateState: GateState
    ) -> GatedMiddleware<Self> {
        GatedMiddleware(middleware: self, controlAction: controlAction, turnOn: turnOn, turnOff: turnOff, default: gateState)
    }

    /// Gated middleware is a middleware that holds an inner middleware that could be either active or not.
    ///
    /// This creates a GatedMiddleware by action:
    ///
    /// It holds an internal state, called `gate state`, that determines whether or not the inner middleware should be in `active` or `bypass` mode.
    /// This can be changed dynamically.
    ///
    /// It starts with an initial gate state, called "default gate state". From that point on, it will evaluate all incoming actions to detect a "control
    /// action", which is an action for switching on or off the gate state. This control action is detected thanks to a control action map closure or a
    /// control action map KeyPath configured in the GatedMiddleware's init, which from a given input action allows the user to inform either or not this
    /// is a control action, by returning an Optional instance of that ControlAction (or nil in case it's a regular action).
    ///
    /// The init also requires some comparison values, for turnOn or turnOff the gate. If it's a control action, and it's equals to turn on, it will set
    /// the inner middleware to active. If it's a control action, and it's equals to turn off, it will set the inner middleware to bypass. If it's not a
    /// control action, or it's not equals to any of the comparison values, the gate will remain untouched.
    ///
    /// The gated middleware by action will ALWAYS forward control actions to inner middlewares, regardless of their gate state (active or bypass) and
    /// regardless of the turn on/turn off comparison result. This will allow important actions like disabling or enabling the inner middleware for
    /// control actions, so for example, even for when we close the gate we still want to tell the inner middleware that it's gonna be bypassed and it
    /// should kill all of its timers or async side-effects.
    ///
    /// - Parameters:
    ///   - controlActionMap: a closure that goes from incoming action to an optional control action. It result is nil, it means this is not a control
    ///                       action. Anything different than nil will be considered a control action and will be forwarded to the middleware
    ///                       regardless of its gate state (active/bypass). Furthermore, control actions will be compared to parameters `turnOn` and
    ///                       `turnOff` to allow mutating the gate state, that's why the `ControlAction` type must be `Equatable`.
    ///   - turnOn: a value to compare some `controlAction` and, in case `==` results to `true`, the gate state will mutate to `active`
    ///   - turnOff: a value to compare some `controlAction` and, in case `==` results to `true`, the gate state will mutate to `bypass`
    ///   - gateState: initial `gateState`, either `active` or `bypass`
    /// - Returns: a `GatedMiddleware` containing internally this current middleware, allowing it to be bypassed or not.
    public func gated<ControlAction: Equatable>(
        controlActionMap: @escaping (InputActionType) -> ControlAction?,
        turnOn: ControlAction,
        turnOff: ControlAction,
        default gateState: GateState
    ) -> GatedMiddleware<Self> {
        GatedMiddleware(middleware: self, controlActionMap: controlActionMap, turnOn: turnOn, turnOff: turnOff, default: gateState)
    }

    /// Gated middleware is a middleware that holds an inner middleware that could be either active or not.
    ///
    /// This creates a GatedMiddleware by action:
    ///
    /// It holds an internal state, called `gate state`, that determines whether or not the inner middleware should be in `active` or `bypass` mode.
    /// This can be changed dynamically.
    ///
    /// It starts with an initial gate state, called "default gate state". From that point on, it will evaluate all incoming actions to detect a "control
    /// action", which is an action for switching on or off the gate state. This control action is detected thanks to a control action map closure or a
    /// control action map KeyPath configured in the GatedMiddleware's init, which from a given input action allows the user to inform either or not this
    /// is a control action, by returning an Optional instance of that ControlAction (or nil in case it's a regular action).
    ///
    /// The init also requires some comparison values, for turnOn or turnOff the gate. If it's a control action, and it's equals to turn on, it will set
    /// the inner middleware to active. If it's a control action, and it's equals to turn off, it will set the inner middleware to bypass. If it's not a
    /// control action, or it's not equals to any of the comparison values, the gate will remain untouched.
    ///
    /// The gated middleware by action will ALWAYS forward control actions to inner middlewares, regardless of their gate state (active or bypass) and
    /// regardless of the turn on/turn off comparison result. This will allow important actions like disabling or enabling the inner middleware for
    /// control actions, so for example, even for when we close the gate we still want to tell the inner middleware that it's gonna be bypassed and it
    /// should kill all of its timers or async side-effects.
    ///
    /// - Parameters:
    ///   - controlAction: a key-path that goes from incoming action to an optional Bool. It result is nil, it means this is not a control action.
    ///                    In case it has a non-nil Bool, this will enable (for `true`) or bypass (for `false`) the inner middleware. The inner
    ///                    middleware will also receive that control action regardless of its gate state.
    ///   - gateState: initial `gateState`, either `active` or `bypass`
    /// - Returns: a `GatedMiddleware` containing internally this current middleware, allowing it to be bypassed or not.
    public func gated(
        controlAction: KeyPath<InputActionType, Bool?>,
        default gateState: GateState
    ) -> GatedMiddleware<Self> {
        GatedMiddleware(middleware: self, controlAction: controlAction, turnOn: true, turnOff: false, default: gateState)
    }

    /// Gated middleware is a middleware that holds an inner middleware that could be either active or not.
    ///
    /// This creates a GatedMiddleware by action:
    ///
    /// It holds an internal state, called `gate state`, that determines whether or not the inner middleware should be in `active` or `bypass` mode.
    /// This can be changed dynamically.
    ///
    /// It starts with an initial gate state, called "default gate state". From that point on, it will evaluate all incoming actions to detect a "control
    /// action", which is an action for switching on or off the gate state. This control action is detected thanks to a control action map closure or a
    /// control action map KeyPath configured in the GatedMiddleware's init, which from a given input action allows the user to inform either or not this
    /// is a control action, by returning an Optional instance of that ControlAction (or nil in case it's a regular action).
    ///
    /// The init also requires some comparison values, for turnOn or turnOff the gate. If it's a control action, and it's equals to turn on, it will set
    /// the inner middleware to active. If it's a control action, and it's equals to turn off, it will set the inner middleware to bypass. If it's not a
    /// control action, or it's not equals to any of the comparison values, the gate will remain untouched.
    ///
    /// The gated middleware by action will ALWAYS forward control actions to inner middlewares, regardless of their gate state (active or bypass) and
    /// regardless of the turn on/turn off comparison result. This will allow important actions like disabling or enabling the inner middleware for
    /// control actions, so for example, even for when we close the gate we still want to tell the inner middleware that it's gonna be bypassed and it
    /// should kill all of its timers or async side-effects.
    ///
    /// - Parameters:
    ///   - controlActionMap: a closure that goes from incoming action to an optional Bool. It result is nil, it means this is not a control action.
    ///                       In case it has a non-nil Bool, this will enable (for `true`) or bypass (for `false`) the inner middleware. The inner
    ///                       middleware will also receive that control action regardless of its gate state.
    ///   - gateState: initial `gateState`, either `active` or `bypass`
    /// - Returns: a `GatedMiddleware` containing internally this current middleware, allowing it to be bypassed or not.
    public func gated(
        controlActionMap: @escaping (InputActionType) -> Bool?,
        default gateState: GateState
    ) -> GatedMiddleware<Self> {
        GatedMiddleware(middleware: self, controlActionMap: controlActionMap, turnOn: true, turnOff: false, default: gateState)
    }

    /// Gated middleware is a middleware that holds an inner middleware that could be either active or not.
    ///
    /// This creates a GatedMiddleware by action:
    ///
    /// It holds an internal state, called `gate state`, that determines whether or not the inner middleware should be in `active` or `bypass` mode.
    /// This can be changed dynamically.
    ///
    /// It starts with an initial gate state, called "default gate state". From that point on, it will evaluate all incoming actions to detect a "control
    /// action", which is an action for switching on or off the gate state. This control action is detected thanks to a control action map closure or a
    /// control action map KeyPath configured in the GatedMiddleware's init, which from a given input action allows the user to inform either or not this
    /// is a control action, by returning an Optional instance of that ControlAction (or nil in case it's a regular action).
    ///
    /// The init also requires some comparison values, for turnOn or turnOff the gate. If it's a control action, and it's equals to turn on, it will set
    /// the inner middleware to active. If it's a control action, and it's equals to turn off, it will set the inner middleware to bypass. If it's not a
    /// control action, or it's not equals to any of the comparison values, the gate will remain untouched.
    ///
    /// The gated middleware by action will ALWAYS forward control actions to inner middlewares, regardless of their gate state (active or bypass) and
    /// regardless of the turn on/turn off comparison result. This will allow important actions like disabling or enabling the inner middleware for
    /// control actions, so for example, even for when we close the gate we still want to tell the inner middleware that it's gonna be bypassed and it
    /// should kill all of its timers or async side-effects.
    ///
    /// - Parameters:
    ///   - controlAction: a key-path that goes from incoming action to an optional `GateState`. It result is nil, it means this is not a control
    ///                    action. In case it has a non-nil `GateState`, this will enable (for `.active`) or bypass (for `.bypass`) the inner
    ///                    middleware. The inner middleware will also receive that control action regardless of its gate state.
    ///   - gateState: initial `gateState`, either `active` or `bypass`
    /// - Returns: a `GatedMiddleware` containing internally this current middleware, allowing it to be bypassed or not.
    public func gated(
        controlAction: KeyPath<InputActionType, GateState?>,
        default gateState: GateState
    ) -> GatedMiddleware<Self> {
        GatedMiddleware(middleware: self, controlAction: controlAction, turnOn: .active, turnOff: .bypass, default: gateState)
    }

    /// Gated middleware is a middleware that holds an inner middleware that could be either active or not.
    ///
    /// This creates a GatedMiddleware by action:
    ///
    /// It holds an internal state, called `gate state`, that determines whether or not the inner middleware should be in `active` or `bypass` mode.
    /// This can be changed dynamically.
    ///
    /// It starts with an initial gate state, called "default gate state". From that point on, it will evaluate all incoming actions to detect a "control
    /// action", which is an action for switching on or off the gate state. This control action is detected thanks to a control action map closure or a
    /// control action map KeyPath configured in the GatedMiddleware's init, which from a given input action allows the user to inform either or not this
    /// is a control action, by returning an Optional instance of that ControlAction (or nil in case it's a regular action).
    ///
    /// The init also requires some comparison values, for turnOn or turnOff the gate. If it's a control action, and it's equals to turn on, it will set
    /// the inner middleware to active. If it's a control action, and it's equals to turn off, it will set the inner middleware to bypass. If it's not a
    /// control action, or it's not equals to any of the comparison values, the gate will remain untouched.
    ///
    /// The gated middleware by action will ALWAYS forward control actions to inner middlewares, regardless of their gate state (active or bypass) and
    /// regardless of the turn on/turn off comparison result. This will allow important actions like disabling or enabling the inner middleware for
    /// control actions, so for example, even for when we close the gate we still want to tell the inner middleware that it's gonna be bypassed and it
    /// should kill all of its timers or async side-effects.
    ///
    /// - Parameters:
    ///   - controlActionMap: a key-path that goes from incoming action to an optional `GateState`. It result is nil, it means this is not a control
    ///                        action. In case it has a non-nil `GateState`, this will enable (for `.active`) or bypass (for `.bypass`) the inner
    ///                        middleware. The inner middleware will also receive that control action regardless of its gate state.
    ///   - gateState: initial `gateState`, either `active` or `bypass`
    /// - Returns: a `GatedMiddleware` containing internally this current middleware, allowing it to be bypassed or not.
    public func gated(
        controlActionMap: @escaping (InputActionType) -> GateState?,
        default gateState: GateState
    ) -> GatedMiddleware<Self> {
        GatedMiddleware(middleware: self, controlActionMap: controlActionMap, turnOn: .active, turnOff: .bypass, default: gateState)
    }
}

extension Middleware {
    /// Gated middleware is a middleware that holds an inner middleware that could be either active or not.
    ///
    /// This creates a GatedMiddleware by state:
    ///
    /// It won't hold any internal state, instead, it will use some state from your App Global State. You're responsible for mutating this state from your
    /// own reducers. At any point that the state tells that this middleware is `active`, it's gonna handle actions and be able to dispatch new actions.
    /// However, whenever the state is set to `bypass`, this middleware will ignore incoming actions and won't be able to dispatch any new action.
    ///
    /// When handling actions, the state is evaluated before reducers, so whatever state is set BEFORE reducer, will define if the inner middleware will
    /// be called before and after the reducer, even if the reducer changes that value. An action that changes the state from `active` to `bypass`, will
    /// trigger inner middleware before and after the reducer, and after the reducer that value will be already set to `bypass`, so you can stop timers
    /// and async tasks. An action that changes the state from `bypass` to `active`, will not trigger the inner middleware before the reducer nor after
    /// it, so you may want to send a second action to start the middleware timers again, because the gated middleware can't do that for you.
    /// - Parameter state: a key-path that goes from global app state to a Bool that determines if this inner middleware is active
    /// - Returns: a `GatedMiddleware` containing internally this current middleware, allowing it to be bypassed or not.
    public func gated(
        state: KeyPath<StateType, Bool>
    ) -> GatedMiddleware<Self> {
        GatedMiddleware(middleware: self, stateMap: { $0[keyPath: state] ? .active : .bypass })
    }

    /// Gated middleware is a middleware that holds an inner middleware that could be either active or not.
    ///
    /// This creates a GatedMiddleware by state:
    ///
    /// It won't hold any internal state, instead, it will use some state from your App Global State. You're responsible for mutating this state from your
    /// own reducers. At any point that the state tells that this middleware is `active`, it's gonna handle actions and be able to dispatch new actions.
    /// However, whenever the state is set to `bypass`, this middleware will ignore incoming actions and won't be able to dispatch any new action.
    ///
    /// When handling actions, the state is evaluated before reducers, so whatever state is set BEFORE reducer, will define if the inner middleware will
    /// be called before and after the reducer, even if the reducer changes that value. An action that changes the state from `active` to `bypass`, will
    /// trigger inner middleware before and after the reducer, and after the reducer that value will be already set to `bypass`, so you can stop timers
    /// and async tasks. An action that changes the state from `bypass` to `active`, will not trigger the inner middleware before the reducer nor after
    /// it, so you may want to send a second action to start the middleware timers again, because the gated middleware can't do that for you.
    /// - Parameter stateMap: a closure that goes from global app state to a Bool that determines if this inner middleware is active
    /// - Returns: a `GatedMiddleware` containing internally this current middleware, allowing it to be bypassed or not.
    public func gated(
        stateMap: @escaping (StateType) -> Bool
    ) -> GatedMiddleware<Self> {
        GatedMiddleware(middleware: self, stateMap: { stateMap($0) ? .active : .bypass })
    }

    /// Gated middleware is a middleware that holds an inner middleware that could be either active or not.
    ///
    /// This creates a GatedMiddleware by state:
    ///
    /// It won't hold any internal state, instead, it will use some state from your App Global State. You're responsible for mutating this state from your
    /// own reducers. At any point that the state tells that this middleware is `active`, it's gonna handle actions and be able to dispatch new actions.
    /// However, whenever the state is set to `bypass`, this middleware will ignore incoming actions and won't be able to dispatch any new action.
    ///
    /// When handling actions, the state is evaluated before reducers, so whatever state is set BEFORE reducer, will define if the inner middleware will
    /// be called before and after the reducer, even if the reducer changes that value. An action that changes the state from `active` to `bypass`, will
    /// trigger inner middleware before and after the reducer, and after the reducer that value will be already set to `bypass`, so you can stop timers
    /// and async tasks. An action that changes the state from `bypass` to `active`, will not trigger the inner middleware before the reducer nor after
    /// it, so you may want to send a second action to start the middleware timers again, because the gated middleware can't do that for you.
    /// - Parameter state: a key-path that goes from global app state to a gate state for this inner middleware
    /// - Returns: a `GatedMiddleware` containing internally this current middleware, allowing it to be bypassed or not.
    public func gated(
        state: KeyPath<StateType, GateState>
    ) -> GatedMiddleware<Self> {
        GatedMiddleware(middleware: self, state: state)
    }

    /// Gated middleware is a middleware that holds an inner middleware that could be either active or not.
    ///
    /// This creates a GatedMiddleware by state:
    ///
    /// It won't hold any internal state, instead, it will use some state from your App Global State. You're responsible for mutating this state from your
    /// own reducers. At any point that the state tells that this middleware is `active`, it's gonna handle actions and be able to dispatch new actions.
    /// However, whenever the state is set to `bypass`, this middleware will ignore incoming actions and won't be able to dispatch any new action.
    ///
    /// When handling actions, the state is evaluated before reducers, so whatever state is set BEFORE reducer, will define if the inner middleware will
    /// be called before and after the reducer, even if the reducer changes that value. An action that changes the state from `active` to `bypass`, will
    /// trigger inner middleware before and after the reducer, and after the reducer that value will be already set to `bypass`, so you can stop timers
    /// and async tasks. An action that changes the state from `bypass` to `active`, will not trigger the inner middleware before the reducer nor after
    /// it, so you may want to send a second action to start the middleware timers again, because the gated middleware can't do that for you.
    /// - Parameter stateMap: a closure that goes from global app state to a gate state for this inner middleware
    /// - Returns: a `GatedMiddleware` containing internally this current middleware, allowing it to be bypassed or not.
    public func gated(
        stateMap: @escaping (StateType) -> GateState
    ) -> GatedMiddleware<Self> {
        GatedMiddleware(middleware: self, stateMap: stateMap)
    }
}
