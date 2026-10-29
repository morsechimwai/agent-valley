import type { Metadata } from 'next';
import { ReviewForm } from '@/components/review-form';
import { Footer } from '@/components/sections/footer';
import { Nav } from '@/components/sections/nav';

export const metadata: Metadata = {
  title: 'A few words · AgentValley',
  robots: { index: false },
};

export default function Review() {
  return (
    <>
      <Nav sub />
      <main className="wrap py-24">
        <header className="grid max-w-[68ch] gap-4">
          <h1>A few words for the site</h1>
          <p className="lead">Tell us what the app is like to live with. We read every one.</p>
        </header>
        <ReviewForm />
      </main>
      <Footer />
    </>
  );
}
