//
//  ItemStyleTests.swift
//  DynamicLayoutTests
//

@testable import DynamicLayout
import Foundation
import Testing

struct ItemStyleTests {
    @Test func allCasesPresent() {
        let cases: Set<ItemStyle> = Set(ItemStyle.allCases)
        #expect(cases == [.photoFrame, .tile, .borderless])
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

    /// UserStorage entries written before the rename hold "contactSheet"
    /// as the raw value. Decoding must keep working so existing users
    /// don't see their pane state reset on first launch after upgrade.
    @Test func decodesLegacyContactSheetRawValueAsTile() throws {
        let json = Data(#""contactSheet""#.utf8)
        let decoded = try JSONDecoder().decode(ItemStyle.self, from: json)
        #expect(decoded == .tile)
    }

    @Test func encodesTileWithCurrentRawValue() throws {
        let encoded = try JSONEncoder().encode(ItemStyle.tile)
        #expect(String(data: encoded, encoding: .utf8) == #""tile""#)
    }
}
