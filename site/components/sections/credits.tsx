import { Reveal } from '@/components/reveal';
import { SponsorButton } from '@/components/sponsor-button';

// Credits: the crew's group photo, an old print with the camera's orange date stamp. The date is
// Apollo 11's landing, the crew's own era.
export function Credits() {
  return (
    <section className="wrap credits grid justify-items-center pt-2 pb-[clamp(64px,12vw,104px)]">
      <Reveal>
        <figure className="photo" id="crew-photo">
          <div className="snap">
            <img
              src="/crew-photo.webp"
              srcSet="/crew-photo-640.webp 640w, /crew-photo.webp 1200w"
              sizes="(max-width:600px) calc(100vw - 60px), 532px"
              width="1200"
              height="896"
              loading="lazy"
              alt="The crew as a 1970s team photo in detailed pixel art, three rows deep. At the back, Felix and Walt. In the middle, Sunny in orange tie-dye waves at the camera, between Norm, who has blinked, and Faye. At the front, Judy and Pearl."
            />
            <span className="stamp" aria-hidden="true">&apos;69 7 20</span>
          </div>
          <figcaption>
            <h2>The AgentValley crew</h2>
            <span>Go take a break.</span>
            <span>We&apos;ll call you when we need you.</span>
          </figcaption>
        </figure>
      </Reveal>
      <div className="mt-12 grid justify-items-center gap-4 text-center">
        <p className="font-mono text-[.9375rem] text-muted-foreground">The app is free. Their coffee isn&apos;t.</p>
        <SponsorButton />
      </div>
    </section>
  );
}
