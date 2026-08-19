import ExcelJS from 'exceljs';

/** Shared building blocks for every report's exported workbook — title
 * block, section headers, bordered/striped tables with an optional TOTAL
 * row, auto-sized columns, and a frozen header row. Every report
 * (Operations, Drivers, Commuters, Trips, Incident Reports) is built from
 * these same pieces so they all read as one consistent, professional
 * document family rather than five bespoke layouts.
 */

const COLOR_INK = 'FF0A0F2C';
const COLOR_MUTED = 'FF6B7280';
const COLOR_BRAND_BLUE = 'FF0B57D0';
const COLOR_HEADER_FILL = 'FF0B57D0';
const COLOR_HEADER_TEXT = 'FFFFFFFF';
const COLOR_SECTION_FILL = 'FFEAF1FD';
const COLOR_TOTAL_FILL = 'FFF3F4F6';
const COLOR_BORDER = 'FFD9DEE7';
const COLOR_STRIPE = 'FFF8FAFC';

export type ColumnType = 'text' | 'number' | 'currency' | 'percent' | 'date' | 'time' | 'boolean';

export interface ColumnSpec {
  header: string;
  type: ColumnType;
  /** Overrides the type's default width (in Excel "characters" units). */
  width?: number;
  /** Overrides the type's default alignment — e.g. a 'text' column that
   * still needs right-alignment because it holds pre-formatted mixed
   * units (see the Operations Report's Metric/Value summary table). */
  align?: 'left' | 'right' | 'center';
}

const MANILA_TZ = 'Asia/Manila';
const manilaPartsFormatter = new Intl.DateTimeFormat('en-US', {
  timeZone: MANILA_TZ,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hour12: false,
});

/** A real local `Date` whose wall-clock components equal `iso`'s moment
 * as seen in Asia/Manila — safe to hand to an Excel date/time cell (which
 * has no timezone concept of its own and just serializes local
 * components), regardless of what timezone the browser generating the
 * file happens to be in. Mirrors formatDate.ts's own Manila-pinned
 * formatters, just producing a Date for a spreadsheet cell instead of a
 * display string. */
export function toManilaExcelDate(iso: string): Date {
  const parts = manilaPartsFormatter.formatToParts(new Date(iso));
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? 0);
  return new Date(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'), get('second'));
}

/** A real local `Date` for a "YYYY-MM-DD" calendar date (no time-of-day
 * or timezone component to begin with, e.g. the Operations Report's daily
 * breakdown) — built from local components directly so it lands on the
 * same calendar day in the generated spreadsheet regardless of the
 * browser's own timezone. */
export function parseDateOnlyForExcel(isoDay: string): Date {
  const [year, month, day] = isoDay.split('-').map(Number);
  return new Date(year, month - 1, day);
}

/** "₱44,177.00" — for the rare mixed-unit table (Operations Report's
 * Metric/Value summary) where a currency and a plain count share one
 * column, so neither can be a real numeric Excel type. Every other
 * currency cell in these reports uses the real 'currency' column type
 * instead (see NUMFMT) so it stays a native, sortable number. */
