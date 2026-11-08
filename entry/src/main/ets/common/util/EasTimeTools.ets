/**
 * EasTimeTools.ets — 课表时间工具（HITA_X utils/TimeTools.kt 直迁；去掉 Context/资源依赖）。
 *
 * 行为要点：
 *  - 周一为一周起点；星期几 getDow：周一=1 … 周日=7
 *  - 节次相关以 List<EasTimePeriodInDay> 的“作息结构”驱动
 *  - 日期串为纯文本格式化（无 i18n 资源，先按 zh 文案内联）
 */
import {
  DAY_MILLIS,
  WEEK_MILLIS,
  EasTimeInDay,
  EasTimePeriodInDay,
  EasTimetable
} from '../model/timetable/TimetableModels';

export enum EasSeason {
  SPRING = 'SPRING',
  SUMMER = 'SUMMER',
  AUTUMN = 'AUTUMN',
  WINTER = 'WINTER'
}

export const DOW_FULL: string[] = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
export const DOW_SHORT: string[] = ['', '一', '二', '三', '四', '五', '六', '日'];

function pad2(n: number): string {
  return n < 10 ? '0' + n.toString() : n.toString();
}

export class EasTimeTools {
  /** 该 ms 所在周的周一 0 点（ms）。 */
  static getMondayMs(ts: number): number {
    return EasTimetable.mondayMsOf(ts);
  }

  /** 星期几（周一=1 … 周日=7）。 */
  static getDow(ts: number): number {
    return EasTimetable.dowOfMs(ts);
  }

  static currentDOW(): number {
    return EasTimetable.dowOfMs(Date.now());
  }

  /** 季节（月份划分与源一致：1-4春 5-7夏 8-10秋 11-12冬）。 */
  static getSeason(ts: number): EasSeason {
    const month: number = new Date(ts).getMonth() + 1;
    if (month >= 1 && month <= 4) {
      return EasSeason.SPRING;
    }
    if (month >= 5 && month <= 7) {
      return EasSeason.SUMMER;
    }
    if (month >= 8 && month <= 10) {
      return EasSeason.AUTUMN;
    }
    return EasSeason.WINTER;
  }

  /** 同一自然日。 */
  static isSameDay(tsA: number, tsB: number): boolean {
    const a: Date = new Date(tsA);
    const b: Date = new Date(tsB);
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() &&
      a.getDate() === b.getDate();
  }

  /** yyyy-MM-dd。 */
  static printDate(ts: number): string {
    const d: Date = new Date(ts);
    return d.getFullYear().toString() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
  }

  /** HH:mm（24h；原资源为 hh:mm 12h，课表内多以 24h 呈现，按需微调）。 */
  static printTime(ts: number): string {
    const d: Date = new Date(ts);
    return pad2(d.getHours()) + ':' + pad2(d.getMinutes());
  }

  /** 本地时 小时/分钟（替代源里“东八区算式”，随设备时区）。 */
  static getHour(ts: number): number {
    return new Date(ts).getHours();
  }

  static getMinute(ts: number): number {
    return new Date(ts).getMinutes();
  }

  /** 与“今天”的相对文案（今天/明天/昨天/大后天/前天/空）。 */
  static relativeDayTag(ts: number): string {
    const todayMs: number = new Date().setHours(0, 0, 0, 0);
    const day: number = Math.round((ts - todayMs) / DAY_MILLIS);
    if (day === 0) {
      return '今天';
    }
    if (day === 1) {
      return '明天';
    }
    if (day === -1) {
      return '昨天';
    }
    if (day === 2) {
      return '大后天';
    }
    if (day === -2) {
      return '前天';
    }
    return '';
  }

  /**
   * 当前处于第几节（对应 TimeTools.getCurrentScheduleNumber）：
   * 结果 = 节数*10（+5 表示课间）。0=未开始第1节前。
   */
  static getCurrentScheduleNumber(structure: EasTimePeriodInDay[]): number {
    let current: number = 0;
    const now: number = Date.now();
    const tp: EasTimeInDay = EasTimeInDay.fromTimestamp(now);
    for (let i = 0; i < structure.length; i++) {
      if (structure[i].containsTimestamp(now)) {
        current = 10 * (i + 1);
        break;
      }
      if (tp.before(structure[i].from)) {
        current += 5;
        break;
      }
      if (tp.after(structure[i].to)) {
        current += 10;
      }
    }
    return current;
  }

  /** 第 weekOfTerm 周、dow 那天的 ms（基于 startDate 所在周）。 */
  static dateAtWeekOfTerm(startDateMs: number, weekOfTerm: number, dow: number): number {
    const days: number = (weekOfTerm - 1) * 7 + (dow - 1);
    return EasTimetable.mondayMsOf(startDateMs) + days * DAY_MILLIS;
  }

  /** 是否同一周（mondayMs 为周一 0 点）。 */
  static isSameWeek(mondayMs: number, ts: number): boolean {
    return ts >= mondayMs && ts < mondayMs + WEEK_MILLIS;
  }
}
