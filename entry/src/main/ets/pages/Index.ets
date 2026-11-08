import { AtomicServiceNavigation, FrameCallback } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { HitaDesign } from '../common/theme/HitaDesign';
import { HitaColors } from '../common/theme/HitaColors';
import { CompatibleSheetMaterial } from '../common/theme/CompatibleSheetMaterial';
import { CompatibleMaterialModifier } from '../common/theme/CompatibleMaterialModifier';
import { NAV_BAR_INSET_KEY, NAV_BAR_INSET_FALLBACK,
  STATUS_BAR_INSET_KEY, STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';
import { HitaButton } from '../common/components/HitaButton';
import { HitaListRow } from '../common/components/HitaListRow';
import { SheetContent } from '../common/components/SheetContent';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasEventItem, EasTimetable, DAY_MILLIS, WEEK_MILLIS } from '../common/model/timetable/TimetableModels';
import { AtomicTimetableStore, ATOMIC_CAMPUSES } from '../atomic/AtomicTimetableStore';
import { AcademicLoginContent } from '../atomic/AcademicLoginContent';
import { AtomicTermSetup } from '../atomic/AtomicTermSetup';
import { AtomicCourseCards } from '../atomic/AtomicCourseCards';
import { EventEditorForm } from './AddEventPage';
import { CourseDetailContent } from '../feature/timetable/views/CourseDetailContent';
import { TimetableCardPainter } from '../feature/timetable/views/TimetableCardPainter';
import { TimetableDisplayOptions } from '../feature/timetable/data/TimetableDisplayOptions';
import {
  DOW_NAMES, TIMETABLE_GUTTER_WIDTH as GUTTER_WIDTH, TIMETABLE_HOUR_HEIGHT as HOUR_HEIGHT,
  TIMETABLE_GRID_TOP_PADDING as GRID_TOP_PADDING, TimetableAxis, TimetableCardLayer,
  TimetableCardSurface, TimetablePlaceLabel, drawTimetableWeek, eventsOfWeek, timetableEventSpan
} from '../feature/timetable/views/TimetableWeekDraw';

enum AtomicSheet { SETUP, EDITOR, DETAIL, IMPORT, LOGIN }

class WeekFrameCallback extends FrameCallback {
  private action: () => void;
  constructor(action: () => void) {
    super();
    this.action = action;
  }
  onFrame(): void { this.action(); }
}

@Entry
@Component
struct Index {
  @State loading: boolean = true;
  @State loadError: string = '';
  @State timetable: EasTimetable | undefined = undefined;
  @State events: EasEventItem[] = [];
  @State week: number = 1;
  @State today: number = Date.now();
  @State gridHeight: number = GRID_TOP_PADDING + 15 * HOUR_HEIGHT + 8;
  @State cards: TimetableCardSurface[] = [];
  @State sheetVisible: boolean = false;
  @State sheetMode: AtomicSheet = AtomicSheet.SETUP;
  @State selected: EasEventItem = new EasEventItem();
  @State selectedEnd: number = 0;
  @State selectedIds: string[] = [];
  @State colorEditing: boolean = false;
  @State colorPreview: number = 0;
  @State busy: boolean = false;
  @State sheetError: string = '';
  @State importMessage: string = '';
  @State loginCampus: string = '威海';
  @State weekOffset: number = 0;
  @State weekAnimating: boolean = false;
  @State capsuleInset: number = 104;
  @StorageProp(NAV_BAR_INSET_KEY) navigationInset: number = NAV_BAR_INSET_FALLBACK;
  @StorageProp(STATUS_BAR_INSET_KEY) statusInset: number = STATUS_BAR_INSET_FALLBACK;
  @StorageProp('atomicDarkMode') @Watch('redraw') darkMode: boolean = false;
  @StorageProp('atomicActive') @Watch('activityChanged') active: boolean = true;
  private paths: NavPathStack = new NavPathStack();
  private grid = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private painter = new TimetableCardPainter();
  private gridWidth: number = 0;
  private gridAreaHeight: number = 0;
  private labels: TimetablePlaceLabel[] = [];
  private animationStart: number = 0;
  private animationTimer: number = -1;
  private dateTimer: number = -1;
  private mounted: boolean = false;
  private canvasReady: boolean = false;
  private weekGeneration: number = 0;
  private weekGestureAllowed: boolean = false;
  private pageWidth: number = 0;
  private headerArea: Area | undefined = undefined;

