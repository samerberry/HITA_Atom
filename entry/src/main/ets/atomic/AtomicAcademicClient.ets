import { webview } from '@kit.ArkWeb';
import { EasCourseItem, EasTermItem } from '../feature/eas/model/EasModels';
import { EasLegacyTimetableParser } from '../feature/eas/data/EasLegacyTimetableParser';
import { EasAcademicCalendar } from '../feature/eas/data/EasAcademicCalendar';
import { EasTimePeriodInDay, EasTimetable } from '../common/model/timetable/TimetableModels';
import { parseShenzhenWebTerms, parseShenzhenWebTimetable, parseShenzhenWebSelectedSubjects,
  parseShenzhenWebScheduleStructure, ShenzhenSubjectMeta } from '../feature/eas/data/ShenzhenWebTimetableParser';
import { AtomicWebFetch } from './AtomicWebFetch';
import { AtomicAcademicConfig } from './AtomicAcademicConfig';

/** Reads school HTML in the authenticated Web page; credentials stay in ArkWeb. */
export class AtomicAcademicClient {
  private bridge: AtomicWebFetch;
  private config: AtomicAcademicConfig;
  private generation: number = 0;
  usesDefaultStructure: boolean = false;

  constructor(campus: string = '威海') {
    this.config = new AtomicAcademicConfig(campus);
    this.bridge = new AtomicWebFetch(campus);
  }

  attachController(controller: webview.WebviewController): void { this.bridge.attach(controller); }
  pageStarted(): void { this.generation++; this.bridge.cancel(); }
  close(): void { this.generation++; this.bridge.close(); }

  private checkGeneration(generation: number): void {
    if (this.generation !== generation) throw new Error('登录页面已切换，请重新读取');
  }

  async terms(): Promise<EasTermItem[]> {
    if (this.config.campus === '深圳') return this.shenzhenTerms();
    const html = await this.bridge.request('/kbcx/queryGrkb');
    const terms = EasLegacyTimetableParser.parseTermsBySelect(html, 'xnxq');
    if (terms.length === 0) throw new Error('教务会话尚未就绪，请待教务页面加载完成后重试');
    return terms;
  }

  async courses(term: EasTermItem): Promise<EasCourseItem[]> {
    if (this.config.campus === '深圳') return this.shenzhenCourses(term);
    const body = 'fhlj=kbcx%2FqueryGrkb&xnxq=' + encodeURIComponent(term.getCode());
    const html = await this.bridge.request('/kbcx/queryGrkb', body);
    const terms = EasLegacyTimetableParser.parseTermsBySelect(html, 'xnxq');
    if (terms.length === 0) throw new Error('教务会话已失效，请返回网页登录后重试');
    const selected = terms.find((item: EasTermItem): boolean => item.isCurrent);
    if (selected !== undefined && selected.getCode() !== term.getCode()) {
      throw new Error('教务返回的学期与选择不一致，请重新读取');
    }
    const courses = EasLegacyTimetableParser.parseScheduleHtml(html);
    if (courses.length === 0) throw new Error('该学期未读取到课程，请检查所选学期或教务课表');
    return courses;
  }

  async firstWeek(term: EasTermItem): Promise<number> {
    if (this.config.campus === '深圳') {
      const json = await this.bridge.request('/component/queryRlZcSj', this.termBody(term) + '&djz=1',
        'POST', '/Xsxk/query/1');
      return EasAcademicCalendar.parseShenzhenJson(json, term) ?? 0;
    }
    const body = 'xnxq=' + encodeURIComponent(term.getCode());
    const html = await this.bridge.request('/xlcx/queryXlcx', body);
    return EasAcademicCalendar.parseLegacyHtml(html, term) ?? 0;
  }

  async structure(term: EasTermItem): Promise<EasTimePeriodInDay[]> {
    this.usesDefaultStructure = false;
    if (this.config.campus === '本部') return EasTimetable.getBenbuTimeStructure();
    if (this.config.campus === '威海') return EasTimetable.getWeihaiTimeStructure();
    const generation = this.generation;
    try {
      const json = await this.bridge.request('/component/queryKbjg', this.termBody(term) + '&pylx=1',
        'POST', '/authentication/main');
      this.checkGeneration(generation);
      const parsed = parseShenzhenWebScheduleStructure(json);
      if (parsed !== undefined && parsed.length > 0) return parsed;
    } catch (_) { this.checkGeneration(generation); }
    this.usesDefaultStructure = true;
    return EasTimetable.getDefaultTimeStructure();
  }

  private termBody(term: EasTermItem): string {
    return 'xn=' + encodeURIComponent(term.yearCode) + '&xq=' + encodeURIComponent(term.termCode);
  }

