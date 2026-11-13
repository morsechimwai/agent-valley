// One review as a card. The review page's preview and the home page's reviews both draw it, so a
// review we put up looks like the card its writer saw.
type Props = { stars: number; words: string; name: string; handle?: string } & Omit<React.ComponentProps<'figure'>, 'children'>;

export function ReviewCard({ stars, words, name, handle, className = '', ...rest }: Props) {
  return (
    <figure className={`m-0 grid gap-3 rounded-xl border border-border bg-card p-5 ${className}`} {...rest}>
      <div role="img" aria-label={stars ? `${stars} out of 5 stars` : 'No stars yet'} style={{ color: 'var(--amber)' }} className="text-xl tracking-wide">
        {'★'.repeat(stars)}
        <span style={{ color: 'var(--border)' }}>{'★'.repeat(5 - stars)}</span>
      </div>
      <blockquote className="m-0 break-words">&ldquo;{words}&rdquo;</blockquote>
      <figcaption className="flex items-center gap-3">
        <span aria-hidden="true" className="grid size-10 shrink-0 place-items-center rounded-full bg-accent font-semibold">
          {name[0].toUpperCase()}
        </span>
        <span className="min-w-0 break-words">
          <b>{name}</b>
          {handle && <span className="block text-sm text-accent-text">{handle}</span>}
        </span>
      </figcaption>
    </figure>
  );
}
