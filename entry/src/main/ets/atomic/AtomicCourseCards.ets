import { CompatibleMaterialModifier } from '../common/theme/CompatibleMaterialModifier';
import { ImmersiveHeader } from '../common/components/ImmersiveHeader';
import { drawTimetableCardText, TimetableCardSurface } from '../feature/timetable/views/TimetableWeekDraw';
import { TimetableCardPainter } from '../feature/timetable/views/TimetableCardPainter';

@Component
struct AtomicCourseCard {
  @Prop card: TimetableCardSurface = new TimetableCardSurface();
  painter: TimetableCardPainter = new TimetableCardPainter();
  onOpen: (key: string) => void = () => {};
  private textCanvas = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private placeCanvas = new CanvasRenderingContext2D(new RenderingContextSettings(true));

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.textCanvas)
        .width('100%').height('100%').hitTestBehavior(HitTestMode.None)
        .onReady(() => drawTimetableCardText(this.textCanvas, this.card))
      if (this.card.place !== undefined && this.card.place.textWidth > this.card.place.width) {
        Canvas(this.placeCanvas)
          .width('100%').height('100%').hitTestBehavior(HitTestMode.None)
          .onReady(() => this.painter.attach(this.card, this.placeCanvas))
      }
    }
    .width(this.card.width).height(this.card.height).borderRadius(this.card.radius)
    .backgroundColor(this.card.color)
    .attributeModifier(new CompatibleMaterialModifier(this.card.color, true, true, this.card.tint()))
    .accessibilityGroup(true)
    .accessibilityText(this.card.titleLines.join('') + '，' + (this.card.place?.text ?? ''))
    .onClick(() => this.onOpen(this.card.key))
    .onDisAppear(() => this.painter.detach(this.placeCanvas));
  }
}

/** Original card geometry, typography and classroom marquee, without particle-effect dependencies. */
@Component
export struct AtomicCourseCards {
  @Prop cards: TimetableCardSurface[] = [];
  @Prop contentHeight: number = 0;
  painter: TimetableCardPainter = new TimetableCardPainter();
  onOpen: (key: string) => void = () => {};

  build() {
    ImmersiveHeader({ barHeight: this.contentHeight }) {
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach(this.cards, (card: TimetableCardSurface) => {
          AtomicCourseCard({ card: card, painter: this.painter, onOpen: this.onOpen })
            .position({ x: card.left, y: card.top })
        }, (card: TimetableCardSurface): string => card.renderKey())
      }
      .width('100%').height(this.contentHeight).hitTestBehavior(HitTestMode.Transparent)
    }
  }
}
