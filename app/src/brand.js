/**
 * Who runs this copy of the town.
 *
 * Trustville is the open core; whoever hosts a copy of it — a university, a training
 * business, a student's fork — names themselves here, through the build's environment,
 * without touching a component. Nothing in the pages names an institution directly.
 *
 *   VITE_BRAND_OPERATOR   who runs this town                     default: DIDLab
 *   VITE_REPO_URL         where its code lives                   default: the public repo
 *   VITE_TRAINING_URL     a page about training for teams        default: none (hidden)
 *   VITE_CONTACT_EMAIL    who to write to                        default: none (hidden)
 */
const env = import.meta.env;

export const BRAND = {
  name: 'Trustville',
  operator: env.VITE_BRAND_OPERATOR || 'DIDLab',
  repo: env.VITE_REPO_URL || 'https://github.com/touidhasan/didlab-trustville',
  trainingUrl: env.VITE_TRAINING_URL || '',
  contactEmail: env.VITE_CONTACT_EMAIL || '',
};
