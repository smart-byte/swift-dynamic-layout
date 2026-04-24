//
//  ItemStyleTests.swift
//  DynamicLayoutTests
//

@testable import DynamicLayout
import Testing

struct ItemStyleTests {
    @Test func allCasesPresent() {
        let cases: Set<ItemStyle> = Set(ItemStyle.allCases)
        #expect(cases == [.photoFrame, .contactSheet, .borderless])
    }

    @Test(arguments: ItemStyle.allCases)
    func everyCaseHasNonEmptyNameAndIcon(_ style: ItemStyle) {
        #expect(!style.name.isEmpty)
        #expect(!style.icon.isEmpty)
    }

    @Test func namesAreDistinct() {
        let names = ItemStyle.allCases.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test func iconsAreDistinct() {
        let icons = ItemStyle.allCases.map(\.icon)
        #expect(Set(icons).count == icons.count)
    }
}
