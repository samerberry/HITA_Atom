export const WEIHAI_ORIGIN: string = 'https://webvpn.hitwh.edu.cn';
export const WEIHAI_EAS: string = WEIHAI_ORIGIN + '/http/77726476706e69737468656265737421fae0558f693861446900c7a99c406d3667';
export const BENBU_EAS: string = 'http://jwts-hit-edu-cn.vpn.hit.edu.cn:1080';
export const SHENZHEN_EAS: string = 'https://jw-hitsz-edu-cn.hitsz.edu.cn';
export const SHENZHEN_DIRECT: string = 'https://jw.hitsz.edu.cn';

/** Fixed school routes. A gateway / CAS page is never a source of timetable data. */
export class AtomicAcademicConfig {
  campus: string;
  constructor(campus: string = '威海') {
    if (!['本部', '威海', '深圳'].includes(campus)) throw new Error('请选择有效校区');
    this.campus = campus;
  }

  get loginUrl(): string {
    if (this.campus === '本部') return BENBU_EAS + '/loginCAS';
    if (this.campus === '深圳') return SHENZHEN_EAS + '/authentication/main';
    return WEIHAI_EAS + '/loginCAS';
  }

  get bases(): string[] {
    if (this.campus === '本部') return [BENBU_EAS];
    if (this.campus === '深圳') return [SHENZHEN_EAS, SHENZHEN_DIRECT];
    return [WEIHAI_EAS, 'http://jwts.hitwh.edu.cn', 'https://jwts.hitwh.edu.cn'];
  }

  get cookieDomains(): string[] {
    if (this.campus === '本部') return ['jwts-hit-edu-cn.vpn.hit.edu.cn', 'i-hit-edu-cn.vpn.hit.edu.cn',
      'vpn.hit.edu.cn', 'ivpn.hit.edu.cn', 'ids.hit.edu.cn'];
    if (this.campus === '深圳') return ['jw-hitsz-edu-cn.hitsz.edu.cn', 'jw.hitsz.edu.cn',
      'trust.hitsz.edu.cn', 'authserver.hitsz.edu.cn', 'ids.hit.edu.cn'];
    return ['webvpn.hitwh.edu.cn', 'jwts.hitwh.edu.cn', 'ids.hit.edu.cn'];
  }

  get requestPaths(): string[] {
    if (this.campus === '深圳') return ['/component/queryXnxq', '/component/queryxnxqdata',
      '/Xsxk/queryXkdqXnxq', '/Xsxk/queryYxkc?sf_request_type=ajax', '/xszykb/queryxszykbzong',
      '/component/queryKbjg', '/component/queryRlZcSj'];
    return ['/kbcx/queryGrkb', '/xlcx/queryXlcx'];
  }

  academicBase(url: string): string {
    const clean = this.cleanUrl(url);
    return this.bases.find((base: string): boolean => clean === base || clean.startsWith(base + '/')) ?? '';
  }

  shouldRead(url: string): boolean {
    return this.academicBase(url).length > 0 &&
      !/\/authserver\/|\/session\/invalid|\/authentication\/require|\/logout(?:[/?#]|$)/i.test(url.replace(/[?#].*$/, ''));
  }

  redirectFor(url: string): string {
    const clean = this.cleanUrl(url).replace(/\/+$/, '');
    if (this.campus === '威海' && clean.startsWith(WEIHAI_ORIGIN) && this.academicBase(url) === '' &&
      (clean === WEIHAI_ORIGIN || clean.startsWith(WEIHAI_ORIGIN + '/portal'))) return this.loginUrl;
    if (this.campus === '本部' && /^http:\/\/i-hit-edu-cn\.vpn\.hit\.edu\.cn:1080\/portal(?:\/home)?$/.test(clean)) {
      return this.loginUrl;
    }
    if (this.campus === '深圳') {
      const base = this.academicBase(url);
      if (base && /\/session\/invalid|\/authentication\/require/i.test(clean)) return base + '/cas';
      // aTrust routes login and MFA through the fragment. Stripping it before
      // classifying the page could navigate away from an unfinished login.
      const fragment = url.includes('#') ? url.substring(url.indexOf('#') + 1).replace(/\?.*$/, '') : '';
      const authentication = /shortcut|login|auth|password|totp|radius|token|trust_terminal|forbidden/i
        .test(clean + '#' + fragment);
      const gatewayHome = /^https:\/\/trust\.hitsz\.edu\.cn(?:\/portal(?:\/(?:index|service_center)\.html)?)?$/.test(clean) &&
        (!fragment || /^!?\/$/.test(fragment) ||
          /^!?\/(?:app_center(?:\/(?:index|home))?|service_center)\/?$/.test(fragment));
      // Unknown mobile routes can request MFA, a client, or show access errors;
      // only known portal homes should automatically return to academic login.
      if (!authentication && (clean === SHENZHEN_EAS || gatewayHome)) return this.loginUrl;
    }
    return '';
  }

  private cleanUrl(url: string): string {
    return url.replace(/[?#].*$/, '').replace(/^(https:\/\/[^/:]+):443(?=\/|$)/, '$1')
      .replace(/^(http:\/\/[^/:]+):80(?=\/|$)/, '$1');
  }
}
