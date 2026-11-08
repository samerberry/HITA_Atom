/**
 * 传统教务（本部/威海）课程属性表解析。
 *
 * 个人课表 /kbcx/queryGrkb 只有排课格子，不含课程性质、学分和“是否考试课”。
 * 执行计划 /zxjh/queryZxkc 与期末成绩 /cjcx/queryQmcj 是服务端渲染的表格，
 * 表头包含这些列；导入课表时据此补全科目类型与学分。
 */
import { EasTermItem } from '../model/EasModels';

export class LegacyCourseAttributes {
  code: string = '';
  name: string = '';
  property: string = '';
  category: string = '';
  /** 学分；未知时为 -1。 */
  credit: number = -1;
  assessMethod: string = '';
  /** 学年学期文本（成绩表“学年学期”或执行计划“开课学年|开课学期”）。 */
  termText: string = '';
}

class LegacyHeaderIndex {
  name: number = -1;
  code: number = -1;
  property: number = -1;
  category: number = -1;
  credit: number = -1;
  assess: number = -1;
  term: number = -1;
  year: number = -1;
  semester: number = -1;
}

export class EasLegacyCourseCatalogParser {
  /** 取页面中数据行最多的课程属性表。 */
  static parseTables(html: string): LegacyCourseAttributes[] {
    let best: LegacyCourseAttributes[] = [];
    const tablePattern: RegExp = /<table\b[^>]*>([\s\S]*?)<\/table>/gi;
    let table: RegExpExecArray | null = tablePattern.exec(html);
    while (table !== null) {
      const records: LegacyCourseAttributes[] = EasLegacyCourseCatalogParser.parseTable(table[1]);
      if (records.length > best.length) {
        best = records;
      }
      table = tablePattern.exec(html);
    }
    return best;
  }

  private static parseTable(tableHtml: string): LegacyCourseAttributes[] {
    const out: LegacyCourseAttributes[] = [];
    const rows: string[] = EasLegacyCourseCatalogParser.tagContents(tableHtml, 'tr');
    let headerRow: number = -1;
    let index: LegacyHeaderIndex = new LegacyHeaderIndex();
    for (let i: number = 0; i < rows.length; i++) {
      const headers: string[] = EasLegacyCourseCatalogParser.cellTexts(rows[i])
        .map((text: string): string => EasLegacyCourseCatalogParser.normalizeHeader(text));
      const candidate: LegacyHeaderIndex = EasLegacyCourseCatalogParser.indexHeaders(headers);
      if (candidate.name >= 0 && (candidate.assess >= 0 || candidate.property >= 0 || candidate.credit >= 0)) {
        headerRow = i;
        index = candidate;
        break;
      }
    }
    if (headerRow < 0) {
      return out;
    }
    for (let i: number = headerRow + 1; i < rows.length; i++) {
      const cells: string[] = EasLegacyCourseCatalogParser.cellTexts(rows[i]);
      const name: string = EasLegacyCourseCatalogParser.cellAt(cells, index.name);
      if (name.length === 0) {
        continue;
      }
      const item: LegacyCourseAttributes = new LegacyCourseAttributes();
      item.name = name;
      item.code = EasLegacyCourseCatalogParser.cellAt(cells, index.code);
      item.property = EasLegacyCourseCatalogParser.cellAt(cells, index.property);
      item.category = EasLegacyCourseCatalogParser.cellAt(cells, index.category);
      item.assessMethod = EasLegacyCourseCatalogParser.cellAt(cells, index.assess);
      const creditText: string = EasLegacyCourseCatalogParser.cellAt(cells, index.credit);
      const credit: number = creditText.length > 0 ? Number(creditText) : NaN;
      item.credit = Number.isNaN(credit) || credit < 0 ? -1 : credit;
      if (index.term >= 0) {
        item.termText = EasLegacyCourseCatalogParser.cellAt(cells, index.term);
      } else if (index.year >= 0 || index.semester >= 0) {
        item.termText = EasLegacyCourseCatalogParser.cellAt(cells, index.year) + '|' +
          EasLegacyCourseCatalogParser.cellAt(cells, index.semester);
      }
      out.push(item);
    }
    return out;
  }

