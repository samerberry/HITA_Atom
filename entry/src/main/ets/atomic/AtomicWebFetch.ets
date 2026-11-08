import { webview } from '@kit.ArkWeb';
import { AtomicAcademicConfig } from './AtomicAcademicConfig';

interface FetchReply {
  id: string;
  state: string;
  status?: number;
  text?: string;
  failure?: string;
}

/** Each runJavaScript expression returns a synchronous string, never a Promise. */
export class AtomicWebFetch {
  private config: AtomicAcademicConfig;
  private controller: webview.WebviewController | undefined = undefined;
  private closed: boolean = false;
  private sequence: number = 0;
  private pending: Map<string, () => void> = new Map<string, () => void>();

  constructor(campus: string = '威海') { this.config = new AtomicAcademicConfig(campus); }

  attach(controller: webview.WebviewController): void {
    if (this.controller !== controller) this.cancel();
    this.controller = controller;
  }

  cancel(): void {
    const callbacks = Array.from(this.pending.values());
    callbacks.forEach((cancel: () => void) => cancel());
  }

  close(): void {
    this.closed = true;
    this.cancel();
    this.controller = undefined;
  }

  private parse(raw: string, id: string): FetchReply {
    let value = JSON.parse(raw) as Object;
    // ArkWeb versions may wrap a returned JS string in one JSON string layer.
    if (typeof value === 'string') value = JSON.parse(value) as Object;
    if (value === null || typeof value !== 'object') throw new Error('教务响应解析失败');
    const reply = value as FetchReply;
    if (reply.id !== id || !['pending', 'done', 'error', 'missing'].includes(reply.state)) {
      throw new Error('教务响应解析失败');
    }
    return reply;
  }

  request(path: string, body: string = '', method: string = body ? 'POST' : 'GET',
    refererPath: string = '', timeoutMs: number = 30000): Promise<string> {
    if (this.closed) return Promise.reject(new Error('登录已取消'));
    const controller = this.controller;
    if (controller === undefined) return Promise.reject(new Error('教务页面尚未就绪，请稍后重试'));
    if (!this.config.requestPaths.includes(path) || !['GET', 'POST'].includes(method)) {
      return Promise.reject(new Error('教务请求地址无效'));
    }
    const id = Date.now().toString(36) + '_' + (++this.sequence);
    const key = JSON.stringify('__hitaFetch_' + id);
    const quotedId = JSON.stringify(id);
    // Fetch stays on the currently authenticated origin. Never downgrade an HTTPS
    // VPN page to direct HTTP, and never fetch from an SSO / unrelated page.
    const startScript = `(function() {
      var id = ${quotedId}, key = ${key};
      var bases = ${JSON.stringify(this.config.bases)};
      var base = '';
      var current = location.origin + location.pathname;
      for (var i = 0; i < bases.length; i++) {
        if (current === bases[i] || current.indexOf(bases[i] + '/') === 0) { base = bases[i]; break; }
      }
      if (!base) return JSON.stringify({id: id, state: 'error', failure: 'context'});
      var abort = new AbortController();
      var slot = {id: id, state: 'pending', abort: abort, timer: 0};
      window[key] = slot;
      function finish(result) {
        clearTimeout(slot.timer);
        if (window[key] === slot) window[key] = result;
      }
      slot.timer = setTimeout(function() {
        finish({id: id, state: 'error', failure: 'timeout'});
        abort.abort();
      }, ${timeoutMs - 2000});
      try {
        fetch(base + ${JSON.stringify(path)}, {
          method: ${JSON.stringify(method)},
          credentials: 'include', mode: 'same-origin', cache: 'no-store',
          headers: {'Accept': ${JSON.stringify(this.config.campus === '深圳' ? 'application/json, text/plain, */*' : 'text/html,application/xhtml+xml,*/*')},
            ${this.config.campus === '深圳' ? "'RoleCode': '01', 'X-Requested-With': 'XMLHttpRequest'," : ''}
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'},
          ${method === 'POST' ? 'body: ' + JSON.stringify(body) + ',' : ''}
          ${refererPath ? 'referrer: base + ' + JSON.stringify(refererPath) + ',' : ''}
          signal: abort.signal
        }).then(function(response) {
          return response.text().then(function(text) {
            finish({id: id, state: 'done', status: response.status, text: text});
          });
        }).catch(function() { finish({id: id, state: 'error', failure: 'network'}); });
      } catch (_) { finish({id: id, state: 'error', failure: 'network'}); }
      return JSON.stringify({id: id, state: 'pending'});
    })();`;
    const pollScript = `(function() {
      var slot = window[${key}];
      if (!slot || slot.id !== ${quotedId}) return JSON.stringify({id: ${quotedId}, state: 'missing'});
      if (slot.state === 'pending') return JSON.stringify({id: slot.id, state: 'pending'});
      return JSON.stringify(slot);
    })();`;
    const cleanupScript = `(function() {
      var key = ${key}, slot = window[key];
      if (slot && slot.id === ${quotedId}) {
        clearTimeout(slot.timer);
        if (slot.abort) slot.abort.abort();
        delete window[key];
      }
      return '';
    })();`;

    return new Promise<string>((resolve, reject) => {
      let settled: boolean = false;
      let pollTimer: number = -1;
      let deadline: number = -1;
      const finish = (error: Error | undefined, text: string = ''): void => {
        if (settled) return;
        settled = true;
        clearTimeout(pollTimer); clearTimeout(deadline);
        this.pending.delete(id);
        // Scope cleanup by request ID so a late response cannot erase a retry.
        try { controller.runJavaScript(cleanupScript).catch(() => {}); } catch (_) {}
        if (error !== undefined) reject(error); else resolve(text);
      };
      const run = (script: string): void => {
        if (settled) return;
        try {
          controller.runJavaScript(script).then((raw: string) => {
            if (settled) return;
            let reply: FetchReply;
            try { reply = this.parse(raw, id); }
            catch (_) { finish(new Error('教务响应解析失败，请重新读取')); return; }
            if (reply.state === 'pending') {
              pollTimer = setTimeout(() => run(pollScript), 200);
            } else if (reply.state === 'missing') {
              finish(new Error('教务页面已切换，请待页面加载完成后重新读取'));
            } else if (reply.state === 'error') {
              const message = reply.failure === 'timeout' ? '教务请求超时，请检查网络后重试' :
                reply.failure === 'context' ? '请先进入教务系统并完成登录，再读取课表' :
                '教务网页请求失败，请确认登录状态和网络后重试';
              finish(new Error(message));
            } else if (typeof reply.status !== 'number' || typeof reply.text !== 'string') {
              finish(new Error('教务响应解析失败，请重新读取'));
            } else if (reply.status !== 200) {
              finish(new Error('教务请求失败（HTTP ' + reply.status + '）'));
            } else {
              finish(undefined, reply.text);
            }
          }).catch(() => finish(new Error('教务页面无法执行请求，请待页面加载完成后重新读取')));
        } catch (_) { finish(new Error('教务页面无法执行请求，请待页面加载完成后重新读取')); }
      };
      this.pending.set(id, () => finish(new Error('登录请求已取消，请重新读取')));
      // Also bounds native bridge calls that never resolve, not just fetch itself.
      deadline = setTimeout(() => finish(new Error('教务请求超时，请检查网络后重试')), timeoutMs);
      run(startScript);
    });
  }
}
