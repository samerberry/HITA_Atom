const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
let ts;
try { ts = require('typescript'); } catch {
  ts = require(path.join(process.env.ProgramFiles, 'Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
}
const root = path.resolve(__dirname, '../entry/src/main/ets');

const vpnBase = 'https://webvpn.hitwh.edu.cn/http/77726476706e69737468656265737421fae0558f693861446900c7a99c406d3667';
const termsHtml = '<select name="xnxq"><option value="2026-20271" selected>秋季</option></select>';

function schoolPage(fetcher, url = vpnBase + '/loginCAS', doubleEncode = false) {
  const requests = [], scripts = [];
  const timers = new Set();
  const context = vm.createContext({ window: {}, location: new URL(url), AbortController,
    setTimeout(callback, delay) { const timer = setTimeout(callback, delay); timers.add(timer); return timer; },
    clearTimeout(timer) { timers.delete(timer); clearTimeout(timer); },
    fetch(target, options) { requests.push({ target, options }); return fetcher(target, options); } });
  return { context, requests, scripts, navigate() {
    // A real document navigation destroys its JS timers and global objects.
    timers.forEach(timer => clearTimeout(timer)); timers.clear(); context.window = {};
  }, async runJavaScript(script) {
    scripts.push(script);
    const result = vm.runInContext(script, context);
    // Match ArkWeb: do NOT await a Promise produced by the injected expression.
    const raw = result == null ? 'null' : String(result);
    return doubleEncode ? JSON.stringify(raw) : raw;
  } };
}

function bridgeFor(t, page) {
  const h = harness(t);
  const { AtomicWebFetch } = h.load('atomic/AtomicWebFetch.ets');
  const bridge = new AtomicWebFetch(); bridge.attach(page);
  t.after(() => bridge.close());
  return bridge;
}

function response(text = termsHtml, status = 200) { return { status, async text() { return text; } }; }

test('async fetch returns through synchronous polling, shares cookies, and releases each result', async t => {
  const page = schoolPage(async () => response(), undefined, true);
  const h = harness(t), { AtomicAcademicClient } = h.load('atomic/AtomicAcademicClient.ets');
  const client = new AtomicAcademicClient(); client.attachController(page); t.after(() => client.close());
  const terms = await client.terms();
  assert.equal(terms[0].getCode(), '2026-20271');
  const wrong = Object.assign(Object.create(Object.getPrototypeOf(terms[0])), terms[0], { termCode: '2' });
  await assert.rejects(client.courses(wrong), /学期与选择不一致/);
  assert.equal(await client.firstWeek(terms[0]), 0);
  assert.equal(page.requests.length, 3);
  assert.equal(page.requests[0].target, vpnBase + '/kbcx/queryGrkb');
  assert.equal(page.requests[1].options.method, 'POST');
  assert.match(page.requests[1].options.body, /xnxq=2026-20272/);
  for (const { options } of page.requests) {
    assert.equal(options.credentials, 'include'); assert.equal(options.mode, 'same-origin');
    assert.equal('Cookie' in options.headers, false);
  }
  assert.equal(Object.keys(page.context.window).length, 0);
  assert.ok(page.scripts.length > page.requests.length * 2, 'polls instead of parsing a Promise result');
});

test('origin selects the matching VPN/direct route, and portal/SSO/other pages never issue a request', async t => {
  for (const origin of ['http://jwts.hitwh.edu.cn', 'https://jwts.hitwh.edu.cn']) {
    const page = schoolPage(async () => response(), origin + '/home');
    assert.equal(await bridgeFor(t, page).request('/kbcx/queryGrkb'), termsHtml);
    assert.equal(page.requests[0].target, origin + '/kbcx/queryGrkb');
  }
  for (const url of ['https://ids.hit.edu.cn/authserver/login', 'https://webvpn.hitwh.edu.cn/',
    'https://jwts.hitwh.edu.cn.example.com/', 'https://webvpn.hitwh.edu.cn' + '/http/other']) {
    const page = schoolPage(async () => response(), url);
    await assert.rejects(bridgeFor(t, page).request('/kbcx/queryGrkb'), /请先进入教务/);
    assert.equal(page.requests.length, 0);
  }
});

test('gateway/login HTML is not authentication and does not trigger an HTTP fallback', async t => {
  const page = schoolPage(async () => response('<html>login</html>'));
  const { AtomicAcademicClient } = harness(t).load('atomic/AtomicAcademicClient.ets');
  const client = new AtomicAcademicClient(); client.attachController(page); t.after(() => client.close());
  await assert.rejects(client.terms(), /会话尚未就绪/);
  assert.equal(page.requests.length, 1);
  assert.ok(page.requests.every(r => r.target.startsWith(vpnBase)));
});

test('HTTP, fetch, invalid bridge values, and page loss have distinct failures and cleanup', async t => {
  const unavailable = schoolPage(async () => response('maintenance', 503));
  await assert.rejects(bridgeFor(t, unavailable).request('/kbcx/queryGrkb'), /HTTP 503/);
  const offline = schoolPage(async () => { throw new Error('private URL and ticket must not reach UI'); });
  await assert.rejects(bridgeFor(t, offline).request('/kbcx/queryGrkb'), /教务网页请求失败/);
  for (const raw of ['[object Promise]', 'null', '"not json"', '{"id":"wrong","state":"done"}']) {
    await assert.rejects(bridgeFor(t, { async runJavaScript() { return raw; } }).request('/kbcx/queryGrkb'), /响应解析失败/);
  }
  const page = schoolPage(() => new Promise(() => {}));
  const bridge = bridgeFor(t, page), pending = bridge.request('/kbcx/queryGrkb');
  const rejected = assert.rejects(pending, /页面已切换/);
  page.navigate();
  await rejected;
  assert.equal(Object.keys(unavailable.context.window).length, 0);
  assert.equal(Object.keys(offline.context.window).length, 0);
});

test('navigation cancels old fetch, retries cannot read stale results, and close settles immediately', async t => {
  let oldResponse;
  const page = schoolPage(() => new Promise(resolve => { oldResponse = resolve; }));
  const bridge = bridgeFor(t, page);
  const pending = bridge.request('/kbcx/queryGrkb');
  const rejected = assert.rejects(pending, /取消/);
  bridge.cancel(); await rejected;
  assert.equal(page.requests[0].options.signal.aborted, true);
  oldResponse(response('stale')); await Promise.resolve();
  page.context.fetch = async () => response('fresh');
  assert.equal(await bridge.request('/kbcx/queryGrkb'), 'fresh');
  assert.equal(Object.keys(page.context.window).length, 0);
  page.context.fetch = () => new Promise(() => {});
  const last = bridge.request('/xlcx/queryXlcx');
  const closed = assert.rejects(last, /取消/);
  bridge.close(); await closed;
  await assert.rejects(bridge.request('/kbcx/queryGrkb'), /取消/);
  assert.equal(Object.keys(page.context.window).length, 0);
});

test('timeouts abort hanging fetch and bound native bridge calls that never return', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const page = schoolPage(() => new Promise(() => {}));
  const pending = bridgeFor(t, page).request('/kbcx/queryGrkb');
  const rejected = assert.rejects(pending, /超时/);
  await Promise.resolve();
  t.mock.timers.tick(30000); await rejected;
  assert.equal(page.requests[0].options.signal.aborted, true);
  assert.equal(Object.keys(page.context.window).length, 0);
  const hanging = bridgeFor(t, { runJavaScript() { return new Promise(() => {}); } }).request('/kbcx/queryGrkb');
  const bounded = assert.rejects(hanging, /超时/);
  t.mock.timers.tick(30000); await bounded;
});

test('Weihai import expands school periods and weeks and commits atomically without replacing local courses', async t => {
  const h = harness(t), { table } = await seed(h);
  const { AcademicImportPlan } = h.load('atomic/AcademicImportPlan.ets');
  const { EasTermItem, EasCourseItem } = h.load('feature/eas/model/EasModels.ets');
  const term = Object.assign(new EasTermItem(), { yearCode: '2026-2027', termCode: '1', termName: '秋季' });
  const course = Object.assign(new EasCourseItem(), { name: '数学', teacher: '老师', classroom: 'H702',
    dayOfWeek: 1, beginSection: 1, sectionCount: 2, weekNumbers: [1, 3] });
  const plan = AcademicImportPlan.create(term, [course, course], new Date(2026, 7, 31).getTime());
  assert.equal(plan.events.length, 2);
  assert.equal(plan.subjects.length, 1);
  assert.equal(new Date(plan.events[0].from).getHours(), 8);
  assert.equal(plan.events[1].from - plan.events[0].from, 14 * 86400000);
  assert.equal(plan.events[0].lastNumber, 2);
  const before = fs.readFileSync(path.join(h.dir, 'atomic-timetable-v1.json'), 'utf8');
  h.state.failRename = true;
  await assert.rejects(h.db.saveImportedTimetable(plan.timetable, plan.subjects, plan.events));
  assert.equal((await h.db.getTimetables()).length, 1);
  assert.equal(fs.readFileSync(path.join(h.dir, 'atomic-timetable-v1.json'), 'utf8'), before);
  h.state.failRename = false;
  await h.db.saveImportedTimetable(plan.timetable, plan.subjects, plan.events);
  await h.db.saveImportedTimetable(plan.timetable, plan.subjects, plan.events);
  assert.equal((await h.db.getTimetables()).length, 2);
  assert.equal((await h.db.getEventsOfTimetable(table.id)).length, 3);
  assert.equal((await h.db.getEventsOfTimetable(plan.timetable.id)).length, 2);
  course.beginSection = 99;
  assert.throws(() => AcademicImportPlan.create(term, [course], Date.now()));
  assert.throws(() => AcademicImportPlan.create(term, [], Date.now()));
});

test('Weihai HTML parser distinguishes gateway pages from valid term selectors', t => {
  const h = harness(t);
  const { EasLegacyTimetableParser: parser } = h.load('feature/eas/data/EasLegacyTimetableParser.ets');
  assert.deepEqual(parser.parseTermsBySelect('<html>WebVPN 登录成功</html>', 'xnxq'), []);
  const terms = parser.parseTermsBySelect('<select name="xnxq"><option value="2026-20271" selected>2026-2027秋季</option></select>', 'xnxq');
  assert.equal(terms.length, 1);
  assert.equal(terms[0].getCode(), '2026-20271');
  assert.equal(terms[0].isCurrent, true);
});

test('campus login routing excludes gateways, forged hosts and authentication screens', t => {
  const { AtomicAcademicConfig } = harness(t).load('atomic/AtomicAcademicConfig.ets');
  const benbu = new AtomicAcademicConfig('本部'), sz = new AtomicAcademicConfig('深圳');
  assert.equal(benbu.loginUrl, 'http://jwts-hit-edu-cn.vpn.hit.edu.cn:1080/loginCAS');
  assert.equal(benbu.shouldRead(benbu.loginUrl), true);
  assert.equal(benbu.shouldRead('https://ivpn.hit.edu.cn/portal/shortcut.html'), false);
  assert.equal(benbu.redirectFor('http://i-hit-edu-cn.vpn.hit.edu.cn:1080/portal/home/'), benbu.loginUrl);
  assert.equal(sz.shouldRead('https://jw.hitsz.edu.cn:443/student_index'), true);
  assert.equal(sz.redirectFor('https://jw.hitsz.edu.cn/authentication/require'), 'https://jw.hitsz.edu.cn/cas');
  assert.equal(sz.redirectFor('https://jw-hitsz-edu-cn.hitsz.edu.cn/session/invalid'),
    'https://jw-hitsz-edu-cn.hitsz.edu.cn/cas');
  assert.equal(sz.redirectFor('https://trust.hitsz.edu.cn:443/portal/'), sz.loginUrl);
  for (const url of ['https://trust.hitsz.edu.cn/portal/shortcut.html',
    'https://authserver.hitsz.edu.cn/authserver/login',
    'https://jw.hitsz.edu.cn/authentication/require',
    'https://jw-hitsz-edu-cn.hitsz.edu.cn.example.com/student_index']) assert.equal(sz.shouldRead(url), false);
  assert.equal(sz.redirectFor('https://trust.hitsz.edu.cn.example.com/portal/'), '');
  assert.throws(() => new AtomicAcademicConfig('unknown'));
});

test('Shenzhen preserves gateway SPA login/MFA routes, including a fragment after the ticket query', t => {
  const { AtomicAcademicConfig } = harness(t).load('atomic/AtomicAcademicConfig.ets');
  const config = new AtomicAcademicConfig('深圳');
  for (const path of ['/portal/#/login', '/portal/#!/login', '/portal/?ticket=test#/login?redirect=home',
    '/portal/#/app_center/auth', '/portal/#/smsAuth', '/portal/#/totpAuth', '/portal/#/radiusAuth',
    '/portal/#/reset_password', '/portal/#/page_forget_password', '/portal/#/trust_terminal_confirm',
    '/portal/#/open_client_mobile', '/portal/#/info_acl', '/portal/#/unknown_future_route',
    '/portal/shortcut.html#/login']) {
    const url = 'https://trust.hitsz.edu.cn:443' + path;
    assert.equal(config.redirectFor(url), '', path);
    assert.equal(config.shouldRead(url), false, path);
  }
  assert.equal(config.redirectFor('https://trust.hitsz.edu.cn/portal/?returnUrl=%2Flogin'), config.loginUrl);
  assert.equal(config.redirectFor('https://trust.hitsz.edu.cn/portal/service_center.html'), config.loginUrl);
  assert.equal(config.redirectFor('https://trust.hitsz.edu.cn:443/portal/#/app_center'), config.loginUrl);
  assert.equal(config.redirectFor('https://trust.hitsz.edu.cn/portal/service_center.html#/'), config.loginUrl);
  assert.equal(config.redirectFor('https://trust.hitsz.edu.cn/portal/service_center.html#!/'), config.loginUrl);
});

test('Shenzhen mobile UA gives the legacy gateway a supported OS without changing the device or engine', t => {
  const { shenzhenMobileUserAgent } = harness(t).load('atomic/ShenzhenWebLogin.ets');
  for (const platform of ['OpenHarmony 7.0', 'HarmonyOS 6.1']) {
    const native = `Mozilla/5.0 (Phone; ${platform}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Mobile Safari/537.36 ArkWeb/4.1.0.0`;
    const compatible = shenzhenMobileUserAgent(native);
    // The gateway's System() requires the case-sensitive Android token; without
    // it authConfig returns HTTP 422, which its SDK endlessly retries as CSRF.
    assert.ok(compatible.includes('Android'));
    assert.ok(compatible.startsWith(native));
    assert.equal(shenzhenMobileUserAgent(compatible), compatible);
    assert.doesNotMatch(compatible, /Windows|Macintosh/);
  }
});

test('Shenzhen mobile compatibility preserves browser UAs already recognized by the gateway', t => {
  const { shenzhenMobileUserAgent } = harness(t).load('atomic/ShenzhenWebLogin.ets');
  for (const ua of ['Mozilla/5.0 (Linux; Android 12; HarmonyOS) Mobile',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Mobile',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64)', '']) {
    assert.equal(shenzhenMobileUserAgent(ua), ua);
  }
});

function gatewayDocument(origin, entries = [], subframe = false) {
  const storage = new Map(entries), window = {};
  window.top = subframe ? {} : window;
  const context = vm.createContext({ window, location: new URL(origin), sessionStorage: {
    getItem(key) { return storage.get(key) ?? null; },
    setItem(key, value) { storage.set(key, String(value)); }
  } });
  return { context, storage };
}

test('Shenzhen gateway sees browser mode on its first initialization and every later document', t => {
  const { SHENZHEN_GATEWAY_BOOTSTRAP: bootstrap, SHENZHEN_GATEWAY_ORIGIN: origin } =
    harness(t).load('atomic/ShenzhenWebLogin.ets');
  const page = gatewayDocument(origin + ':443/portal/shortcut.html');
  for (let navigation = 0; navigation < 3; navigation++) {
    page.storage.set('forceWeb', 'false');
    vm.runInContext(bootstrap, page.context);
    // Match the public gateway's startup read, before onPageEnd can fire.
    assert.equal(vm.runInContext("JSON.parse(sessionStorage.getItem('forceWeb'))", page.context), true);
    const prefixes = JSON.parse(page.storage.get('__Prefix_map__'));
    assert.deepEqual(prefixes, [{ pre: '[1]', addr: origin }]);
    assert.equal(page.storage.get('[1]forceWeb'), 'true');
    assert.deepEqual(Object.keys(page.context.window), ['top']);
  }
});

test('Shenzhen browser preference preserves gateway storage and tolerates old or malformed prefix maps', t => {
  const { SHENZHEN_GATEWAY_BOOTSTRAP: bootstrap, SHENZHEN_GATEWAY_ORIGIN: origin } =
    harness(t).load('atomic/ShenzhenWebLogin.ets');
  const existing = [{ pre: '[4]', addr: 'https://other.school.example' }, { pre: '[8]', addr: origin }];
  const page = gatewayDocument(origin, [['__Prefix_map__', JSON.stringify(existing)], ['school-setting', 'keep']]);
  vm.runInContext(bootstrap, page.context);
  assert.deepEqual(JSON.parse(page.storage.get('__Prefix_map__')), existing);
  assert.equal(page.storage.get('[8]forceWeb'), 'true');
  assert.equal(page.storage.get('school-setting'), 'keep');
  assert.equal(page.storage.has('[4]forceWeb'), false);
  for (const raw of ['not JSON', '{}', 'null', '[null]', JSON.stringify([existing[0]])]) {
    const fresh = gatewayDocument(origin, [['__Prefix_map__', raw]]);
    assert.doesNotThrow(() => vm.runInContext(bootstrap, fresh.context));
    assert.equal(fresh.storage.get('forceWeb'), 'true');
    const prefix = JSON.parse(fresh.storage.get('__Prefix_map__')).find(item => item?.addr === origin).pre;
    assert.equal(fresh.storage.get(prefix + 'forceWeb'), 'true');
  }
});

test('Shenzhen bootstrap never changes CAS/other origins or iframes and tolerates unavailable storage', t => {
  const { SHENZHEN_GATEWAY_BOOTSTRAP: bootstrap, SHENZHEN_GATEWAY_ORIGIN: origin } =
    harness(t).load('atomic/ShenzhenWebLogin.ets');
  for (const [url, subframe] of [[origin, true], [origin + '.example.com', false], [origin + ':444', false],
    ['https://authserver.hitsz.edu.cn/authserver/login', false], ['https://ids.hit.edu.cn/authserver/login', false],
    ['https://webvpn.hitwh.edu.cn/', false]]) {
    const page = gatewayDocument(url, [], subframe);
    vm.runInContext(bootstrap, page.context);
    assert.equal(page.storage.size, 0, url);
  }
  const unavailable = gatewayDocument(origin);
  unavailable.context.sessionStorage.setItem = () => { throw new Error('Storage unavailable'); };
  assert.doesNotThrow(() => vm.runInContext(bootstrap, unavailable.context));
});

function loginControl(label, tag = 'button', extra = {}) {
  return { innerText: label, tag, clicks: 0, disabled: false, type: 'button',
    getAttribute() { return null; },
    getBoundingClientRect() { return { width: 100, height: 40 }; },
    matches(selector) { return selector.split(',').some(part => part === this.tag ||
      part === 'input[type="button"]' && this.tag === 'input' && this.type === 'button'); },
    closest() { return this.tag === 'button' ? this : this.parentButton ?? null; },
    click() { this.clicks++; }, ...extra };
}

function mobileLoginPage(url) {
  const page = gatewayDocument(url), timers = new Map(), listeners = new Map(), observers = new Set();
  let now = 0, sequence = 0, elements = [];
  const document = { documentElement: {}, body: { innerText: '' },
    querySelectorAll(selector) { return elements.filter(element => element.matches(selector)); } };
  Object.assign(page.context, { document,
    setTimeout(callback, delay) { const id = ++sequence; timers.set(id, { at: now + delay, callback }); return id; },
    clearTimeout(id) { timers.delete(id); },
    MutationObserver: class {
      constructor(callback) { this.callback = callback; }
      observe() { observers.add(this); }
      disconnect() { observers.delete(this); }
    }
  });
  Object.assign(page.context.window, {
    getComputedStyle(element) { return { display: element.hidden ? 'none' : 'block', visibility: 'visible' }; },
    addEventListener(name, callback) { listeners.set(name, callback); },
    removeEventListener(name) { listeners.delete(name); }
  });
  return { ...page, timers, observers, listeners,
    render(nodes, text = '') {
      elements = nodes; document.body.innerText = text;
      for (const observer of observers) observer.callback();
    },
    tick(duration) {
      const end = now + duration;
      for (let count = 0; count < 100; count++) {
        const first = [...timers].sort((a, b) => a[1].at - b[1].at)[0];
        if (!first || first[1].at > end) { now = end; return; }
        now = first[1].at; timers.delete(first[0]); first[1].callback();
      }
      throw new Error('Unexpected unbounded login retry');
    }
  };
}

test('mobile Shenzhen advances SSO and undergraduate choices once, including asynchronously rendered buttons', t => {
  const { SHENZHEN_LOGIN_ADVANCE: script } = harness(t).load('atomic/ShenzhenWebLogin.ets');
  for (const origin of ['https://trust.hitsz.edu.cn:443/portal/', 'https://jw.hitsz.edu.cn/authentication/main',
    'https://jw-hitsz-edu-cn.hitsz.edu.cn/authentication/main']) {
    const page = mobileLoginPage(origin), wrapper = loginControl('统一身份认证登录', 'div');
    const unified = loginControl(' 统一身份认证 登录 '), undergrad = loginControl('本科生');
    const postgrad = loginControl('研究生'), manualLogin = loginControl('登录');
    page.render([wrapper, unified, manualLogin]);
    vm.runInContext(script, page.context); page.tick(100);
    assert.equal(unified.clicks, 1); assert.equal(wrapper.clicks, 0); assert.equal(manualLogin.clicks, 0);
    page.render([unified, manualLogin]); page.tick(100);
    assert.equal(unified.clicks, 1, 'DOM changes must not repeatedly click SSO');
    page.render([undergrad, postgrad], '请选择 本科生 研究生'); page.tick(100);
    assert.equal(undergrad.clicks, 1); assert.equal(postgrad.clicks, 0);
    assert.equal(page.timers.size, 0); assert.equal(page.observers.size, 0);
  }
});

test('mobile Shenzhen skips hidden, disabled and password-form submit controls', t => {
  const { SHENZHEN_LOGIN_ADVANCE: script } = harness(t).load('atomic/ShenzhenWebLogin.ets');
  const page = mobileLoginPage('https://jw.hitsz.edu.cn/authentication/main');
  const hidden = loginControl('统一身份认证', 'button', { hidden: true });
  const disabled = loginControl('统一身份认证', 'button', { disabled: true });
  const submit = loginControl('统一身份认证登录', 'button', { type: 'submit',
    form: { querySelector() { return {}; } } });
  const submitLabel = loginControl('统一身份认证登录', 'span', { parentButton: submit });
  const password = loginControl('', 'input', { type: 'password' });
  Object.defineProperty(password, 'value', { get() { throw new Error('must not read credentials'); } });
  page.render([hidden, disabled, submit, submitLabel, password]);
  vm.runInContext(script, page.context); page.tick(100);
  assert.equal(hidden.clicks + disabled.clicks + submit.clicks + submitLabel.clicks + password.clicks, 0);
  const sso = loginControl('统一身份认证登录', 'a');
  page.render([sso]); page.tick(100);
  assert.equal(sso.clicks, 1);
  page.listeners.get('pagehide')();
  assert.equal(page.timers.size, 0); assert.equal(page.observers.size, 0); assert.equal(page.listeners.size, 0);
});

test('mobile Shenzhen advancement stops on timeout or page exit and leaves CAS/other origins alone', t => {
  const { SHENZHEN_LOGIN_ADVANCE: script } = harness(t).load('atomic/ShenzhenWebLogin.ets');
  for (const exit of [false, true]) {
    const page = mobileLoginPage('https://trust.hitsz.edu.cn/portal/');
    vm.runInContext(script, page.context);
    if (exit) page.listeners.get('pagehide')(); else page.tick(20000);
    const sso = loginControl('统一身份认证登录'); page.render([sso]); page.tick(100);
    assert.equal(sso.clicks, 0); assert.equal(page.timers.size, 0); assert.equal(page.observers.size, 0);
  }
  for (const url of ['https://authserver.hitsz.edu.cn/authserver/login', 'https://ids.hit.edu.cn/authserver/login',
    'https://jw.hitsz.edu.cn/authserver/login', 'https://trust.hitsz.edu.cn.example.com/',
    'https://trust.hitsz.edu.cn:444/', 'http://trust.hitsz.edu.cn/', 'https://webvpn.hitwh.edu.cn/']) {
    const page = mobileLoginPage(url); vm.runInContext(script, page.context);
    assert.equal(page.timers.size, 0, url); assert.equal(page.observers.size, 0, url);
  }
  const frame = mobileLoginPage('https://trust.hitsz.edu.cn/portal/'); frame.context.window.top = {};
  vm.runInContext(script, frame.context); assert.equal(frame.timers.size, 0);
});

test('Benbu reads its current VPN endpoint, and campus bridges never reuse another campus origin', async t => {
  const h = harness(t), { AtomicAcademicClient } = h.load('atomic/AtomicAcademicClient.ets');
  const page = schoolPage(async () => response(), 'http://jwts-hit-edu-cn.vpn.hit.edu.cn:1080/loginCAS');
  const client = new AtomicAcademicClient('本部'); client.attachController(page); t.after(() => client.close());
  const terms = await client.terms();
  assert.equal(terms[0].getCode(), '2026-20271');
  assert.equal(page.requests[0].target, 'http://jwts-hit-edu-cn.vpn.hit.edu.cn:1080/kbcx/queryGrkb');
  assert.equal((await client.structure(terms[0]))[0].to.toString(), '8:50');
  const { AtomicWebFetch } = h.load('atomic/AtomicWebFetch.ets');
  for (const [campus, url] of [['本部', vpnBase + '/home'], ['深圳', page.context.location.href],
    ['深圳', 'https://trust.hitsz.edu.cn/portal/'], ['威海', 'https://jw.hitsz.edu.cn/student_index']]) {
    const wrong = schoolPage(async () => response(), url), bridge = new AtomicWebFetch(campus);
    bridge.attach(wrong); t.after(() => bridge.close());
    await assert.rejects(bridge.request(campus === '深圳' ? '/component/queryXnxq' : '/kbcx/queryGrkb'), /请先进入教务/);
    assert.equal(wrong.requests.length, 0);
  }
});

test('Shenzhen uses empty POST, current-role term calibration, metadata, school periods and calendar', async t => {
  const h = harness(t), { AtomicAcademicClient } = h.load('atomic/AtomicAcademicClient.ets');
  for (const base of ['https://jw-hitsz-edu-cn.hitsz.edu.cn', 'https://jw.hitsz.edu.cn']) {
    const page = schoolPage(async target => {
      const endpoint = new URL(target).pathname;
      const replies = {
        '/component/queryXnxq': { data: [] },
        '/component/queryxnxqdata': { data: [
          { XN: '2026-2027', XQ: '1', XQMC: '秋季' }, { XN: '2026-2027', XQ: '2', XQMC: '春季' }] },
        '/Xsxk/queryXkdqXnxq': { data: { p_xn: '2026-2027', p_xq: '1' } },
        '/Xsxk/queryYxkc': { data: [{ kcdm: 'MATH', kcmc: '数学', dgjsmc: '老师', rwh: 'task' }] },
        '/xszykb/queryxszykbzong': { content: [{ RWH: 'task', XQJ: 1, KSJC: 1, JSJC: 2,
          ZC: '1,3', CDMC: 'H702' }] },
        '/component/queryKbjg': { data: [ { XJ: 2, KSSJ: '09:35', JSSJ: '10:25' },
          { XJ: 1, KSSJ: '08:40', JSSJ: '09:30' }] },
        '/component/queryRlZcSj': { data: [{ XN: '2026-2027', XQ: '1', DJZ: '1', RQ: '2026-08-31' }] }
      };
      assert.ok(endpoint in replies, endpoint);
      return response(JSON.stringify(replies[endpoint]));
    }, base + '/student_index');
    const client = new AtomicAcademicClient('深圳'); client.attachController(page); t.after(() => client.close());
    const terms = await client.terms(), term = terms[0];
    assert.equal(term.getCode(), '2026-20271'); assert.equal(term.isCurrent, true);
    const courses = await client.courses(term), structure = await client.structure(term), start = await client.firstWeek(term);
    assert.equal(courses[0].name, '数学'); assert.equal(courses[0].teacher, '老师');
    assert.deepEqual(courses[0].weekNumbers, [1, 3]); assert.equal(courses[0].classroom, 'H702');
    assert.equal(structure[0].from.toString(), '8:40'); assert.equal(client.usesDefaultStructure, false);
    assert.equal(new Date(start).getDay(), 1);
    assert.equal(page.requests[0].options.body, '');
    const selection = page.requests.find(r => r.target.includes('/queryYxkc'));
    const form = new URLSearchParams(selection.options.body);
    assert.equal(form.get('p_xnxq'), '2026-20271'); assert.equal(form.get('p_xkfsdm'), 'yixuan');
    assert.equal(form.get('p_pylx'), '1'); assert.equal(form.get('pageSize'), '200');
    for (const { target, options } of page.requests) {
      assert.ok(target.startsWith(base + '/')); assert.equal(options.method, 'POST');
      assert.equal(options.headers.RoleCode, '01'); assert.equal(options.headers['X-Requested-With'], 'XMLHttpRequest');
      assert.equal(options.credentials, 'include'); assert.equal(options.mode, 'same-origin');
      assert.equal('Cookie' in options.headers, false);
    }
    const { AcademicImportPlan } = h.load('atomic/AcademicImportPlan.ets');
    const plan = AcademicImportPlan.create(term, courses, start, '深圳', structure);
    assert.equal(plan.events.length, 2); assert.equal(plan.timetable.code.startsWith('SHENZHEN:'), true);
    assert.equal(new Date(plan.events[0].from).getMinutes(), 40);
    assert.equal(new Date(plan.events[0].to).getHours(), 10); assert.equal(new Date(plan.events[0].to).getMinutes(), 25);
  }
});

test('Shenzhen optional metadata/period failures preserve courses; navigation cancels the entire read chain', async t => {
  const h = harness(t), { AtomicAcademicClient } = h.load('atomic/AtomicAcademicClient.ets');
  const term = Object.assign(new (h.load('feature/eas/model/EasModels.ets').EasTermItem)(), { yearCode: '2026-2027', termCode: '1' });
  const page = schoolPage(async target => {
    if (target.includes('/queryxszykbzong')) return response(JSON.stringify({ data: [
      { KCMC: '物理', XQJ: 2, KSJC: 1, JSJC: 2, ZC: '2-4' }] }));
    return response('unavailable', 503);
  }, 'https://jw.hitsz.edu.cn/student_index');
  const client = new AtomicAcademicClient('深圳'); client.attachController(page); t.after(() => client.close());
  assert.equal((await client.courses(term))[0].name, '物理');
  assert.equal((await client.structure(term))[0].from.toString(), '8:30');
  assert.equal(client.usesDefaultStructure, true);
  const pendingPage = schoolPage(() => new Promise(() => {}), 'https://jw.hitsz.edu.cn/student_index');
  client.attachController(pendingPage);
  const pending = client.courses(term), cancelled = assert.rejects(pending, /页面已切换/);
  client.pageStarted(); await cancelled;
  assert.equal(pendingPage.requests.length, 1, 'cancelled metadata must not start a timetable request on another page');
  const expired = schoolPage(async () => response('<html>login</html>'), 'https://jw.hitsz.edu.cn/authentication/main');
  client.attachController(expired);
  await assert.rejects(client.terms(), /会话尚未就绪/);
});

test('import plans retain each campus schedule and reject invalid or overlapping period times', t => {
  const h = harness(t), { AcademicImportPlan } = h.load('atomic/AcademicImportPlan.ets');
  const { EasCourseItem, EasTermItem } = h.load('feature/eas/model/EasModels.ets');
  const { EasTimePeriodInDay } = h.models;
  const term = Object.assign(new EasTermItem(), { yearCode: '2026-2027', termCode: '1' });
  const course = Object.assign(new EasCourseItem(), { name: '数学', dayOfWeek: 1, beginSection: 1, sectionCount: 2, weekNumbers: [1] });
  const start = new Date(2026, 7, 31).getTime();
  for (const [campus, minutes] of [['本部', 45], ['威海', 45], ['深圳', 15]]) {
    const plan = AcademicImportPlan.create(term, [course], start, campus);
    assert.ok(plan.timetable.name.startsWith(campus));
    assert.equal(new Date(plan.events[0].to).getMinutes(), minutes);
  }
  const invalid = [EasTimePeriodInDay.ofHour(9, 0, 8, 0)];
  assert.throws(() => AcademicImportPlan.create(term, [course], start, '本部', invalid), /作息时间无法解析/);
  const overlapping = [EasTimePeriodInDay.ofHour(8, 0, 9, 0), EasTimePeriodInDay.ofHour(8, 50, 10, 0)];
  assert.throws(() => AcademicImportPlan.create(term, [course], start, '深圳', overlapping), /作息时间无法解析/);
});

test('login reads publish a complete term snapshot and navigation discards late results', async t => {
  const { page } = loginHarness(t);
  const term = { name: '秋季', isCurrent: true };
  const courses = [{ name: '数学' }], periods = [{ from: '08:00', to: '08:45' }];
  let resolvePeriods;
  page.client.terms = async () => [term];
  page.client.courses = async () => courses;
  page.client.structure = () => new Promise(resolve => { resolvePeriods = resolve; });
  page.client.firstWeek = async () => 12345;
  const pending = page.verify();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(page.ready, true);
  assert.equal(page.busy, true);
  assert.deepEqual(page.courses, []);
  assert.deepEqual(page.structure, []);
  resolvePeriods(periods); await pending;
  assert.equal(page.courses, courses);
  assert.equal(page.structure, periods);
  assert.equal(page.firstWeek, 12345);
  assert.equal(page.busy, false);

  const cancelled = page.verify();
  await new Promise(resolve => setImmediate(resolve));
  page.pageStarted('https://ids.hit.edu.cn/authserver/login');
  resolvePeriods(periods); await cancelled;
  assert.equal(page.ready, false);
  assert.deepEqual(page.courses, []);
  assert.deepEqual(page.structure, []);
  assert.equal(page.firstWeek, 0);
  assert.equal(page.error, '');
});

test('failed term reads never expose a partial course snapshot; missing calendar remains editable', async t => {
  const { page } = loginHarness(t);
  page.client.terms = async () => [{ name: '秋季', isCurrent: true }];
  page.client.courses = async () => [{ name: '数学' }];
  page.client.structure = async () => { throw new Error('教务节次读取失败'); };
  await page.verify();
  assert.equal(page.error, '教务节次读取失败');
  assert.equal(page.busy, false);
  assert.deepEqual(page.courses, []);
  assert.deepEqual(page.structure, []);
  assert.equal(page.firstWeek, 0);

  page.client.structure = async () => [{ from: '08:00', to: '08:45' }];
  page.client.firstWeek = async () => { throw new Error('教务校历不可用'); };
  await page.verify();
  assert.equal(page.error, '');
  assert.equal(page.courses.length, 1);
  assert.equal(page.firstWeek, 0, 'requires a manually selected Monday before import');
});

test('login callbacks ignore old documents and attempt each document only once', async t => {
  const { page, controller } = loginHarness(t);
  const current = vpnBase + '/home';
  controller.url = current;
  page.pageStarted(current);
  let requests = 0;
  page.client.terms = async () => { requests++; throw new Error('教务会话尚未就绪'); };
  page.pageEnded('https://ids.hit.edu.cn/authserver/login');
  assert.equal(page.pageLoading, true);
  assert.equal(requests, 0);
  page.pageEnded(current);
  await new Promise(resolve => setImmediate(resolve));
  page.pageEnded(current);
  assert.equal(requests, 1, 'duplicate page callbacks must not keep retrying a failed read');
  assert.equal(page.pageLoading, false);
  assert.equal(page.error, '', 'an unauthenticated landing page is not a user-visible failure');
  await page.verify();
  assert.equal(requests, 2, 'manual retry is still available');
  assert.equal(page.error, '教务会话尚未就绪');
  page.pageStarted('https://ids.hit.edu.cn/authserver/login');
  page.loadFailed('网页加载较慢，请刷新重试');
  controller.url = 'https://ids.hit.edu.cn/authserver/login';
  page.pageEnded(controller.url);
  assert.equal(page.error, '', 'a page which eventually loads clears its loading error');
  page.aboutToDisappear();
  page.pageEnded(current);
  assert.equal(requests, 2);
  assert.equal(page.pageLoadTimer, -1);
});

test('hidden-page navigation cannot reset an in-progress import', t => {
  const { page } = loginHarness(t);
  page.ready = true; page.busy = true; page.importing = true;
  page.courses = [{ name: '数学' }]; page.firstWeek = 12345;
  const generation = page.navigationGeneration;
  page.pageStarted('https://ids.hit.edu.cn/authserver/login');
  page.loadFailed('网页加载失败');
  assert.equal(page.navigationGeneration, generation);
  assert.equal(page.ready, true);
  assert.equal(page.busy, true);
  assert.equal(page.courses.length, 1);
  assert.equal(page.firstWeek, 12345);
  assert.equal(page.error, '');
});

function loginHarness(t) {
  class Controller {
    url = vpnBase + '/home';
    getUrl() { return this.url; }
    accessBackward() { return false; }
  }
  const h = harness(t, { '@kit.ArkWeb': { webview: { WebviewController: Controller } } });
  const { AcademicLoginContent } = h.load('atomic/AcademicLoginContent.ets');
  const page = new AcademicLoginContent();
  page.alive = true; page.pageLoading = false;
  t.after(() => page.aboutToDisappear());
  return { page, controller: page.controller };
}

function harness(t, kitMocks = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hita-atomic-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const state = { failRename: false, partialWrite: false, id: '', failSelection: false };
  const selection = { async init() {}, async load() {
    if (state.failSelection) throw new Error('preference read failed');
    return state.id;
  }, async save(id) { state.id = id; } };
  const fileIo = {
    accessSync: fs.existsSync, readTextSync: file => fs.readFileSync(file, 'utf8'),
    OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    openSync: file => ({ fd: fs.openSync(file, 'w') }),
    writeSync: (fd, bytes) => fs.writeSync(fd, Buffer.from(bytes), 0,
      state.partialWrite ? Math.min(37, bytes.byteLength) : bytes.byteLength),
    closeSync: file => fs.closeSync(file.fd),
    renameSync: (from, to) => {
      if (state.failRename) throw new Error('disk failure');
      fs.renameSync(from, to);
    }
  };
  const load = (relative, cache = new Map()) => {
    const file = path.resolve(root, relative);
    if (cache.has(file)) return cache.get(file).exports;
    let source = fs.readFileSync(file, 'utf8');
    if (file.endsWith('AcademicLoginContent.ets')) {
      // Execute the actual component's lifecycle/read methods in Node. Declarative
      // ArkUI builders are checked by the real SDK in assembleHap instead.
      source = source.slice(0, source.indexOf('  @Builder')) + '}';
      source = source.replace('@Component', '').replace('export struct ', 'export class ')
        .replace(/@StorageProp\([^)]*\)\s*/g, '').replace(/@State\s*/g, '');
    }
    const compiled = ts.transpileModule(source, { compilerOptions: {
      target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS
    } }).outputText;
    const mod = { exports: {} };
    cache.set(file, mod);
    new Function('require', 'module', 'exports', compiled)(name => {
      if (name in kitMocks) return kitMocks[name];
      if (name === '@kit.CoreFileKit') return { fileIo };
      if (name === '@kit.ArkTS') return { util: { TextEncoder: class {
        encodeInto(text) { return new Uint8Array(Buffer.from(text)); }
      } } };
      if (name.startsWith('@kit.')) return {};
      if (name.endsWith('/TimetableSelectionStore')) return { TimetableSelectionStore: { getInstance: () => selection } };
      return load(path.resolve(path.dirname(file), name + '.ets'), cache);
    }, mod, mod.exports);
    return mod.exports;
  };
  const cache = new Map();
  const models = load('common/model/timetable/TimetableModels.ets', cache);
  const { RdbHelper } = load('common/db/RdbHelper.ets', cache);
  const { AtomicTimetableStore } = load('atomic/AtomicTimetableStore.ets', cache);
  const { CourseBatchEdit } = load('feature/timetable/CourseBatchEdit.ets', cache);
  return { dir, state, load, models, db: new RdbHelper(), store: AtomicTimetableStore, batch: CourseBatchEdit,
    sharedDb: RdbHelper.getInstance(), context: { filesDir: dir } };
}

