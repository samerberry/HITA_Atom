// Match Android basicMarquee's timing and spacing in logical screen units.
export const PLACE_MARQUEE_PAUSE_MS: number = 1200;
export const PLACE_MARQUEE_SPEED: number = 30;

export class PlaceMarqueeFrame {
  offset: number = 0;
  nextFrameDelayMs: number = -1;
}

export function placeMarqueeFrame(elapsedMs: number, textWidth: number,
  viewportWidth: number): PlaceMarqueeFrame {
  const frame: PlaceMarqueeFrame = new PlaceMarqueeFrame();
  if (viewportWidth <= 0 || textWidth <= viewportWidth) {
    return frame;
  }
  const distance: number = textWidth + viewportWidth / 3;
  const travelMs: number = distance / PLACE_MARQUEE_SPEED * 1000;
  const phase: number = Math.max(0, elapsedMs) % (PLACE_MARQUEE_PAUSE_MS + travelMs);
  if (phase < PLACE_MARQUEE_PAUSE_MS) {
    frame.nextFrameDelayMs = PLACE_MARQUEE_PAUSE_MS - phase;
  } else {
    frame.offset = (phase - PLACE_MARQUEE_PAUSE_MS) / 1000 * PLACE_MARQUEE_SPEED;
    frame.nextFrameDelayMs = 0;
  }
  return frame;
}
