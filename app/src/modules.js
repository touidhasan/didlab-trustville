/**
 * The sixteen modules, in one place.
 *
 * Every stop card links to the guides for the modules it contains, so a student who does
 * not know what a sealed-bid auction is can find out without leaving the page. The slugs
 * are the filenames in docs/modules/ -- keep them in step, and the docs build will fail
 * loudly if a guide is renamed and this file is not.
 */
export const MODULES = {
  1: { title: 'Resident record', slug: '01-resident-record' },
  2: { title: 'Soulbound Passport', slug: '02-soulbound-passport' },
  3: { title: 'Town token', slug: '03-town-token' },
  4: { title: 'Product provenance', slug: '04-product-provenance' },
  5: { title: 'Escrow', slug: '05-escrow' },
  6: { title: 'Sealed-bid auction', slug: '06-sealed-bid-auction' },
  7: { title: 'Verifiable certificates', slug: '07-verifiable-certificates' },
  8: { title: 'Event tickets', slug: '08-event-tickets' },
  9: { title: 'Property deeds', slug: '09-property-deeds' },
  10: { title: 'Rent escrow', slug: '10-rent-escrow' },
  11: { title: 'Multisig treasury', slug: '11-multisig-treasury' },
  12: { title: 'DAO governance', slug: '12-dao-governance' },
  13: { title: 'Charity', slug: '13-charity' },
  14: { title: 'Insurer and oracle', slug: '14-insurer' },
  15: { title: 'Swap and lending', slug: '15-defi' },
};

/** The index page for all of them. */
export const MODULE_INDEX = 'README';