async function seed(h) {
  const { EasTimetable, EasTermSubject, EasEventItem, EasEventType, WEEK_MILLIS } = h.models;
  await h.db.init(h.context);
  const table = new EasTimetable();
  table.id = 'table'; table.code = 'LOCAL:table';
  table.startTime = new Date(2026, 7, 31).getTime(); table.endTime = table.startTime + 20 * WEEK_MILLIS - 1;
  table.scheduleStructure = EasTimetable.getWeihaiTimeStructure();
  await h.db.saveTimetable(table);
  const subject = new EasTermSubject();
  subject.id = 'subject'; subject.timetableId = table.id; subject.name = '数学';
  const course = (id, week) => Object.assign(new EasEventItem(), {
    id, type: EasEventType.CLASS, name: subject.name, subjectId: subject.id, timetableId: table.id,
    from: table.startTime + (week - 1) * WEEK_MILLIS + 7.75 * 3600000,
    to: table.startTime + (week - 1) * WEEK_MILLIS + 9.5 * 3600000,
    fromNumber: 1, lastNumber: 2, place: 'N551-9', teacher: '老师'
  });
  const courses = [course('a', 1), course('b', 2), course('c', 3)];
  await h.db.saveCourseOccurrences(subject, courses, true);
  return { table, subject, courses, course };
}

