//
//  PDFTableTitleAdoption.swift
//  TPPDF
//
//  Created by Philip Niedertscheider on 15.10.2026.
//  Copyright © 2016-2025 techprimate GmbH. All rights reserved.
//

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    import UIKit
#else
    import AppKit
#endif

extension PDFContainer: Equatable {}
extension PDFGroupContainer: Equatable {}
extension PDFSectionColumnContainer: Equatable {}

/// Pulls a short heading that sits directly above a table into the table.
///
/// Pagination only knows the cursor once the table is calculated. Keeping the heading inside
/// the table lets that calculation move the heading together with the first body row and
/// append ``PDFTable/continuationSuffix`` when the table continues on the next page.
enum PDFTableTitleAdoption {
    /// Gaps larger than this belong to the previous section, not to the table heading.
    static let maximumGap: CGFloat = 10

    /// Longer text is body copy, not a table heading.
    static let maximumLength = 180

    static func adopt<Container: Equatable>(
        into table: PDFTable,
        objects: inout [(Container, PDFRenderObject)],
        container: Container
    ) {
        guard table.adoptsPrecedingTitle, table.titleRowCount == 0, table.leadingTitle == nil else {
            return
        }
        guard var index = lastIndex(in: objects, container: container, before: objects.count) else {
            return
        }

        var gap: CGFloat = 0
        if let space = objects[index].1 as? PDFSpaceObject {
            guard space.space <= maximumGap else { return }
            gap = space.space
            guard let textIndex = lastIndex(in: objects, container: container, before: index) else {
                return
            }
            guard let title = adoptableTitle(objects[textIndex].1) else { return }
            table.leadingTitle = title
            table.leadingTitleGap = gap
            let spaceIndex = index
            objects.remove(at: spaceIndex)
            objects.remove(at: textIndex)
            return
        }

        guard let title = adoptableTitle(objects[index].1) else { return }
        table.leadingTitle = title
        table.leadingTitleGap = 0
        objects.remove(at: index)
    }

    private static func lastIndex<Container: Equatable>(
        in objects: [(Container, PDFRenderObject)],
        container: Container,
        before limit: Int
    ) -> Int? {
        guard limit > 0 else { return nil }
        var index = limit - 1
        while index >= 0 {
            if objects[index].0 == container {
                return index
            }
            index -= 1
        }
        return nil
    }

    /// A heading is one short line of simple text. Attributed paragraphs stay where they were added.
    private static func adoptableTitle(_ object: PDFRenderObject) -> PDFSimpleText? {
        guard let textObject = object as? PDFAttributedTextObject, let simple = textObject.simpleText else {
            return nil
        }
        let trimmed = simple.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength else { return nil }
        guard !simple.text.contains("\n"), !simple.text.contains("\r") else { return nil }
        return PDFSimpleText(text: simple.text, spacing: simple.spacing, style: simple.style)
    }
}
