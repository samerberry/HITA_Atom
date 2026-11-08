import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { HitaColors } from '../common/theme/HitaColors';
import { HitaDesign } from '../common/theme/HitaDesign';
import { HitaButton, HitaButtonVariant } from '../common/components/HitaButton';
import { HitaListRow } from '../common/components/HitaListRow';
import { EasCourseItem, EasTermItem } from '../feature/eas/model/EasModels';
import { EasTimetable, EasTimePeriodInDay } from '../common/model/timetable/TimetableModels';
import { AtomicTimetableStore } from './AtomicTimetableStore';
import { AtomicAcademicClient } from './AtomicAcademicClient';
import { AtomicAcademicConfig } from './AtomicAcademicConfig';
import {
  SHENZHEN_GATEWAY_ORIGIN, SHENZHEN_GATEWAY_BOOTSTRAP, SHENZHEN_LOGIN_ORIGINS, SHENZHEN_LOGIN_ADVANCE,
  shenzhenMobileUserAgent
} from './ShenzhenWebLogin';
import { AcademicImportPlan } from './AcademicImportPlan';
import { RdbHelper } from '../common/db/RdbHelper';
import { TimetableSelectionStore } from '../feature/timetable/data/TimetableSelectionStore';

@Component
export struct AcademicLoginContent {
  campus: string = '威海';
  onImported: () => void = () => {};
  @State private busy: boolean = false;
  @State private message: string = '请在学校页面完成登录';
  @State private terms: EasTermItem[] = [];
  @State private selectedTerm: number = 0;
  @State private courses: EasCourseItem[] = [];
  @State private firstWeek: number = 0;
  @State private ready: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private config: AtomicAcademicConfig = new AtomicAcademicConfig();
  private client: AtomicAcademicClient = new AtomicAcademicClient();
  private structure: EasTimePeriodInDay[] = [];
  private alive: boolean = false;
  private plan: AcademicImportPlan | undefined = undefined;
  private autoAttempted: boolean = false;
  private navigationGeneration: number = 0;

