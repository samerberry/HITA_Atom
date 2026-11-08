import { placeMarqueeFrame } from './PlaceMarquee';
import { image } from '@kit.ImageKit';
import {
  drawTimetableCardSnapshot,
  drawTimetablePlaces,
  TimetableCardSurface,
  TimetablePlaceLabel
} from './TimetableWeekDraw';

class TimetablePlaceCanvas {
  card: TimetableCardSurface;
  context: CanvasRenderingContext2D;

  constructor(card: TimetableCardSurface, context: CanvasRenderingContext2D) {
    this.card = card;
    this.context = context;
  }
}

/** One page clock drives the small classroom canvases without rebuilding ArkUI cards. */
export class TimetableCardPainter {
  private entries: TimetablePlaceCanvas[] = [];
  private elapsedMs: number = 0;

  async capture(card: TimetableCardSurface, density: number): Promise<image.PixelMap> {
    const scale: number = Math.min(1, Math.sqrt(360000 / (card.width * card.height * density * density)));
    const width: number = card.width * scale;
    const height: number = card.height * scale;
    const canvas = new OffscreenCanvasRenderingContext2D(width, height, new RenderingContextSettings(true));
    canvas.scale(scale, scale);
    drawTimetableCardSnapshot(canvas, card, this.elapsedMs);
    return canvas.getPixelMap(0, 0, width, height);
  }

  attach(card: TimetableCardSurface, context: CanvasRenderingContext2D): void {
    if (card.place === undefined || card.place.textWidth <= card.place.width) {
      return;
    }
    const key: string = card.renderKey();
    this.entries = this.entries.filter((entry: TimetablePlaceCanvas): boolean =>
      entry.card.renderKey() !== key);
    this.entries.push(new TimetablePlaceCanvas(card, context));
    drawTimetablePlaces(context, card.width, card.height, [card.place], this.elapsedMs);
  }

  detach(context: CanvasRenderingContext2D): void {
    this.entries = this.entries.filter((entry: TimetablePlaceCanvas): boolean => entry.context !== context);
  }

  drawPlaces(labels: TimetablePlaceLabel[], elapsedMs: number): number {
    this.elapsedMs = elapsedMs;
    for (const entry of this.entries) {
      if (entry.card.place !== undefined) {
        drawTimetablePlaces(entry.context, entry.card.width, entry.card.height, [entry.card.place], elapsedMs);
      }
    }
    // Schedule from the layout even before native canvases finish mounting.
    let nextDelay: number = -1;
    for (const label of labels) {
      const delay: number = placeMarqueeFrame(elapsedMs, label.textWidth, label.width).nextFrameDelayMs;
      if (delay >= 0) {
        nextDelay = nextDelay < 0 ? delay : Math.min(nextDelay, delay);
      }
    }
    return nextDelay;
  }
}
