import { guideUrl } from '../chain.js';
import { MODULES } from '../modules.js';

/**
 * "Read first" links under a stop's heading.
 *
 * The point of Trustville is not that you can press the buttons; it is that you understand
 * why the contract behind each button is shaped the way it is. Every stop therefore carries
 * the guides for its modules, one click away, before the forms rather than after them.
 */
export default function GuideLinks({ ids }) {
  const known = ids.filter((id) => MODULES[id]);
  if (known.length === 0) return null;

  return (
    <p className="guide-links">
      <span className="guide-links-label">Read first</span>
      {known.map((id) => (
        <a key={id} href={guideUrl(MODULES[id].slug)} target="_blank" rel="noreferrer">
          {id} · {MODULES[id].title}
        </a>
      ))}
    </p>
  );
}