  private async shenzhenTerms(): Promise<EasTermItem[]> {
    const generation = this.generation;
    let terms: EasTermItem[] = [];
    for (const path of ['/component/queryXnxq', '/component/queryxnxqdata']) {
      try {
        // An empty POST is intentional: the portal determines the current role.
        const json = await this.bridge.request(path, '', 'POST', '/Xsxk/query/1');
        terms = parseShenzhenWebTerms(json);
      } catch (_) { this.checkGeneration(generation); }
      this.checkGeneration(generation);
      if (terms.length > 0) break;
    }
    if (terms.length === 0) throw new Error('教务会话尚未就绪，请完成统一身份认证并选择本科生身份后重新读取');
    try {
      const json = await this.bridge.request('/Xsxk/queryXkdqXnxq', 'p_pylx=1', 'POST', '/Xsxk/query/1');
      this.checkGeneration(generation);
      const selected = this.selectionTerm(JSON.parse(json) as Object);
      if (selected && terms.some((term: EasTermItem): boolean => term.yearCode + '-' + term.termCode === selected)) {
        terms.forEach((term: EasTermItem) => { term.isCurrent = term.yearCode + '-' + term.termCode === selected; });
      }
    } catch (_) { this.checkGeneration(generation); }
    return terms.sort((a: EasTermItem, b: EasTermItem): number => a.isCurrent !== b.isCurrent ?
      (a.isCurrent ? -1 : 1) : b.getCode().localeCompare(a.getCode()));
  }

  private selectionTerm(value: Object, depth: number = 0): string {
    if (value === null || typeof value !== 'object' || depth > 8) return '';
    const record = value as Record<string, Object>;
    const text = (keys: string[]): string => {
      for (const key of keys) {
        if (typeof record[key] === 'string' || typeof record[key] === 'number') return String(record[key]).trim();
      }
      return '';
    };
    const year = text(['p_xn', 'xn', 'XN', 'p_dqxn', 'dqxn']);
    const term = text(['p_xq', 'xq', 'XQ', 'p_dqxq', 'dqxq']);
    if (year && term) return year + '-' + term;
    for (const key of Object.keys(record)) {
      const found = this.selectionTerm(record[key], depth + 1);
      if (found) return found;
    }
    return '';
  }

  private selectionBody(term: EasTermItem): string {
    const fields: Map<string, string> = new Map<string, string>();
    for (const key of ['p_xktjz', 'p_chaxunxh', 'p_gjz', 'p_skjs', 'p_xiaoqu', 'p_kkyx', 'p_kclb',
      'p_xkxs', 'p_dyc', 'p_kkxnxq', 'p_id', 'p_kxsj_xqj', 'p_kxsj_ksjc', 'p_kxsj_jsjc', 'p_kcdm_js',
      'p_kcdm_cxrw', 'p_kcdm_cxrw_zckc', 'p_kc_gjz', 'p_xzcxtjz_nj', 'p_xzcxtjz_yx', 'p_xzcxtjz_zy',
      'p_xzcxtjz_zyfx', 'p_xzcxtjz_bj', 'p_skyy', 'p_sfmxzj', 'p_chaxunxkfsdm']) fields.set(key, '');
    for (const key of ['cxsfmt', 'p_sfgldjr', 'p_sfredis', 'p_sfsyxkgwc', 'p_sfhlctkc', 'p_sfhllrlkc']) fields.set(key, '0');
    for (const key of ['p_pylx', 'mxpylx', 'p_sfxsgwckb', 'pageNum', 'studentType']) fields.set(key, '1');
    fields.set('p_xn', term.yearCode); fields.set('p_xq', term.termCode); fields.set('p_xnxq', term.getCode());
    fields.set('p_xkfsdm', 'yixuan'); fields.set('pageSize', '200');
    return Array.from(fields.entries()).map((pair: [string, string]): string => pair[0] + '=' + encodeURIComponent(pair[1])).join('&');
  }

  private async shenzhenCourses(term: EasTermItem): Promise<EasCourseItem[]> {
    const generation = this.generation;
    let subjects: ShenzhenSubjectMeta[] = [];
    try {
      const json = await this.bridge.request('/Xsxk/queryYxkc?sf_request_type=ajax', this.selectionBody(term),
        'POST', '/authentication/main');
      subjects = parseShenzhenWebSelectedSubjects(json);
    } catch (_) { this.checkGeneration(generation); }
    this.checkGeneration(generation);
    const json = await this.bridge.request('/xszykb/queryxszykbzong', this.termBody(term),
      'POST', '/xszykb/queryxszykb', 60000);
    const courses = parseShenzhenWebTimetable(json, subjects);
    if (courses === undefined) throw new Error('教务课表响应无法解析，请确认已登录教务系统');
    if (courses.length === 0) throw new Error('该学期未读取到课程，请检查所选学期或教务课表');
    return courses;
  }
}