  private static indexHeaders(headers: string[]): LegacyHeaderIndex {
    const index: LegacyHeaderIndex = new LegacyHeaderIndex();
    for (let i: number = 0; i < headers.length; i++) {
      const h: string = headers[i];
      if (h === '课程名称' && index.name < 0) {
        index.name = i;
      } else if ((h.indexOf('课程代码') >= 0 || h === '课程号') && index.code < 0) {
        index.code = i;
      } else if (h === '课程性质' && index.property < 0) {
        index.property = i;
      } else if (h === '课程类别' && index.category < 0) {
        index.category = i;
      } else if (h === '学分' && index.credit < 0) {
        index.credit = i;
      } else if ((h === '是否考试课' || h === '考核方式') && index.assess < 0) {
        index.assess = i;
      } else if (h === '学年学期' && index.term < 0) {
        index.term = i;
      } else if ((h === '开课学年' || h === '开课年度') && index.year < 0) {
        index.year = i;
      } else if (h === '开课学期' && index.semester < 0) {
        index.semester = i;
      }
    }
    return index;
  }

  /**
   * 提取包含指定字段的表单的全部提交字段（hidden/text 输入与 select 选中值）。
   * 传统教务的查询页拒绝只带部分筛选字段的 POST，必须原样回传隐藏字段。
   */
  static parseFormFields(html: string, requiredField: string): Map<string, string> | undefined {
    const formPattern: RegExp = /<form\b[^>]*>([\s\S]*?)<\/form>/gi;
    let form: RegExpExecArray | null = formPattern.exec(html);
    while (form !== null) {
      const body: string = form[1];
      if (new RegExp('name\\s*=\\s*["\']?' + requiredField + '\\b', 'i').test(body)) {
        return EasLegacyCourseCatalogParser.collectFields(body);
      }
      form = formPattern.exec(html);
    }
    return undefined;
  }

  private static collectFields(formHtml: string): Map<string, string> {
    const fields: Map<string, string> = new Map<string, string>();
    const inputPattern: RegExp = /<input\b([^>]*)>/gi;
    let input: RegExpExecArray | null = inputPattern.exec(formHtml);
    while (input !== null) {
      const attrs: string = input[1];
      const name: string = EasLegacyCourseCatalogParser.attribute(attrs, 'name');
      const type: string = EasLegacyCourseCatalogParser.attribute(attrs, 'type').toLowerCase();
      const skip: boolean = type === 'button' || type === 'submit' || type === 'reset' || type === 'image' ||
        ((type === 'checkbox' || type === 'radio') && !/\bchecked\b/i.test(attrs));
      if (name.length > 0 && !skip) {
        fields.set(name, EasLegacyCourseCatalogParser.decodeHtml(
          EasLegacyCourseCatalogParser.attribute(attrs, 'value')));
      }
      input = inputPattern.exec(formHtml);
    }
    const selectPattern: RegExp = /<select\b([^>]*)>([\s\S]*?)<\/select>/gi;
    let select: RegExpExecArray | null = selectPattern.exec(formHtml);
    while (select !== null) {
      const name: string = EasLegacyCourseCatalogParser.attribute(select[1], 'name');
      if (name.length > 0) {
        fields.set(name, EasLegacyCourseCatalogParser.selectedOption(select[2]));
      }
      select = selectPattern.exec(formHtml);
    }
    return fields;
  }

