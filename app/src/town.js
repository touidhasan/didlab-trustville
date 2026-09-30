import { MODULES } from './modules.js';

/**
 * The town, in the order a learner walks it.
 *
 * ONE list drives the landing page, the town map, every stop page and the previous/next
 * links. It replaced a second list (stops.js) that had drifted from the first: it still
 * said "Opens in D1" on stops that had been live for weeks, called module 1 by a different
 * name from its guide, and left two stops off the map entirely. Two lists describing the
 * same thing will always disagree eventually; this file exists so there is only one.
 *
 * Stops appear in module-number order, so walking the town from start to finish is walking
 * modules 1 to 16. `contract` is the address that decides whether a stop is open on the
 * chain this build points at.
 */
export const STOPS = [
  {
    slug: 'notice-board',
    name: 'Notice Board',
    warmUp: true,
    modules: [],
    contract: 'TownNoticeBoard',
    problem: 'Your first transaction: change shared state, emit an event, and sign it with your own key.',
  },
  {
    slug: 'town-hall',
    name: 'Town Hall',
    modules: [1, 2],
    contract: 'ResidentRegistry',
    problem: 'Proving who you are without a central database.',
  },
  {
    slug: 'bank',
    name: 'Bank',
    modules: [3],
    contract: 'TownToken',
    problem: 'A local currency anyone can audit.',
  },
  {
    slug: 'market',
    name: 'Market',
    modules: [4, 5, 6],
    contract: 'ProductRegistry',
    problem: 'Buying from strangers, and knowing where the goods came from.',
  },
  {
    slug: 'college',
    name: 'College',
    modules: [7, 8],
    contract: 'CertificateRegistry',
    problem: 'Fake diplomas and forged tickets.',
  },
  {
    slug: 'housing',
    name: 'Housing',
    modules: [9, 10],
    contract: 'PropertyDeeds',
    problem: 'Deed fraud and lost security deposits.',
  },
  {
    slug: 'council',
    name: 'Council',
    modules: [11, 12],
    contract: 'TownTreasury',
    problem: 'Opaque spending, and votes nobody can check.',
  },
  {
    slug: 'charity',
    name: 'Charity',
    modules: [13],
    contract: 'TownCharity',
    problem: '"Did my donation actually arrive?"',
  },
  {
    slug: 'insurer',
    name: 'Insurer',
    modules: [14],
    contract: 'CropInsurance',
    problem: 'Claims that take months to pay.',
  },
  {
    slug: 'exchange',
    name: 'Exchange',
    modules: [15],
    contract: 'TownSwap',
    problem: 'Trading without a counterparty, and borrowing against a price someone can move.',
  },
  {
    slug: 'privacy-lab',
    name: 'Privacy Lab',
    modules: [16],
    contract: 'PrivacyLab',
    problem: 'Proving you qualify without revealing who you are.',
  },
];

export const STOP_BY_SLUG = Object.fromEntries(STOPS.map((s) => [s.slug, s]));

/** Every module number, 1 to 16, in walking order. */
export const MODULE_NUMBERS = STOPS.flatMap((s) => s.modules);

export const stopOfModule = (id) => STOPS.find((s) => s.modules.includes(id));

/** "Modules 4–6", "Module 3", or "Warm-up". */
export function moduleRange(stop) {
  const m = stop.modules;
  if (m.length === 0) return 'Warm-up';
  if (m.length === 1) return `Module ${m[0]}`;
  return `Modules ${m[0]}–${m[m.length - 1]}`;
}

/** Just the numbers, for badges: "4–6", "3", or "0". */
export function moduleNumbers(stop) {
  const m = stop.modules;
  if (m.length === 0) return '0';
  if (m.length === 1) return String(m[0]);
  return `${m[0]}–${m[m.length - 1]}`;
}

/** Open when this chain's deployments file has the stop's contract. */
export const isOpen = (stop, contracts) => Boolean(contracts[stop.contract]);

export function neighbours(slug) {
  const i = STOPS.findIndex((s) => s.slug === slug);
  return { prev: i > 0 ? STOPS[i - 1] : null, next: i >= 0 && i < STOPS.length - 1 ? STOPS[i + 1] : null };
}

export const moduleTitle = (id) => MODULES[id]?.title ?? `Module ${id}`;