  aboutToAppear(): void {
    this.alive = true;
    this.config = new AtomicAcademicConfig(this.campus);
    this.client = new AtomicAcademicClient(this.campus);
    // VPN authentication depends on cross-origin cookie writes from the gateway;
    // third-party cookies and the ITP bypass list must both be active before the
    // WebView loads any page.
    try {
      webview.WebCookieManager.putAcceptCookieEnabled(true);
      webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true);
    } catch (_) {}
    try {
      webview.WebviewController.addIntelligentTrackingPreventionBypassingList(
        this.config.cookieDomains);
    } catch (_) {}
  }
  aboutToDisappear(): void { this.alive = false; this.navigationGeneration++; this.client.close(); }

  private isCurrent(generation: number): boolean { return this.alive && generation === this.navigationGeneration; }

  private attachWeb(): void {
    this.client.attachController(this.controller);
    if (this.campus !== '深圳') return;
    try {
      // Configure once before the first request. aTrust rejects platform=Unknown
      // for the native OpenHarmony UA; retain its mobile layout and engine tokens.
      const deviceUserAgent = this.controller.getUserAgent();
      const compatibleUserAgent = shenzhenMobileUserAgent(deviceUserAgent);
      if (compatibleUserAgent !== deviceUserAgent) this.controller.setCustomUserAgent(compatibleUserAgent);
      this.controller.loadUrl(this.config.loginUrl);
    } catch (_) { this.message = '登录网页初始化失败，请关闭后重试'; }
  }

  private pageStarted(): void {
    if (!this.alive) return;
    this.navigationGeneration++;
    this.client.pageStarted();
    this.busy = false; this.ready = false; this.autoAttempted = false;
    this.courses = []; this.structure = []; this.firstWeek = 0; this.plan = undefined;
  }

  private pageEnded(url: string): void {
    if (!this.alive || this.busy) return;
    const redirect = this.config.redirectFor(url);
    if (redirect) {
      try { this.controller.loadUrl(redirect); } catch (_) {}
      return;
    }
    if (!this.autoAttempted && this.config.shouldRead(url)) {
      this.autoAttempted = true; this.verify();
    }
  }

  private enterAcademic(): void {
    if (this.busy) return;
    this.ready = false;
    this.autoAttempted = false;
    try { this.controller.loadUrl(this.config.loginUrl); this.message = '请在学校页面完成登录，登录后自动读取课表'; }
    catch (_) { this.message = '网页尚未准备好，请稍后重试'; }
  }

  private async verify(): Promise<void> {
    if (this.busy || !this.alive) return;
    const generation = this.navigationGeneration;
    this.busy = true; this.message = '正在验证教务会话';
    try {
      this.client.attachController(this.controller);
      const terms = await this.client.terms();
      if (!this.isCurrent(generation)) return;
      this.terms = terms;
      this.selectedTerm = Math.max(0, terms.findIndex((term: EasTermItem): boolean => term.isCurrent));
      this.ready = true;
      await this.loadCourses();
    } catch (error) {
      if (this.isCurrent(generation)) {
        this.message = this.errorText(error as Error);
        this.autoAttempted = false;
      }
    } finally { if (this.isCurrent(generation)) this.busy = false; }
  }

  private errorText(error: Error): string {
    // Native network errors can contain internal details; show only our business messages.
    return /^(请|教务|该学期|课程|导入|登录)/.test(error.message) ? error.message : '网络请求失败，请检查网络后重试';
  }

  private async loadCourses(): Promise<void> {
    const generation = this.navigationGeneration;
    this.courses = []; this.firstWeek = 0; this.plan = undefined;
    this.message = '正在读取课表';
    const term = this.terms[this.selectedTerm];
    const courses = await this.client.courses(term);
    if (!this.isCurrent(generation)) return;
    this.courses = courses;
    this.structure = await this.client.structure(term);
    if (!this.isCurrent(generation)) return;
    let start = 0;
    try { start = await this.client.firstWeek(term); } catch (_) {}
    if (!this.isCurrent(generation)) return;
    this.firstWeek = start;
    this.message = start > 0 ? '请确认学期和开学日期' : '未获取到校历，请选择第一教学周的周一';
    if (this.client.usesDefaultStructure) this.message += '；未获取到教务节次，使用深圳默认作息';
  }

  private chooseTerm(): void {
    if (this.busy) return;
    this.getUIContext().showTextPickerDialog({
      range: this.terms.map((term: EasTermItem): string => term.name), selected: this.selectedTerm, canLoop: false,
      onAccept: (result: TextPickerResult) => {
        if (this.alive && typeof result.index === 'number' && result.index !== this.selectedTerm) {
          this.selectedTerm = result.index;
          if (!this.busy) {
            const generation = this.navigationGeneration;
            this.busy = true;
            this.loadCourses()
              .catch((error: Error) => { if (this.isCurrent(generation)) this.message = this.errorText(error); })
              .finally(() => { if (this.isCurrent(generation)) this.busy = false; });
          }
        }
      }
    });
  }

  private chooseDate(): void {
    if (this.busy) return;
    CalendarPickerDialog.show({ selected: new Date(this.firstWeek || Date.now()),
      onAccept: (date: Date) => {
        if (this.alive) { this.firstWeek = EasTimetable.mondayMsOf(date.getTime()); this.plan = undefined; }
      }
    });
  }

  private async save(): Promise<void> {
    if (this.busy || !this.courses.length || !this.firstWeek || !this.alive) return;
    this.busy = true;
    try {
      if (this.plan === undefined) this.plan = AcademicImportPlan.create(this.terms[this.selectedTerm], this.courses,
        this.firstWeek, this.campus, this.structure);
      const plan = this.plan;
      const context = this.getUIContext().getHostContext() as common.Context;
      const db = RdbHelper.getInstance(); await db.init(context);
      if (!this.alive) return;
      await db.saveImportedTimetable(plan.timetable, plan.subjects, plan.events);
      const selection = TimetableSelectionStore.getInstance(); await selection.init(context);
      await selection.save(plan.timetable.id);
      if (this.alive) this.onImported();
    } catch (_) { if (this.alive) this.message = '导入保存失败，请重试；已有课表未被覆盖'; }
    finally { if (this.alive) this.busy = false; }
  }

  build() {
    Column({ space: HitaDesign.spaceSm }) {
      Text(this.campus + '教务登录').fontSize(HitaDesign.title).fontWeight(FontWeight.Medium)
        .fontColor(HitaColors.onSurface).width('100%')
      // Keep the authenticated JS context mounted for semester/course/calendar reads.
        Web({ src: this.campus === '深圳' ? '' : this.config.loginUrl, controller: this.controller })
          .javaScriptAccess(true).domStorageAccess(true)
          // Set the gateway preference before its scripts without reloading.
          .javaScriptOnDocumentStart(this.campus === '深圳' ? [{
            script: SHENZHEN_GATEWAY_BOOTSTRAP, scriptRules: [SHENZHEN_GATEWAY_ORIGIN]
          }] : [])
          .javaScriptOnDocumentEnd(this.campus === '深圳' ? [{
            script: SHENZHEN_LOGIN_ADVANCE, scriptRules: SHENZHEN_LOGIN_ORIGINS
          }] : [])
          .width('100%').height(this.ready ? 1 : '100%').layoutWeight(this.ready ? 0 : 1)
          .visibility(this.ready ? Visibility.Hidden : Visibility.Visible)
          .onControllerAttached(() => this.attachWeb())
          .onPageBegin(() => this.pageStarted())
          .onPageEnd((event) => { if (event !== undefined) this.pageEnded(event.url); })
          .onNavigationEntryCommitted((event) => {
            // aTrust may finish login through an SPA route without onPageEnd.
            if (this.campus === '深圳' && event.isMainFrame && event.isSameDocument && !this.ready) {
              this.pageStarted();
              this.pageEnded(event.url);
            }
          })
          .onErrorReceive((event) => {
            if (event !== undefined && event.request.isMainFrame()) this.message = '登录网页加载失败，请检查网络后重试';
          })
      if (!this.ready) {
        Text(this.message).fontSize(HitaDesign.caption).fontColor(HitaColors.onSurfaceVariant).width('100%')
        Row({ space: HitaDesign.spaceSm }) {
          HitaButton({ label: '进入教务', variant: HitaButtonVariant.SECONDARY,
            disabled: this.busy, onTap: () => this.enterAcademic() }).layoutWeight(1)
          HitaButton({ label: this.busy ? '正在读取' : '读取课表',
            disabled: this.busy, onTap: () => this.verify() }).layoutWeight(1)
        }.width('100%')
      } else {
        Scroll() {
          Column({ space: HitaDesign.spaceMd }) {
            Column() {
              HitaListRow({ symbol: $r('sys.symbol.calendar'), title: '学期',
                subtitle: this.terms[this.selectedTerm]?.name ?? '', onTap: () => this.chooseTerm() })
              HitaListRow({ symbol: $r('sys.symbol.calendar'), title: '第一周周一', divider: true,
                subtitle: this.firstWeek ? AtomicTimetableStore.dateLabel(this.firstWeek) : '请选择',
                onTap: () => this.chooseDate() })
            }.backgroundColor($r('app.color.hita_surface')).borderRadius(HitaDesign.cardRadius).enabled(!this.busy)
            Text(this.message).fontSize(HitaDesign.caption).fontColor(HitaColors.onSurfaceVariant).width('100%')
            Text('导入为新课表，保留已有课表').fontSize(HitaDesign.caption).fontColor(HitaColors.onSurfaceVariant).width('100%')
            ForEach(this.courses.slice(0, 5), (course: EasCourseItem) => {
              Text(course.name + ' · 周' + ['一', '二', '三', '四', '五', '六', '日'][course.dayOfWeek - 1] +
                ' 第' + course.beginSection + '–' + (course.beginSection + course.sectionCount - 1) + '节')
                .fontSize(HitaDesign.body).fontColor(HitaColors.onSurface).width('100%')
            })
            HitaButton({ label: this.busy ? '正在处理' : '导入课表',
              disabled: this.busy || !this.firstWeek || !this.courses.length, onTap: () => this.save() })
            HitaButton({ label: '重新读取', variant: HitaButtonVariant.SECONDARY,
              disabled: this.busy, onTap: () => this.verify() })
            HitaButton({ label: '返回教务登录', variant: HitaButtonVariant.SECONDARY,
              disabled: this.busy, onTap: () => this.enterAcademic() })
          }.width('100%')
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      }
    }.width('100%').height('100%').padding({ left: HitaDesign.inset, right: HitaDesign.inset,
      bottom: HitaDesign.spaceLg })
  }
}
