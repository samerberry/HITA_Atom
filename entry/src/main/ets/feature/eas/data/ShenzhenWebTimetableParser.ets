/**
 * 深圳新版 Web 教务课表解析器。
 *
 * Android 端对应 ShenzhenWebAcademicParser：课表和已选课程都是 JSON，
 * 结构在不同部署之间会落在 list/content/data/result 等包裹层中，因此这里
 * 只依赖字段语义，不依赖某一个固定的根节点形状。
 */
import {
  EasTimePeriodInDay
} from '../../../common/model/timetable/TimetableModels';
import { EasCourseItem, EasTermItem } from '../model/EasModels';
import { EasLegacyTimetableParser } from './EasLegacyTimetableParser';

export class ShenzhenSubjectMeta {
  code: string = '';
  name: string = '';
  teacher: string = '';
  key: string = '';
  /** 课程性质：必修、限选、任选等。 */
  courseProperty: string = '';
  /** 课程类别：专业课、通识课等。 */
  courseCategory: string = '';
  /** 考核方式：考试、考查，或“是否考试课”的布尔值。 */
  assessMethod: string = '';
  /** 选课方式/任务类型：专选、任选、MOOC 等。 */
  selectionCategory: string = '';
}

class SchedulePeriodEntry {
  order: number;
  period: EasTimePeriodInDay;

  constructor(order: number, period: EasTimePeriodInDay) {
    this.order = order;
    this.period = period;
  }
}

function asRecord(value: Object | undefined): Record<string, Object> | undefined {
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) {
    return undefined;
  }
  return value as Record<string, Object>;
}

function textValue(row: Record<string, Object>, keys: string[]): string {
  for (let i = 0; i < keys.length; i++) {
    const value: Object | undefined = row[keys[i]];
    if (value === undefined || value === null) {
      continue;
    }
    let text: string = '';
    if (typeof value === 'string') {
      text = value as string;
    } else if (typeof value === 'number' || typeof value === 'boolean') {
      text = String(value);
    }
    text = text.trim();
    if (text.length > 0 && text.toLowerCase() !== 'null') {
      return text;
    }
  }
  return '';
}

function numberValue(row: Record<string, Object>, keys: string[]): number | undefined {
  const text: string = textValue(row, keys);
  if (text.length === 0) {
    return undefined;
  }
  const result: number = Number(text);
  return Number.isNaN(result) ? undefined : result;
}

function parseRoot(body: string): Object | undefined {
  try {
    return JSON.parse(body) as Object;
  } catch (e) {
    return undefined;
  }
}

function rowsFromValue(value: Object | undefined): Array<Record<string, Object>> {
  const result: Array<Record<string, Object>> = [];
  if (value === undefined || value === null) {
    return result;
  }
  if (Array.isArray(value)) {
    const values: Object[] = value as Object[];
    for (let i = 0; i < values.length; i++) {
      const row: Record<string, Object> | undefined = asRecord(values[i]);
      if (row === undefined) {
        continue;
      }
      const hasRowShape: boolean = ['XQJ', 'xqj', 'KSJC', 'ksjc', 'KCMC', 'kcmc',
        'XN', 'xn', 'XQ', 'xq', 'KCDM', 'kcdm'].some((key: string): boolean => {
        return row[key] !== undefined;
      });
      if (hasRowShape) {
        result.push(row);
      } else {
        const nestedRows: Array<Record<string, Object>> = rowsFromValue(row);
        if (nestedRows.length > 0) {
          result.push(...nestedRows);
        } else {
          result.push(row);
        }
      }
    }
    return result;
  }
  const record: Record<string, Object> | undefined = asRecord(value);
  if (record === undefined) {
    return result;
  }
  const directKeys: string[] = [
    'list', 'content', 'data', 'rows', 'result', 'resultData', 'kbjclist',
    'kbxxList', 'kcxxList', 'yxkcList', 'sksjList', 'timeList'
  ];
  for (let i = 0; i < directKeys.length; i++) {
    const nested: Object | undefined = record[directKeys[i]];
    if (nested === undefined || nested === null) {
      continue;
    }
    const rows: Array<Record<string, Object>> = rowsFromValue(nested);
    if (rows.length > 0) {
      return rows;
    }
  }
  const keys: string[] = Object.keys(record);
  for (let i = 0; i < keys.length; i++) {
    const nested: Object | undefined = record[keys[i]];
    const rows: Array<Record<string, Object>> = rowsFromValue(nested);
    if (rows.length > 0) {
      result.push(...rows);
    }
  }
  return result;
}

