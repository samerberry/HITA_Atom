/**
 * 所有带系统拖拽条的底部弹层共用的内容边界。
 * 顶部留白只由此处提供，内部内容不要再次添加顶部 padding。
 */
export const SHEET_CONTENT_TOP_INSET: number = 24;

@Component
export struct SheetContent {
  @Prop fillHeight: boolean = false;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  private emptyContent() {}

  build() {
    Column() {
      this.content();
    }
    .width('100%')
    .height(this.fillHeight ? '100%' : undefined)
    .padding({ top: SHEET_CONTENT_TOP_INSET })
  }
}