  private static selectedOption(optionsHtml: string): string {
    const optionPattern: RegExp = /<option\b([^>]*)>/gi;
    let first: string | undefined = undefined;
    let option: RegExpExecArray | null = optionPattern.exec(optionsHtml);
    while (option !== null) {
      const value: string = EasLegacyCourseCatalogParser.decodeHtml(
        EasLegacyCourseCatalogParser.attribute(option[1], 'value'));
      if (first === undefined) {
        first = value;
      }
      if (/\bselected\b/i.test(option[1])) {
        return value;
      }
      option = optionPattern.exec(optionsHtml);
    }
    return first === undefined ? '' : first;
  }

  /** 课程名匹配键：去空白、统一全/半角括号。 */
  static nameKey(name: string): string {
    return name.replace(/[\s\u00a0\u3000]/g, '')
      .replace(/（/g, '(').replace(/）/g, ')')
      .replace(/【/g, '[').replace(/】/g, ']')
      .toLowerCase();
  }

  /** 行的学年学期文本是否对应指定学期（兼容“2025-20262”“2025-2026春季”“2025-2026|2”）。 */
  static matchesTerm(termText: string, term: EasTermItem): boolean {
    const text: string = termText.replace(/\s/g, '');
    if (text.length === 0 || text === '|') {
      return false;
    }
    if (text.indexOf(term.getCode()) >= 0) {
      return true;
    }
    const yearAt: number = text.indexOf(term.yearCode);
    if (yearAt < 0) {
      return false;
    }
    const rest: string = text.substring(0, yearAt) + text.substring(yearAt + term.yearCode.length);
    if (rest.replace(/[^0-9]/g, '') === term.termCode) {
      return true;
    }
    if (term.termCode === '1') {
      return /秋|第一|一学期/.test(rest);
    }
    if (term.termCode === '2') {
      return /春|第二|二学期/.test(rest);
    }
    if (term.termCode === '3') {
      return /夏|第三|三学期/.test(rest);
    }
    return /冬|第四|四学期/.test(rest);
  }

  private static cellAt(cells: string[], index: number): string {
    return index >= 0 && index < cells.length ? cells[index] : '';
  }

  private static normalizeHeader(raw: string): string {
    return raw.replace(/[\s\u00a0：:*]/g, '');
  }

  private static cellTexts(rowHtml: string): string[] {
    const pattern: RegExp = /<(?:td|th)\b[^>]*>([\s\S]*?)<\/(?:td|th)>/gi;
    const out: string[] = [];
    let match: RegExpExecArray | null = pattern.exec(rowHtml);
    while (match !== null) {
      out.push(EasLegacyCourseCatalogParser.decodeHtml(match[1].replace(/<[^>]+>/g, ' '))
        .replace(/[\u00a0\s]+/g, ' ').trim());
      match = pattern.exec(rowHtml);
    }
    return out;
  }

  private static tagContents(html: string, tag: string): string[] {
    const pattern: RegExp = new RegExp('<' + tag + '\\b[^>]*>([\\s\\S]*?)<\\/' + tag + '>', 'gi');
    const out: string[] = [];
    let match: RegExpExecArray | null = pattern.exec(html);
    while (match !== null) {
      out.push(match[1]);
      match = pattern.exec(html);
    }
    return out;
  }

  private static attribute(attrs: string, name: string): string {
    const quoted: RegExpExecArray | null = new RegExp('\\b' + name +
      '\\s*=\\s*["\']([^"\']*)["\']', 'i').exec(attrs);
    if (quoted !== null) {
      return quoted[1];
    }
    const bare: RegExpExecArray | null = new RegExp('\\b' + name + '\\s*=\\s*([^\\s>]+)', 'i').exec(attrs);
    return bare === null ? '' : bare[1];
  }

  private static decodeHtml(raw: string): string {
    return raw.replace(/&nbsp;|&#160;/gi, ' ')
      .replace(/&amp;/gi, '&').replace(/&lt;/gi, '<').replace(/&gt;/gi, '>')
      .replace(/&quot;/gi, '"').replace(/&#39;|&apos;/gi, "'");
  }
}
