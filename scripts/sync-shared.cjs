// Extract the timetable dependency closure, never the full app or its signing configuration.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const project = path.resolve(__dirname, '..');
const sourceProject = path.resolve(process.argv[2] || path.join(project, '../HITA_NEXT-0.3.0'));
const source = path.join(sourceProject, 'entry/src/main/ets');
const target = path.join(project, 'entry/src/main/ets');
const manifestPath = path.join(project, 'shared-sources.json');
const previous = fs.existsSync(manifestPath) ? JSON.parse(fs.readFileSync(manifestPath, 'utf8')) : [];

function transform(file, text) {
  if (file === 'common/db/RdbHelper.ets') return fs.readFileSync(path.join(project, 'scripts/adapters/RdbHelper.ets'), 'utf8');
  if (file === 'common/theme/CompatibleLightModifier.ets') return `
// RenderNode/drawing glow is unavailable to atomic services. Preserve the host's
// geometry: light feedback must never replace a course card's own corner radius.
export class CompatibleLightModifier implements AttributeModifier<CommonAttribute> {
  constructor(_radius: number = 22, _enabled: boolean = true, _panel: boolean = false) {}
  applyNormalAttribute(_instance: CommonAttribute): void {}
}
`;
  if (file === 'common/components/DetailActionBar.ets') {
    return text.replace(/import \{ LearningTaskLink \}[^;]+;\s*/g, '')
      .replace(/          if \(this\.taskEvent !== undefined\) \{[\s\S]*?\n          \}/, '');
  }
  return text;
}

const pending = ['pages/AddEventPage.ets', 'feature/timetable/views/TimetableWeekDraw.ets',
  'feature/timetable/views/TimetableCardPainter.ets', 'feature/timetable/views/CourseDetailContent.ets',
  'common/components/SheetContent.ets', 'common/components/HitaButton.ets',
  'common/components/HitaListRow.ets', 'common/components/HeaderActionButton.ets',
  'feature/eas/data/EasLegacyTimetableParser.ets', 'feature/eas/data/EasAcademicCalendar.ets',
  'feature/eas/data/ShenzhenWebTimetableParser.ets'];
const seen = new Set();
const manifest = [];
while (pending.length) {
  const file = pending.pop();
  if (seen.has(file)) continue;
  seen.add(file);
  const original = fs.readFileSync(path.join(source, file), 'utf8').replace(/^\uFEFF/, '');
  const text = transform(file, original);
  const dest = path.join(target, file);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, text);
  manifest.push({ file, sourceSha256: crypto.createHash('sha256').update(original).digest('hex'),
    extractedSha256: crypto.createHash('sha256').update(text).digest('hex'), adapted: original !== text });
  for (const match of text.matchAll(/from\s*['"]([^'"]+)['"]/g)) {
    if (!match[1].startsWith('.')) continue;
    const dependency = path.resolve(path.dirname(dest), match[1] + '.ets');
    const relative = path.relative(target, dependency).replaceAll('\\', '/');
    if (relative.startsWith('../')) throw new Error(`Dependency escapes project: ${relative}`);
    pending.push(relative);
  }
}
for (const { file } of previous) {
  const obsolete = path.resolve(target, file);
  if (!seen.has(file) && obsolete.startsWith(target + path.sep) && fs.existsSync(obsolete)) fs.unlinkSync(obsolete);
}
for (const appearance of ['base', 'dark']) {
  const resource = `entry/src/main/resources/${appearance}/element/color.json`;
  const dest = path.join(project, resource);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(path.resolve(sourceProject, resource), dest);
}
const icon = 'AppScope/resources/base/media/app_icon.png';
if (fs.existsSync(path.resolve(sourceProject, icon))) {
  fs.mkdirSync(path.dirname(path.join(project, icon)), { recursive: true });
  fs.copyFileSync(path.resolve(sourceProject, icon), path.join(project, icon));
}
fs.writeFileSync(path.join(project, 'shared-sources.json'), JSON.stringify(manifest.sort((a, b) => a.file.localeCompare(b.file)), null, 2) + '\n');
console.log(`Extracted ${manifest.length} shared timetable/parser files; atomic login stays independent.`);