test('empty installation stays empty; each campus gets a real Monday and its own period schedule', async t => {
  const h = harness(t);
  assert.equal((await h.store.load(h.context)).timetable, undefined);
  assert.equal(fs.readdirSync(h.dir).length, 0);
  const expected = [8 * 60, 8 * 60, 8 * 60 + 30];
  const firstEnds = [8 * 60 + 50, 8 * 60 + 45, 9 * 60 + 20];
  for (let campus = 0; campus < 3; campus++) {
    await h.store.create(h.context, new Date(2026, 8, 2).getTime(), 20, campus);
    const { timetable } = await h.store.load(h.context);
    assert.equal(timetable.startTime, new Date(2026, 7, 31).getTime());
    assert.equal(h.store.weekCount(timetable), 20);
    const first = timetable.scheduleStructure[0].from;
    assert.equal(first.hour * 60 + first.minute, expected[campus]);
    const end = timetable.scheduleStructure[0].to;
    assert.equal(end.hour * 60 + end.minute, firstEnds[campus]);
  }
  await assert.rejects(h.store.create(h.context, NaN, 20, 0));
  await assert.rejects(h.store.create(h.context, Date.now(), 0, 0));
  await assert.rejects(h.store.create(h.context, Date.now(), 20, 3));
});

test('cold load hydrates timetable/time/event methods and survives partial UTF-8 writes', async t => {
  const h = harness(t); h.state.partialWrite = true;
  const { table } = await seed(h);
  const { RdbHelper } = h.load('common/db/RdbHelper.ets');
  const cold = new RdbHelper(); await cold.init(h.context);
  const restored = await cold.getTimetableById(table.id);
  assert.equal(restored.getWeekNumber(table.startTime + 7 * 86400000), 2);
  assert.equal(restored.scheduleStructure[0].from.toString(), '8:00');
  assert.equal(restored.scheduleStructure[0].to.toString(), '8:45');
  assert.equal(restored.scheduleStructure[0].getLengthInMinutes() > 0, true);
  const event = await cold.getEventById('a');
  assert.equal(event.name, '数学'); assert.equal(event.place, 'N551-9'); assert.equal(event.getDow(), 1);
  event.place = 'caller modification';
  assert.equal((await cold.getEventById('a')).place, 'N551-9');
});

