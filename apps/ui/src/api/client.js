/**
 * BrandSense API client.
 *
 * Connects to the brandsense-api FastAPI service.
 * In development Vite proxies /validate → http://localhost:80.
 * In production the built static files are served by the same container.
 */

const BASE = import.meta.env.VITE_API_BASE ?? ''

/**
 * POST /validate — upload a PDF and stream ndjson progress + result.
 *
 * Async generator that yields parsed event objects as they arrive:
 *   { event: 'progress', agent: 'researcher', status: 'running', message: '...' }
 *   { event: 'progress', agent: 'auditor',    status: 'done',    message: '...' }
 *   { event: 'complete', result: { ...BrieferOutput } }
 *   { event: 'error',    message: '...' }   // on pipeline failure
 *
 * @param {File} file — PDF file selected by the user
 * @yields {Object} parsed ndjson event
 */
export async function* validateAssetStream(file) {
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
    } catch { /* ignore */ }
    throw new Error(detail)
  }

  const reader  = res.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''

  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true })
    const lines = buffer.split('\n')
    buffer = lines.pop() // keep last incomplete line
    for (const line of lines) {
      const trimmed = line.trim()
      if (trimmed) yield JSON.parse(trimmed)
    }
  }
  // flush any remaining buffer
  if (buffer.trim()) yield JSON.parse(buffer.trim())
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
