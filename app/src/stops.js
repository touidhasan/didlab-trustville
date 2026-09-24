// The Trustville map: every stop, its problem, and when it ships.
export const stops = [
  {
    name: 'Town Hall',
    problem: 'Proving who you are without a central database',
    modules: ['Resident identity (DID + VC)', 'Soulbound Passport'],
    phase: 'D1',
  },
  {
    name: 'Bank',
    problem: 'A local currency anyone can audit',
    modules: ['Town token (ERC-20)', 'Swap and lending'],
    phase: 'D1',
  },
  {
    name: 'Market',
    problem: 'Buying from strangers, and knowing where goods came from',
    modules: ['Product provenance', 'Escrow', 'Sealed-bid auction'],
    phase: 'now',
  },
  {
    name: 'College',
    problem: 'Fake diplomas and forged tickets',
    modules: ['Verifiable certificates', 'Event tickets (ERC-1155)'],
    phase: 'now',
  },
  {
    name: 'Housing',
    problem: 'Deed fraud and lost security deposits',
    modules: ['Property deeds (ERC-721)', 'Rent escrow'],
    phase: 'D3',
  },
  {
    name: 'Council',
    problem: 'Opaque spending and votes nobody can check',
    modules: ['Multisig treasury', 'DAO governance'],
    phase: 'D3',
  },
  {
    name: 'Charity',
    problem: '“Did my donation actually arrive?”',
    modules: ['Milestone crowdfunding'],
    phase: 'D4',
  },
  {
    name: 'Insurer',
    problem: 'Claims that take months to pay',
    modules: ['Parametric insurance with an oracle'],
    phase: 'D4',
  },
  {
    name: 'Privacy Lab',
    problem: 'Proving a fact without revealing your data',
    modules: ['Zero-knowledge proofs'],
    phase: 'D6',
  },
];
