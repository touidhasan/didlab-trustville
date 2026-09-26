import { defineConfig } from 'vitepress';

/**
 * lab.didlab.org — the DIDLab course site.
 *
 * Built from docs/ in the Trustville repository, in place. The file a student reads here
 * is the same file a contributor edits in the pull request that changed the code it
 * describes, so a lab cannot document a version of the codebase that no longer exists.
 *
 * When a second course needs a home here, move this config into its own repository and
 * fetch each course's docs at build time. Doing that now would be building for a course
 * that does not exist.
 */
export default defineConfig({
  title: 'DIDLab',
  description: 'Blockchain engineering labs — University of Missouri–Kansas City',
  lang: 'en-US',

  srcDir: '.',
  outDir: '.vitepress/dist',
  cleanUrls: true,

  // Student incident write-ups live in docs/incidents/. They are coursework, not course
  // material, and some of them will name a classmate's pull request. The blank template
  // stays published -- the labs link to it.
  srcExclude: ['incidents/**'],

  // docs/labs/README.md and docs/modules/README.md are what GitHub shows when you open
  // those folders. Serve the same files at /labs/ and /modules/ so one document does both
  // jobs -- the index a contributor reads on GitHub is the index a student reads here.
  rewrites: {
    'labs/README.md': 'labs/index.md',
    'modules/README.md': 'modules/index.md',
  },

  // A broken link in a lab sends a student to a 404 in the middle of an assessment, so it
  // fails the build instead.
  ignoreDeadLinks: false,

  head: [
    ['meta', { name: 'robots', content: 'index,follow' }],
    ['meta', { name: 'theme-color', content: '#c8802a' }],
  ],

  themeConfig: {
    nav: [
      { text: 'Labs', link: '/labs/' },
      { text: 'Modules', link: '/modules/' },
      { text: 'Trustville', link: 'https://dapp.didlab.org' },
      { text: 'Code', link: 'https://github.com/touidhasan/didlab-trustville' },
    ],

    sidebar: {
      '/labs/': [
        {
          text: 'Labs',
          items: [
            { text: 'How the labs work', link: '/labs/' },
            { text: '1 · Shipping your first change', link: '/labs/lab-1-shipping-your-first-change' },
            { text: '2 · Reading the chain', link: '/labs/lab-2-reading-the-chain' },
            { text: '3 · Writing transactions', link: '/labs/lab-3-writing-transactions' },
            { text: '4 · A vertical slice', link: '/labs/lab-4-a-vertical-slice' },
            { text: '5 · State machines and time', link: '/labs/lab-5-state-machines-and-time' },
            { text: '6 · Money, prices and failure', link: '/labs/lab-6-money-prices-and-failure' },
          ],
        },
        {
          text: 'Reference',
          items: [{ text: 'Module guides', link: '/modules/' }],
        },
      ],
      '/modules/': [
        {
          text: 'Module guides',
          items: [{ text: 'How to read these', link: '/modules/' }],
        },
        {
          text: 'Town Hall',
          collapsed: false,
          items: [
            { text: '1 · Resident record', link: '/modules/01-resident-record' },
            { text: '2 · Soulbound Passport', link: '/modules/02-soulbound-passport' },
            { text: '3 · Town token', link: '/modules/03-town-token' },
          ],
        },
        {
          text: 'Market',
          collapsed: false,
          items: [
            { text: '4 · Product provenance', link: '/modules/04-product-provenance' },
            { text: '5 · Escrow', link: '/modules/05-escrow' },
            { text: '6 · Sealed-bid auction', link: '/modules/06-sealed-bid-auction' },
          ],
        },
        {
          text: 'College',
          collapsed: false,
          items: [
            { text: '7 · Verifiable certificates', link: '/modules/07-verifiable-certificates' },
            { text: '8 · Event tickets', link: '/modules/08-event-tickets' },
          ],
        },
        {
          text: 'Housing',
          collapsed: false,
          items: [
            { text: '9 · Property deeds', link: '/modules/09-property-deeds' },
            { text: '10 · Rent escrow', link: '/modules/10-rent-escrow' },
          ],
        },
        {
          text: 'Council',
          collapsed: false,
          items: [
            { text: '11 · Multisig treasury', link: '/modules/11-multisig-treasury' },
            { text: '12 · DAO governance', link: '/modules/12-dao-governance' },
          ],
        },
        {
          text: 'Charity, Insurer, Exchange',
          collapsed: false,
          items: [
            { text: '13 · Charity', link: '/modules/13-charity' },
            { text: '14 · Insurer and oracle', link: '/modules/14-insurer' },
            { text: '15 · Swap and lending', link: '/modules/15-defi' },
          ],
        },
        { text: 'Labs', items: [{ text: 'All six labs', link: '/labs/' }] },
      ],
    },

    outline: { level: [2, 3] },

    search: { provider: 'local' },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/touidhasan/didlab-trustville' },
    ],

    editLink: {
      pattern: 'https://github.com/touidhasan/didlab-trustville/edit/main/docs/:path',
      text: 'Found a mistake? Fix it',
    },

    lastUpdated: { text: 'Updated' },

    footer: {
      message: 'MIT licensed. Fork it, break it, rebuild it.',
      copyright: 'DIDLab · UMKC',
    },
  },
});
