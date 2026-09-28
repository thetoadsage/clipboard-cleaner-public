import Foundation
import Testing

@testable import ClipboardCleaner

@MainActor
struct MenuBarIconFlashControllerTests {
    @Test func flashUsesFilledSymbolAndRestoresNormalSymbol() {
        var symbols = [String]()
        let controller = MenuBarIconFlashController(setSymbolName: { symbols.append($0) })

        controller.flash()

        #expect(controller.isFlashing)
        #expect(symbols == [MenuBarIconFlashController.flashedSymbolName])

        controller.finishFlash()

        #expect(!controller.isFlashing)
        #expect(symbols == [
            MenuBarIconFlashController.flashedSymbolName,
            MenuBarIconFlashController.normalSymbolName,
        ])
    }

    @Test func defaultFlashDurationIsHalfASecond() {
        #expect(MenuBarIconFlashController.defaultDuration == 0.5)
    }
}
