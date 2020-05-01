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

/// Gated middleware is a middleware that holds an inner middleware that could be either active or not. The gated middleware has an internal state,
/// called `gate state`, that determines whether or not the inner middleware should be in `active` or `bypass` mode. This can be changed dynamically.
///
/// Every gated middleware starts with an initial gate state, called "default gate state". From that point, it will evaluate all incoming actions to
/// detect a "control action", which is an action for switching on or off the gate state. This control action is detected thanks to a control action
/// map closure or a control action map KeyPath configured in the GatedMiddleware's init, which from a given input action allows the user to inform
/// or not either this is a control action returning an Optional instance of that ControlAction (or nil in case it's a regular action).
///
/// The init also requires some comparison values, for turnOn or turnOff the gate. If it's a control action, and it's equals to turn on, it will set
/// the inner middleware to active. If it's a control action, and it's equals to turn off, it will set the inner middleware to bypass. If it's not a
/// control action, or it's not equals to any of the comparison values, the gate will remain untouched.
///
/// There one last important topic. The gated middleware will ALWAYS forward control actions to inner middlewares, regardless of their gate state
/// (active or bypass) and regardless of the turn on/turn off comparison result. This will allow important actions like disabling or enabling the
/// inner middleware for control actions, so for example, even for when we close the gate we still want to tell the inner middleware that it's gonna
/// be bypassed and it should kill all of its timers or async side-effects.
public final class GatedMiddleware<M: Middleware>: Middleware {
    public typealias InputActionType = M.InputActionType
    public typealias OutputActionType = M.OutputActionType
    public typealias StateType = M.StateType

    private let middleware: M
    private var gate: GateState
    private var predicateToChangeGateState: (M.InputActionType) -> Bool = { _ in false }