function htmlText(raw: string): string {
  let text: string = raw;
  text = text.replace(/<br\s*\/?>/gi, '\n');
  text = text.replace(/<[^>]+>/g, ' ');
  text = text.replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'");
  text = text.replace(/&#(\d+);/g, (all: string, n: string): string => {
    const code: number = Number(n);
    return Number.isNaN(code) ? all : String.fromCharCode(code);
  });
  return text.replace(/\u00a0/g, ' ').trim();
}

function scheduleLines(raw: string): string[] {
  const text: string = htmlText(raw);
  const pieces: string[] = text.split(/[\n;；]+/);
  const result: string[] = [];
  for (let i = 0; i < pieces.length; i++) {
    const item: string = pieces[i].replace(/\s+/g, ' ').trim();
    if (item.length > 0) {
      result.push(item);
    }
  }
  return result;
}

function parseWeeks(raw: string): number[] {
  const compact: string = raw.replace(/\s/g, '');
  const result: Set<number> = new Set<number>();
  if (compact.length >= 3 && /^[01]+$/.test(compact)) {
    const bits: string = compact.substring(1);
    for (let i = 0; i < bits.length && i < 33; i++) {
      if (bits.charAt(i) === '1') {
        result.add(i + 1);
      }
    }
  } else {
    const matches: RegExpMatchArray | null = compact.match(/(\d+)(?:[-－–—~～至到](\d+))?/g);
    if (matches !== null) {
      for (let i = 0; i < matches.length; i++) {
        const range: RegExpExecArray | null = /^(\d+)(?:[-－–—~～至到](\d+))?$/.exec(matches[i]);
        if (range === null) {
          continue;
        }
        const start: number = Number(range[1]);
        const end: number = range[2] === undefined ? start : Number(range[2]);
        if (start < 1 || end < start || end > 33) {
          continue;
        }
        for (let week = start; week <= end; week++) {
          result.add(week);
        }
      }
    }
  }
  return Array.from(result).sort((a: number, b: number): number => a - b);
}

function parseWeekday(row: Record<string, Object>): number | undefined {
  const direct: number | undefined = numberValue(row, ['XQJ', 'xqj', 'weekday', 'weekDay']);
  if (direct !== undefined && direct >= 1 && direct <= 7) {
    return Math.trunc(direct);
  }
  const key: string = textValue(row, ['KEY', 'key']);
  const match: RegExpExecArray | null = /xq(\d+)_jc/i.exec(key);
  if (match !== null) {
    const parsed: number = Number(match[1]);
    if (parsed >= 1 && parsed <= 7) {
      return parsed;
    }
  }
  return undefined;
}

function inferCourseCode(task: string): string {
  const match: RegExpExecArray | null = /^\d{4}-\d{4}-\d-([A-Za-z]+\d+[A-Za-z]?(?:-\d+)?)/.exec(task);
  return match === null ? '' : match[1];
}

function looksLikeWeeks(value: string): boolean {
  return value.indexOf('周') >= 0 || /week/i.test(value);
}

function looksLikePeriods(value: string): boolean {
  return value.indexOf('节') >= 0 || /^\d+\s*[-—]\s*\d+$/.test(value);
}

