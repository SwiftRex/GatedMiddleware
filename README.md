# GatedMiddleware
Turn SwiftRex middlewares on or off dynamically

Gated middleware is a middleware that holds an inner middleware that could be either active or not. The gated middleware has an internal state,
called `gate state`, that determines whether or not the inner middleware should be in `active` or `bypass` mode. This can be changed dynamically.

Every gated middleware starts with an initial gate state, called "default gate state". From that point, it will evaluate all incoming actions to
detect a "control action", which is an action for switching on or off the gate state. This control action is detected thanks to a control action
map closure or a control action map KeyPath configured in the GatedMiddleware's init, which from a given input action allows the user to inform
or not either this is a control action returning an Optional instance of that ControlAction (or nil in case it's a regular action).

The init also requires some comparison values, for turnOn or turnOff the gate. If it's a control action, and it's equals to turn on, it will set
the inner middleware to active. If it's a control action, and it's equals to turn off, it will set the inner middleware to bypass. If it's not a
control action, or it's not equals to any of the comparison values, the gate will remain untouched.

There one last important topic. The gated middleware will ALWAYS forward control actions to inner middlewares, regardless of their gate state
(active or bypass) and regardless of the turn on/turn off comparison result. This will allow important actions like disabling or enabling the
inner middleware for control actions, so for example, even for when we close the gate we still want to tell the inner middleware that it's gonna
be bypassed and it should kill all of its timers or async side-effects.

Example:

```
// sourcery: Prism
enum AppAction {
    case something
    case anotherSomething
    case dynamicMiddlewares(DynamicMiddlewareAction)
}

// sourcery: Prism
enum DynamicMiddlewareAction: Equatable {
    case toggleCrashReportsMiddleware(enable: Bool)
}

let gatedCrashReportsMiddleware =
    CrashReportsMiddleware
        .init()
        .gated(
            controlAction: \AppAction.dynamicMiddlewares?.toggleCrashReportsMiddleware?.enable,
            default: .active            
        )
```

With custom comparison:

```
// sourcery: Prism
enum AppAction {
    case something
    case anotherSomething
    case dynamicMiddlewares(DynamicMiddlewareAction)
}

// sourcery: Prism
enum DynamicMiddlewareAction: Equatable {
    case controlCrashReportsMiddleware(controlAction: MiddlewareControlAction)
}

enum MiddlewareControlAction: Equatable {
    case activate
    case bypass
    case sayHello
}

let gatedCrashReportsMiddleware =
    CrashReportsMiddleware
        .init()
        .gated(
            controlAction: \AppAction.dynamicMiddlewares?.controlCrashReportsMiddleware,
            turnOn: MiddlewareControlAction.activate,
            turnOff: MiddlewareControlAction.bypass,
            default: .active
        )
        // in this example, MiddlewareControlAction.activate will activate the crash reports,
        // MiddlewareControlAction.bypass will disable the crash reports, and
        // MiddlewareControlAction.sayHello won't change the gate state, but will be forwarded to the
        // crash reports middleware regardless of its current state.
```

You can also lift the inner middleware before gating it, in case the AppActions or AppStates don't match. Evidently lift can also be done
after the gated middleware if this is what you need.

Gating composed middlewares will disable or enable all of them at once, and the control action will be the same and be forwarded to all
the inner middlewares all the times. If this is not what you need, you need disabling them individually, you can first gate them and with
the gated collection you compose them.

This has no interference on Reducers and this doesn't change the AppState in any way. GatedMiddleware only matches AppState with its inner
middleware to allow proxying the `getState` context.

All examples above use Sourcery Prism templates to simplify traversing action trees, but the `GatedMiddleware` offers closures in case you
prefer switch/case approach or other custom functions.