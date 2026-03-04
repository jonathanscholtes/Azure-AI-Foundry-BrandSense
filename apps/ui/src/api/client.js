/**
 * BrandSense API client.
 *
 * Connects to the brandsense-api FastAPI service.
 * In development Vite proxies /validate → http://localhost:80.
 * In production the built static files are served by the same container.
 */

const BASE = import.meta.env.VITE_API_BASE ?? ''

/**
 * POST /validate — upload a marketing asset (PDF) for validation.
 *
 * @param {File} file — PDF file selected by the user
 * @returns {Promise<import('../types').ValidationResult>}
 */
export async function validateAsset(file) {
  const form = new FormData()
  form.append('file', file)

  const res = await fetch(`${BASE}/validate`, {
    method: 'POST',
    body: form,
  })

  if (!res.ok) {
    let detail = `HTTP ${res.status}`
    try {
      const body = await res.json()
      detail = body.detail ?? body.message ?? detail
    } catch {
      // ignore parse failure — use status text
    }
    throw new Error(detail)
  }

  return res.json()
}

/**
 * GET /health — liveness check.
 *
 * @returns {Promise<{ status: string, version: string }>}
 */
export async function getHealth() {
  const res = await fetch(`${BASE}/health`)
  if (!res.ok) throw new Error(`Health check failed: HTTP ${res.status}`)
  return res.json()
}
