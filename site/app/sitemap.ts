import type { MetadataRoute } from 'next';
import { STRIPS } from './comics/strips';

export const dynamic = 'force-static';

// The home page, the funnies, and a page per strip, each with the day it last changed and its
// pictures, so the strips can turn up in image search too.
export default function sitemap(): MetadataRoute.Sitemap {
  const pic = (slug: string) => `https://agentvalley.app/comics/${slug}.webp`;
  const newest = STRIPS.map((s) => s.date).sort().at(-1);
  return [
    { url: 'https://agentvalley.app/', images: ['https://agentvalley.app/og.png', 'https://agentvalley.app/crew-photo.webp'] },
    { url: 'https://agentvalley.app/comics/', lastModified: newest, images: STRIPS.map((s) => pic(s.slug)) },
    ...STRIPS.map((s) => ({ url: `https://agentvalley.app/comics/${s.slug}/`, lastModified: s.date, images: [pic(s.slug)] })),
    { url: 'https://agentvalley.app/privacy/', lastModified: '2026-10-27' },
  ];
}
