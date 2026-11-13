import { ReviewCard } from '@/components/review-card';

// Reviews sent from /review with "OK to show" ticked, put up by hand once we have read them.
// handle is written out as the card shows it, such as '@tim on GitHub'.
const REVIEWS: { stars: number; words: string; name: string; handle?: string }[] = [
  { stars: 5, words: 'Simple. But a lot of fun!', name: 'Tim' },
];

export function Reviews() {
  return (
    <section className="wrap section more reviews py-[clamp(56px,10vw,88px)]" id="reviews">
      <h2 className="mb-7">In their words.</h2>
      <div className="grid gap-5 min-[760px]:grid-cols-2">
        {REVIEWS.map((review) => (
          <ReviewCard key={review.name + review.words} {...review} />
        ))}
      </div>
      <p className="small mt-6">
        Used it a while? <a href="/review/">Write us a few words</a>.
      </p>
    </section>
  );
}