function looksLikeClassroom(value: string): boolean {
  return /^(?:[A-Z]{1,4}|教学楼|大学城|体育馆|主楼|实训楼|经管楼).*[0-9场地]|^[A-Z]{1,4}\d{2,4}$/i.test(value);
}

function firstNonBlank(values: string[]): string {
  for (let i = 0; i < values.length; i++) {
    if (values[i].trim().length > 0) {
      return values[i].trim();
    }
  }
  return '';
}

function termFromRow(row: Record<string, Object>): EasTermItem | undefined {
  let year: string = textValue(row, ['XN', 'xn', 'yearCode', 'year']);
  let term: string = textValue(row, ['XQ', 'xq', 'termCode', 'term']);
  const combined: string = textValue(row, ['XNXQ', 'xnxq', 'XNXQMC', 'xnxqmc', 'id', 'ID']);
  if ((year.length === 0 || term.length === 0) && combined.length > 0) {
    const match: RegExpExecArray | null = /(\d{4}\s*[-－]\s*\d{4})[-－]?(\d{1,2})/.exec(combined);
    if (match !== null) {
      if (year.length === 0) {
        year = match[1].replace(/\s/g, '');
      }
      if (term.length === 0) {
        term = match[2];
      }
    }
  }
  if (year.length === 0 || term.length === 0) {
    return undefined;
  }
  const out: EasTermItem = new EasTermItem();
  out.yearCode = year;
  out.yearName = firstNonBlank([textValue(row, ['XNMC', 'xnmc', 'yearName']), year]);
  out.termCode = term;
  out.termName = textValue(row, ['XQMC', 'xqmc', 'XNXQMC', 'xnxqmc', 'termName']);
  out.isCurrent = textValue(row, ['SFDQXQ', 'sfdqxq', 'isCurrent', 'current']) === '1' ||
    textValue(row, ['isCurrent', 'current']).toLowerCase() === 'true';
  return out;
}

export function parseShenzhenWebTerms(body: string): EasTermItem[] {
  const root: Object | undefined = parseRoot(body);
  if (root !== undefined) {
    const rows: Array<Record<string, Object>> = rowsFromValue(root);
    const result: EasTermItem[] = [];
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < rows.length; i++) {
      const term: EasTermItem | undefined = termFromRow(rows[i]);
      if (term !== undefined && !seen.has(term.getCode())) {
        seen.add(term.getCode());
        result.push(term);
      }
    }
    if (result.length > 0) {
      return result;
    }
  }
  return EasLegacyTimetableParser.parseTerms(body);
}

export function parseShenzhenWebSelectedSubjects(body: string): ShenzhenSubjectMeta[] {
  const root: Object | undefined = parseRoot(body);
  if (root === undefined) {
    return [];
  }
  const rows: Array<Record<string, Object>> = rowsFromValue(root);
  const result: ShenzhenSubjectMeta[] = [];
  for (let i = 0; i < rows.length; i++) {
    const row: Record<string, Object> = rows[i];
    const code: string = textValue(row, ['kcdm', 'KCDM', 'courseCode']);
    const name: string = textValue(row, ['kcmc', 'KCMC', 'courseName']);
    if (code.length === 0 && name.length === 0) {
      continue;
    }
    const meta: ShenzhenSubjectMeta = new ShenzhenSubjectMeta();
    meta.code = code;
    meta.name = name;
    meta.teacher = textValue(row, ['dgjsmc', 'DGJSMC', 'jsmc', 'JSMC', 'skjs', 'SKJS']);
    meta.key = textValue(row, ['rwh', 'RWH', 'id', 'ID']);
    meta.courseProperty = textValue(row, [
      'kcxzmc', 'KCXZMC', 'kcxz', 'KCXZ', 'courseProperty', 'courseNature'
    ]);
    meta.courseCategory = textValue(row, [
      'kclbmc', 'KCLBMC', 'kclb', 'KCLB', 'courseCategory', 'courseField'
    ]);
    meta.assessMethod = textValue(row, [
      'khfs', 'KHFS', 'khfsmc', 'KHFSMC', 'khsj', 'KHSJ',
      'sfks', 'SFKS', 'sffsks', 'SFFSKS', 'isExamCourse', 'examCourse', 'isExam'
    ]);
    meta.selectionCategory = textValue(row, [
      'rwlxmc', 'RWLXMC', 'xkfsmc', 'XKFSMC', 'xklbmc', 'XKLBMC',
      'xkfsdm', 'XKFSDM', 'selectCategory', 'selectionCategory'
    ]);
    result.push(meta);
  }
  return result;
}