  aboutToAppear(): void {
    this.mounted = true;
    this.refresh(true);
    this.startDateClock();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.weekGeneration++;
    this.stopClocks();
  }

  private context(): common.Context {
    return this.getUIContext().getHostContext() as common.Context;
  }

  private async refresh(selectCurrentWeek: boolean = false): Promise<void> {
    this.loadError = '';
    try {
      const snapshot = await AtomicTimetableStore.load(this.context());
      if (!this.mounted) return;
      this.timetable = snapshot.timetable;
      this.events = snapshot.events;
      if (this.timetable !== undefined) {
        this.week = Math.max(1, Math.min(AtomicTimetableStore.weekCount(this.timetable),
          selectCurrentWeek ? this.timetable.getWeekNumber(Date.now()) : this.week));
      }
    } catch (_) {
      if (this.mounted) this.loadError = '课表读取失败，请重试';
    } finally {
      if (this.mounted) {
        this.loading = false;
        this.redraw();
      }
    }
  }

  private activityChanged(): void {
    if (!this.active) {
      this.resetWeekMotion();
      this.stopClocks();
    } else if (this.mounted) {
      this.today = Date.now();
      this.updateCapsuleInset();
      this.redraw();
      this.startDateClock();
    }
  }

  private startDateClock(): void {
    if (this.dateTimer >= 0) clearInterval(this.dateTimer);
    this.dateTimer = setInterval(() => {
      this.today = Date.now();
      this.redraw();
    }, 60000);
  }

  private stopClocks(): void {
    if (this.animationTimer >= 0) clearTimeout(this.animationTimer);
    if (this.dateTimer >= 0) clearInterval(this.dateTimer);
    this.animationTimer = -1;
    this.dateTimer = -1;
  }

  private drawPlaces(): void {
    if (!this.mounted || !this.active) return;
    const delay: number = this.painter.drawPlaces(this.labels, Date.now() - this.animationStart);
    if (delay >= 0) this.animationTimer = setTimeout(() => this.drawPlaces(), Math.max(16, delay));
  }

  private redraw(): void {
    if (!this.mounted || !this.canvasReady || this.gridWidth <= 0 || this.timetable === undefined) return;
    if (this.animationTimer >= 0) clearTimeout(this.animationTimer);
    const axis = TimetableAxis.forEvents(this.timetable, eventsOfWeek(this.timetable, this.events, this.week));
    this.gridHeight = GRID_TOP_PADDING + axis.hours() * HOUR_HEIGHT + 8;
    const layer = new TimetableCardLayer();
    this.labels = drawTimetableWeek(this.grid, this.gridWidth, this.gridHeight, this.timetable, this.events, this.week,
      this.timetable.getWeekNumber(this.today) === this.week, HOUR_HEIGHT, 0, false, false, '', this.darkMode,
      layer, new TimetableDisplayOptions(), undefined, false, true, axis);
    this.cards = layer.surfaces;
    this.animationStart = Date.now();
    this.drawPlaces();
  }

  private resetWeekMotion(): void {
    this.weekGeneration++;
    this.weekGestureAllowed = false;
    this.weekOffset = 0;
    this.weekAnimating = false;
  }

  private weekWidth(): number { return Math.max(1, this.pageWidth); }

  private weekOpacity(): number {
    return 1 - Math.min(1, Math.abs(this.weekOffset) / this.weekWidth());
  }