export function formatCurrencyText(n: number): string {
  return `₱${n.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/** A row's cells, positionally matching `columns` — numbers/Dates pass
 * through as real Excel values (so they stay sortable/filterable), not
 * pre-formatted strings; null renders as an em dash except in numeric
 * columns, where it renders as 0 (see [buildDataRow]'s doc comment). */
export type CellValue = string | number | Date | boolean | null;

const DEFAULT_WIDTH: Record<ColumnType, number> = {
  text: 20,
  number: 11,
  currency: 15,
  percent: 12,
  date: 13,
  time: 11,
  boolean: 11,
};

const NUMFMT: Partial<Record<ColumnType, string>> = {
  currency: '"₱"#,##0.00',
  number: '#,##0',
  // Excel's own percent format multiplies the raw cell value by 100 for
  // display — cells using this must hold a fraction (0.798), not 79.8.
  percent: '0.0%',
  date: 'mmm d, yyyy',
  time: 'h:mm AM/PM',
};

const ALIGN: Record<ColumnType, 'left' | 'right' | 'center'> = {
  text: 'left',
  number: 'right',
  currency: 'right',
  percent: 'right',
  date: 'left',
  time: 'left',
  boolean: 'center',
};

function thinBorder(): Partial<ExcelJS.Borders> {
  const style = { style: 'thin' as const, color: { argb: COLOR_BORDER } };
  return { top: style, left: style, bottom: style, right: style };
}

export function createReportWorkbook(): ExcelJS.Workbook {
  const wb = new ExcelJS.Workbook();
  wb.creator = 'Manibela App Admin';
  wb.created = new Date();
  return wb;
}

export function addReportSheet(workbook: ExcelJS.Workbook, name: string): ExcelJS.Worksheet {
  // Sheet names can't exceed 31 chars or contain []:*?/\\.
  const safeName = name.replace(/[[\]:*?/\\]/g, ' ').slice(0, 31);
  return workbook.addWorksheet(safeName, { views: [{ showGridLines: false }] });
}

/** Big bold report title + a subtitle line per entry in `subtitleLines`
 * (report period, "Generated <date>", etc.), each merged across
 * `columnCount` columns. Returns the next empty row number, ready for a
 * section header or table. */
export function addTitleBlock(sheet: ExcelJS.Worksheet, title: string, subtitleLines: string[], columnCount: number): number {
  let row = 1;
  sheet.mergeCells(row, 1, row, columnCount);
  const titleCell = sheet.getCell(row, 1);
  titleCell.value = title;
  titleCell.font = { bold: true, size: 16, color: { argb: COLOR_INK } };
  titleCell.alignment = { vertical: 'middle' };
  sheet.getRow(row).height = 26;
  row++;

  for (const line of subtitleLines) {
    sheet.mergeCells(row, 1, row, columnCount);
    const cell = sheet.getCell(row, 1);
    cell.value = line;
    cell.font = { size: 11, color: { argb: COLOR_MUTED } };
    row++;
  }

  return row + 1; // blank spacer row
}

/** A labeled band (e.g. "SUMMARY", "DAILY BREAKDOWN") spanning
 * `columnCount` columns, marking the start of the section beneath it.
 * Returns the next empty row number. */
export function addSectionHeader(sheet: ExcelJS.Worksheet, label: string, row: number, columnCount: number): number {
  sheet.mergeCells(row, 1, row, columnCount);
  sheet.getRow(row).height = 20;
  for (let c = 1; c <= columnCount; c++) {
    const cell = sheet.getCell(row, c);
    cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: COLOR_SECTION_FILL } };
  }
  const labelCell = sheet.getCell(row, 1);
  labelCell.value = label.toUpperCase();
  labelCell.font = { bold: true, size: 11, color: { argb: COLOR_BRAND_BLUE } };
  labelCell.alignment = { vertical: 'middle', indent: 1 };
  return row + 1;
}

/** Header row (bold white-on-blue) + one row per entry in `rows` (bordered,
 * per-column aligned/number-formatted) + an optional bold TOTAL row.
 * Returns the next empty row after the table (plus a blank spacer). Also
 * returns the header row's own number, for freezing panes above it. */
export function addTable(
  sheet: ExcelJS.Worksheet,
  startRow: number,
  columns: ColumnSpec[],
  rows: CellValue[][],
  totalRow?: CellValue[],
): { headerRow: number; nextRow: number } {
  const headerRow = sheet.getRow(startRow);
  columns.forEach((col, i) => {
    const cell = headerRow.getCell(i + 1);
    cell.value = col.header;
    cell.font = { bold: true, color: { argb: COLOR_HEADER_TEXT } };
    cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: COLOR_HEADER_FILL } };
    cell.alignment = { horizontal: ALIGN[col.type], vertical: 'middle' };
    cell.border = thinBorder();
  });
  headerRow.height = 20;

  let r = startRow + 1;
  rows.forEach((rowValues, rowIndex) => {
    const row = sheet.getRow(r);
    const striped = rowIndex % 2 === 1;
    columns.forEach((col, i) => {
      const cell = row.getCell(i + 1);
      const raw = rowValues[i];
      // A blank numeric cell reads as a hole in the data to a reader
      // scanning a financial table — 0 is what "no fuel expense that day"
      // actually means. Text columns keep the em dash for "not
      // applicable" (a trip with no flag, a driver with no route yet).
      cell.value =
        raw ?? (col.type === 'number' || col.type === 'currency' || col.type === 'percent' ? 0 : col.type === 'text' ? '—' : raw);
      const numFmt = NUMFMT[col.type];
      if (numFmt) cell.numFmt = numFmt;
      cell.alignment = { horizontal: col.align ?? ALIGN[col.type], vertical: 'middle' };
      cell.border = thinBorder();
      if (striped) {
        cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: COLOR_STRIPE } };
      }
    });
    r++;
  });

  if (totalRow) {
    const row = sheet.getRow(r);
    columns.forEach((col, i) => {
      const cell = row.getCell(i + 1);
      cell.value = totalRow[i] ?? '';
      const numFmt = NUMFMT[col.type];
      if (numFmt && typeof totalRow[i] === 'number') cell.numFmt = numFmt;
      cell.font = { bold: true, color: { argb: COLOR_INK } };
      cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: COLOR_TOTAL_FILL } };
      cell.alignment = { horizontal: col.align ?? ALIGN[col.type], vertical: 'middle' };
      cell.border = thinBorder();
    });
    r++;
  }

  return { headerRow: startRow, nextRow: r + 1 };
}

/** Sizes each column from its type's sensible default, widened for text
 * columns to fit the longest actual value — long names/routes/
 * descriptions get room, but a currency or date column never balloons
 * just because one description cell was long. Prevents ####### without
 * needlessly wide numeric columns. */
export function autoFitColumns(sheet: ExcelJS.Worksheet, columns: ColumnSpec[], rows: CellValue[][]): void {
  columns.forEach((col, i) => {
    let width = col.width ?? DEFAULT_WIDTH[col.type];
    if (col.type === 'text' && !col.width) {
      let maxLen = col.header.length;
      for (const row of rows) {
        const v = row[i];
        if (typeof v === 'string') maxLen = Math.max(maxLen, v.length);
      }
      width = Math.min(Math.max(maxLen + 2, col.header.length + 2), 48);
    }
    sheet.getColumn(i + 1).width = width;
  });
}

/** Keeps `headerRowNumber` (and everything above it) visible while the
 * rest of a long table scrolls — only meaningful for a sheet with one
 * dominant table; the multi-table Operations sheets don't use this. */
export function freezeHeaderRow(sheet: ExcelJS.Worksheet, headerRowNumber: number): void {
  sheet.views = [{ showGridLines: false, state: 'frozen', ySplit: headerRowNumber }];
}

/** Renders `workbook` to a .xlsx file and triggers a browser download —
 * the XLSX equivalent of csvExport.ts's downloadCsv. */
export async function downloadWorkbook(workbook: ExcelJS.Workbook, filename: string): Promise<void> {
  const buffer = await workbook.xlsx.writeBuffer();
  const blob = new Blob([buffer], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}
