import { common } from '@kit.AbilityKit';
import { RdbHelper } from '../common/db/RdbHelper';
import { EasEventItem, EasEventType, EasTimetable, WEEK_MILLIS } from '../common/model/timetable/TimetableModels';
import { TimetableSelectionStore } from '../feature/timetable/data/TimetableSelectionStore';

export const ATOMIC_CAMPUSES: string[] = ['本部', '威海', '深圳'];

export class AtomicTimetableSnapshot {
  timetable: EasTimetable | undefined = undefined;
  events: EasEventItem[] = [];
}

/** One selected timetable, in the atomic service's own sandbox. No full-app dependency. */
export class AtomicTimetableStore {
  static async load(context: common.Context): Promise<AtomicTimetableSnapshot> {
    const db = RdbHelper.getInstance();
    await db.init(context);
    const selection = TimetableSelectionStore.getInstance();
    await selection.init(context);
    const id: string = await selection.load(true);
    const snapshot = new AtomicTimetableSnapshot();
    snapshot.timetable = id.length > 0 ? await db.getTimetableById(id, true) : undefined;
    if (snapshot.timetable === undefined) snapshot.timetable = (await db.getTimetables(true))[0];
    if (snapshot.timetable !== undefined) {
      snapshot.events = (await db.getEventsOfTimetable(snapshot.timetable.id, true))
        .filter((event: EasEventItem): boolean => event.type === EasEventType.CLASS);
      await selection.save(snapshot.timetable.id);
    }
    return snapshot;
  }

  static async create(context: common.Context, firstWeek: number, weeks: number, campus: number): Promise<void> {
    if (!Number.isFinite(firstWeek) || firstWeek <= 0 || !Number.isInteger(weeks) || weeks < 1 || weeks > 40 ||
      !Number.isInteger(campus) || campus < 0 || campus >= ATOMIC_CAMPUSES.length) {
      throw new Error('课表日期或周数无效');
    }
    const db = RdbHelper.getInstance();
    await db.init(context);
    const timetable = new EasTimetable();
    timetable.name = 'HITA课表';
    timetable.code = 'LOCAL:' + timetable.id;
    timetable.startTime = EasTimetable.mondayMsOf(firstWeek);
    timetable.endTime = timetable.startTime + weeks * WEEK_MILLIS - 1;
    timetable.scheduleStructure = campus === 0 ? EasTimetable.getBenbuTimeStructure() :
      (campus === 1 ? EasTimetable.getWeihaiTimeStructure() : EasTimetable.getDefaultTimeStructure());
    await db.saveTimetable(timetable);
    const selection = TimetableSelectionStore.getInstance();
    await selection.init(context);
    await selection.save(timetable.id);
  }

  static weekCount(timetable: EasTimetable): number {
    return Math.max(1, Math.ceil((timetable.endTime + 1 - timetable.startTime) / WEEK_MILLIS));
  }

  static dateLabel(value: number): string {
    const date = new Date(value);
    return date.getFullYear() + '年' + (date.getMonth() + 1) + '月' + date.getDate() + '日';
  }
}
