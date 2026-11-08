
// RenderNode/drawing glow is unavailable to atomic services. Preserve the host's
// geometry: light feedback must never replace a course card's own corner radius.
export class CompatibleLightModifier implements AttributeModifier<CommonAttribute> {
  constructor(_radius: number = 22, _enabled: boolean = true, _panel: boolean = false) {}
  applyNormalAttribute(_instance: CommonAttribute): void {}
}
