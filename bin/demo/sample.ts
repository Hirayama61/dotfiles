/**
 * palette-engine — a tiny, deterministic color palette engine.
 *
 * Everything here is fictional and side-effect free. It exists purely to
 * showcase syntax highlighting (types, generics, doc comments, enums,
 * discriminated unions) for screenshots. No real APIs, paths or secrets.
 */

/** A single RGB channel, clamped to the 0–255 range. */
export type Channel = number & { readonly __brand: "Channel" };

/** Named roles a palette must provide for a UI theme. */
export enum Role {
  Background = "background",
  Foreground = "foreground",
  Accent = "accent",
  Muted = "muted",
  Danger = "danger",
}

/** An immutable RGB triple. */
export interface Rgb {
  readonly r: Channel;
  readonly g: Channel;
  readonly b: Channel;
}

/** A swatch is a color bound to a semantic role. */
export interface Swatch {
  readonly role: Role;
  readonly rgb: Rgb;
  /** Human label, e.g. "Mint" or "Pink". */
  readonly label: string;
}

/** Result type used instead of throwing, so callers stay total. */
export type Result<T, E = string> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: E };

const ok = <T>(value: T): Result<T> => ({ ok: true, value });
const err = <E>(error: E): Result<never, E> => ({ ok: false, error });

/** Narrows an arbitrary number into a {@link Channel}, or fails. */
export function toChannel(n: number): Result<Channel> {
  if (!Number.isInteger(n)) return err(`channel must be an integer: ${n}`);
  if (n < 0 || n > 255) return err(`channel out of range: ${n}`);
  return ok(n as Channel);
}

/**
 * Parse a `#rrggbb` string into an {@link Rgb}.
 *
 * @param hex - a 7-char string beginning with `#`
 * @returns the parsed color, or a descriptive error
 */
export function parseHex(hex: string): Result<Rgb> {
  const match = /^#([0-9a-fA-F]{6})$/.exec(hex.trim());
  if (match === null) return err(`not a hex color: "${hex}"`);

  const body = match[1];
  const parts = [0, 2, 4].map((i) => parseInt(body.slice(i, i + 2), 16));
  const [r, g, b] = parts.map(toChannel);

  for (const channel of [r, g, b]) {
    if (!channel.ok) return channel;
  }
  return ok({
    r: (r as Extract<typeof r, { ok: true }>).value,
    g: (g as Extract<typeof g, { ok: true }>).value,
    b: (b as Extract<typeof b, { ok: true }>).value,
  });
}

/** Relative luminance per the WCAG 2.x formula (0 = black, 1 = white). */
export function luminance({ r, g, b }: Rgb): number {
  const linear = (c: number): number => {
    const s = c / 255;
    return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
}

/** Pick a readable text color (dark on bright, light on dark). */
export function contrastText(bg: Rgb): "#242526" | "#e6e6e6" {
  return luminance(bg) > 0.4 ? "#242526" : "#e6e6e6";
}

/**
 * A frozen, lookup-friendly palette keyed by {@link Role}.
 *
 * @typeParam Roles - the subset of roles this palette guarantees
 */
export class Palette<Roles extends Role = Role> {
  private readonly byRole: ReadonlyMap<Roles, Swatch>;

  private constructor(swatches: ReadonlyArray<Swatch>) {
    this.byRole = new Map(
      swatches.map((s) => [s.role as Roles, s] as const),
    );
  }

  static from(swatches: ReadonlyArray<Swatch>): Result<Palette> {
    const seen = new Set<Role>();
    for (const s of swatches) {
      if (seen.has(s.role)) return err(`duplicate role: ${s.role}`);
      seen.add(s.role);
    }
    return ok(new Palette(swatches));
  }

  get(role: Roles): Swatch | undefined {
    return this.byRole.get(role);
  }

  /** Project every swatch through a mapper, keeping roles intact. */
  map<U>(fn: (swatch: Swatch) => U): ReadonlyMap<Roles, U> {
    const out = new Map<Roles, U>();
    for (const [role, swatch] of this.byRole) out.set(role, fn(swatch));
    return out;
  }

  get size(): number {
    return this.byRole.size;
  }
}

// A small, fixed demo palette (Panda-flavored, but values are arbitrary).
const demoSwatches: ReadonlyArray<Swatch> = [
  { role: Role.Background, label: "Ink", rgb: { r: 36, g: 37, b: 38 } as Rgb },
  { role: Role.Foreground, label: "Bone", rgb: { r: 230, g: 230, b: 230 } as Rgb },
  { role: Role.Accent, label: "Mint", rgb: { r: 25, g: 249, b: 216 } as Rgb },
  { role: Role.Muted, label: "Slate", rgb: { r: 103, g: 107, b: 121 } as Rgb },
  { role: Role.Danger, label: "Rose", rgb: { r: 255, g: 75, b: 130 } as Rgb },
];

const built = Palette.from(demoSwatches);
if (built.ok) {
  const accent = built.value.get(Role.Accent);
  if (accent) {
    const text = contrastText(accent.rgb);
    console.log(`accent=${accent.label} text=${text} size=${built.value.size}`);
  }
}
