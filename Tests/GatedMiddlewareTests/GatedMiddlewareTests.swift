@testable import SwiftRex
@testable import GatedMiddleware
import XCTest

final class GatedMiddlewareTests: XCTestCase {
    func testByActionDefaultActive() {
        let store = Store()
        let sampleMiddleware = SampleMiddleware()
        let gatedMiddleware = sampleMiddleware.gated(
            controlActionMap: { $0.enableSample },
            default: .active
        )
        gatedMiddleware.receiveContext(getState: store.getState, output: store.actionHandler)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 0)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 0)

        var afterReducer = AfterReducer.doNothing()
        gatedMiddleware.handle(action: .somethingElse, from: .here(), afterReducer: &afterReducer)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 0)

        afterReducer.reducerIsDone()
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 1)

        sampleMiddleware.send(action: .oneMore)
        XCTAssertEqual(store.actionsReceived, [.oneMore])
    }

    func testByActionAfterDisable() {
        let store = Store()
        let sampleMiddleware = SampleMiddleware()
        let gatedMiddleware = sampleMiddleware.gated(
            controlActionMap: { $0.enableSample },
            default: .active
        )
        gatedMiddleware.receiveContext(getState: store.getState, output: store.actionHandler)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 0)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 0)

        var afterReducer1 = AfterReducer.doNothing()
        gatedMiddleware.handle(action: .toggleSampleMiddleware(false), from: .here(), afterReducer: &afterReducer1)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 0)

        afterReducer1.reducerIsDone()
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 1)

        var afterReducer2 = AfterReducer.doNothing()
        gatedMiddleware.handle(action: .somethingElse, from: .here(), afterReducer: &afterReducer2)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 1)

        afterReducer2.reducerIsDone()
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 1)

        sampleMiddleware.send(action: .oneMore)
        XCTAssertEqual(store.actionsReceived, [])
    }

    func testByActionAfterDisableStillReceivesControlAction() {
        let store = Store()
        let sampleMiddleware = SampleMiddleware()
        let gatedMiddleware = sampleMiddleware.gated(
            controlActionMap: { $0.enableSample },
            default: .active
        )
        gatedMiddleware.receiveContext(getState: store.getState, output: store.actionHandler)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 0)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 0)

        var afterReducer1 = AfterReducer.doNothing()
        gatedMiddleware.handle(action: .toggleSampleMiddleware(false), from: .here(), afterReducer: &afterReducer1)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 0)

        afterReducer1.reducerIsDone()
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 1)

        var afterReducer2 = AfterReducer.doNothing()
        gatedMiddleware.handle(action: .toggleSampleMiddleware(false), from: .here(), afterReducer: &afterReducer2)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 2)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 1)

        afterReducer2.reducerIsDone()
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 2)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 2)

        sampleMiddleware.send(action: .oneMore)
        XCTAssertEqual(store.actionsReceived, [])
    }

    func testByActionAfterDisableAndReenable() {
        let store = Store()
        let sampleMiddleware = SampleMiddleware()
        let gatedMiddleware = sampleMiddleware.gated(
            controlActionMap: { $0.enableSample },
            default: .active
        )
        gatedMiddleware.receiveContext(getState: store.getState, output: store.actionHandler)
        var afterReducer1 = AfterReducer.doNothing()
        gatedMiddleware.handle(action: .toggleSampleMiddleware(false), from: .here(), afterReducer: &afterReducer1)
        afterReducer1.reducerIsDone()

        var afterReducer2 = AfterReducer.doNothing()
        gatedMiddleware.handle(action: .somethingElse, from: .here(), afterReducer: &afterReducer2)
        afterReducer2.reducerIsDone()

        var afterReducer3 = AfterReducer.doNothing()
        gatedMiddleware.handle(action: .toggleSampleMiddleware(true), from: .here(), afterReducer: &afterReducer3)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 2)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 1)

        afterReducer3.reducerIsDone()
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 2)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 2)

        var afterReducer4 = AfterReducer.doNothing()
        gatedMiddleware.handle(action: .somethingElse, from: .here(), afterReducer: &afterReducer4)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 3)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 2)

        afterReducer4.reducerIsDone()
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 3)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 3)

        sampleMiddleware.send(action: .oneMore)
        XCTAssertEqual(store.actionsReceived, [.oneMore])
    }
}

