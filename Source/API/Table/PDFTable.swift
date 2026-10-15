//
//  PDFTable.swift
//  TPPDF
//
//  Created by Philip Niedertscheider on 06.13.2017.
//  Copyright © 2016-2025 techprimate GmbH. All rights reserved.
//

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    import UIKit
#else
    import AppKit
#endif

/**
 * A table is a two dimensional list.
 *
 * It can be styled and can contain different data.
 */
public class PDFTable: PDFDocumentObject {
    /// Styling used for drawing
    public var style: PDFTableStyle = PDFTableStyleDefaults.simple

    /// Two-dimensional array of cells
    public var cells: [[PDFTableCell]] = []

    /**
     * List of relative horizontal column widths.
     *
     * Values are between `0.0` and `1.0` and should sum up to `1.0` (100%)
     */
    public var widths: [CGFloat] = []

    /// Padding is the distance between the cell content and its borders.
    public var padding: CGFloat = 0

    /// Distance between the table outline and the first and last column.
    /// Applied on the left and the right only.
    public var horizontalInset: CGFloat = 0

    /// Distance between the table outline and the first and last row.
    /// Applied above the first row and below the last row only.
    public var verticalInset: CGFloat = 0

    /// Margin is the distance between the cell borders and other cells
    public var margin: CGFloat = 0

    /// Stretch a non-clear row fill across the gutters and the side inset.
    ///
    /// Cell fills stop at each cell frame, so margin and the side inset leave
    /// the page color showing between columns. One band behind the row closes that gap.
    /// Header rows stay untouched because their fill is clear.
    public var continuousRowFills: Bool = false

    /// Header rows will be drawn on every page
    public var showHeadersOnEveryPage: Bool = false

    //// Cells should split when overlapping page
    public var shouldSplitCellsOnPageBreak = false

    /**
     * Body rows that must fit below the title and column header before the table may start.
     *
     * Zero keeps the historical behavior. A positive value moves the whole table to the next
     * page when the current page cannot hold that many full body rows after the header block.
     */
    public var minimumBodyRowsOnFirstPage: Int = 0

    /**
     * Leading rows that describe the table, above the column headers.
     *
     * Those rows are repeated on continuation pages. ``PDFTable/continuationSuffix`` is appended
     * to their text there. Column-header rows are left unchanged.
     */
    public var titleRowCount: Int = 0

    /**
     * Text appended once to a continued table title, including any separating space.
     *
     * Empty means continuation pages keep the original title. The suffix is not appended again
     * when the title already ends with it.
     */
    public var continuationSuffix: String = ""

    /**
     * When true, a short simple-text object placed directly above this table is treated as its title.
     *
     * The text, and at most one small space between it and the table, is removed from the container
     * and drawn again by the table so a page break can keep the title with the first row.
     */
    public var adoptsPrecedingTitle: Bool = false

    /// Simple text adopted from the object directly above the table. Nil when the table has its own title row.
    public var leadingTitle: PDFSimpleText?

    /// Space that was between ``PDFTable/leadingTitle`` and the table. Drawn between the title and the outline.
    public var leadingTitleGap: CGFloat = 0

    /**
     * Optional fixed heights for individual table rows.
     *
     * The dictionary key is the zero-based row index and the value is the height
     * of that row. Rows without an entry keep the default automatic height
     * calculation based on their content.
     *
     * ```swift
     * table.fixedRowHeights = [
     *     0: 24,
     *     1: 28,
     *     2: 32
     * ]
     * ```
     */
    public var fixedRowHeights: [Int: CGFloat] = [:]

    /**
     * Count of rows and columns in this table
     *
     * The size of the table needs to be defined beforehand, so that cells can be accessed using subscript accessors
     */
    public private(set) var size: (rows: Int, columns: Int)

    /**
     * Creates a new table with the given size and populates it with empty cells
     *
     * - Parameter size: Row and column count of table
     */
    public convenience init(size: (rows: Int, columns: Int)) {
        self.init(rows: size.rows, columns: size.columns)
    }

