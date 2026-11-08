import { HitaDesign } from '../common/theme/HitaDesign';
import { HitaColors } from '../common/theme/HitaColors';
import { HitaButton, HitaButtonVariant } from '../common/components/HitaButton';
import { HitaListRow } from '../common/components/HitaListRow';
import { EasTimetable } from '../common/model/timetable/TimetableModels';
import { ATOMIC_CAMPUSES, AtomicTimetableStore } from './AtomicTimetableStore';

/** Essential term information is requested when creating the first manual timetable. */
@Component
export struct AtomicTermSetup {
  @State firstWeek: number = EasTimetable.mondayMsOf(Date.now());
  @State weeks: number = 20;
  @State campus: number = 0;
  @Prop saving: boolean = false;
  @Prop error: string = '';
  onCreate: (date: number, weeks: number, campus: number) => void = () => {};
  onCancel: () => void = () => {};

  private chooseDate(): void {
    CalendarPickerDialog.show({
      selected: new Date(this.firstWeek),
      onAccept: (date: Date) => { this.firstWeek = EasTimetable.mondayMsOf(date.getTime()); }
    });
  }

  private chooseWeeks(): void {
    const choices: string[] = [];
    for (let week = 1; week <= 40; week++) choices.push(week + ' 周');
    this.getUIContext().showTextPickerDialog({
      range: choices,
      selected: this.weeks - 1, canLoop: false,
      onAccept: (value: TextPickerResult) => {
        if (typeof value.index === 'number') this.weeks = value.index + 1;
      }
    });
  }

  private chooseCampus(): void {
    this.getUIContext().showTextPickerDialog({
      range: ATOMIC_CAMPUSES, selected: this.campus, canLoop: false,
      onAccept: (value: TextPickerResult) => {
        if (typeof value.index === 'number') this.campus = value.index;
      }
    });
  }

  build() {
    Column({ space: HitaDesign.spaceLg }) {
      Text('新建课表').fontSize(HitaDesign.title).fontWeight(FontWeight.Medium).fontColor(HitaColors.onSurface)
        .width('100%')
      Column() {
        HitaListRow({ symbol: $r('sys.symbol.calendar'), title: '第一周周一',
          subtitle: AtomicTimetableStore.dateLabel(this.firstWeek), onTap: () => this.chooseDate() })
        HitaListRow({ symbol: $r('sys.symbol.repeat_1'), title: '教学周数', subtitle: this.weeks + ' 周',
          divider: true, onTap: () => this.chooseWeeks() })
        HitaListRow({ symbol: $r('sys.symbol.clock'), title: '校区作息', subtitle: ATOMIC_CAMPUSES[this.campus],
          divider: true, onTap: () => this.chooseCampus() })
      }.width('100%').borderRadius(HitaDesign.cardRadius).backgroundColor($r('app.color.hita_surface'))
        .enabled(!this.saving)
      if (this.error.length > 0) {
        Text(this.error).fontSize(HitaDesign.caption).fontColor(HitaColors.error).width('100%')
      }
      Row({ space: HitaDesign.spaceSm }) {
        HitaButton({ label: '取消', variant: HitaButtonVariant.NEUTRAL, disabled: this.saving,
          onTap: () => this.onCancel() }).width(0).layoutWeight(1)
        HitaButton({ label: this.saving ? '正在创建' : '创建并添加课程', disabled: this.saving,
          onTap: () => this.onCreate(this.firstWeek, this.weeks, this.campus) }).width(0).layoutWeight(2)
      }
    }
    .width('100%').padding({ left: HitaDesign.inset, right: HitaDesign.inset, bottom: HitaDesign.spaceLg })
  }
}