extension GatedMiddlewareTests {
    func testByStateDefaultActive() {
        let store = Store()
        let sampleMiddleware = SampleMiddleware()
        let gatedMiddleware = sampleMiddleware.gated(
            state: \AppState.sampleEnabled
        )
        gatedMiddleware.receiveContext(getState: store.getState, output: store.actionHandler)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 0)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 0)

        var afterReducer = AfterReducer.doNothing()
        gatedMiddleware.handle(action: .somethingElse, from: .here(), afterReducer: &afterReducer)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 0)

        afterReducer.reducerIsDone()
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 1)

        sampleMiddleware.send(action: .oneMore)
        XCTAssertEqual(store.actionsReceived, [.oneMore])
    }

    func testByStateAfterDisable() {
        let store = Store()
        let sampleMiddleware = SampleMiddleware()
        let gatedMiddleware = sampleMiddleware.gated(
            state: \AppState.sampleEnabled
        )
        gatedMiddleware.receiveContext(getState: store.getState, output: store.actionHandler)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 0)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 0)

        var afterReducer1 = AfterReducer.doNothing()
        gatedMiddleware.handle(action: .somethingElse, from: .here(), afterReducer: &afterReducer1)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 0)

        store.state.sampleEnabled = .bypass

        afterReducer1.reducerIsDone()
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 1)

        var afterReducer2 = AfterReducer.doNothing()
        gatedMiddleware.handle(action: .somethingElse, from: .here(), afterReducer: &afterReducer2)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 1)

        afterReducer2.reducerIsDone()
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 1)

        sampleMiddleware.send(action: .oneMore)
        XCTAssertEqual(store.actionsReceived, [])
    }

    func testByStateAfterDisableAndReenable() {
        let store = Store()
        let sampleMiddleware = SampleMiddleware()
        let gatedMiddleware = sampleMiddleware.gated(
            state: \AppState.sampleEnabled
        )
        gatedMiddleware.receiveContext(getState: store.getState, output: store.actionHandler)
        var afterReducer1 = AfterReducer.doNothing()
        gatedMiddleware.handle(action: .somethingElse, from: .here(), afterReducer: &afterReducer1)
        store.state.sampleEnabled = .bypass
        afterReducer1.reducerIsDone()

        var afterReducer2 = AfterReducer.doNothing()
        gatedMiddleware.handle(action: .somethingElse, from: .here(), afterReducer: &afterReducer2)
        afterReducer2.reducerIsDone()

        var afterReducer3 = AfterReducer.doNothing()
        gatedMiddleware.handle(action: .somethingElse, from: .here(), afterReducer: &afterReducer3)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 1)

        store.state.sampleEnabled = .active

        afterReducer3.reducerIsDone()
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 1)

        var afterReducer4 = AfterReducer.doNothing()
        gatedMiddleware.handle(action: .somethingElse, from: .here(), afterReducer: &afterReducer4)
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 2)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 1)

        afterReducer4.reducerIsDone()
        XCTAssertEqual(sampleMiddleware.receiveContextCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionCount, 2)
        XCTAssertEqual(sampleMiddleware.handleActionAfterReducerCount, 2)

        sampleMiddleware.send(action: .oneMore)
        XCTAssertEqual(store.actionsReceived, [.oneMore])
    }
}

extension GatedMiddlewareTests {
    static var allTests = [
        ("testByActionDefaultActive", testByActionDefaultActive),
        ("testByActionAfterDisable", testByActionAfterDisable),
        ("testByActionAfterDisableStillReceivesControlAction", testByActionAfterDisableStillReceivesControlAction),
        ("testByActionAfterDisableAndReenable", testByActionAfterDisableAndReenable),
        ("testByStateDefaultActive", testByStateDefaultActive),
        ("testByStateAfterDisable", testByStateAfterDisable),
        ("testByStateAfterDisableAndReenable", testByStateAfterDisableAndReenable),
    ]
}

struct AppState {
    var sampleEnabled: GateState
}

enum AppAction: Equatable {
    case somethingElse
    case oneMore
    case toggleSampleMiddleware(Bool)

    var enableSample: Bool? {
        switch self {
        case let .toggleSampleMiddleware(enabled):
            return enabled
        default:
            return nil
        }
    }
}

class Store {
    var state: AppState = AppState(sampleEnabled: .active)
    var actionsReceived: [AppAction] = []

    var getState: (() -> AppState)!
    var actionHandler: AnyActionHandler<AppAction>!

    init() {
        actionHandler = .init { action, _ in
            self.actionsReceived.append(action)
        }
        getState = { self.state }
    }
}

class SampleMiddleware: Middleware {
    typealias InputActionType = AppAction
    typealias OutputActionType = AppAction
    typealias StateType = AppState

    var getState: GetState<AppState>?
    var output: AnyActionHandler<AppAction>?

    var receiveContextCount: Int = 0
    func receiveContext(getState: @escaping GetState<AppState>, output: AnyActionHandler<AppAction>) {
        self.getState = getState
        self.output = output
        receiveContextCount += 1
    }

    func send(action: AppAction) {
        output?.dispatch(action, from: .here())
    }

    var handleActionCount: Int = 0
    var handleActionAfterReducerCount: Int = 0
    func handle(action: AppAction, from dispatcher: ActionSource, afterReducer: inout AfterReducer) {
        handleActionCount += 1
        afterReducer = .do {
            self.handleActionAfterReducerCount += 1
        }
    }
}
