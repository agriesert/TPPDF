//
//  PDFRepeatingSectionHeading.swift
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

/// A table heading that introduces several following objects and is redrawn after each page break.
///
/// The heading is not drawn when it is added. The next text or table draws it, and keeps it on the
/// same page as that content. A later page break draws it again at the top of the new page.
final class PDFRepeatingSectionHeading {
    /// One line of body text that must still fit under the heading. Otherwise the heading moves.
    static let minimumTextBelow: CGFloat = 12

    let table: PDFTable
    let gap: CGFloat

    /// Height of the heading table plus ``gap``. Measured once.
    private(set) var blockHeight: CGFloat = 0

    /// True after the heading has been drawn on the page currently being filled.
    var drawnOnCurrentPage = false

    init(table: PDFTable, gap: CGFloat) {
        self.table = table
        self.gap = gap
    }

    func measuredBlockHeight(generator: PDFGenerator, container: PDFContainer) throws -> CGFloat {
        if blockHeight > 0 {
            return blockHeight
        }
        let savedHeights = generator.layout.heights
        guard let savedColumns = generator.columnState.copy() as? PDFColumnLayoutState else {
            throw PDFError.copyingFailed
        }
        let savedPage = generator.currentPage
        let savedRendering = generator.isRenderingRepeatingHeading
        defer {
            generator.layout.heights = savedHeights
            generator.columnState = savedColumns
            generator.currentPage = savedPage
            generator.isRenderingRepeatingHeading = savedRendering
        }

        // Measure at the top of a page so a heading that would not fit at the real cursor
        // still reports its own height instead of a page-break offset.
        generator.isRenderingRepeatingHeading = true
        generator.layout.heights.content = 0
        _ = try PDFTableObject(table: table.copy).calculate(generator: generator, container: container)
        let height = generator.layout.heights.content + gap
        blockHeight = height
        return height
    }

    /// Draws the heading at the current cursor and leaves the cursor below it.
    func renderAtCurrentCursor(generator: PDFGenerator, container: PDFContainer) throws -> [PDFLocatedRenderObject] {
        let start = generator.layout.heights.content
        generator.isRenderingRepeatingHeading = true
        defer { generator.isRenderingRepeatingHeading = false }
        let objects = try PDFTableObject(table: table.copy).calculate(generator: generator, container: container)
        generator.layout.heights.add(gap, to: container)
        // The table offset replaces the cursor, so the delta is the heading block when it started here.
        if blockHeight == 0 {
            blockHeight = generator.layout.heights.content - start
        }
        drawnOnCurrentPage = true
        generator.repeatingHeadingPlacements += 1
        return objects
    }

    /// Draws the heading at `anchorY` without moving the cursor left by the surrounding table.
    func render(
        atAbsoluteY anchorY: CGFloat,
        generator: PDFGenerator,
        container: PDFContainer
    ) throws -> [PDFLocatedRenderObject] {
        let savedHeights = generator.layout.heights
        guard let savedColumns = generator.columnState.copy() as? PDFColumnLayoutState else {
            throw PDFError.copyingFailed
        }
        let savedPage = generator.currentPage
        defer {
            generator.layout.heights = savedHeights
            generator.columnState = savedColumns
            generator.currentPage = savedPage
        }
        let top = PDFCalculations.calculateTopMinimum(for: generator)
        generator.layout.heights.content = anchorY - top
        return try renderAtCurrentCursor(generator: generator, container: container)
    }
}

/// Marks the start of a section whose heading repeats on later pages.
class PDFRepeatingSectionHeadingObject: PDFRenderObject {
    var table: PDFTable
    var gap: CGFloat

    init(table: PDFTable, gap: CGFloat) {
        self.table = table
        self.gap = gap
    }

    override func calculate(generator: PDFGenerator, container _: PDFContainer) throws -> [PDFLocatedRenderObject] {
        generator.repeatingSectionHeading = PDFRepeatingSectionHeading(table: table, gap: gap)
        generator.pendingRepeatingHeadingAnchor = nil
        return []
    }

    override var copy: PDFRenderObject {
        PDFRepeatingSectionHeadingObject(table: table.copy, gap: gap)
    }
}

/// Stops repeating the active section heading. The following page break no longer redraws it.
class PDFEndRepeatingSectionHeadingObject: PDFRenderObject {
    override func calculate(generator: PDFGenerator, container _: PDFContainer) throws -> [PDFLocatedRenderObject] {
        generator.repeatingSectionHeading = nil
        generator.pendingRepeatingHeadingAnchor = nil
        return []
    }

    override var copy: PDFRenderObject {
        PDFEndRepeatingSectionHeadingObject()
    }
}

extension PDFGenerator {
    /// Reserves room for the active section heading above a table, or moves both to the next page.
    ///
    /// The heading is drawn only after the table is known to stay. A table that has to move
    /// takes the reserved heading with it, so the heading is not left alone at the bottom.
    func prepareRepeatingHeadingForTable(in container: PDFContainer) throws -> [PDFLocatedRenderObject] {
        guard !isRenderingRepeatingHeading else { return [] }
        pendingRepeatingHeadingAnchor = nil
        guard let heading = repeatingSectionHeading, !heading.drawnOnCurrentPage else { return [] }

        let block = try heading.measuredBlockHeight(generator: self, container: container)
        let available = PDFCalculations.calculateAvailableFrameHeight(for: self, in: container)
        if available < block - 0.5 {
            return try PDFPageBreakObject().calculate(generator: self, container: container)
        }
        let top = PDFCalculations.calculateTopMinimum(for: self)
        pendingRepeatingHeadingAnchor = top + layout.heights.content
        layout.heights.add(block, to: container)
        return []
    }

    /// Draws a heading that was reserved above a table which stayed on this page.
    func finishRepeatingHeadingAfterTable(
        stayedOnPage: Bool,
        container: PDFContainer
    ) throws -> [PDFLocatedRenderObject] {
        guard !isRenderingRepeatingHeading else { return [] }
        guard stayedOnPage,
              let anchor = pendingRepeatingHeadingAnchor,
              let heading = repeatingSectionHeading,
              !heading.drawnOnCurrentPage else {
            pendingRepeatingHeadingAnchor = nil
            return []
        }
        pendingRepeatingHeadingAnchor = nil
        return try heading.render(atAbsoluteY: anchor, generator: self, container: container)
    }

    /// Draws the heading in front of a text object, unless one line of that text would no longer fit.
    func prepareRepeatingHeadingForText(in container: PDFContainer) throws -> [PDFLocatedRenderObject] {
        guard !isRenderingRepeatingHeading,
              let heading = repeatingSectionHeading,
              !heading.drawnOnCurrentPage else {
            return []
        }
        let block = try heading.measuredBlockHeight(generator: self, container: container)
        let available = PDFCalculations.calculateAvailableFrameHeight(for: self, in: container)
        if available < block + PDFRepeatingSectionHeading.minimumTextBelow {
            return try PDFPageBreakObject().calculate(generator: self, container: container)
        }
        return try heading.renderAtCurrentCursor(generator: self, container: container)
    }
}
