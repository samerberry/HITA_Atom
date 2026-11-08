/** Use the API 11 shape signature; API 26's Circle overload also accepts ColorMetrics. */
export class CirclePaintModifier implements AttributeModifier<CircleAttribute> {
  private color: ResourceColor;
  private outline: ResourceColor | undefined;

  constructor(color: ResourceColor, outline?: ResourceColor) {
    this.color = color;
    this.outline = outline;
  }

  applyNormalAttribute(instance: CircleAttribute): void {
    const shape: CommonShapeMethod<CircleAttribute> = instance;
    shape.fill(this.color);
    if (this.outline !== undefined) {
      shape.stroke(this.outline);
    }
  }
}
