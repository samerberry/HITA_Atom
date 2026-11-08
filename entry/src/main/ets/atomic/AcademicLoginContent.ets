import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { HitaColors } from '../common/theme/HitaColors';
import { HitaDesign } from '../common/theme/HitaDesign';
import { HitaButton } from '../common/components/HitaButton';
import { HitaListRow } from '../common/components/HitaListRow';
import { HeaderBackButton } from '../common/components/HeaderBackButton';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { CompatibleMaterialModifier } from '../common/theme/CompatibleMaterialModifier';
import { CompatibleSheetMaterial } from '../common/theme/CompatibleSheetMaterial';
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
  onBack: () => void = () => {};
  @StorageProp('atomicDarkMode') private darkMode: boolean = false;
  @State private busy: boolean = false;
  @State private importing: boolean = false;
  @State private error: string = '';
  @State private pageLoading: boolean = true;
  @State private progress: number = 0;
  @State private canGoBack: boolean = false;
  @State private defaultStructure: boolean = false;
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
  private pageLoadTimer: number = -1;
  private currentUrl: string = '';
  private webFailed: boolean = false;

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
  aboutToDisappear(): void {
    this.alive = false;
    this.navigationGeneration++;
    this.clearPageLoadTimer();
    this.client.close();
  }

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
    } catch (_) { this.loadFailed('登录网页初始化失败，请重试'); }
  }

  private clearPageLoadTimer(): void {
    if (this.pageLoadTimer >= 0) clearTimeout(this.pageLoadTimer);
    this.pageLoadTimer = -1;
  }

  private updateWebNavigation(): void {
    try { this.canGoBack = this.controller.accessBackward(); }
    catch (_) { this.canGoBack = false; }
  }

  private pageStarted(url: string): void {
    if (!this.alive || this.importing) return;
    this.currentUrl = url;
    this.navigationGeneration++;
    this.client.pageStarted();
    this.busy = false; this.ready = false; this.autoAttempted = false;
    this.error = ''; this.pageLoading = true; this.progress = 0;
    this.webFailed = false;
    this.courses = []; this.structure = []; this.firstWeek = 0; this.plan = undefined;
    this.defaultStructure = false;
    this.clearPageLoadTimer();
    const generation = this.navigationGeneration;
    this.pageLoadTimer = setTimeout(() => {
      this.pageLoadTimer = -1;
      if (this.isCurrent(generation) && this.pageLoading) this.loadFailed('网页加载较慢，请刷新重试');
    }, 20000);
    this.updateWebNavigation();
  }

  private pageEnded(url: string): void {
    if (!this.alive || this.importing) return;
    // Redirects can finish out of order. Only the currently displayed document
    // may finish loading or start a read of its authenticated JS context.
    try { if (this.controller.getUrl() !== url) return; } catch (_) { return; }
    if (this.currentUrl !== url) this.pageStarted(url);
    this.clearPageLoadTimer();
    this.pageLoading = false; this.progress = 100;
    if (this.webFailed) { this.error = ''; this.webFailed = false; }
    this.updateWebNavigation();
    if (this.busy) return;
    const redirect = this.config.redirectFor(url);
    if (redirect) {
      try { this.controller.loadUrl(redirect); } catch (_) {}
      return;
    }
    if (!this.autoAttempted && this.config.shouldRead(url)) {
      this.autoAttempted = true; this.verify(true);
    }
  }

  private loadFailed(message: string): void {
    if (!this.alive || this.importing) return;
    this.clearPageLoadTimer();
    this.pageLoading = false;
    this.webFailed = true;
    this.error = message;
  }

  private refreshPage(): void {
    if (this.busy || !this.alive) return;
    if (this.ready) { this.verify(); return; }
    try {
      const url = this.controller.getUrl();
      this.pageStarted(url || this.config.loginUrl);
      if (!url || url === 'about:blank') this.controller.loadUrl(this.config.loginUrl);
      else this.controller.refresh();
    } catch (_) { this.loadFailed('网页尚未准备好，请重试'); }
  }

  private goWebBack(): void {
    if (this.busy || !this.alive) return;
    try { if (this.controller.accessBackward()) this.controller.backward(); } catch (_) {}
  }

  private async verify(automatic: boolean = false): Promise<void> {
    if (this.busy || this.pageLoading || !this.alive) return;
    const generation = this.navigationGeneration;
    this.busy = true; this.error = ''; this.autoAttempted = true;
    try {
      this.client.attachController(this.controller);
      const terms = await this.client.terms();
      if (!this.isCurrent(generation)) return;
      if (terms.length === 0) throw new Error('教务未返回学期，请重新读取');
      this.terms = terms;
      this.selectedTerm = Math.max(0, terms.findIndex((term: EasTermItem): boolean => term.isCurrent));
      this.ready = true;
      await this.loadCourses();
    } catch (error) {
      if (this.isCurrent(generation)) {
        const message = this.errorText(error as Error);
        // Landing on loginCAS can precede authentication. A background probe
        // should not show an expected "not logged in" error over the login form.
        const waitingForLogin = /会话尚未就绪|请先进入教务|请先.*登录/.test(message);
        this.error = automatic && !this.ready && waitingForLogin ? '' : message;
      }
    } finally { if (this.isCurrent(generation)) this.busy = false; }
  }

  private errorText(error: Error, fallback: string = '网络请求失败，请检查网络后重试'): string {
    // Native network errors can contain internal details; show only our business messages.
    return /^(请|教务|该学期|课程|导入|登录)/.test(error.message) ? error.message : fallback;
  }

  private async loadCourses(): Promise<void> {
    const generation = this.navigationGeneration;
    this.courses = []; this.structure = []; this.firstWeek = 0; this.plan = undefined;
    this.error = ''; this.defaultStructure = false;
    const term = this.terms[this.selectedTerm];
    const courses = await this.client.courses(term);
    if (!this.isCurrent(generation)) return;
    const structure = await this.client.structure(term);
    if (!this.isCurrent(generation)) return;
    let start = 0;
    try { start = await this.client.firstWeek(term); } catch (_) {}
    if (!this.isCurrent(generation)) return;
    // Publish a complete term snapshot together. A failed read must never make
    // courses from one term importable with another term's bell schedule.
    this.courses = courses; this.structure = structure; this.firstWeek = start;
    this.defaultStructure = this.client.usesDefaultStructure;
  }

  private chooseTerm(): void {
    if (this.busy) return;
    const generation = this.navigationGeneration;
    this.getUIContext().showTextPickerDialog({
      range: this.terms.map((term: EasTermItem): string => term.name), selected: this.selectedTerm, canLoop: false,
      onAccept: (result: TextPickerResult) => {
        if (this.isCurrent(generation) && !this.busy && typeof result.index === 'number' &&
          result.index >= 0 && result.index < this.terms.length && result.index !== this.selectedTerm) {
          this.selectedTerm = result.index;
          this.busy = true;
          this.loadCourses()
            .catch((error: Error) => { if (this.isCurrent(generation)) this.error = this.errorText(error); })
            .finally(() => { if (this.isCurrent(generation)) this.busy = false; });
        }
      }
    });
  }

  private chooseDate(): void {
    if (this.busy) return;
    const generation = this.navigationGeneration;
    CalendarPickerDialog.show({ selected: new Date(this.firstWeek || Date.now()),
      onAccept: (date: Date) => {
        if (this.isCurrent(generation) && !this.busy && Number.isFinite(date.getTime())) {
          this.firstWeek = EasTimetable.mondayMsOf(date.getTime()); this.plan = undefined;
        }
      }
    });
  }

  private async save(): Promise<void> {
    if (this.busy || !this.courses.length || !this.firstWeek || !this.alive) return;
    this.busy = true; this.importing = true; this.error = '';
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
    } catch (error) { if (this.alive) this.error = this.errorText(error as Error, '导入失败，请重试'); }
    finally { if (this.alive) { this.busy = false; this.importing = false; } }
  }

  private courseDetail(course: EasCourseItem): string {
    return '周' + ['一', '二', '三', '四', '五', '六', '日'][course.dayOfWeek - 1] +
      ' · 第' + course.beginSection + '–' + (course.beginSection + course.sectionCount - 1) + '节' +
      (course.classroom ? ' · ' + course.classroom : '');
  }

  @Builder
  private webAction(symbol: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(symbol).fontSize(HitaDesign.iconMd)
        .fontColor([CompatibleMaterialModifier.foreground(HitaColors.primary)])
    }.width(HitaDesign.minTouchTarget).height(HitaDesign.minTouchTarget).padding(0)
      .backgroundColor(Color.Transparent)
      .attributeModifier(new CompatibleMaterialModifier(Color.Transparent))
      .accessibilityText(label).enabled(!this.busy).onClick(action)
  }

  @Builder
  private header() {
    ImmersiveHeader({ barHeight: HitaDesign.headerHeight }) {
      Row({ space: HitaDesign.spaceXs }) {
        HeaderBackButton({ accessibilityLabel: '返回校区选择', onBack: () => this.onBack() })
          .enabled(!this.importing)
        Column({ space: HitaDesign.space2xs }) {
          Text(this.ready ? '导入课表' : '统一认证登录')
            .fontSize(HitaDesign.section).fontWeight(FontWeight.Medium).fontColor(HitaColors.onSurface)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.campus + '教务').fontSize(HitaDesign.caption).fontColor(HitaColors.primary).maxLines(1)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (!this.ready && this.canGoBack) {
          this.webAction($r('sys.symbol.arrow_left'), '返回上一网页', () => this.goWebBack());
        }
        this.webAction($r('sys.symbol.repeat_1'), this.ready ? '重新读取课表' : '刷新登录网页', () => this.refreshPage());
      }.width('100%').height(HitaDesign.headerHeight)
        .padding({ left: HitaDesign.inset, right: HitaDesign.inset })
    }
  }

  @Builder
  private loginWeb() {
    // Keep this Web instance mounted, including on the confirmation screen:
    // semester, course and calendar reads all need its authenticated JS context.
    Web({ src: this.campus === '深圳' ? '' : this.config.loginUrl, controller: this.controller })
      .javaScriptAccess(true).domStorageAccess(true)
      .darkMode(this.darkMode ? WebDarkMode.On : WebDarkMode.Off).forceDarkAccess(false)
      .javaScriptOnDocumentStart(this.campus === '深圳' ? [{
        script: SHENZHEN_GATEWAY_BOOTSTRAP, scriptRules: [SHENZHEN_GATEWAY_ORIGIN]
      }] : [])
      .javaScriptOnDocumentEnd(this.campus === '深圳' ? [{
        script: SHENZHEN_LOGIN_ADVANCE, scriptRules: SHENZHEN_LOGIN_ORIGINS
      }] : [])
      .width('100%').height(this.ready ? 1 : '100%').layoutWeight(this.ready ? 0 : 1)
      .visibility(this.ready ? Visibility.Hidden : Visibility.Visible)
      .onControllerAttached(() => this.attachWeb())
      .onPageBegin((event) => { if (event !== undefined) this.pageStarted(event.url); })
      .onPageEnd((event) => { if (event !== undefined) this.pageEnded(event.url); })
      .onProgressChange((event) => { if (this.alive && event !== undefined) this.progress = event.newProgress; })
      .onNavigationEntryCommitted((event) => {
        // aTrust may finish login through an SPA route without onPageEnd.
        if (this.campus === '深圳' && event.isMainFrame && event.isSameDocument &&
          !this.ready && event.url !== this.currentUrl) {
          this.pageStarted(event.url);
          this.pageEnded(event.url);
        }
      })
      .onErrorReceive((event) => {
        if (event !== undefined && event.request.isMainFrame() && event.request.getRequestUrl() === this.currentUrl) {
          this.loadFailed('网页加载失败，请检查网络后刷新');
        }
      })
  }

  @Builder
  private previewRow(course: EasCourseItem, index: number) {
    Column({ space: HitaDesign.space2xs }) {
      Text(course.name).fontSize(HitaDesign.body).fontColor(HitaColors.onSurface).width('100%')
      Text(this.courseDetail(course)).fontSize(HitaDesign.caption)
        .fontColor(HitaColors.onSurfaceVariant).width('100%')
    }.width('100%').padding(HitaDesign.inset)
    if (index < this.courses.length - 1) {
      Divider().strokeWidth(HitaDesign.hairline).color(HitaColors.divider)
        .margin({ left: HitaDesign.inset, right: HitaDesign.inset })
    }
  }

  @Builder
  private importPreview() {
    Scroll() {
      Column({ space: HitaDesign.spaceLg }) {
        Column() {
          HitaListRow({ symbol: $r('sys.symbol.calendar'), title: '学期',
            subtitle: this.terms[this.selectedTerm]?.name ?? '', onTap: () => this.chooseTerm() })
          HitaListRow({ symbol: $r('sys.symbol.calendar'), title: '第一周周一', divider: true,
            subtitle: this.firstWeek ? AtomicTimetableStore.dateLabel(this.firstWeek) : '请选择第一教学周的周一',
            onTap: () => this.chooseDate() })
        }.width('100%').backgroundColor(CompatibleSheetMaterial.cardColor($r('app.color.hita_surface')))
          .borderRadius(HitaDesign.cardRadius).enabled(!this.busy)
        if (this.busy && !this.importing) {
          Column({ space: HitaDesign.spaceSm }) {
            LoadingProgress().width(HitaDesign.controlHeight).height(HitaDesign.controlHeight).color(HitaColors.primary)
            Text('正在读取课表').fontSize(HitaDesign.caption).fontColor(HitaColors.onSurfaceVariant)
          }.width('100%').padding(HitaDesign.spaceXl)
        } else if (this.courses.length > 0) {
          Column({ space: HitaDesign.spaceXs }) {
            Row() {
              Text('课程预览').fontSize(HitaDesign.caption).fontColor(HitaColors.onSurfaceVariant)
              Blank()
              Text(this.courses.length + '项安排').fontSize(HitaDesign.caption).fontColor(HitaColors.onSurfaceVariant)
            }.width('100%').padding({ left: HitaDesign.inset, right: HitaDesign.inset })
            Column() {
              ForEach(this.courses, (course: EasCourseItem, index: number) => {
                this.previewRow(course, index);
              }, (course: EasCourseItem, index: number): string => index + ':' + course.name)
            }.width('100%').backgroundColor(CompatibleSheetMaterial.cardColor($r('app.color.hita_surface')))
              .borderRadius(HitaDesign.cardRadius)
            if (this.defaultStructure) {
              Text('已使用深圳默认作息').fontSize(HitaDesign.caption).fontColor(HitaColors.onSurfaceVariant).width('100%')
            }
          }.width('100%')
        }
      }.width('100%').constraintSize({ maxWidth: HitaDesign.contentMaxWidth })
        .padding({ left: HitaDesign.inset, right: HitaDesign.inset, bottom: HitaDesign.spaceLg })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
  }

  @Builder
  private actionBar() {
    Column({ space: HitaDesign.spaceSm }) {
      if (this.error.length > 0) {
        Text(this.error).fontSize(HitaDesign.caption).fontColor(HitaColors.error).width('100%')
          .accessibilityLevel('yes')
      }
      if (this.ready && this.courses.length > 0) {
        HitaButton({ label: this.importing ? '正在导入' : '导入课表',
          disabled: this.busy || !this.firstWeek, onTap: () => this.save() })
      } else {
        HitaButton({ label: this.busy ? '正在读取' : this.error ? '重新读取' : '读取课表',
          disabled: this.busy || this.pageLoading, onTap: () => this.verify() })
      }
    }.width('100%').constraintSize({ maxWidth: HitaDesign.contentMaxWidth })
      .padding({ left: HitaDesign.inset, right: HitaDesign.inset,
        top: HitaDesign.spaceSm, bottom: HitaDesign.spaceLg })
  }

  build() {
    Column() {
      this.header();
      if (!this.ready && this.pageLoading) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%').height(HitaDesign.space2xs).color(HitaColors.primary).backgroundColor(HitaColors.selected)
      }
      this.loginWeb();
      if (this.ready) this.importPreview();
      this.actionBar();
    }.width('100%').height('100%')
      .backgroundColor(CompatibleSheetMaterial.bodyColor($r('app.color.hita_page')))
  }
}
