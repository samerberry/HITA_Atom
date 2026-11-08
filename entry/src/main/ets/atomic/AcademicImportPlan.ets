import { EasCourseItem, EasTermItem } from '../feature/eas/model/EasModels';
import { EasTimetable, EasTermSubject, EasEventItem, EasEventType, EasTimePeriodInDay, WEEK_MILLIS } from '../common/model/timetable/TimetableModels';
import { AtomicAcademicConfig } from './AtomicAcademicConfig';

export class AcademicImportPlan {
  timetable: EasTimetable = new EasTimetable();
  subjects: EasTermSubject[] = [];
  events: EasEventItem[] = [];

  static create(term: EasTermItem, courses: EasCourseItem[], start: number, campus: string = '威海',
    structure?: EasTimePeriodInDay[]): AcademicImportPlan {
    new AtomicAcademicConfig(campus);
    if (!Number.isFinite(start) || start <= 0) throw new Error('请选择第一教学周的周一');
    if (courses.length === 0) throw new Error('该学期没有可导入的课程');
    const plan = new AcademicImportPlan();
    const table = plan.timetable;
    table.name = campus + ' ' + term.name;
    table.code = (campus === '本部' ? 'BENBU' : campus === '深圳' ? 'SHENZHEN' : 'WEIHAI') + ':' + term.getCode() + ':' + table.id;
    table.startTime = EasTimetable.mondayMsOf(start);
    table.scheduleStructure = structure !== undefined ? structure.map((period: EasTimePeriodInDay) => period.clone()) :
      campus === '本部' ? EasTimetable.getBenbuTimeStructure() :
      campus === '深圳' ? EasTimetable.getDefaultTimeStructure() : EasTimetable.getWeihaiTimeStructure();
    if (table.scheduleStructure.length === 0 || table.scheduleStructure.some((period: EasTimePeriodInDay, index: number): boolean =>
      period.getLengthInMinutes() <= 0 || index > 0 && period.from.before(table.scheduleStructure[index - 1].to))) {
      throw new Error('教务作息时间无法解析，请重新读取');
    }
    let lastWeek = 1;
    for (const course of courses) {
      const last = course.beginSection + course.sectionCount - 1;
      if (!course.name.trim() || !Number.isInteger(course.dayOfWeek) || course.dayOfWeek < 1 || course.dayOfWeek > 7 ||
        !Number.isInteger(course.beginSection) || course.beginSection < 1 || !Number.isInteger(last) ||
        course.sectionCount < 1 || last > table.scheduleStructure.length || course.weekNumbers.length === 0) {
        throw new Error('课程日期或节次无法解析，请核对教务课表');
      }
      let subject = plan.subjects.find((item: EasTermSubject): boolean => item.name === course.name);
      if (subject === undefined) {
        subject = new EasTermSubject();
        subject.timetableId = table.id; subject.name = course.name; subject.code = course.code;
        subject.credit = course.credit;
        plan.subjects.push(subject);
      }
      for (const week of course.weekNumbers) {
        if (!Number.isInteger(week) || week < 1 || week > 40) throw new Error('课程教学周超出范围');
        lastWeek = Math.max(lastWeek, week);
        const times = table.getTimestamps(week, course.dayOfWeek, course.beginSection, last);
        const duplicate = plan.events.find((item: EasEventItem): boolean =>
          item.subjectId === subject!.id && item.from === times[0] && item.to === times[1]);
        if (duplicate !== undefined) {
          if (course.teacher && !duplicate.teacher.split('、').includes(course.teacher)) duplicate.teacher += '、' + course.teacher;
          if (course.classroom && !duplicate.place.split('、').includes(course.classroom)) duplicate.place += '、' + course.classroom;
          continue;
        }
        const event = new EasEventItem();
        event.type = EasEventType.CLASS; event.timetableId = table.id; event.subjectId = subject.id;
        event.name = course.name; event.teacher = course.teacher; event.place = course.classroom;
        event.fromNumber = course.beginSection; event.lastNumber = last;
        event.from = times[0]; event.to = times[1];
        plan.events.push(event);
      }
    }
    table.endTime = table.startTime + lastWeek * WEEK_MILLIS - 1;
    return plan;
  }
}
