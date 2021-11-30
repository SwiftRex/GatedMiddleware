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
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 0)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 0)

        let io = gatedMiddleware.handle(action: .somethingElse, from: .here(), state: store.getState)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 0)

        io.runIO(store.actionHandler)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 1)

        sampleMiddleware.send(action: .oneMore)
        XCTAssertEqual(store.actionsReceived.map(\.action), [.oneMore])
    }

    func testByActionAfterDisable() {
        let store = Store()
        let sampleMiddleware = SampleMiddleware()
        let gatedMiddleware = sampleMiddleware.gated(
            controlActionMap: { $0.enableSample },
            default: .active
        )
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 0)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 0)

        let io1 = gatedMiddleware.handle(action: .toggleSampleMiddleware(false), from: .here(), state: store.getState)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 0)

        io1.runIO(store.actionHandler)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 1)

        let io2 = gatedMiddleware.handle(action: .somethingElse, from: .here(), state: store.getState)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 1)

        io2.runIO(store.actionHandler)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 1)

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
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 0)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 0)

        let io1 = gatedMiddleware.handle(action: .toggleSampleMiddleware(false), from: .here(), state: store.getState)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 0)

        io1.runIO(store.actionHandler)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 1)

        let io2 = gatedMiddleware.handle(action: .toggleSampleMiddleware(false), from: .here(), state: store.getState)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 2)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 1)

        io2.runIO(store.actionHandler)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 2)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 2)

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
        let io1 = gatedMiddleware.handle(action: .toggleSampleMiddleware(false), from: .here(), state: store.getState)
        io1.runIO(store.actionHandler)

        let io2 = gatedMiddleware.handle(action: .somethingElse, from: .here(), state: store.getState)
        io2.runIO(store.actionHandler)

        let io3 = gatedMiddleware.handle(action: .toggleSampleMiddleware(true), from: .here(), state: store.getState)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 2)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 1)

        io3.runIO(store.actionHandler)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 2)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 2)

        let io4 = gatedMiddleware.handle(action: .somethingElse, from: .here(), state: store.getState)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 3)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 2)

        io4.runIO(store.actionHandler)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 3)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 3)

        sampleMiddleware.send(action: .oneMore)
        XCTAssertEqual(store.actionsReceived.map(\.action), [.oneMore])
    }
}

extension GatedMiddlewareTests {
    func testByStateDefaultActive() {
        let store = Store()
        let sampleMiddleware = SampleMiddleware()
        let gatedMiddleware = sampleMiddleware.gated(
            state: \AppState.sampleEnabled
        )
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 0)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 0)

        let io = gatedMiddleware.handle(action: .somethingElse, from: .here(), state: store.getState)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 0)

        io.runIO(store.actionHandler)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 1)

        sampleMiddleware.send(action: .oneMore)
        XCTAssertEqual(store.actionsReceived.map(\.action), [.oneMore])
    }

    func testByStateAfterDisable() {
        let store = Store()
        let sampleMiddleware = SampleMiddleware()
        let gatedMiddleware = sampleMiddleware.gated(
            state: \AppState.sampleEnabled
        )
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 0)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 0)

        let io1 = gatedMiddleware.handle(action: .somethingElse, from: .here(), state: store.getState)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 0)

        store.state.sampleEnabled = .bypass

        io1.runIO(store.actionHandler)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 1)

        let io2 = gatedMiddleware.handle(action: .somethingElse, from: .here(), state: store.getState)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 1)

        io2.runIO(store.actionHandler)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 1)

        sampleMiddleware.send(action: .oneMore)
        XCTAssertEqual(store.actionsReceived, [])
    }

    func testByStateAfterDisableAndReenable() {
        let store = Store()
        let sampleMiddleware = SampleMiddleware()
        let gatedMiddleware = sampleMiddleware.gated(
            state: \AppState.sampleEnabled
        )
        let io1 = gatedMiddleware.handle(action: .somethingElse, from: .here(), state: store.getState)
        store.state.sampleEnabled = .bypass
        io1.runIO(store.actionHandler)

        let io2 = gatedMiddleware.handle(action: .somethingElse, from: .here(), state: store.getState)
        io2.runIO(store.actionHandler)

        let io3 = gatedMiddleware.handle(action: .somethingElse, from: .here(), state: store.getState)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 1)

        store.state.sampleEnabled = .active

        io3.runIO(store.actionHandler)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 1)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 1)

        let io4 = gatedMiddleware.handle(action: .somethingElse, from: .here(), state: store.getState)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 2)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 1)

        io4.runIO(store.actionHandler)
        XCTAssertEqual(sampleMiddleware.handleActionStateCount, 2)
        XCTAssertEqual(sampleMiddleware.handleActionStateIOCount, 2)

        sampleMiddleware.send(action: .oneMore)
        XCTAssertEqual(store.actionsReceived.map(\.action), [.oneMore])
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
    var actionsReceived: [DispatchedAction<AppAction>] = []

    var getState: (() -> AppState)!
    var actionHandler: AnyActionHandler<AppAction>!

    init() {
        actionHandler = AnyActionHandler { [weak self] action in
            self?.actionsReceived.append(action)
        }
        getState = { self.state }
    }
}

class SampleMiddleware: MiddlewareProtocol {
    typealias InputActionType = AppAction
    typealias OutputActionType = AppAction
    typealias StateType = AppState

    var output: AnyActionHandler<AppAction>?

    func send(action: AppAction) {
        output?.dispatch(action, from: .here())
    }

    var handleActionStateCount: Int = 0
    var handleActionStateIOCount: Int = 0
    func handle(action: AppAction, from dispatcher: ActionSource, state: GetState<AppState>) -> IO<OutputActionType> {
        handleActionStateCount += 1
        return IO { [weak self] output in
            self?.output = output
            self?.handleActionStateIOCount += 1
        }
    }
}