    /**
     * Creates a new table with the given size and populates it with empty cells.
     * - Parameters:
     *   - rows: Rows of table, must be greater than 0
     *   - columns: Columns of table, must be greater than 0
     */
    public init(rows: Int, columns: Int) {
        assert(rows >= 0, "Can't create a table with negative row count")
        assert(columns >= 0, "Can't create a table with negative column count")
        self.size = (rows: rows, columns: columns)
        self.cells = (0..<rows).map { _ in (0..<columns).map { _ in PDFTableCell() } }
        self.widths = (0..<columns).map { _ in 1.0 / CGFloat(columns) }
    }

    /// nodoc
    var copy: PDFTable {
        let table = PDFTable(size: size)
        table.style = style
        table.cells = cells
        table.widths = widths
        table.padding = padding
        table.horizontalInset = horizontalInset
        table.verticalInset = verticalInset
        table.margin = margin
        table.continuousRowFills = continuousRowFills
        table.showHeadersOnEveryPage = showHeadersOnEveryPage
        table.fixedRowHeights = fixedRowHeights
        table.minimumBodyRowsOnFirstPage = minimumBodyRowsOnFirstPage
        table.titleRowCount = titleRowCount
        table.continuationSuffix = continuationSuffix
        table.adoptsPrecedingTitle = adoptsPrecedingTitle
        table.leadingTitle = leadingTitle.map { PDFSimpleText(text: $0.text, spacing: $0.spacing, style: $0.style) }
        table.leadingTitleGap = leadingTitleGap
        return table
    }

    /// Shorthand accessor to the rows stored in ``PDFTable/cells``
    public var rows: PDFTableRows {
        self[rows: 0..<size.rows]
    }

    /// Shorthand accessor to the columns stored in ``PDFTable/cells``
    public var columns: PDFTableColumns {
        self[columns: 0..<size.columns]
    }

    /// Shorthand accessor to the cell values of this table
    public var content: [[PDFTableContentable?]] {
        get {
            rows.content
        }
        set {
            rows.content = newValue
        }
    }

    /// Shorthand accessor to the cell alignments of this table
    public var alignment: [[PDFTableCellAlignment]] {
        get {
            rows.alignment
        }
        set {
            rows.alignment = newValue
        }
    }

    // MARK: - Equatable

    /// nodoc
    override public func isEqual(to other: PDFDocumentObject) -> Bool {
        guard super.isEqual(to: other) else { return false }

        guard let otherTable = other as? PDFTable else {
            return false
        }
        guard style == otherTable.style else {
            return false
        }
        guard cells.count == otherTable.cells.count else {
            return false
        }
        for i in 0..<cells.count where cells[i] != otherTable.cells[i] {
            return false
        }
        guard widths == otherTable.widths else {
            return false
        }
        guard padding == otherTable.padding else {
            return false
        }
        guard horizontalInset == otherTable.horizontalInset else {
            return false
        }
        guard verticalInset == otherTable.verticalInset else {
            return false
        }
        guard margin == otherTable.margin else {
            return false
        }
        guard continuousRowFills == otherTable.continuousRowFills else {
            return false
        }
        guard showHeadersOnEveryPage == otherTable.showHeadersOnEveryPage else {
            return false
        }
        guard fixedRowHeights == otherTable.fixedRowHeights else {
            return false
        }
        guard minimumBodyRowsOnFirstPage == otherTable.minimumBodyRowsOnFirstPage else {
            return false
        }
        guard titleRowCount == otherTable.titleRowCount else {
            return false
        }
        guard continuationSuffix == otherTable.continuationSuffix else {
            return false
        }
        guard adoptsPrecedingTitle == otherTable.adoptsPrecedingTitle else {
            return false
        }
        guard leadingTitleGap == otherTable.leadingTitleGap else {
            return false
        }
        guard leadingTitle?.text == otherTable.leadingTitle?.text else {
            return false
        }
        guard leadingTitle?.spacing == otherTable.leadingTitle?.spacing else {
            return false
        }
        guard leadingTitle?.style == otherTable.leadingTitle?.style else {
            return false
        }
        return true
    }
}