    /// GatedMiddleware init with Closure variant
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
        self.gate = gateState
        self.predicateToChangeGateState = { inputAction in
            guard let controlAction = controlActionMap(inputAction) else { return false }
            switch controlAction {
            case turnOn: self.gate = .active
            case turnOff: self.gate = .bypass
            default: break
            }
            return true
        }
    }

    /// GatedMiddleware init with KeyPath variant
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


    /// Middleware setup. This function will be called before actions are handled to the middleware, so you can configure your middleware with the given
    /// parameters. You can hold any of them if you plan to read the state or dispatch new actions.
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
        middleware.receiveContext(getState: getState, output: .init { [weak self] outputAction, source in
            guard let self = self, self.gate == .active else { return }
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
    /// This will be handled by the gated middleware and only forwarded to the inner middleware in some cases: if its gate state is `active` or if
    /// it's a control action (in that case, regardless of the gate state). Furthermore, when it's a control action, the value will be compared to
    /// `turnOn` and `turnOff` templates, given in the `GatedMiddleware`'s `init`, and if it's equals (`==`) to one of them, the gate state will
    /// change before the inner middleware call. The order doesn't matter too much because control actions are always forwarded to the inner
    /// middleware.
    ///
    /// - Parameters:
    ///   - action: the action to be handled
    ///   - dispatcher: information about the action source, representing the entity that created and dispatched the action
    ///   - afterReducer: it can be set to perform any operation after the reducer has changed the global state. If the function ends before you set
    ///                   this in/out parameter, `afterReducer` will default to `.doNothing()`.
    public func handle(action: M.InputActionType, from dispatcher: ActionSource, afterReducer: inout AfterReducer) {
        let isControlAction = predicateToChangeGateState(action)
        guard isControlAction || gate == .active else { return }
        middleware.handle(action: action, from: dispatcher, afterReducer: &afterReducer)
    }
}

extension Middleware {
    /// Gated middleware is a middleware that holds an inner middleware that could be either active or not. The gated middleware has an internal state,
    /// called `gate state`, that determines whether or not the inner middleware should be in `active` or `bypass` mode. This can be changed dynamically.
    ///
    /// Every gated middleware starts with an initial gate state, called "default gate state". From that point, it will evaluate all incoming actions to
    /// detect a "control action", which is an action for switching on or off the gate state. This control action is detected thanks to a control action
    /// map or a control map KeyPath configured in the GatedMiddleware's init, which from a given input action allows the user to inform either or not
    /// this is a control action returning an Optional instance of that ControlAction (or nil in case it's a regular action).
    ///
    /// The init also requires some comparison values, for turnOn or turnOff the gate. If it's a control action, and it's equals to turn on, it will set
    /// the inner middleware to active. If it's a control action, and it's equals to turn off, it will set the inner middleware to bypass. If it's not a
    /// control action, or it's not equals to any of the comparison values, the gate will remain untouched.
    ///
    /// There one last important topic. The gated middleware will ALWAYS forward control actions to inner middlewares, regardless of their gate state
    /// (active or bypass) and regardless of the turn on/turn off comparison result. This will allow important actions like disabling or enabling the
    /// inner middleware for control actions, so for example, even for when we close the gate we still want to tell the inner middleware that it's gonna
    /// be bypassed and it should kill all of its timers or async side-effects.
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

    /// Gated middleware is a middleware that holds an inner middleware that could be either active or not. The gated middleware has an internal state,
    /// called `gate state`, that determines whether or not the inner middleware should be in `active` or `bypass` mode. This can be changed dynamically.
    ///
    /// Every gated middleware starts with an initial gate state, called "default gate state". From that point, it will evaluate all incoming actions to
    /// detect a "control action", which is an action for switching on or off the gate state. This control action is detected thanks to a control action
    /// map or a control map KeyPath configured in the GatedMiddleware's init, which from a given input action allows the user to inform either or not
    /// this is a control action returning an Optional instance of that ControlAction (or nil in case it's a regular action).
    ///
    /// The init also requires some comparison values, for turnOn or turnOff the gate. If it's a control action, and it's equals to turn on, it will set
    /// the inner middleware to active. If it's a control action, and it's equals to turn off, it will set the inner middleware to bypass. If it's not a
    /// control action, or it's not equals to any of the comparison values, the gate will remain untouched.
    ///
    /// There one last important topic. The gated middleware will ALWAYS forward control actions to inner middlewares, regardless of their gate state
    /// (active or bypass) and regardless of the turn on/turn off comparison result. This will allow important actions like disabling or enabling the
    /// inner middleware for control actions, so for example, even for when we close the gate we still want to tell the inner middleware that it's gonna
    /// be bypassed and it should kill all of its timers or async side-effects.
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

    /// Gated middleware is a middleware that holds an inner middleware that could be either active or not. The gated middleware has an internal state,
    /// called `gate state`, that determines whether or not the inner middleware should be in `active` or `bypass` mode. This can be changed dynamically.
    ///
    /// Every gated middleware starts with an initial gate state, called "default gate state". From that point, it will evaluate all incoming actions to
    /// detect a "control action", which is an action for switching on or off the gate state. This control action is detected thanks to a control action
    /// map or a control map KeyPath configured in the GatedMiddleware's init, which from a given input action allows the user to inform either or not
    /// this is a control action returning an Optional instance of that ControlAction (or nil in case it's a regular action).
    ///
    /// The init also requires some comparison values, for turnOn or turnOff the gate. If it's a control action, and it's equals to turn on, it will set
    /// the inner middleware to active. If it's a control action, and it's equals to turn off, it will set the inner middleware to bypass. If it's not a
    /// control action, or it's not equals to any of the comparison values, the gate will remain untouched.
    ///
    /// There one last important topic. The gated middleware will ALWAYS forward control actions to inner middlewares, regardless of their gate state
    /// (active or bypass) and regardless of the turn on/turn off comparison result. This will allow important actions like disabling or enabling the
    /// inner middleware for control actions, so for example, even for when we close the gate we still want to tell the inner middleware that it's gonna
    /// be bypassed and it should kill all of its timers or async side-effects.
    /// - Parameters:
    ///   - controlAction: a key-path that goes from incoming action to an optional Bool. It result is nil, it means this is not a control action.
    ///                    In case it has a non-nil Bool, this will enable (for `true`) or bypass (for `false`) the inner middleware. The inner
    ///                    middleware will also receive that control action regardless of its gate state.
    ///   - gateState: initial `gateState`, either `active` or `bypass`
    /// - Returns: a `GatedMiddleware` containing internally this current middleware, allowing it to be bypassed or not.
    public func gated(
        controlActionMap: @escaping (InputActionType) -> Bool?,
        default gateState: GateState
    ) -> GatedMiddleware<Self> {
        GatedMiddleware(middleware: self, controlActionMap: controlActionMap, turnOn: true, turnOff: false, default: gateState)
    }
}