test('duplicate batches and failed file replacement leave disk and memory unchanged', async t => {
  const h = harness(t), { table, subject, course } = await seed(h);
  const file = path.join(h.dir, 'atomic-timetable-v1.json');
  const original = fs.readFileSync(file, 'utf8');
  await assert.rejects(h.db.saveCourseOccurrences(subject, [course('new', 4), course('a', 5)], false));
  assert.equal(fs.readFileSync(file, 'utf8'), original);
  h.state.failRename = true;
  await assert.rejects(h.db.saveCourseOccurrences(subject, [course('new', 4)], false));
  assert.equal((await h.db.getEventsOfTimetable(table.id)).length, 3);
  assert.equal(fs.readFileSync(file, 'utf8'), original);
  h.state.failRename = false;
  await h.db.saveCourseOccurrences(subject, [course('new', 4)], false);
  assert.equal((await h.db.getEventsOfTimetable(table.id)).length, 4);
});

test('period-based batch edits persist, stale requests fail, and undo restores original occurrences', async t => {
  const h = harness(t), { table } = await seed(h);
  const before = await h.db.getEventsOfTimetable(table.id);
  const edited = h.batch.copy(before[0]);
  edited.from += 2 * 3600000; edited.to += 2 * 3600000;
  const after = h.batch.update(before, before[0], edited, [3, 4]);
  await h.db.replaceCourseOccurrences(before, after, table.id);
  assert.deepEqual((await h.db.getEventsOfTimetable(table.id)).map(e => e.fromNumber), [3, 3, 3]);
  await assert.rejects(h.db.replaceCourseOccurrences(before, after, table.id));
  await h.db.replaceCourseOccurrences(after, before, table.id);
  assert.deepEqual((await h.db.getEventsOfTimetable(table.id)).map(e => [e.id, e.from, e.fromNumber]),
    before.map(e => [e.id, e.from, e.fromNumber]));
});

