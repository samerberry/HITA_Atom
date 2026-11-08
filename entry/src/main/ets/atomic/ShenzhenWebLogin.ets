import { SHENZHEN_EAS, SHENZHEN_DIRECT } from './AtomicAcademicConfig';

/** aTrust's legacy OS parser rejects OpenHarmony as platform=Unknown. */
export function shenzhenMobileUserAgent(deviceUserAgent: string): string {
  if (!/\b(?:OpenHarmony|HarmonyOS)\b/i.test(deviceUserAgent) || /\bAndroid\b/i.test(deviceUserAgent)) {
    return deviceUserAgent;
  }
  // Keep the device, Mobile, ArkWeb and Chromium tokens. Android is only the
  // gateway's supported mobile compatibility token, not a desktop UA override.
  return deviceUserAgent + ' Android';
}

/** Browser mode avoids the native aTrust client; it does not require a desktop UA. */
export const SHENZHEN_GATEWAY_ORIGIN: string = 'https://trust.hitsz.edu.cn';
export const SHENZHEN_GATEWAY_BOOTSTRAP: string = `(function() {
  if (window.top !== window || location.origin !== 'https://trust.hitsz.edu.cn') return;
  try {
    sessionStorage.setItem('forceWeb', 'true');
    var key = '__Prefix_map__', map;
    try { map = JSON.parse(sessionStorage.getItem(key) || '[]'); } catch (_) { map = []; }
    if (!Array.isArray(map)) map = [];
    var origin = location.origin;
    var item = map.find(function(v) { return v && v.addr === origin && /^\\[\\d+\\]$/.test(v.pre); });
    if (!item) {
      var max = map.reduce(function(n, v) {
        var m = v && String(v.pre || '').match(/^\\[(\\d+)\\]$/);
        return m ? Math.max(n, Number(m[1])) : n;
      }, 0);
      item = {pre: '[' + (max + 1) + ']', addr: origin};
      map.unshift(item);
    }
    sessionStorage.setItem(key, JSON.stringify(map));
    sessionStorage.setItem(item.pre + 'forceWeb', 'true');
  } catch (_) {}
})();`;

export const SHENZHEN_LOGIN_ORIGINS: string[] = [SHENZHEN_GATEWAY_ORIGIN, SHENZHEN_EAS, SHENZHEN_DIRECT];

/** Advance only the school's SSO/undergraduate choices, never credential forms. */
export const SHENZHEN_LOGIN_ADVANCE: string = `(function() {
  if (window.top !== window || ${JSON.stringify(SHENZHEN_LOGIN_ORIGINS)}.indexOf(location.origin) < 0 ||
    /\\/authserver\\//i.test(location.pathname)) return;
  var unifiedClicked = false, roleClicked = false, active = true;
  var pending = 0, deadline = 0, observer = null;
  function normalized(value) { return String(value || '').replace(/\\s+/g, ''); }
  function labelOf(element) {
    return normalized(element.innerText || element.textContent ||
      element.getAttribute('aria-label') || element.getAttribute('title') ||
      (element.matches('input[type="button"]') ? element.value : ''));
  }
  function visible(element) {
    if (typeof element.click !== 'function' || element.disabled || element.getAttribute('aria-disabled') === 'true') return false;
    var button = element.closest('button');
    if (button && button.type === 'submit' && button.form &&
      button.form.querySelector('input[type="password"]')) return false;
    var style = window.getComputedStyle(element), rect = element.getBoundingClientRect();
    return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
  }
  function choose(items, predicate) {
    var matches = items.filter(function(element) { return predicate(labelOf(element)); });
    return matches.find(function(element) {
      return element.matches('a,button,[role="button"],input[type="button"],[onclick]');
    }) || matches[matches.length - 1];
  }
  function stop() {
    active = false;
    clearTimeout(pending); clearTimeout(deadline);
    if (observer) observer.disconnect();
    window.removeEventListener('pagehide', stop);
  }
  function advance() {
    pending = 0;
    if (!active) return;
    var items = Array.prototype.slice.call(document.querySelectorAll(
      'a,button,[role="button"],input[type="button"],[onclick],span,div'
    )).filter(visible);
    if (!unifiedClicked) {
      var unified = choose(items, function(label) {
        return label === '统一身份认证登录' || label === '统一身份认证';
      });
      if (unified) {
        unifiedClicked = true;
        unified.click();
        schedule();
        return;
      }
    }
    var pageText = normalized(document.body && document.body.innerText);
    if (!roleClicked && pageText.indexOf('本科') >= 0 && pageText.indexOf('研究生') >= 0) {
      var role = choose(items, function(label) {
        return ['本科', '本科生', '本科生登录', '本科生入口', '本科教务', '本科生教务',
          '本科教务入口', '本科教务管理系统', '本科生教务管理系统'].indexOf(label) >= 0;
      });
      if (role) { roleClicked = true; role.click(); }
    }
    if (unifiedClicked && roleClicked) stop();
  }
  function schedule() {
    if (active && !pending) pending = setTimeout(advance, 100);
  }
  if (typeof MutationObserver === 'function' && document.documentElement) {
    observer = new MutationObserver(schedule);
    observer.observe(document.documentElement, {childList: true, subtree: true, characterData: true,
      attributes: true, attributeFilter: ['class', 'style', 'disabled', 'aria-disabled']});
  }
  window.addEventListener('pagehide', stop);
  deadline = setTimeout(stop, 20000);
  schedule();
})();`;
