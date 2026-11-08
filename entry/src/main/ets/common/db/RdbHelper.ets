import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { EasTimetable, EasEventItem, EasEventType, EasTermSubject } from '../model/timetable/TimetableModels';
import { CourseDateSelection } from '../../feature/timetable/CourseDateSelection';
import { ScheduleChangeSignal } from '../util/ScheduleChangeSignal';

class AtomicDataFile {
  version: number = 1;
  timetables: EasTimetable[] = [];
  subjects: EasTermSubject[] = [];
  events: EasEventItem[] = [];
}

/** Compatibility facade for the reused editor. Atomic services cannot use relationalStore.
 * Each mutation writes a complete draft to a sibling file and renames it before publishing in memory.
 * There is no await inside a mutation: concurrent UI calls are serialized by the JS event loop.
 */
export class RdbHelper {
  private static instance: RdbHelper | undefined = undefined;
  private data: AtomicDataFile | undefined = undefined;
  private path: string = '';

  static getInstance(): RdbHelper {
    if (RdbHelper.instance === undefined) RdbHelper.instance = new RdbHelper();
    return RdbHelper.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.data !== undefined) return;
    const path = context.filesDir + '/atomic-timetable-v1.json';
    // Only a genuinely absent file is an empty installation. Corrupt/unreadable files stay untouched.
    const data = fileIo.accessSync(path) ? RdbHelper.decode(fileIo.readTextSync(path)) : new AtomicDataFile();
    this.path = path;
    this.data = data;
  }

  private current(): AtomicDataFile {
    if (this.data === undefined) throw new Error('课表存储尚未就绪');
    return this.data;
  }

  private static table(value: EasTimetable): EasTimetable {
    const result = new EasTimetable();
    result.id = value.id; result.name = value.name; result.code = value.code;
    result.startTime = value.startTime; result.endTime = value.endTime; result.createdAt = value.createdAt;
    result.scheduleStructure = EasTimetable.decodeStructure(EasTimetable.encodeStructure(value.scheduleStructure));
    return result;
  }

  private static subject(value: EasTermSubject): EasTermSubject {
    const result = new EasTermSubject();
    result.id = value.id; result.name = value.name; result.timetableId = value.timetableId;
    result.type = value.type; result.field = value.field; result.credit = value.credit;
    result.school = value.school; result.countInSPA = value.countInSPA; result.code = value.code;
    result.key = value.key; result.createdAt = value.createdAt; result.color = value.color;
    return result;
  }

  private static event(value: EasEventItem): EasEventItem {
    const result = new EasEventItem();
    result.id = value.id; result.type = value.type; result.name = value.name;
    result.place = value.place; result.teacher = value.teacher; result.subjectId = value.subjectId;
    result.timetableId = value.timetableId; result.from = value.from; result.to = value.to;
    result.fromNumber = value.fromNumber; result.lastNumber = value.lastNumber;
    result.createdAt = value.createdAt; result.color = value.color;
    return result;
  }

  private static decode(text: string): AtomicDataFile {
    const raw = JSON.parse(text) as AtomicDataFile;
    if (raw.version !== 1 || !Array.isArray(raw.timetables) || !Array.isArray(raw.subjects) || !Array.isArray(raw.events)) {
      throw new Error('课表存储格式无效');
    }
    const result = new AtomicDataFile();
    result.timetables = raw.timetables.map((value: EasTimetable): EasTimetable => {
      if (typeof value.id !== 'string' || value.id.length === 0 || !Number.isFinite(value.startTime) ||
        !Number.isFinite(value.endTime) || value.endTime <= value.startTime ||
        !Array.isArray(value.scheduleStructure) || value.scheduleStructure.length === 0) throw new Error('无效课表');
      return RdbHelper.table(value);
    });
    result.subjects = raw.subjects.map((value: EasTermSubject): EasTermSubject => RdbHelper.subject(value));
    result.events = raw.events.map((value: EasEventItem): EasEventItem => {
      if (typeof value.id !== 'string' || !Number.isFinite(value.from) || !Number.isFinite(value.to) ||
        value.to <= value.from) throw new Error('无效课程');
      return RdbHelper.event(value);
    });
    return result;
  }

  private mutate(change: (draft: AtomicDataFile) => void): void {
    const draft = RdbHelper.decode(JSON.stringify(this.current()));
    change(draft);
    const bytes = new util.TextEncoder().encodeInto(JSON.stringify(draft));
    const temp = this.path + '.pending';
    const file = fileIo.openSync(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      let written: number = 0;
      while (written < bytes.length) {
        const count = fileIo.writeSync(file.fd, bytes.buffer.slice(written));
        if (count <= 0) throw new Error('课表写入失败');
        written += count;
      }
    } finally {
      fileIo.closeSync(file);
    }
    fileIo.renameSync(temp, this.path);
    this.data = draft;
    ScheduleChangeSignal.notify();
  }

  private static projected(data: AtomicDataFile, value: EasEventItem): EasEventItem {
    const result = RdbHelper.event(value);
    if (result.type === EasEventType.CLASS) {
      result.color = data.subjects.find((subject: EasTermSubject): boolean =>
        subject.id === result.subjectId && subject.timetableId === result.timetableId)?.color ?? 0;
    }
    return result;
  }

  private static requireTable(data: AtomicDataFile, id: string): EasTimetable {
    const result = data.timetables.find((value: EasTimetable): boolean => value.id === id);
    if (result === undefined) throw new Error('课表不存在');
    return result;
  }

  private static cover(table: EasTimetable, events: EasEventItem[]): void {
    for (const event of events) {
      if (!Number.isFinite(event.from) || !Number.isFinite(event.to) || event.to <= event.from) throw new Error('课程时间无效');
      if (event.from < EasTimetable.mondayMsOf(table.startTime)) throw new Error('课程早于开学日期');
      if (event.to > table.endTime) table.endTime = CourseDateSelection.weekEnd(event.to);
    }
  }

  async getTimetables(_strict: boolean = false): Promise<EasTimetable[]> {
    return this.current().timetables.map((value: EasTimetable): EasTimetable => RdbHelper.table(value))
      .sort((left: EasTimetable, right: EasTimetable): number => right.startTime - left.startTime);
  }

  async getTimetableById(id: string, _strict: boolean = false): Promise<EasTimetable | undefined> {
    const value = this.current().timetables.find((table: EasTimetable): boolean => table.id === id);
    return value === undefined ? undefined : RdbHelper.table(value);
  }

  /** Commit an imported timetable and all children together; retain other timetables. */
  async saveImportedTimetable(table: EasTimetable, subjects: EasTermSubject[], events: EasEventItem[]): Promise<void> {
    if (this.current().timetables.some((item: EasTimetable): boolean => item.id === table.id)) return;
    if (!events.length || !subjects.length || !Number.isFinite(table.startTime) || table.startTime <= 0 ||
      !Number.isFinite(table.endTime) || table.endTime <= table.startTime) throw new Error('导入课表无效');
    const subjectIds = new Set<string>();
    for (const subject of subjects) {
      if (subject.timetableId !== table.id || subjectIds.has(subject.id)) throw new Error('导入课程关联无效');
      subjectIds.add(subject.id);
    }
    for (const event of events) {
      if (event.timetableId !== table.id || !subjectIds.has(event.subjectId) ||
        event.type !== EasEventType.CLASS) throw new Error('导入课次关联无效');
    }
    this.mutate((data: AtomicDataFile) => {
      const imported = RdbHelper.table(table);
      RdbHelper.cover(imported, events);
      data.timetables.push(imported);
      subjects.forEach((subject: EasTermSubject) => data.subjects.push(RdbHelper.subject(subject)));
      events.forEach((event: EasEventItem) => data.events.push(RdbHelper.event(event)));
    });
  }

  async saveTimetable(table: EasTimetable): Promise<void> {
    this.mutate((data: AtomicDataFile) => {
      if (table.id.length === 0 || !Number.isFinite(table.startTime) || !Number.isFinite(table.endTime) ||
        table.endTime <= table.startTime || table.scheduleStructure.length === 0) throw new Error('课表无效');
      data.timetables = data.timetables.filter((value: EasTimetable): boolean => value.id !== table.id);
      data.timetables.push(RdbHelper.table(table));
    });
  }

  async getSubjectsOfTimetable(id: string): Promise<EasTermSubject[]> {
    return this.current().subjects.filter((subject: EasTermSubject): boolean => subject.timetableId === id)
      .map((subject: EasTermSubject): EasTermSubject => RdbHelper.subject(subject));
  }

  async getEventsOfTimetable(id: string, _strict: boolean = false): Promise<EasEventItem[]> {
    const data = this.current();
    return data.events.filter((event: EasEventItem): boolean => event.timetableId === id)
      .map((event: EasEventItem): EasEventItem => RdbHelper.projected(data, event))
      .sort((left: EasEventItem, right: EasEventItem): number => left.from - right.from);
  }

  async getEventById(id: string, _strict: boolean = false): Promise<EasEventItem | undefined> {
    const data = this.current();
    const event = data.events.find((item: EasEventItem): boolean => item.id === id);
    return event === undefined ? undefined : RdbHelper.projected(data, event);
  }

  async getClassesOfSubject(id: string): Promise<EasEventItem[]> {
    const data = this.current();
    return data.events.filter((item: EasEventItem): boolean => item.subjectId === id && item.type === EasEventType.CLASS)
      .map((event: EasEventItem): EasEventItem => RdbHelper.projected(data, event))
      .sort((left: EasEventItem, right: EasEventItem): number => left.from - right.from);
  }

  async saveCourseOccurrences(subject: EasTermSubject, events: EasEventItem[], newSubject: boolean): Promise<void> {
    this.mutate((data: AtomicDataFile) => {
      const table = RdbHelper.requireTable(data, subject.timetableId);
      if (events.length === 0 || events.some((event: EasEventItem): boolean => event.type !== EasEventType.CLASS ||
        event.subjectId !== subject.id || event.timetableId !== table.id || event.id.length === 0) ||
        new Set(events.map((event: EasEventItem): string => event.id)).size !== events.length ||
        events.some((event: EasEventItem): boolean => data.events.some((existing: EasEventItem): boolean =>
          existing.id === event.id))) throw new Error('课程重复或无效');
      const existing = data.subjects.find((item: EasTermSubject): boolean => item.id === subject.id);
      if (newSubject) {
        if (existing !== undefined) throw new Error('科目已存在');
        data.subjects.push(RdbHelper.subject(subject));
      } else if (existing === undefined || existing.timetableId !== table.id) throw new Error('科目不存在');
      RdbHelper.cover(table, events);
      for (const event of events) data.events.push(RdbHelper.event(event));
    });
  }

  async replaceCourseOccurrences(before: EasEventItem[], after: EasEventItem[], timetableId: string): Promise<void> {
    this.mutate((data: AtomicDataFile) => {
      const table = RdbHelper.requireTable(data, timetableId);
      if ((before.length === 0 && after.length === 0) || before.concat(after).some((event: EasEventItem): boolean =>
        event.type !== EasEventType.CLASS || event.timetableId !== timetableId || event.id.length === 0) ||
        new Set(before.map((item: EasEventItem): string => item.id)).size !== before.length ||
        new Set(after.map((item: EasEventItem): string => item.id)).size !== after.length) throw new Error('课程范围无效');
      for (const event of before) {
        const current = data.events.find((item: EasEventItem): boolean => item.id === event.id && item.timetableId === timetableId);
        if (current === undefined || JSON.stringify(RdbHelper.projected(data, current)) !== JSON.stringify(RdbHelper.event(event))) {
          throw new Error('课程已变化，请重新打开后修改');
        }
      }
      for (const event of after) {
        if (!data.subjects.some((subject: EasTermSubject): boolean => subject.id === event.subjectId &&
          subject.timetableId === timetableId)) throw new Error('科目不存在');
        if (data.events.some((item: EasEventItem): boolean => item.id === event.id) &&
          !before.some((item: EasEventItem): boolean => item.id === event.id)) throw new Error('课程已存在');
      }
      RdbHelper.cover(table, after);
      data.events = data.events.filter((item: EasEventItem): boolean =>
        !before.some((event: EasEventItem): boolean => event.id === item.id));
      for (const event of after) data.events.push(RdbHelper.event(event));
    });
  }

  async deleteClassOccurrences(ids: string[], timetableId: string): Promise<void> {
    this.mutate((data: AtomicDataFile) => {
      const previous = data.events.length;
      data.events = data.events.filter((event: EasEventItem): boolean =>
        event.type !== EasEventType.CLASS || event.timetableId !== timetableId || !ids.includes(event.id));
      if (data.events.length === previous) throw new Error('课程不存在');
    });
  }

  async saveCourseColor(id: string, timetableId: string, color: number): Promise<void> {
    this.mutate((data: AtomicDataFile) => {
      const subject = data.subjects.find((item: EasTermSubject): boolean => item.id === id && item.timetableId === timetableId);
      if (subject === undefined) throw new Error('科目不存在');
      subject.color = color;
    });
  }

  async saveEvent(event: EasEventItem): Promise<void> {
    this.mutate((data: AtomicDataFile) => {
      if (data.events.some((item: EasEventItem): boolean => item.id === event.id)) throw new Error('日程已存在');
      RdbHelper.cover(RdbHelper.requireTable(data, event.timetableId), [event]);
      data.events.push(RdbHelper.event(event));
    });
  }

  async updateEvent(event: EasEventItem): Promise<void> {
    this.mutate((data: AtomicDataFile) => {
      if (!data.events.some((item: EasEventItem): boolean => item.id === event.id &&
        item.timetableId === event.timetableId)) throw new Error('日程不存在');
      RdbHelper.cover(RdbHelper.requireTable(data, event.timetableId), [event]);
      data.events = data.events.filter((item: EasEventItem): boolean => item.id !== event.id);
      data.events.push(RdbHelper.event(event));
    });
  }
}