test('simultaneous saves retain both batches and extend the visible semester for late courses', async t => {
  const h = harness(t), { table, subject, course } = await seed(h);
  await Promise.all([h.db.saveCourseOccurrences(subject, [course('d', 21)], false),
    h.db.saveCourseOccurrences(subject, [course('e', 22)], false)]);
  assert.equal((await h.db.getEventsOfTimetable(table.id)).length, 5);
  assert.equal(h.store.weekCount(await h.db.getTimetableById(table.id)), 22);
});

test('deletion and color updates stay within the selected subject/table and preserve other occurrences', async t => {
  const h = harness(t), { table, subject, course } = await seed(h);
  const exam = course('exam', 1); exam.type = h.models.EasEventType.EXAM;
  await h.db.saveEvent(exam);
  await h.db.saveCourseColor(subject.id, table.id, 123);
  assert.equal((await h.db.getEventById('a')).color, 123);
  assert.notEqual((await h.db.getEventById('exam')).color, 123);
  await h.db.deleteClassOccurrences(['a', 'exam'], table.id);
  assert.deepEqual((await h.db.getEventsOfTimetable(table.id)).map(e => e.id), ['exam', 'b', 'c']);
  await assert.rejects(h.db.deleteClassOccurrences(['b'], 'wrong-table'));
  assert.equal((await h.db.getEventsOfTimetable(table.id)).length, 3);
});

