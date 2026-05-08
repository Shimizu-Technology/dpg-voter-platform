import { resolve } from 'node:path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

const publicSiteVariant = (process.env.VITE_PUBLIC_SITE_VARIANT || process.env.VITE_CAMPAIGN_VARIANT || 'jt').toLowerCase()
const publicSiteConfigFile = publicSiteVariant === 'dpg' ? 'publicSite.dpg.ts' : 'publicSite.jt.ts'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@public-site-config': resolve(__dirname, 'src/lib', publicSiteConfigFile),
    },
  },
  server: {
    port: 5175,
    proxy: {
      '/api': {
        target: 'http://localhost:3000',
        changeOrigin: true,
      },
    },
  },
})