  private snapWeekBack(): void {
    if (this.weekAnimating || this.weekOffset === 0) return;
    this.weekAnimating = true;
    const generation = ++this.weekGeneration;
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut, onFinish: () => {
      if (this.mounted && generation === this.weekGeneration) this.weekAnimating = false;
    } }, () => { this.weekOffset = 0; });
  }

  private selectWeek(value: number): void {
    if (this.timetable === undefined || this.weekAnimating || !this.active || !this.mounted) return;
    const next = Math.max(1, Math.min(AtomicTimetableStore.weekCount(this.timetable), value));
    if (next === this.week) { this.snapWeekBack(); return; }
    const direction: number = next > this.week ? 1 : -1;
    const generation = ++this.weekGeneration;
    this.weekAnimating = true;
    this.getUIContext().animateTo({ duration: 140, curve: Curve.EaseIn, onFinish: () => {
      if (!this.mounted || !this.active || generation !== this.weekGeneration) return;
      this.week = next;
      this.redraw();
      // Reposition invisibly, render the new cards, then animate in from the other edge.
      this.weekOffset = direction * this.weekWidth();
      this.getUIContext().postFrameCallback(new WeekFrameCallback(() => {
        if (!this.mounted || !this.active || generation !== this.weekGeneration) return;
        this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut, onFinish: () => {
          if (this.mounted && generation === this.weekGeneration) this.weekAnimating = false;
        } }, () => { this.weekOffset = 0; });
      }));
    } }, () => { this.weekOffset = -direction * this.weekWidth(); });
  }

  private recordWeekTouch(event: TouchEvent): void {
    if (event.type !== TouchType.Down) return;
    const touch = event.touches[0];
    // Keep both screen edges available for the system back gesture.
    this.weekGestureAllowed = touch !== undefined && touch.x > HitaDesign.spaceLg &&
      touch.x < this.pageWidth - HitaDesign.spaceLg && !this.weekAnimating && !this.sheetVisible && this.active;
  }

  private dragWeek(event: GestureEvent): void {
    if (!this.weekGestureAllowed || this.weekAnimating || this.timetable === undefined) return;
    const atBoundary: boolean = (event.offsetX > 0 && this.week === 1) ||
      (event.offsetX < 0 && this.week === AtomicTimetableStore.weekCount(this.timetable));
    const offset = atBoundary ? event.offsetX * 0.2 : event.offsetX;
    this.weekOffset = Math.max(-this.weekWidth(), Math.min(this.weekWidth(), offset));
  }

  private finishWeekDrag(event: GestureEvent): void {
    if (!this.weekGestureAllowed || this.weekAnimating) return;
    this.weekGestureAllowed = false;
    const fling: boolean = Math.abs(event.offsetX) >= 24 && Math.abs(event.velocityX) >= 700 &&
      event.offsetX * event.velocityX > 0;
    if (fling || Math.abs(event.offsetX) >= Math.min(96, this.weekWidth() * 0.22)) {
      this.selectWeek(this.week + (event.offsetX < 0 ? 1 : -1));
    } else this.snapWeekBack();
  }

  private updateCapsuleInset(): void {
    const area = this.headerArea;
    if (area === undefined) return;
    try {
      const rect = this.getUIContext().getAtomicServiceBar()?.getBarRect();
      if (rect === undefined || rect.width <= 0) return;
      const top = Number(area.globalPosition.y);
      const overlaps: boolean = rect.y < top + Number(area.height) && rect.y + rect.height > top;
      this.capsuleInset = overlaps ? Math.max(HitaDesign.inset,
        Number(area.globalPosition.x) + Number(area.width) - rect.x + HitaDesign.spaceXs) : HitaDesign.inset;
    } catch (_) {
      // Keep the initial capsule reserve until its native layout is available.
    }
  }

  private canReturnToCurrentWeek(): boolean {
    if (this.timetable === undefined) return false;
    const current = this.timetable.getWeekNumber(this.today);
    return current >= 1 && current <= AtomicTimetableStore.weekCount(this.timetable) && current !== this.week;
  }

  private chooseWeek(): void {
    if (this.timetable === undefined || this.weekAnimating || this.sheetVisible) return;
    const choices: string[] = [];
    for (let week = 1; week <= AtomicTimetableStore.weekCount(this.timetable); week++) choices.push('第 ' + week + ' 周');
    this.getUIContext().showTextPickerDialog({
      range: choices, selected: this.week - 1, canLoop: false,
      onAccept: (result: TextPickerResult) => {
        if (typeof result.index === 'number') {
          this.selectWeek(result.index + 1);
        }
      }
    });
  }

  private addCourse(): void {
    if (this.loading || this.loadError.length > 0 || this.sheetVisible || this.weekAnimating) return;
    this.selected = new EasEventItem();
    this.selectedIds = [];
    this.sheetMode = this.timetable === undefined ? AtomicSheet.SETUP : AtomicSheet.EDITOR;
    this.sheetError = '';
    this.sheetVisible = true;
  }

  private async createTimetable(date: number, weeks: number, campus: number): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.sheetError = '';
    try {
      await AtomicTimetableStore.create(this.context(), date, weeks, campus);
      await this.refresh(true);
      if (this.timetable === undefined || this.loadError.length > 0) throw new Error('load failed');
      this.sheetMode = AtomicSheet.EDITOR;
    } catch (_) {
      this.sheetError = '创建课表失败，请重试';
    } finally {
      this.busy = false;
    }
  }

  private openCourse(key: string): void {
    if (this.sheetVisible || this.timetable === undefined || this.weekAnimating || this.weekOffset !== 0) return;
    const card = this.cards.find((item: TimetableCardSurface): boolean => item.key === key);
    if (card === undefined) return;
    const event = this.events.find((item: EasEventItem): boolean => item.id === card.eventIds[0]);
    if (event === undefined) return;
    this.selected = event;
    this.selectedIds = card.eventIds.slice();
    this.selectedEnd = event.to;
    for (const id of this.selectedIds) {
      const item = this.events.find((candidate: EasEventItem): boolean => candidate.id === id);
      if (item !== undefined) {
        this.selectedEnd = Math.max(this.selectedEnd, timetableEventSpan(this.timetable, item, this.week)?.to ?? item.to);
      }
    }
    this.colorEditing = false;
    this.sheetMode = AtomicSheet.DETAIL;
    this.sheetVisible = true;
  }

  private async saveColor(color: number): Promise<void> {
    if (this.busy || this.timetable === undefined) return;
    this.busy = true;
    try {
      await RdbHelper.getInstance().saveCourseColor(this.selected.subjectId, this.timetable.id, color);
      const id = this.selected.id;
      await this.refresh();
      this.selected = this.events.find((item: EasEventItem): boolean => item.id === id) ?? this.selected;
      this.colorEditing = false;
    } catch (_) {
      this.notify('颜色保存失败，请重试');
    } finally {
      this.busy = false;
    }
  }

  private deleteCourse(): void {
    if (this.busy || this.timetable === undefined) return;
    this.getUIContext().showAlertDialog({
      title: '删除这次课程？', message: '其他日期的课程会保留。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', fontColor: HitaColors.error, action: () => this.commitDelete() }
    });
  }

  private async commitDelete(): Promise<void> {
    if (this.busy || this.timetable === undefined) return;
    this.busy = true;
    try {
      await RdbHelper.getInstance().deleteClassOccurrences(this.selectedIds, this.timetable.id);
      this.sheetVisible = false;
      await this.refresh();
    } catch (_) {
      this.notify('删除失败，请重试');
    } finally {
      this.busy = false;
    }
  }

  private notify(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private dateAt(day: number): number {
    return (this.timetable?.startTime ?? 0) + (this.week - 1) * WEEK_MILLIS + day * DAY_MILLIS;
  }

  private isToday(day: number): boolean {
    return new Date(this.dateAt(day)).toDateString() === new Date(this.today).toDateString();
  }

  private periodText(): string {
    let end = this.selected.lastNumber;
    for (const id of this.selectedIds) {
      const event = this.events.find((item: EasEventItem): boolean => item.id === id);
      if (event !== undefined) end = Math.max(end, event.lastNumber);
    }
    return this.selected.fromNumber > 0 ? '第 ' + this.selected.fromNumber +
      (end > this.selected.fromNumber ? ' - ' + end : '') + ' 节' : '自定义时间';
  }

  private progressText(): string {
    const courses = this.events.filter((item: EasEventItem): boolean => item.subjectId === this.selected.subjectId);
    const dates: string[] = [];
    for (const event of courses) {
      const date = new Date(event.from).toDateString();
      if (!dates.includes(date)) dates.push(date);
    }
    const position = dates.indexOf(new Date(this.selected.from).toDateString());
    return '第 ' + (position + 1) + ' 次 / 共 ' + dates.length + ' 次';
  }

  @Builder
  private headerAction(symbol: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(symbol).fontSize(HitaDesign.iconMd)
        .fontColor([CompatibleMaterialModifier.foreground(HitaColors.primary)])
    }.width(HitaDesign.minTouchTarget).height(HitaDesign.minTouchTarget)
      .backgroundColor(HitaColors.selected)
      .attributeModifier(new CompatibleMaterialModifier(HitaColors.selected))
      .accessibilityText(label)
      .enabled(!this.loading && this.loadError.length === 0 && !this.weekAnimating && !this.sheetVisible)
      .onClick(action)
  }

  @Builder
  private timetableHeader() {
    Row({ space: HitaDesign.spaceXs }) {
      Button({ type: ButtonType.Normal }) {
        Text('第' + this.week + '周').fontSize(HitaDesign.title).fontWeight(FontWeight.Medium)
          .fontColor(HitaColors.onSurface).maxLines(1).minFontSize(HitaDesign.body)
          .maxFontSize(HitaDesign.title).textAlign(TextAlign.Start).width('100%')
      }.layoutWeight(1).height(HitaDesign.minTouchTarget).padding(0)
        .backgroundColor(Color.Transparent).borderRadius(HitaDesign.radiusSm)
        .accessibilityText('第' + this.week + '周，点击选择教学周')
        .enabled(this.timetable !== undefined && !this.weekAnimating && !this.sheetVisible)
        .onClick(() => this.chooseWeek())
      this.headerAction($r('sys.symbol.arrow_down'), '教务导入', () => {
        this.importMessage = '';
        this.sheetMode = AtomicSheet.IMPORT;
        this.sheetVisible = true;
      });
      this.headerAction($r('sys.symbol.plus'), '添加课程', () => this.addCourse());
    }.width('100%').height(HitaDesign.headerHeight)
      .padding({ left: HitaDesign.inset, right: this.capsuleInset })
      .onAreaChange((_old: Area, area: Area) => {
        this.headerArea = area;
        this.updateCapsuleInset();
        this.getUIContext().postFrameCallback(new WeekFrameCallback(() => {
          if (this.mounted) this.updateCapsuleInset();
        }));
      })
  }

  @Builder
  private returnToCurrentWeek() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(HitaDesign.iconLg)
        .fontColor([CompatibleMaterialModifier.foreground(HitaColors.primary)])
    }.id('atomic-return-current-week').width(HitaDesign.buttonHeight).height(HitaDesign.buttonHeight)
      .backgroundColor(HitaColors.selected)
      .attributeModifier(new CompatibleMaterialModifier(HitaColors.selected))
      .accessibilityText('回到本周').enabled(!this.weekAnimating)
      .position({ right: HitaDesign.inset, bottom: this.navigationInset + HitaDesign.spaceLg })
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 72 }))
        .animation({ duration: 200, curve: Curve.EaseOut }))
      .onClick(() => this.selectWeek(this.timetable?.getWeekNumber(this.today) ?? this.week))
  }

  @Builder
  private dateHeader() {
    Row() {
      Text((new Date(this.dateAt(0)).getMonth() + 1) + '月')
        .fontSize(11).fontWeight(FontWeight.Medium)
        .fontColor(HitaColors.onSurfaceVariant).width(GUTTER_WIDTH)
        .textAlign(TextAlign.Center)
      ForEach(DOW_NAMES, (day: string, index: number) => {
        Column({ space: HitaDesign.space2xs }) {
          Text(day).fontSize(this.isToday(index) ? 11 : 10).fontWeight(FontWeight.Medium)
            .fontColor(HitaColors.onSurfaceVariant)
          Text(new Date(this.dateAt(index)).getDate().toString()).fontSize(10)
            .fontColor(HitaColors.onSurfaceVariant)
        }.layoutWeight(1).height(HitaDesign.headerHeight).justifyContent(FlexAlign.Center)
          .backgroundColor(this.isToday(index) ? HitaColors.selected : Color.Transparent)
          .borderRadius(HitaDesign.radiusSm)
      }, (day: string): string => day)
    }.width('100%').height(HitaDesign.headerHeight)
  }

  @Builder
  private emptyContent() {
    Column({ space: HitaDesign.spaceLg }) {
      SymbolGlyph($r('sys.symbol.calendar')).fontSize(HitaDesign.iconXl).fontColor([HitaColors.primary])
      Text(this.loadError.length > 0 ? this.loadError : '从这一周开始').fontSize(HitaDesign.section)
        .fontWeight(FontWeight.Medium).fontColor(HitaColors.onSurface)
      if (this.loadError.length === 0) {
        Text('添加课程，安排每周学习').fontSize(HitaDesign.caption).fontColor(HitaColors.onSurfaceVariant)
      }
      HitaButton({ label: this.loadError.length > 0 ? '重试' : '添加课程', onTap: () => {
        if (this.loadError.length > 0) {
          this.loading = true;
          this.refresh(true);
        } else this.addCourse();
      } })
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).padding(HitaDesign.spaceXl)
  }

  @Builder
  private weekPage() {
    Column() {
      // Match the full app's timetable start without moving the top actions.
      Row().height(46).width('100%')
      this.dateHeader();
      Scroll() {
        Column() {
          Stack({ alignContent: Alignment.TopStart }) {
            Canvas(this.grid).width('100%').height(this.gridHeight).hitTestBehavior(HitTestMode.None)
              .onReady(() => { this.canvasReady = true; this.redraw(); })
              .onDisAppear(() => { this.canvasReady = false; })
            AtomicCourseCards({ cards: this.cards, contentHeight: this.gridHeight, painter: this.painter,
              onOpen: (key: string) => this.openCourse(key) })
          }.width('100%').height(this.gridHeight)
            .onAreaChange((_old: Area, area: Area) => {
              const width = Number(area.width);
              const height = Number(area.height);
              if (width > 0 && (width !== this.gridWidth || height !== this.gridAreaHeight)) {
                this.gridWidth = width;
                this.gridAreaHeight = height;
                this.redraw();
              }
            })
        }.width('100%')
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }.width('100%').height('100%').translate({ x: this.weekOffset }).opacity(this.weekOpacity())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private timetableContent() {
    Column() {
      this.timetableHeader();
      if (this.loading) {
        Column({ space: HitaDesign.spaceMd }) {
          LoadingProgress().width(HitaDesign.controlHeight).height(HitaDesign.controlHeight)
          Text('正在读取课表').fontSize(HitaDesign.caption).fontColor(HitaColors.onSurfaceVariant)
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.loadError.length > 0 || this.timetable === undefined) {
        Column() { this.emptyContent(); }.width('100%').layoutWeight(1)
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          Stack() {
            this.weekPage();
          }.width('100%').height('100%').clip(true)
            .onTouch((event: TouchEvent) => this.recordWeekTouch(event))
            .parallelGesture(PanGesture({ direction: PanDirection.Horizontal, distance: 10 })
              .tag('atomic-week-swipe')
              .onActionUpdate((event: GestureEvent) => this.dragWeek(event))
              .onActionEnd((event: GestureEvent) => this.finishWeekDrag(event))
              .onActionCancel(() => {
                this.weekGestureAllowed = false;
                this.snapWeekBack();
              }))
            .onGestureJudgeBegin((info: GestureInfo, _event: BaseGestureEvent) => {
              return info.tag === 'atomic-week-swipe' && !this.weekGestureAllowed ?
                GestureJudgeResult.REJECT : GestureJudgeResult.CONTINUE;
            })
          if (this.canReturnToCurrentWeek()) this.returnToCurrentWeek();
        }.width('100%').layoutWeight(1)
          .onAreaChange((_old: Area, area: Area) => {
            const width = Number(area.width);
            if (this.pageWidth > 0 && width !== this.pageWidth) this.resetWeekMotion();
            this.pageWidth = width;
          })
      }
    }.width('100%').height('100%').padding({ top: this.statusInset })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.hita_page'))
  }

  @Builder
  private importContent() {
    Column({ space: HitaDesign.spaceMd }) {
      Text('教务导入').fontSize(HitaDesign.title).fontWeight(FontWeight.Medium)
        .fontColor(HitaColors.onSurface).width('100%')
      Column() {
        ForEach(ATOMIC_CAMPUSES, (campus: string, index: number) => {
          HitaListRow({ symbol: $r('sys.symbol.person_crop_circle_fill'), title: campus + '教务登录',
            divider: index > 0, onTap: () => {
              this.loginCampus = campus;
              this.sheetMode = AtomicSheet.LOGIN;
            } })
        }, (campus: string): string => campus)
      }.width('100%').backgroundColor($r('app.color.hita_surface')).borderRadius(HitaDesign.cardRadius)
      Text(this.importMessage.length > 0 ? this.importMessage : '请选择校区')
        .fontSize(HitaDesign.caption).fontColor(HitaColors.onSurfaceVariant).width('100%')
    }.padding({ left: HitaDesign.inset, right: HitaDesign.inset, bottom: HitaDesign.spaceLg })
  }

  @Builder
  private sheetContent() {
    SheetContent({ fillHeight: this.sheetMode === AtomicSheet.EDITOR || this.sheetMode === AtomicSheet.LOGIN }) {
      if (this.sheetMode === AtomicSheet.LOGIN) {
        AcademicLoginContent({ campus: this.loginCampus, onImported: () => { this.sheetVisible = false; this.refresh(true); } })
      } else if (this.sheetMode === AtomicSheet.SETUP) {
        AtomicTermSetup({ saving: this.busy, error: this.sheetError,
          onCreate: (date: number, weeks: number, campus: number) => this.createTimetable(date, weeks, campus),
          onCancel: () => { this.sheetVisible = false; } })
      } else if (this.sheetMode === AtomicSheet.EDITOR) {
        EventEditorForm({ eventId: this.selectedIds.length > 0 ? this.selected.id : '', targetTimetableId: this.timetable?.id ?? '',
          initialType: 'CLASS', sheetMode: true,
          onCancel: () => { this.sheetVisible = false; },
          onSaved: () => { this.sheetVisible = false; this.refresh(); } })
      } else if (this.sheetMode === AtomicSheet.DETAIL) {
        CourseDetailContent({ event: this.selected, endTime: this.selectedEnd,
          periodText: this.periodText(), dateText: AtomicTimetableStore.dateLabel(this.selected.from),
          progressText: this.progressText(), deleteLabel: '删除', busy: this.busy,
          courseColorEditing: $colorEditing, courseColorPreview: $colorPreview,
          onSaveColor: (color: number) => this.saveColor(color),
          onEdit: () => { this.colorEditing = false; this.sheetMode = AtomicSheet.EDITOR; },
          onDelete: () => this.deleteCourse() })
      } else {
        this.importContent();
      }
    }
  }

  build() {
    Column() {
      AtomicServiceNavigation({
        navPathStack: this.paths, hideTitleBar: true, mode: NavigationMode.Stack,
        navigationContent: () => { this.timetableContent(); }
      }).width('100%').height('100%')
        .backgroundColor($r('app.color.hita_page'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }.width('100%').height('100%')
      .backgroundColor($r('app.color.hita_page'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.sheetVisible, this.sheetContent(), CompatibleSheetMaterial.options({
        height: this.sheetMode === AtomicSheet.EDITOR || this.sheetMode === AtomicSheet.LOGIN ? '90%' : SheetSize.FIT_CONTENT,
        dragBar: true, showClose: false, preferType: SheetType.BOTTOM,
        backgroundColor: $r('app.color.hita_surface_soft'), maskColor: $r('app.color.hita_sheet_mask'),
        onWillDisappear: () => { this.sheetVisible = false; },
        onDisappear: () => {
          this.sheetVisible = false;
          this.selected = new EasEventItem();
          this.selectedIds = [];
          this.colorEditing = false;
          this.sheetMode = AtomicSheet.SETUP;
        }
      }))
  }
}