test('corrupt data and preference read failures are surfaced without creating replacement data', async t => {
  const h = harness(t), file = path.join(h.dir, 'atomic-timetable-v1.json');
  fs.writeFileSync(file, '{broken');
  await assert.rejects(h.store.load(h.context));
  assert.equal(fs.readFileSync(file, 'utf8'), '{broken');
  fs.unlinkSync(file);
  h.state.failSelection = true;
  await assert.rejects(h.store.load(h.context));
  assert.equal(fs.readdirSync(h.dir).length, 0);
});

test('visible-week axis expands only for that week, preserving the original timetable behavior', t => {
  const h = harness(t), { EasTimetable, EasEventItem, WEEK_MILLIS } = h.models;
  const table = new EasTimetable(); table.startTime = new Date(2026, 7, 31).getTime(); table.endTime = table.startTime + 20 * WEEK_MILLIS;
  const early = Object.assign(new EasEventItem(), { from: table.startTime + WEEK_MILLIS + 7.75 * 3600000,
    to: table.startTime + WEEK_MILLIS + 9.5 * 3600000 });
  const { TimetableAxis, eventsOfWeek } = h.load('feature/timetable/views/TimetableWeekDraw.ets');
  assert.equal(TimetableAxis.forEvents(table, eventsOfWeek(table, [early], 1)).startHour, 8);
  assert.equal(TimetableAxis.forEvents(table, eventsOfWeek(table, [early], 2)).startHour, 7);
});
