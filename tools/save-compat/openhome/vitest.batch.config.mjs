import { fileURLToPath } from 'node:url'

const repo = process.env.OPENHOME_ROOT ?? '/Users/bryanbassett/Documents/development/OpenHome'
const here = fileURLToPath(new URL('.', import.meta.url))

export default {
  root: repo,
  server: { fs: { strict: false, allow: [repo, here] } },
  test: {
    globals: true,
    testTimeout: 900000,
    environment: 'jsdom',
    setupFiles: [`${repo}/src/test-setup.ts`],
    include: [`${here}batch-probe.test.ts`],
    dir: here,
    reporters: ['dot'],
    hideSkippedTests: true,
  },
  resolve: {
    alias: {
      src: `${repo}/src`,
      '@openhome-core': `${repo}/src/core`,
      '@openhome-ui': `${repo}/src/ui`,
      '@pokemon-files': `${repo}/src/core/pokemon-files/src`,
      '@openhome-core/resources': `${repo}/src/core/pokemon-resources/src`,
      '@pkm-rs': `${repo}/pkm_rs`,
    },
  },
}