export function parseShenzhenWebTimetable(body: string, subjects: ShenzhenSubjectMeta[] = []): EasCourseItem[] | undefined {
  const root: Object | undefined = parseRoot(body);
  if (root === undefined) {
    return undefined;
  }
  const rows: Array<Record<string, Object>> = rowsFromValue(root);
  if (rows.length === 0) {
    return [];
  }
  const metadata: Map<string, ShenzhenSubjectMeta> = new Map<string, ShenzhenSubjectMeta>();
  for (let i = 0; i < subjects.length; i++) {
    if (subjects[i].key.length > 0) {
      metadata.set(subjects[i].key, subjects[i]);
    }
    if (subjects[i].code.length > 0) {
      metadata.set(subjects[i].code, subjects[i]);
    }
  }
  const result: EasCourseItem[] = [];
  for (let i = 0; i < rows.length; i++) {
    const row: Record<string, Object> = rows[i];
    const beginValue: number | undefined = numberValue(row, ['KSJC', 'ksjc', 'beginPeriod']);
    const endValue: number | undefined = numberValue(row, ['JSJC', 'jsjc', 'endPeriod']);
    const weekday: number | undefined = parseWeekday(row);
    const weeks: number[] = parseWeeks(textValue(row, ['ZC', 'zc', 'weeks', 'SKZC', 'skzc']));
    if (beginValue === undefined || endValue === undefined || weekday === undefined ||
      beginValue < 1 || endValue < beginValue || weeks.length === 0) {
      continue;
    }
    const task: string = textValue(row, ['RWH', 'rwh', 'taskId']);
    const detailLines: string[] = scheduleLines(textValue(row, ['SKSJ', 'sksj', 'schedule']));
    const meta: ShenzhenSubjectMeta | undefined = metadata.get(task) ||
      metadata.get(textValue(row, ['KCDM', 'kcdm']));
    const rawName: string = firstNonBlank([
      textValue(row, ['KCMC', 'kcmc', 'courseName']),
      meta === undefined ? '' : meta.name,
      detailLines.length > 0 ? detailLines[0] : ''
    ]);
    if (rawName.length === 0 || rawName === '备注' || rawName === '说明') {
      continue;
    }
    const bracketValues: string[] = [];
    for (let j = 0; j < detailLines.length; j++) {
      const matches: RegExpMatchArray | null = detailLines[j].match(/[\[【]([^\]】]+)[\]】]/g);
      if (matches === null) {
        continue;
      }
      for (let k = 0; k < matches.length; k++) {
        bracketValues.push(matches[k].substring(1, matches[k].length - 1).trim());
      }
    }
    let teacher: string = '';
    for (let j = 0; j < bracketValues.length; j++) {
      const value: string = bracketValues[j];
      if (!looksLikeWeeks(value) && !looksLikePeriods(value) && !looksLikeClassroom(value)) {
        teacher = value;
        break;
      }
    }
    teacher = firstNonBlank([teacher, meta === undefined ? '' : meta.teacher,
      textValue(row, ['JSXM', 'jsxm', 'teacher'])]);
    let classroom: string = '';
    for (let j = bracketValues.length - 1; j >= 0; j--) {
      const value: string = bracketValues[j];
      if (!looksLikeWeeks(value) && !looksLikePeriods(value) && value !== teacher) {
        classroom = value;
        break;
      }
    }
    classroom = firstNonBlank([classroom, textValue(row, ['CDMC', 'cdmc', 'JASMC', 'jasmc', 'location'])]);
    const item: EasCourseItem = new EasCourseItem();
    item.code = firstNonBlank([textValue(row, ['KCDM', 'kcdm']), meta === undefined ? '' : meta.code,
      inferCourseCode(task)]);
    item.name = rawName;
    item.rawName = rawName;
    item.weekNumbers = weeks;
    item.weeks = weeks.join(',');
    item.teacher = teacher;
    item.classroom = classroom;
    item.courseProperty = firstNonBlank([
      textValue(row, ['KCXZMC', 'kcxzmc', 'KCXZ', 'kcxz', 'courseProperty', 'courseNature']),
      meta === undefined ? '' : meta.courseProperty
    ]);
    item.courseCategory = firstNonBlank([
      textValue(row, ['KCLBMC', 'kclbmc', 'KCLB', 'kclb', 'courseCategory', 'courseField']),
      meta === undefined ? '' : meta.courseCategory
    ]);
    item.assessMethod = firstNonBlank([
      textValue(row, [
        'KHFS', 'khfs', 'KHFSMC', 'khfsmc', 'KHSJ', 'khsj',
        'SFKS', 'sfks', 'SFFSKS', 'sffsks', 'isExamCourse', 'examCourse', 'isExam'
      ]),
      meta === undefined ? '' : meta.assessMethod
    ]);
    item.selectionCategory = firstNonBlank([
      textValue(row, [
        'RWLXMC', 'rwlxmc', 'XKFSMC', 'xkfsmc', 'XKLBMC', 'xklbmc',
        'XKFSDM', 'xkfsdm', 'selectCategory', 'selectionCategory'
      ]),
      meta === undefined ? '' : meta.selectionCategory
    ]);
    item.dayOfWeek = weekday;
    item.beginSection = Math.trunc(beginValue);
    item.sectionCount = Math.trunc(endValue - beginValue + 1);
    result.push(item);
  }
  return result;
}

