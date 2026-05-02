//
//  LayoutModeTests.swift
//  DynamicLayoutTests
//

@testable import DynamicLayout
import Testing

struct LayoutModeTests {
    @Test func allCasesPresent() {
        let cases: Set<LayoutMode> = Set(LayoutMode.allCases)
        #expect(cases == [
            .list, .verticalFlow, .waterfall,
            .horizontalFlow, .justified, .horizontalJustified,
        ])
    }

    @Test func pickerCasesContainsExpectedModes() {
        #expect(LayoutMode.pickerCases == [
            .list, .justified, .horizontalJustified, .horizontalFlow,
        ])
    }

    @Test(arguments: LayoutMode.allCases)
    func everyCaseHasNonEmptyNameAndIcon(_ mode: LayoutMode) {
        #expect(!mode.name.isEmpty)
        #expect(!mode.icon.isEmpty)
    }

    // MARK: - defaultItemStyle mapping

    @Test func waterfallDefaultsToPhotoFrame() {
        #expect(LayoutMode.waterfall.defaultItemStyle == .photoFrame)
    }

    @Test func horizontalFlowDefaultsToBorderless() {
        #expect(LayoutMode.horizontalFlow.defaultItemStyle == .borderless)
    }

    @Test func verticalFlowDefaultsToBorderless() {
        #expect(LayoutMode.verticalFlow.defaultItemStyle == .borderless)
    }

    @Test func listDefaultsToTile() {
        #expect(LayoutMode.list.defaultItemStyle == .tile)
    }

    @Test func justifiedDefaultsToTile() {
        #expect(LayoutMode.justified.defaultItemStyle == .tile)
    }

    @Test func horizontalJustifiedDefaultsToTile() {
        #expect(LayoutMode.horizontalJustified.defaultItemStyle == .tile)
    }
}
