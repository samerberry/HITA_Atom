import { deviceInfo } from '@kit.BasicServicesKit';

/** API 26 only renders ordinary-component materials inside a native title bar. */
@Component
export struct ImmersiveHeader {
  @Prop barHeight: number = 60;
  @Prop materialEnabled: boolean = true;
  @BuilderParam content: () => void;

  build() {
    if (this.materialEnabled && deviceInfo.apiAvailable('26.0.0')) {
      Navigation() {}
        .title({ builder: () => { this.content(); }, height: this.barHeight }, {
          backgroundColor: Color.Transparent
        })
        .mode(NavigationMode.Stack)
        .hideBackButton(true)
        .hideToolBar(true)
        .width('100%')
        .height(this.barHeight)
        .backgroundColor(Color.Transparent)
        .ignoreLayoutSafeArea([], [])
        .hitTestBehavior(HitTestMode.Transparent);
    } else {
      this.content();
    }
  }
}