export function parseShenzhenWebScheduleStructure(body: string): EasTimePeriodInDay[] | undefined {
  const root: Object | undefined = parseRoot(body);
  if (root === undefined) {
    return undefined;
  }
  const rows: Array<Record<string, Object>> = rowsFromValue(root);
  const result: SchedulePeriodEntry[] = [];
  for (let i = 0; i < rows.length; i++) {
    const row: Record<string, Object> = rows[i];
    const order: number | undefined = numberValue(row, ['XJ', 'xj', 'KS', 'ks', 'DJ', 'dj']);
    const start: string = textValue(row, ['KSSJ', 'kssj', 'startTime']);
    const end: string = textValue(row, ['JSSJ', 'jssj', 'endTime']);
    const from: number[] = parseClock(start);
    const to: number[] = parseClock(end);
    if (order === undefined || from.length < 2 || to.length < 2) {
      continue;
    }
    result.push(new SchedulePeriodEntry(Math.trunc(order),
      EasTimePeriodInDay.ofHour(from[0], from[1], to[0], to[1])));
  }
  result.sort((a, b) => a.order - b.order);
  return result.length === 0 ? undefined : result.map((item) => item.period);
}

function parseClock(raw: string): number[] {
  const direct: RegExpExecArray | null = /(\d{1,2}):(\d{1,2})/.exec(raw);
  if (direct !== null) {
    const hour: number = Number(direct[1]);
    const minute: number = Number(direct[2]);
    if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
      return [hour, minute];
    }
  }
  const parsed: Date = new Date(raw);
  if (!Number.isNaN(parsed.getTime())) {
    return [parsed.getHours(), parsed.getMinutes()];
  }
  return [];
}
